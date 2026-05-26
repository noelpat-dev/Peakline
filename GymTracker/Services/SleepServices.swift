import Foundation
import SwiftData
import UserNotifications

struct SleepSettingsStore {
    private let key = "sleep.settings.v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> SleepSettings {
        guard let data = defaults.data(forKey: key),
              let settings = try? JSONDecoder().decode(SleepSettings.self, from: data) else {
            return .default
        }

        return settings
    }

    func save(_ settings: SleepSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: key)
    }
}

enum SleepSessionValidationError: LocalizedError, Equatable {
    case tooShort
    case tooLong
    case wakeBeforeStart
    case startInFuture

    var errorDescription: String? {
        switch self {
        case .tooShort:
            return "This looks too short to count as a sleep session."
        case .tooLong:
            return "This looks unusually long. Please confirm the times."
        case .wakeBeforeStart:
            return "Wake time must be after sleep start."
        case .startInFuture:
            return "Sleep start cannot be in the future."
        }
    }
}

struct SleepSessionRepository {
    func activeSession(in context: ModelContext) -> SleepSession? {
        var descriptor = FetchDescriptor<SleepSession>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 20
        return try? context.fetch(descriptor).first { $0.status == .active }
    }

    func startSleepMode(windDownMinutes: Int, in context: ModelContext) throws -> SleepSession {
        if let existing = activeSession(in: context) {
            return existing
        }

        let now = Date()
        let estimatedStart = now.addingTimeInterval(TimeInterval(windDownMinutes * 60))
        let session = SleepSession(
            sleepModeStartedAt: now,
            windDownDurationMinutes: windDownMinutes,
            estimatedSleepStartAt: estimatedStart,
            confirmedSleepStartAt: estimatedStart,
            wakeAt: estimatedStart,
            durationMinutes: 0,
            source: .inAppTimer,
            confidence: .low,
            status: .active
        )
        context.insert(session)
        try context.save()
        return session
    }

    func startManualSession(start: Date, wake: Date, quality: Int?, tags: [SleepTag], notes: String?, in context: ModelContext) throws {
        try validate(start: start, wake: wake)
        let session = SleepSession(
            confirmedSleepStartAt: start,
            wakeAt: wake,
            durationMinutes: durationMinutes(start: start, wake: wake),
            qualityRating: quality,
            tags: tags,
            notes: notes,
            source: .manual,
            confidence: .medium,
            status: .completed
        )
        context.insert(session)
        try context.save()
    }

    func confirmActiveSession(
        _ session: SleepSession,
        sleepStart: Date,
        wake: Date,
        quality: Int?,
        tags: [SleepTag],
        in context: ModelContext
    ) throws {
        try validate(start: sleepStart, wake: wake)
        session.confirmedSleepStartAt = sleepStart
        session.wakeAt = wake
        session.durationMinutes = durationMinutes(start: sleepStart, wake: wake)
        session.qualityRating = quality
        session.tags = tags
        session.confidence = .estimatedConfirmed
        session.status = .completed
        session.updatedAt = .now
        try context.save()
    }

    func updateCompletedSession(
        _ session: SleepSession,
        sleepStart: Date,
        wake: Date,
        quality: Int?,
        tags: [SleepTag],
        notes: String?,
        in context: ModelContext
    ) throws {
        try validate(start: sleepStart, wake: wake)
        session.confirmedSleepStartAt = sleepStart
        session.wakeAt = wake
        session.durationMinutes = durationMinutes(start: sleepStart, wake: wake)
        session.qualityRating = quality
        session.tags = tags
        session.notes = notes
        session.updatedAt = .now
        try context.save()
    }

    func discard(_ session: SleepSession, in context: ModelContext) throws {
        session.status = .discarded
        session.updatedAt = .now
        try context.save()
    }

    func delete(_ session: SleepSession, in context: ModelContext) throws {
        context.delete(session)
        try context.save()
    }

    func durationMinutes(start: Date, wake: Date) -> Int {
        max(0, Int(wake.timeIntervalSince(start) / 60))
    }

    func validate(start: Date, wake: Date, allowTooLongWarning: Bool = false) throws {
        guard start <= Date.now.addingTimeInterval(60) else { throw SleepSessionValidationError.startInFuture }
        guard wake > start else { throw SleepSessionValidationError.wakeBeforeStart }

        let minutes = durationMinutes(start: start, wake: wake)
        guard minutes >= 60 else { throw SleepSessionValidationError.tooShort }
        if !allowTooLongWarning {
            guard minutes <= 14 * 60 else { throw SleepSessionValidationError.tooLong }
        }
    }
}

struct SleepSourceResolver {
    private let toleranceMinutes = 45
    private let largeConflictMinutes = 120

    func resolvedSession(for date: Date, sessions: [SleepSession], settings: SleepSettings, calendar: Calendar = .current) -> ResolvedSleepSession? {
        let completed = sessions.filter { $0.status == .completed }
        let appleHealth = bestSession(
            from: completed.filter { $0.source == .appleHealth && calendar.isDate($0.nightDate, inSameDayAs: date) }
        )
        let sleepMode = bestSession(
            from: completed.filter { $0.source == .inAppTimer && calendar.isDate($0.nightDate, inSameDayAs: date) }
        )
        let manual = bestSession(
            from: completed.filter { $0.source == .manual && calendar.isDate($0.nightDate, inSameDayAs: date) }
        )

        switch settings.preferredSource {
        case .appleHealth:
            return appleHealth.map { resolved(from: $0, source: .appleHealth) }
                ?? sleepMode.map { resolved(from: $0, source: .inAppTimer) }
                ?? manual.map { resolved(from: $0, source: .manual) }
        case .sleepMode:
            return sleepMode.map { resolved(from: $0, source: .inAppTimer) }
                ?? appleHealth.map { resolved(from: $0, source: .appleHealth) }
                ?? manual.map { resolved(from: $0, source: .manual) }
        case .manual:
            return manual.map { resolved(from: $0, source: .manual) }
                ?? appleHealth.map { resolved(from: $0, source: .appleHealth) }
                ?? sleepMode.map { resolved(from: $0, source: .inAppTimer) }
        case .automatic:
            return automaticResolved(date: date, appleHealth: appleHealth, sleepMode: sleepMode, manual: manual)
        }
    }

    func resolvedSessions(from sessions: [SleepSession], settings: SleepSettings, days: Int = 28, calendar: Calendar = .current) -> [ResolvedSleepSession] {
        let start = calendar.startOfDay(for: .now)
        return (0..<days).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: start) else { return nil }
            return resolvedSession(for: date, sessions: sessions, settings: settings, calendar: calendar)
        }
    }

    private func automaticResolved(date: Date, appleHealth: SleepSession?, sleepMode: SleepSession?, manual: SleepSession?) -> ResolvedSleepSession? {
        guard let appleHealth else {
            return sleepMode.map { resolved(from: $0, source: .inAppTimer) }
                ?? manual.map { resolved(from: $0, source: .manual) }
        }

        guard let sleepMode else {
            return resolved(from: appleHealth, source: .appleHealth)
        }

        let difference = abs(appleHealth.durationMinutes - sleepMode.durationMinutes)
        if difference <= toleranceMinutes {
            return ResolvedSleepSession(
                id: appleHealth.id,
                sleepDate: date,
                startDate: appleHealth.confirmedSleepStartAt,
                endDate: appleHealth.wakeAt,
                asleepDuration: TimeInterval(appleHealth.durationMinutes * 60),
                inBedDuration: inBedDuration(for: sleepMode),
                qualityRating: sleepMode.qualityRating,
                dataSource: .merged,
                confidence: appleHealth.confidence,
                appleHealthSummary: nil,
                appSessionID: sleepMode.id,
                notes: sleepMode.notes,
                conflict: nil,
                stageBreakdown: nil
            )
        }

        let conflict: SleepSourceConflict = difference > largeConflictMinutes
            ? .largeMismatch
            : (appleHealth.durationMinutes < sleepMode.durationMinutes ? .appleHealthShorter : .appEstimateShorter)

        if appleHealth.confidence == .high {
            return resolved(from: appleHealth, source: .appleHealth, conflict: conflict)
        }

        if sleepMode.confidence == .estimatedConfirmed {
            return resolved(from: sleepMode, source: .inAppTimer, conflict: .lowConfidenceHealthKit)
        }

        return resolved(from: appleHealth, source: .appleHealth, conflict: conflict)
    }

    private func bestSession(from sessions: [SleepSession]) -> SleepSession? {
        sessions.sorted { lhs, rhs in
            if lhs.confidence != rhs.confidence {
                return confidenceRank(lhs.confidence) > confidenceRank(rhs.confidence)
            }
            return lhs.durationMinutes > rhs.durationMinutes
        }.first
    }

    private func confidenceRank(_ confidence: SleepConfidence) -> Int {
        switch confidence {
        case .high:
            return 4
        case .estimatedConfirmed:
            return 3
        case .medium:
            return 2
        case .low:
            return 1
        }
    }

    private func resolved(from session: SleepSession, source: SleepSource, conflict: SleepSourceConflict? = nil) -> ResolvedSleepSession {
        ResolvedSleepSession(
            id: session.id,
            sleepDate: session.nightDate,
            startDate: session.confirmedSleepStartAt,
            endDate: session.wakeAt,
            asleepDuration: TimeInterval(session.durationMinutes * 60),
            inBedDuration: inBedDuration(for: session),
            qualityRating: session.qualityRating,
            dataSource: source,
            confidence: session.confidence,
            appleHealthSummary: nil,
            appSessionID: session.source == .appleHealth ? nil : session.id,
            notes: session.notes,
            conflict: conflict,
            stageBreakdown: nil
        )
    }

    private func inBedDuration(for session: SleepSession) -> TimeInterval? {
        guard let started = session.sleepModeStartedAt, started < session.wakeAt else { return nil }
        return session.wakeAt.timeIntervalSince(started)
    }
}

enum NapSessionValidationError: LocalizedError, Equatable {
    case tooShort
    case tooLong
    case endBeforeStart
    case startInFuture

    var errorDescription: String? {
        switch self {
        case .tooShort:
            return "Naps need to be at least 10 minutes to count."
        case .tooLong:
            return "That looks longer than a normal nap. Add it as sleep if it was your main rest."
        case .endBeforeStart:
            return "Nap end time must be after the start time."
        case .startInFuture:
            return "Nap start time cannot be in the future."
        }
    }
}

struct NapSessionRepository {
    func addNap(start: Date, end: Date, quality: Int?, note: String?, source: NapSource = .manual, healthKitSampleIds: [String] = [], in context: ModelContext) throws {
        try validate(start: start, end: end)
        let nap = NapSession(
            startDate: start,
            endDate: end,
            qualityRating: quality,
            source: source,
            timingCategory: NapSession.timingCategory(for: start),
            note: note?.isEmpty == true ? nil : note,
            healthKitSampleIds: healthKitSampleIds
        )
        context.insert(nap)
        try context.save()
    }

    func delete(_ nap: NapSession, in context: ModelContext) throws {
        context.delete(nap)
        try context.save()
    }

    func validate(start: Date, end: Date) throws {
        guard start <= Date.now.addingTimeInterval(60) else { throw NapSessionValidationError.startInFuture }
        guard end > start else { throw NapSessionValidationError.endBeforeStart }
        let minutes = Int(end.timeIntervalSince(start) / 60)
        guard minutes >= 10 else { throw NapSessionValidationError.tooShort }
        guard minutes <= 180 else { throw NapSessionValidationError.tooLong }
    }
}

struct NapRecoveryCalculator {
    func calculateNapCredit(naps: [NapSession], overnightSleep: ResolvedSleepSession?, sleepTarget: TimeInterval, calendar: Calendar = .current) -> NapRecoveryCredit {
        let uniqueNaps = deduplicated(naps)
        let sleepMinutes = overnightSleep.map { Int($0.asleepDuration / 60) } ?? 0
        let targetMinutes = Int(sleepTarget / 60)
        let sleepDeficit = max(0, targetMinutes - sleepMinutes)
        let sleepDebtMultiplier: Double

        if sleepDeficit >= 90 {
            sleepDebtMultiplier = 1.2
        } else if sleepDeficit <= 0 {
            sleepDebtMultiplier = 0.4
        } else {
            sleepDebtMultiplier = 0.7
        }

        var totalCredit = 0.0
        var factors: [RecoveryFactor] = []
        var notes: [String] = []

        for nap in uniqueNaps {
            let duration = nap.durationMinutes
            guard duration >= 10 else { continue }

            let efficiency: Double
            switch duration {
            case 10..<20:
                efficiency = 0.35
                notes.append("Short power nap logged.")
            case 20..<35:
                efficiency = 0.50
                notes.append("Useful short nap logged.")
            case 35..<60:
                efficiency = 0.35
                notes.append("Moderate nap credit applied.")
            case 60..<110:
                efficiency = 0.60
                notes.append("Long nap helped reduce fatigue.")
            case 110...180:
                efficiency = 0.45
                notes.append("Long nap logged; this can also signal fatigue.")
            default:
                efficiency = 0.20
            }

            let timing = nap.timingCategory == .unknown ? NapSession.timingCategory(for: nap.startDate, calendar: calendar) : nap.timingCategory
            let timingMultiplier: Double
            switch timing {
            case .morning:
                timingMultiplier = 0.8
            case .earlyAfternoon:
                timingMultiplier = 1.0
            case .lateAfternoon:
                timingMultiplier = 0.7
            case .evening:
                timingMultiplier = 0.4
                factors.append(.lateNapMayAffectSleep)
                notes.append("Late nap may affect bedtime.")
            case .unknown:
                timingMultiplier = 0.6
            }

            totalCredit += Double(duration) * efficiency * timingMultiplier * sleepDebtMultiplier
        }

        let capped = min(90, Int(totalCredit.rounded()))
        if capped > 0 {
            factors.append(.napImprovedRecovery)
        }

        return NapRecoveryCredit(
            totalCreditMinutes: Int(totalCredit.rounded()),
            cappedCreditMinutes: capped,
            factors: Array(Set(factors)),
            notes: Array(Set(notes))
        )
    }

    private func deduplicated(_ naps: [NapSession]) -> [NapSession] {
        naps.sorted { $0.startDate < $1.startDate }.reduce(into: [NapSession]()) { result, nap in
            guard let existing = result.first(where: { overlapRatio($0, nap) > 0.5 }) else {
                result.append(nap)
                return
            }

            if nap.source == .manual, existing.source != .manual, let index = result.firstIndex(where: { $0.id == existing.id }) {
                result[index] = nap
            }
        }
    }

    private func overlapRatio(_ lhs: NapSession, _ rhs: NapSession) -> Double {
        let overlap = max(0, min(lhs.endDate, rhs.endDate).timeIntervalSince(max(lhs.startDate, rhs.startDate)))
        let shortest = max(1, min(lhs.endDate.timeIntervalSince(lhs.startDate), rhs.endDate.timeIntervalSince(rhs.startDate)))
        return overlap / shortest
    }
}

struct AdvancedRecoveryScoreService {
    private let napCalculator = NapRecoveryCalculator()

    func calculateRecovery(
        sleep: ResolvedSleepSession?,
        naps: [NapSession],
        recentSleep: [ResolvedSleepSession],
        recentNaps: [NapSession],
        recentWorkouts: [WorkoutSession],
        settings: SleepSettings,
        calendar: Calendar = .current
    ) -> RecoveryScoreBreakdown {
        guard let sleep else {
            return RecoveryScoreBreakdown(
                finalScore: 55,
                label: .moderate,
                overnightSleepComponent: 55,
                sleepDebtComponent: 60,
                consistencyComponent: 60,
                qualityComponent: nil,
                napComponent: 0,
                trainingLoadComponent: trainingLoadScore(recentWorkouts),
                performanceTrendComponent: performanceTrendScore(recentWorkouts),
                confidence: .low,
                contributingFactors: [.missingSleepData]
            )
        }

        let targetMinutes = settings.targetSleepMinutes
        let sleepMinutes = Int(sleep.asleepDuration / 60)
        let napCredit = napCalculator.calculateNapCredit(naps: naps, overnightSleep: sleep, sleepTarget: TimeInterval(targetMinutes * 60), calendar: calendar)
        let overnight = overnightScore(minutes: sleepMinutes, targetMinutes: targetMinutes)
        let debt = sleepDebtScore(recentSleep: recentSleep, recentNaps: recentNaps, targetMinutes: targetMinutes, calendar: calendar)
        let consistency = consistencyScore(recentSleep: recentSleep, calendar: calendar)
        let quality = sleep.qualityRating.map { Double(min(100, max(20, $0 * 20))) }
        let nap = napScore(creditMinutes: napCredit.cappedCreditMinutes, sleepMinutes: sleepMinutes, targetMinutes: targetMinutes, hasNaps: !naps.isEmpty)
        let load = trainingLoadScore(recentWorkouts)
        let performance = performanceTrendScore(recentWorkouts)

        var weightedTotal = overnight * 0.30 + debt * 0.20 + consistency * 0.15 + nap * 0.10
        var weights = 0.75

        if let quality {
            weightedTotal += quality * 0.10
            weights += 0.10
        }

        if let load {
            weightedTotal += load * 0.10
            weights += 0.10
        }

        if let performance {
            weightedTotal += performance * 0.05
            weights += 0.05
        }

        var score = Int((weightedTotal / weights).rounded())
        if sleepMinutes < 300 {
            score = min(score, 62)
        }
        if napCredit.cappedCreditMinutes > 0, sleepMinutes < targetMinutes {
            score = min(100, score + min(8, napCredit.cappedCreditMinutes / 12))
        }
        if napCredit.factors.contains(.lateNapMayAffectSleep) {
            score = min(score, 74)
        }

        var factors: [RecoveryFactor] = napCredit.factors
        factors.append(sleepMinutes >= targetMinutes ? .sleptAboveTarget : .sleptBelowTarget)
        if debt < 55 { factors.append(.sleepDebtHigh) }
        factors.append(consistency >= 80 ? .sleepConsistent : .sleepInconsistent)
        if let quality {
            if quality <= 40 { factors.append(.poorSleepQuality) }
            if quality >= 80 { factors.append(.strongSleepQuality) }
        }
        if let load, load < 55 { factors.append(.highTrainingLoad) }
        if let performance {
            factors.append(performance < 55 ? .recentPerformanceDip : .recentPerformanceStrong)
        }
        if sleep.confidence == .low { factors.append(.lowConfidenceData) }

        let confidence: RecoveryConfidence
        if sleep.confidence == .high, recentSleep.count >= 5 {
            confidence = .high
        } else if recentSleep.count >= 2 {
            confidence = .medium
        } else {
            confidence = .low
        }

        return RecoveryScoreBreakdown(
            finalScore: max(0, min(100, score)),
            label: label(for: score),
            overnightSleepComponent: overnight,
            sleepDebtComponent: debt,
            consistencyComponent: consistency,
            qualityComponent: quality,
            napComponent: nap,
            trainingLoadComponent: load,
            performanceTrendComponent: performance,
            confidence: confidence,
            contributingFactors: Array(Set(factors))
        )
    }

    private func overnightScore(minutes: Int, targetMinutes: Int) -> Double {
        let deficit = max(0, targetMinutes - minutes)
        switch deficit {
        case 0:
            return 100
        case 1...30:
            return 85
        case 31...60:
            return 70
        case 61...90:
            return 55
        case 91...120:
            return 40
        default:
            return 20
        }
    }

    private func sleepDebtScore(recentSleep: [ResolvedSleepSession], recentNaps: [NapSession], targetMinutes: Int, calendar: Calendar) -> Double {
        let recent = recentSleep.prefix(7)
        guard !recent.isEmpty else { return 60 }

        let debt = recent.reduce(0) { total, sleep in
            let dayNaps = recentNaps.filter { calendar.isDate($0.startDate, inSameDayAs: sleep.sleepDate) }
            let credit = napCalculator.calculateNapCredit(naps: dayNaps, overnightSleep: sleep, sleepTarget: TimeInterval(targetMinutes * 60), calendar: calendar).cappedCreditMinutes
            return total + max(0, targetMinutes - Int(sleep.asleepDuration / 60) - credit)
        }

        switch debt {
        case 0...60:
            return 100
        case 61...120:
            return 85
        case 121...240:
            return 70
        case 241...360:
            return 50
        case 361...480:
            return 35
        default:
            return 20
        }
    }

    private func consistencyScore(recentSleep: [ResolvedSleepSession], calendar: Calendar) -> Double {
        let recent = Array(recentSleep.prefix(7))
        guard recent.count >= 3 else { return 65 }
        let starts = recent.map { minutesSinceStartOfDay($0.startDate, calendar: calendar) }
        let wakes = recent.map { minutesSinceStartOfDay($0.endDate, calendar: calendar) }
        let variation = max(circularRange(of: starts), circularRange(of: wakes))

        switch variation {
        case 0..<30:
            return 100
        case 30..<60:
            return 85
        case 60..<90:
            return 70
        case 90..<120:
            return 55
        default:
            return 35
        }
    }

    private func napScore(creditMinutes: Int, sleepMinutes: Int, targetMinutes: Int, hasNaps: Bool) -> Double {
        guard hasNaps else { return sleepMinutes >= targetMinutes ? 80 : 45 }
        let base = min(100, Double(creditMinutes) / 60 * 100)
        return sleepMinutes >= targetMinutes ? min(base, 45) : base
    }

    private func trainingLoadScore(_ workouts: [WorkoutSession]) -> Double? {
        let recent = workouts.prefix(7).filter(\.completed)
        guard !recent.isEmpty else { return nil }
        let workingSets = recent.reduce(0) { $0 + $1.exerciseLogs.flatMap(\.setLogs).filter { $0.completed && !$0.isWarmup }.count }
        let longSessions = recent.filter { ($0.durationMinutes ?? 0) >= 75 }.count
        let hardSessions = recent.filter { ($0.perceivedDifficulty ?? 0) >= 8 || ($0.sorenessLevel ?? 0) >= 4 }.count
        let loadPenalty = min(45, workingSets / 2 + longSessions * 6 + hardSessions * 8)
        return Double(max(35, 100 - loadPenalty))
    }

    private func performanceTrendScore(_ workouts: [WorkoutSession]) -> Double? {
        let recent = Array(workouts.prefix(6).filter(\.completed))
        guard recent.count >= 4 else { return nil }
        let volumes = recent.map { workout in
            workout.exerciseLogs.flatMap(\.setLogs).filter { $0.completed && !$0.isWarmup }.reduce(0) { $0 + ($1.weight * Double($1.reps)) }
        }
        let recentAverage = volumes.prefix(2).reduce(0, +) / Double(min(2, volumes.count))
        let baseline = volumes.dropFirst(2)
        guard !baseline.isEmpty else { return nil }
        let baselineAverage = baseline.reduce(0, +) / Double(baseline.count)
        if baselineAverage == 0 { return 65 }
        if recentAverage >= baselineAverage * 1.05 { return 85 }
        if recentAverage <= baselineAverage * 0.85 { return 45 }
        return 70
    }

    private func label(for score: Int) -> RecoveryLabel {
        switch score {
        case 85...100:
            return .strong
        case 70..<85:
            return .good
        case 55..<70:
            return .moderate
        case 40..<55:
            return .low
        default:
            return .veryLow
        }
    }

    private func minutesSinceStartOfDay(_ date: Date, calendar: Calendar) -> Int {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    private func circularRange(of values: [Int], minutesPerDay: Int = 1_440) -> Int {
        guard values.count > 1 else { return 0 }
        let sorted = values.map { (($0 % minutesPerDay) + minutesPerDay) % minutesPerDay }.sorted()
        let gaps = sorted.indices.map { index -> Int in
            let nextIndex = sorted.index(after: index)
            if nextIndex < sorted.endIndex {
                return sorted[nextIndex] - sorted[index]
            }
            return sorted[0] + minutesPerDay - sorted[index]
        }
        return minutesPerDay - (gaps.max() ?? 0)
    }
}

struct RecoveryCoachingRecommendationService {
    func buildRecommendation(recovery: RecoveryScoreBreakdown, plannedWorkout: WorkoutSession?, naps: [NapSession]) -> RecoveryCoachingRecommendation {
        let splitName = plannedWorkout?.splitNameSnapshot.components(separatedBy: " - ").first?.lowercased()
        let highSensitivity = splitName?.contains("leg") == true || splitName?.contains("full") == true
        let readiness: TrainingReadinessRecommendation

        switch recovery.finalScore {
        case 85...100:
            readiness = highSensitivity && recovery.contributingFactors.contains(.highTrainingLoad) ? .normal : .push
        case 70..<85:
            readiness = recovery.contributingFactors.contains(.sleepDebtHigh) ? .moderate : .normal
        case 55..<70:
            readiness = .moderate
        case 40..<55:
            readiness = highSensitivity ? .recovery : .light
        case 25..<40:
            readiness = .recovery
        default:
            readiness = .rest
        }

        let actions: [TrainingAdjustment]
        switch readiness {
        case .push:
            actions = [.trainAsPlanned]
        case .normal:
            actions = [.trainAsPlanned, .keepRepsInReserve]
        case .moderate:
            actions = [.reduceVolume, .avoidPR, .increaseRest]
        case .light:
            actions = [.reduceVolume, .reduceLoad, .focusTechnique]
        case .recovery:
            actions = [.focusTechnique, .increaseRest, .considerRest]
        case .rest:
            actions = [.considerRest, .deload]
        }

        let title: String
        let message: String
        if recovery.contributingFactors.contains(.napImprovedRecovery), let nap = naps.sorted(by: { $0.startDate > $1.startDate }).first {
            title = nap.durationMinutes >= 60 ? "Nap helped, stay controlled" : "Useful power nap"
            message = "Recovery is \(recovery.label.displayName.lowercased()). You slept below target, and your \(SleepScoringService.durationText(minutes: nap.durationMinutes)) nap helped slightly. Keep today practical and avoid forcing a PR."
        } else if recovery.contributingFactors.contains(.sleepDebtHigh) {
            title = "Sleep debt is building"
            message = "Recovery is \(recovery.label.displayName.lowercased()). Sleep debt is elevated, so reduce each main exercise by 1 working set and keep 1-2 reps in reserve."
        } else if highSensitivity, recovery.finalScore < 70 {
            title = "Keep heavy work controlled"
            message = "Recovery is \(recovery.label.displayName.lowercased()). For legs or full-body work, avoid max-effort compounds and extend rest times."
        } else {
            title = readinessTitle(for: readiness)
            message = "Recovery is \(recovery.label.displayName.lowercased()). \(defaultActionText(for: readiness))"
        }

        return RecoveryCoachingRecommendation(
            readiness: readiness,
            title: title,
            message: message,
            suggestedAdjustments: actions,
            reasons: recovery.contributingFactors,
            confidence: recovery.confidence
        )
    }

    private func readinessTitle(for readiness: TrainingReadinessRecommendation) -> String {
        switch readiness {
        case .push:
            return "Recovery looks strong"
        case .normal:
            return "Ready to train"
        case .moderate:
            return "Keep it controlled"
        case .light:
            return "Reduce intensity today"
        case .recovery:
            return "Recovery-focused session"
        case .rest:
            return "Rest may be useful"
        }
    }

    private func defaultActionText(for readiness: TrainingReadinessRecommendation) -> String {
        switch readiness {
        case .push:
            return "Train as planned and progress if warm-ups feel good."
        case .normal:
            return "Train normally, but let warm-ups decide how hard to push."
        case .moderate:
            return "Train as planned, but avoid extra volume."
        case .light:
            return "Use lighter loads or reduce total sets."
        case .recovery:
            return "Consider mobility, technique work, or a lighter session."
        case .rest:
            return "Taking a rest day could help your next session."
        }
    }
}

struct WorkoutPerformanceService {
    func calculatePerformanceScore(for workout: WorkoutSession) -> WorkoutPerformanceScore {
        calculatePerformanceScore(for: workout, recentWorkouts: [])
    }

    func calculatePerformanceScore(for workout: WorkoutSession, recentWorkouts: [WorkoutSession]) -> WorkoutPerformanceScore {
        guard workout.completed else {
            return WorkoutPerformanceScore(score: 25, label: .incomplete, contributingFactors: [.missedWorkout])
        }

        let completedSets = completedWorkingSets(in: workout)
        let plannedSets = max(1, workout.exerciseLogs.reduce(0) { $0 + max($1.targetSets, $1.setLogs.filter { !$0.isWarmup }.count) })
        let completionRatio = min(1, Double(completedSets.count) / Double(plannedSets))
        let volume = completedVolume(in: workout)
        let recentComparable = recentWorkouts
            .filter { $0.id != workout.id && $0.completed && baseSplitName($0.splitNameSnapshot) == baseSplitName(workout.splitNameSnapshot) }
            .prefix(5)
        let averageVolume = recentComparable.isEmpty ? nil : recentComparable.map { completedVolume(in: $0) }.reduce(0, +) / Double(recentComparable.count)

        var score = 45 + Int((completionRatio * 35).rounded())
        var factors: [WorkoutPerformanceFactor] = []

        if completionRatio >= 0.85 {
            factors.append(.completedMostSets)
        }

        if let averageVolume, averageVolume > 0 {
            if volume >= averageVolume * 1.08 {
                score += 10
                factors.append(.volumeAboveAverage)
            } else if volume <= averageVolume * 0.90 {
                score -= 12
                factors.append(.volumeBelowAverage)
            }
        }

        if progressedStrength(workout: workout, recentWorkouts: Array(recentComparable)) {
            score += 8
            factors.append(.strengthProgressed)
        }

        if repsDropped(workout: workout, recentWorkouts: Array(recentComparable)) {
            score -= 8
            factors.append(.repsDropped)
        }

        if let durationMinutes = workout.durationMinutes, durationMinutes < 25, completedSets.count >= 3 {
            score -= 5
            factors.append(.shorterThanUsual)
        }

        if let difficulty = workout.perceivedDifficulty, difficulty >= 8 {
            score -= 6
            factors.append(.highDifficulty)
        }

        if let energy = workout.energyLevel, energy >= 4 {
            score += 4
            factors.append(.highEnergy)
        }

        if let soreness = workout.sorenessLevel, soreness >= 4 {
            score -= 5
            factors.append(.highSoreness)
        }

        let clamped = min(100, max(0, score))
        return WorkoutPerformanceScore(score: clamped, label: label(for: clamped), contributingFactors: factors)
    }

    func completedVolume(in workout: WorkoutSession) -> Double {
        completedWorkingSets(in: workout).reduce(0) { $0 + ($1.weight * Double($1.reps)) }
    }

    func completionRatio(in workout: WorkoutSession) -> Double {
        let completed = completedWorkingSets(in: workout).count
        let planned = max(1, workout.exerciseLogs.reduce(0) { $0 + max($1.targetSets, $1.setLogs.filter { !$0.isWarmup }.count) })
        return min(1, Double(completed) / Double(planned))
    }

    func estimatedEffort(in workout: WorkoutSession) -> Double? {
        let rpes = workout.exerciseLogs.flatMap(\.setLogs).compactMap(\.rpe)
        if !rpes.isEmpty {
            return rpes.reduce(0, +) / Double(rpes.count)
        }
        return workout.perceivedDifficulty.map(Double.init)
    }

    private func completedWorkingSets(in workout: WorkoutSession) -> [SetLog] {
        workout.exerciseLogs.flatMap(\.setLogs).filter { $0.completed && !$0.isWarmup }
    }

    private func label(for score: Int) -> WorkoutPerformanceLabel {
        switch score {
        case 85...100:
            return .strong
        case 70..<85:
            return .good
        case 55..<70:
            return .moderate
        case 40..<55:
            return .reduced
        default:
            return .incomplete
        }
    }

    private func progressedStrength(workout: WorkoutSession, recentWorkouts: [WorkoutSession]) -> Bool {
        guard let currentBest = bestEstimatedOneRepMax(in: workout), currentBest > 0 else { return false }
        let priorBest = recentWorkouts.compactMap(bestEstimatedOneRepMax(in:)).max() ?? 0
        return priorBest > 0 && currentBest >= priorBest * 1.02
    }

    private func repsDropped(workout: WorkoutSession, recentWorkouts: [WorkoutSession]) -> Bool {
        let currentAverage = averageWorkingReps(in: workout)
        let priorAverage = recentWorkouts.compactMap(averageWorkingReps(in:)).first
        guard let currentAverage, let priorAverage, priorAverage > 0 else { return false }
        return currentAverage <= priorAverage * 0.88
    }

    private func bestEstimatedOneRepMax(in workout: WorkoutSession) -> Double? {
        workout.exerciseLogs
            .flatMap(\.setLogs)
            .filter { $0.completed && !$0.isWarmup }
            .map { $0.weight * (1 + Double($0.reps) / 30) }
            .max()
    }

    private func averageWorkingReps(in workout: WorkoutSession) -> Double? {
        let sets = completedWorkingSets(in: workout)
        guard !sets.isEmpty else { return nil }
        return Double(sets.map(\.reps).reduce(0, +)) / Double(sets.count)
    }

    private func baseSplitName(_ splitNameSnapshot: String) -> String {
        splitNameSnapshot.components(separatedBy: " - ").first ?? splitNameSnapshot
    }
}

struct SleepWorkoutCorrelationService {
    private let performanceService = WorkoutPerformanceService()
    private let scoring = SleepScoringService()

    func correlate(workouts: [WorkoutSession], sleepSessions: [ResolvedSleepSession], historicalSleepSessions: [SleepSession], settings: SleepSettings, calendar: Calendar = .current) -> [SleepWorkoutCorrelation] {
        let sortedWorkouts = workouts.sorted { $0.date > $1.date }
        return sortedWorkouts.map { workout in
            let workoutDay = calendar.startOfDay(for: workout.date)
            let sleepDate = calendar.date(byAdding: .day, value: -1, to: workoutDay) ?? workoutDay.addingTimeInterval(-86_400)
            let sleep = sleepSessions.first { calendar.isDate($0.sleepDate, inSameDayAs: sleepDate) }
            let performance = performanceService.calculatePerformanceScore(for: workout, recentWorkouts: sortedWorkouts.filter { $0.date < workout.date })
            let recoveryScore = sleep.map { scoring.score(for: $0, recentSessions: historicalSleepSessions, settings: settings) }

            return SleepWorkoutCorrelation(
                workoutID: workout.id,
                workoutDate: workout.date,
                splitName: baseSplitName(workout.splitNameSnapshot),
                resolvedSleepSession: sleep,
                sleepDuration: sleep?.asleepDuration,
                sleepQuality: sleep?.qualityRating,
                recoveryScore: recoveryScore,
                performanceScore: performance.score,
                volumeCompletedRatio: performanceService.completionRatio(in: workout),
                estimatedEffort: performanceService.estimatedEffort(in: workout),
                completedVolume: performanceService.completedVolume(in: workout)
            )
        }
    }

    private func baseSplitName(_ splitNameSnapshot: String) -> String {
        splitNameSnapshot.components(separatedBy: " - ").first ?? splitNameSnapshot
    }
}

struct SleepPerformanceBaselineService {
    func baseline(from correlations: [SleepWorkoutCorrelation]) -> SleepPerformanceBaseline? {
        let linked = correlations.filter { $0.sleepDuration != nil && $0.performanceScore != nil }
        guard !linked.isEmpty else { return nil }

        let averageSleep = linked.compactMap(\.sleepDuration).reduce(0, +) / Double(linked.count)
        let qualities = linked.compactMap(\.sleepQuality).map(Double.init)
        let recoveryScores = linked.compactMap(\.recoveryScore).map(Double.init)
        let performanceScores = linked.compactMap(\.performanceScore).map(Double.init)
        let bestRange = bestPerformanceRange(from: linked)
        let lowThreshold = lowPerformanceThreshold(from: linked)

        return SleepPerformanceBaseline(
            averageSleepDuration: averageSleep,
            averageSleepQuality: qualities.isEmpty ? nil : qualities.reduce(0, +) / Double(qualities.count),
            averageRecoveryScore: recoveryScores.isEmpty ? 0 : recoveryScores.reduce(0, +) / Double(recoveryScores.count),
            averagePerformanceScore: performanceScores.isEmpty ? 0 : performanceScores.reduce(0, +) / Double(performanceScores.count),
            bestPerformanceSleepRange: bestRange,
            lowPerformanceSleepThreshold: lowThreshold
        )
    }

    private func bestPerformanceRange(from correlations: [SleepWorkoutCorrelation]) -> ClosedRange<TimeInterval>? {
        let buckets: [(range: ClosedRange<TimeInterval>, items: [SleepWorkoutCorrelation])] = [
            (0...(6 * 3_600), correlations.filter { ($0.sleepDuration ?? 0) < 6 * 3_600 }),
            ((6 * 3_600)...(7 * 3_600), correlations.filter { ($0.sleepDuration ?? 0) >= 6 * 3_600 && ($0.sleepDuration ?? 0) < 7 * 3_600 }),
            ((7 * 3_600)...(8 * 3_600), correlations.filter { ($0.sleepDuration ?? 0) >= 7 * 3_600 && ($0.sleepDuration ?? 0) < 8 * 3_600 }),
            ((8 * 3_600)...(12 * 3_600), correlations.filter { ($0.sleepDuration ?? 0) >= 8 * 3_600 })
        ]

        return buckets
            .filter { $0.items.count >= 2 }
            .max { averagePerformance($0.items) < averagePerformance($1.items) }?
            .range
    }

    private func lowPerformanceThreshold(from correlations: [SleepWorkoutCorrelation]) -> TimeInterval? {
        let low = correlations.filter { ($0.performanceScore ?? 100) < 55 }.compactMap(\.sleepDuration)
        guard low.count >= 2 else { return nil }
        return low.reduce(0, +) / Double(low.count)
    }

    private func averagePerformance(_ items: [SleepWorkoutCorrelation]) -> Double {
        let scores = items.compactMap(\.performanceScore)
        guard !scores.isEmpty else { return 0 }
        return Double(scores.reduce(0, +)) / Double(scores.count)
    }
}

struct RecoveryInterventionService {
    func interventions(summaries: [SleepSummary], correlations: [SleepWorkoutCorrelation], workouts: [WorkoutSession], settings: SleepSettings, calendar: Calendar = .current) -> [RecoveryIntervention] {
        guard settings.coachingPreferences.deloadSuggestionsEnabled else { return [] }

        let recentSummaries = Array(summaries.prefix(7))
        let sleepDebt = SleepScoringService().sleepDebtMinutes(summaries: recentSummaries, targetMinutes: settings.targetSleepMinutes)
        let poorNights = recentSummaries.filter { $0.primarySession != nil && ($0.totalSleepMinutes < 360 || settings.targetSleepMinutes - $0.totalSleepMinutes >= 90) }.count
        let lowRecoveryDays = recentSummaries.filter { ($0.sleepScore ?? 100) < 55 }.count
        let recentWorkouts = workouts.filter { workout in
            let days = calendar.dateComponents([.day], from: workout.date, to: .now).day ?? 99
            return days < 7
        }
        let performanceDip = hasPerformanceDip(correlations: correlations)
        let highSoreness = recentWorkouts.contains { ($0.sorenessLevel ?? 0) >= 4 }

        var signals = 0
        if poorNights >= 3 { signals += 1 }
        if sleepDebt >= 180 { signals += 1 }
        if lowRecoveryDays >= 2 { signals += 1 }
        if performanceDip { signals += 1 }
        if highSoreness { signals += 1 }
        if recentWorkouts.count >= 4 { signals += 1 }

        if signals >= 4 {
            return [
                RecoveryIntervention(
                    type: .deloadWeek,
                    title: "Deload may help",
                    message: "Sleep and performance have both trended down recently. A lighter week could help recovery and progress.",
                    severity: .important,
                    basedOn: [.sevenDaySleepDebt, .recentPerformance, .trainingFrequency]
                )
            ]
        }

        if signals >= 3 {
            return [
                RecoveryIntervention(
                    type: .restDay,
                    title: "Recovery is trending low",
                    message: "Consider reducing volume today or taking a recovery-focused session.",
                    severity: .caution,
                    basedOn: [.lastNightSleep, .sevenDaySleepDebt, .recentPerformance]
                )
            ]
        }

        if poorNights >= 2 || sleepDebt >= 180 {
            return [
                RecoveryIntervention(
                    type: .reduceVolume,
                    title: "Reduce volume today",
                    message: "Recovery has been lower this week. Consider dropping 1 set from each main exercise.",
                    severity: .caution,
                    basedOn: [.sevenDaySleepDebt, .recoveryScore]
                )
            ]
        }

        if recentSummaries.first?.totalSleepMinutes ?? settings.targetSleepMinutes < 360 {
            return [
                RecoveryIntervention(
                    type: .avoidPR,
                    title: "Avoid max effort today",
                    message: "Sleep was low and recovery is not fully back. Keep sets controlled and leave 1-2 reps in reserve.",
                    severity: .neutral,
                    basedOn: [.lastNightSleep]
                )
            ]
        }

        return []
    }

    private func hasPerformanceDip(correlations: [SleepWorkoutCorrelation]) -> Bool {
        let scores = correlations.compactMap(\.performanceScore)
        guard scores.count >= 4 else { return false }
        let recent = Array(scores.prefix(2))
        let baseline = Array(scores.dropFirst(2).prefix(6))
        guard !baseline.isEmpty else { return false }
        let recentAverage = Double(recent.reduce(0, +)) / Double(recent.count)
        let baselineAverage = Double(baseline.reduce(0, +)) / Double(baseline.count)
        return recentAverage <= baselineAverage * 0.85
    }
}

struct AdaptiveTrainingRecommendationService {
    func recommendation(sleep: SleepSummary, summaries: [SleepSummary], correlations: [SleepWorkoutCorrelation], interventions: [RecoveryIntervention], settings: SleepSettings) -> AdaptiveTrainingRecommendation {
        guard settings.coachingPreferences.adaptiveWorkoutRecommendationsEnabled else {
            return AdaptiveTrainingRecommendation(
                level: .normal,
                title: "Adaptive coaching is off",
                message: "Follow your planned session and use warm-ups to decide intensity.",
                suggestedActions: [.trainAsPlanned],
                confidence: .low,
                basedOn: []
            )
        }

        guard sleep.primarySession != nil else {
            return AdaptiveTrainingRecommendation(
                level: .normal,
                title: "Add last night's sleep",
                message: "Add last night's sleep to improve today's workout guidance.",
                suggestedActions: [.trainAsPlanned],
                confidence: .low,
                basedOn: [.recentPerformance]
            )
        }

        if sleep.sourceConflict != nil {
            return AdaptiveTrainingRecommendation(
                level: .moderate,
                title: "Keep it controlled",
                message: "Sleep data is unclear, so today's recommendation is based mostly on recent training.",
                suggestedActions: [.trainAsPlanned, .keepRepsInReserve],
                confidence: .low,
                basedOn: [.sleepSourceConflict, .recentPerformance]
            )
        }

        if interventions.contains(where: { $0.type == .deloadWeek }) {
            return AdaptiveTrainingRecommendation(
                level: .rest,
                title: "Rest may be useful",
                message: "Recovery has been low for several days. Taking a rest day could help your next session.",
                suggestedActions: [.considerRest, .deload],
                confidence: .medium,
                basedOn: [.sevenDaySleepDebt, .recentPerformance, .trainingFrequency]
            )
        }

        if interventions.contains(where: { $0.type == .restDay }) {
            return AdaptiveTrainingRecommendation(
                level: .recovery,
                title: "Recovery-focused session recommended",
                message: "Sleep and recent performance are trending low. Consider mobility, technique work, or a lighter session.",
                suggestedActions: [.focusTechnique, .reduceLoad, .considerRest],
                confidence: .medium,
                basedOn: [.lastNightSleep, .recentPerformance, .recoveryScore]
            )
        }

        let debt = SleepScoringService().sleepDebtMinutes(summaries: Array(summaries.prefix(7)), targetMinutes: settings.targetSleepMinutes)
        let poorNights = summaries.prefix(7).filter { $0.primarySession != nil && ($0.totalSleepMinutes < 360 || settings.targetSleepMinutes - $0.totalSleepMinutes >= 90) }.count
        let performanceDip = hasPerformanceDip(correlations: correlations)

        if poorNights >= 3 && performanceDip {
            return AdaptiveTrainingRecommendation(
                level: .recovery,
                title: "Recovery has been trending low",
                message: "Consider reducing volume today or taking a recovery-focused session.",
                suggestedActions: [.reduceVolume, .focusTechnique, .increaseRest],
                confidence: .medium,
                basedOn: [.lastNightSleep, .sevenDaySleepDebt, .recentPerformance]
            )
        }

        if sleep.totalSleepMinutes < 360 || (sleep.qualityRating ?? 5) <= 2 || debt >= 180 {
            return AdaptiveTrainingRecommendation(
                level: .light,
                title: "Reduce intensity today",
                message: "Sleep was low and recovery is down. Use lighter loads or reduce total sets.",
                suggestedActions: [.reduceVolume, .avoidPR, .increaseRest],
                confidence: .medium,
                basedOn: [.lastNightSleep, .sleepQuality, .sevenDaySleepDebt]
            )
        }

        if settings.targetSleepMinutes - sleep.totalSleepMinutes >= 30 {
            return AdaptiveTrainingRecommendation(
                level: .moderate,
                title: "Keep it controlled",
                message: "Sleep was slightly below target. Train as planned, but avoid adding extra sets.",
                suggestedActions: [.trainAsPlanned, .keepRepsInReserve],
                confidence: .medium,
                basedOn: [.lastNightSleep, .recoveryScore]
            )
        }

        if sleep.totalSleepMinutes >= settings.targetSleepMinutes, (sleep.qualityRating ?? 4) >= 4, (sleep.sleepScore ?? 0) >= 85 {
            return AdaptiveTrainingRecommendation(
                level: .push,
                title: "Recovery looks strong",
                message: "Sleep and recent performance are trending well. Train as planned and progress if warm-ups feel good.",
                suggestedActions: [.trainAsPlanned],
                confidence: .medium,
                basedOn: [.lastNightSleep, .sleepQuality, .recoveryScore]
            )
        }

        return AdaptiveTrainingRecommendation(
            level: .normal,
            title: "Ready to train",
            message: "Sleep was close to target. Follow your planned session.",
            suggestedActions: [.trainAsPlanned],
            confidence: .medium,
            basedOn: [.lastNightSleep, .recoveryScore]
        )
    }

    private func hasPerformanceDip(correlations: [SleepWorkoutCorrelation]) -> Bool {
        let scores = correlations.compactMap(\.performanceScore)
        guard scores.count >= 4 else { return false }
        let recent = Double(scores.prefix(2).reduce(0, +)) / Double(min(2, scores.count))
        let baselineItems = Array(scores.dropFirst(2).prefix(6))
        guard !baselineItems.isEmpty else { return false }
        let baseline = Double(baselineItems.reduce(0, +)) / Double(baselineItems.count)
        return recent <= baseline * 0.85
    }
}

struct SleepCoachingInsightService {
    private let baselineService = SleepPerformanceBaselineService()

    func generateInsights(correlations: [SleepWorkoutCorrelation], sleepSummaries: [SleepSummary], interventions: [RecoveryIntervention], settings: SleepSettings) -> [SleepCoachingInsight] {
        guard settings.coachingPreferences.sleepCoachingInsightsEnabled else { return [] }

        let linked = correlations.filter { $0.resolvedSleepSession != nil && $0.performanceScore != nil }
        let trackedSleep = sleepSummaries.filter { $0.primarySession != nil }

        if trackedSleep.count < 3 {
            return [
                SleepCoachingInsight(
                    type: .notEnoughData,
                    title: "Keep tracking sleep and workouts",
                    message: "Once you have more history, the app can show how your sleep affects performance.",
                    confidence: .low,
                    severity: .neutral,
                    basedOn: []
                )
            ]
        }

        if correlations.isEmpty {
            return [
                SleepCoachingInsight(
                    type: .missingWorkoutData,
                    title: "Log workouts to unlock patterns",
                    message: "Sleep tracking is active. Log workouts to unlock sleep-performance insights.",
                    confidence: .low,
                    severity: .neutral,
                    relatedSleepSessionIDs: trackedSleep.compactMap(\.primarySession?.id),
                    basedOn: [.lastNightSleep]
                )
            ]
        }

        var insights: [SleepCoachingInsight] = []

        if settings.coachingPreferences.sleepPerformanceInsightsEnabled {
            insights.append(contentsOf: performanceInsights(from: linked, settings: settings))
            insights.append(contentsOf: splitSensitivityInsights(from: linked))
        }

        insights.append(contentsOf: sleepTrendInsights(from: sleepSummaries, settings: settings))

        if settings.coachingPreferences.deloadSuggestionsEnabled, let intervention = interventions.first(where: { $0.type == .deloadWeek || $0.type == .restDay }) {
            insights.append(
                SleepCoachingInsight(
                    type: .deloadSuggested,
                    title: intervention.title,
                    message: intervention.message,
                    confidence: .medium,
                    severity: intervention.severity,
                    basedOn: intervention.basedOn
                )
            )
        }

        if insights.isEmpty {
            insights.append(
                SleepCoachingInsight(
                    type: .notEnoughData,
                    title: "Patterns are building",
                    message: "Keep tracking sleep and workouts. The app will show stronger personalised coaching when there is more linked history.",
                    confidence: .low,
                    severity: .neutral,
                    relatedWorkoutIDs: correlations.map(\.workoutID),
                    relatedSleepSessionIDs: trackedSleep.compactMap(\.primarySession?.id),
                    basedOn: [.lastNightSleep, .recentPerformance]
                )
            )
        }

        return Array(insights.prefix(5))
    }

    private func performanceInsights(from linked: [SleepWorkoutCorrelation], settings: SleepSettings) -> [SleepCoachingInsight] {
        guard linked.count >= 4 else { return [] }
        var insights: [SleepCoachingInsight] = []
        let strongSleep = linked.filter { ($0.sleepDuration ?? 0) >= 7 * 3_600 }
        let shortSleep = linked.filter { ($0.sleepDuration ?? 0) < 6.5 * 3_600 }

        if strongSleep.count >= 2, shortSleep.count >= 2 {
            let strongAverage = averagePerformance(strongSleep)
            let shortAverage = averagePerformance(shortSleep)
            if strongAverage - shortAverage >= 10 {
                insights.append(
                    SleepCoachingInsight(
                        type: .sleepImprovesPerformance,
                        title: "Better sleep, stronger sessions",
                        message: "Your recent workouts have been stronger after 7h+ of sleep.",
                        confidence: linked.count >= 8 ? .high : .medium,
                        severity: .positive,
                        relatedWorkoutIDs: strongSleep.map(\.workoutID),
                        relatedSleepSessionIDs: strongSleep.compactMap(\.resolvedSleepSession?.id),
                        basedOn: [.lastNightSleep, .recentPerformance]
                    )
                )
            }
        }

        let poorSleepWorkouts = linked.filter { correlation in
            guard let duration = correlation.sleepDuration else { return false }
            return duration < 6 * 3_600 || TimeInterval(settings.targetSleepMinutes * 60) - duration >= 90 * 60
        }

        if poorSleepWorkouts.count >= 2 {
            let recentAverage = averageVolume(linked)
            let poorAverage = averageVolume(poorSleepWorkouts)
            if recentAverage > 0, poorAverage <= recentAverage * 0.90 {
                insights.append(
                    SleepCoachingInsight(
                        type: .poorSleepReducesPerformance,
                        title: "Low sleep may be reducing volume",
                        message: "Your recent low-sleep workouts had less completed volume than usual.",
                        confidence: .medium,
                        severity: .caution,
                        relatedWorkoutIDs: poorSleepWorkouts.map(\.workoutID),
                        relatedSleepSessionIDs: poorSleepWorkouts.compactMap(\.resolvedSleepSession?.id),
                        basedOn: [.lastNightSleep, .recentPerformance]
                    )
                )
            }
        }

        if let baseline = baselineService.baseline(from: linked), let range = baseline.bestPerformanceSleepRange, linked.count >= 8 {
            insights.append(
                SleepCoachingInsight(
                    type: .goodSleepBeforeStrongSession,
                    title: "Your best sleep window is emerging",
                    message: "Your best recent sessions usually happen after \(rangeText(range)) of sleep.",
                    confidence: .high,
                    severity: .positive,
                    relatedWorkoutIDs: linked.map(\.workoutID),
                    relatedSleepSessionIDs: linked.compactMap(\.resolvedSleepSession?.id),
                    basedOn: [.lastNightSleep, .recentPerformance]
                )
            )
        }

        return insights
    }

    private func splitSensitivityInsights(from linked: [SleepWorkoutCorrelation]) -> [SleepCoachingInsight] {
        let grouped = Dictionary(grouping: linked, by: { $0.splitName ?? "Workout" })
        guard grouped.count > 1 else { return [] }

        let candidates = grouped.compactMap { splitName, items -> (String, Double, [SleepWorkoutCorrelation])? in
            guard items.count >= 3 else { return nil }
            let poor = items.filter { ($0.sleepDuration ?? 0) < 6.5 * 3_600 }
            let normal = items.filter { ($0.sleepDuration ?? 0) >= 6.5 * 3_600 }
            guard !poor.isEmpty, !normal.isEmpty else { return nil }
            return (splitName, averagePerformance(normal) - averagePerformance(poor), items)
        }

        guard let sensitive = candidates.max(by: { $0.1 < $1.1 }), sensitive.1 >= 10 else { return [] }
        return [
            SleepCoachingInsight(
                type: .poorSleepReducesPerformance,
                title: "\(sensitive.0) days may need more recovery",
                message: "Your \(sensitive.0.lowercased()) sessions appear more affected by short sleep.",
                confidence: .medium,
                severity: .caution,
                relatedWorkoutIDs: sensitive.2.map(\.workoutID),
                relatedSleepSessionIDs: sensitive.2.compactMap(\.resolvedSleepSession?.id),
                basedOn: [.lastNightSleep, .recentPerformance]
            )
        ]
    }

    private func sleepTrendInsights(from summaries: [SleepSummary], settings: SleepSettings) -> [SleepCoachingInsight] {
        let recent = Array(summaries.prefix(7))
        guard recent.filter({ $0.primarySession != nil }).count >= 5 else { return [] }

        var insights: [SleepCoachingInsight] = []
        let debt = SleepScoringService().sleepDebtMinutes(summaries: recent, targetMinutes: settings.targetSleepMinutes)
        let scoreValues = recent.compactMap(\.sleepScore)
        let recoveryLow = scoreValues.contains { $0 < 70 }

        if debt > 180, recoveryLow {
            insights.append(
                SleepCoachingInsight(
                    type: .sleepDebtAccumulating,
                    title: "Sleep debt is building",
                    message: "You are \(SleepScoringService.durationText(minutes: debt)) below your target across the last week. Consider keeping today's session moderate.",
                    confidence: .medium,
                    severity: .caution,
                    relatedSleepSessionIDs: recent.compactMap(\.primarySession?.id),
                    basedOn: [.sevenDaySleepDebt, .recoveryScore]
                )
            )
        }

        let durations = recent.compactMap { $0.primarySession == nil ? nil : $0.totalSleepMinutes }
        if durations.count >= 3 {
            let latestThree = Array(durations.prefix(3))
            if latestThree[0] > latestThree[1], latestThree[1] > latestThree[2], (scoreValues.first ?? 0) >= 70 {
                insights.append(
                    SleepCoachingInsight(
                        type: .recoveryTrendImproving,
                        title: "Recovery is improving",
                        message: "Sleep has been trending up and your recovery score is stabilising.",
                        confidence: .medium,
                        severity: .positive,
                        relatedSleepSessionIDs: recent.compactMap(\.primarySession?.id),
                        basedOn: [.lastNightSleep, .recoveryScore]
                    )
                )
            }
        }

        if let consistency = SleepAnalyticsService().consistencySummary(from: recent.compactMap(\.primarySession)).approximateVariationMinutes, consistency > 90 {
            insights.append(
                SleepCoachingInsight(
                    type: .bedtimeConsistencyOpportunity,
                    title: "Bedtime consistency opportunity",
                    message: "Your sleep timing has varied recently. A steadier window may make recovery guidance more reliable.",
                    confidence: .low,
                    severity: .neutral,
                    relatedSleepSessionIDs: recent.compactMap(\.primarySession?.id),
                    basedOn: [.sleepConsistency]
                )
            )
        }

        return insights
    }

    private func averagePerformance(_ items: [SleepWorkoutCorrelation]) -> Double {
        let scores = items.compactMap(\.performanceScore)
        guard !scores.isEmpty else { return 0 }
        return Double(scores.reduce(0, +)) / Double(scores.count)
    }

    private func averageVolume(_ items: [SleepWorkoutCorrelation]) -> Double {
        guard !items.isEmpty else { return 0 }
        return items.map(\.completedVolume).reduce(0, +) / Double(items.count)
    }

    private func rangeText(_ range: ClosedRange<TimeInterval>) -> String {
        let lower = Int(range.lowerBound / 3_600)
        let upper = Int(range.upperBound / 3_600)
        if upper >= 12 {
            return "\(lower)h+"
        }
        return "\(lower)-\(upper)h"
    }
}

struct SleepScoringService {
    private let resolver = SleepSourceResolver()
    private let advancedRecovery = AdvancedRecoveryScoreService()

    func summaries(from sessions: [SleepSession], settings: SleepSettings, days: Int = 7, calendar: Calendar = .current) -> [SleepSummary] {
        summaries(from: sessions, naps: [], workouts: [], settings: settings, days: days, calendar: calendar)
    }

    func summaries(from sessions: [SleepSession], naps: [NapSession], workouts: [WorkoutSession], settings: SleepSettings, days: Int = 7, calendar: Calendar = .current) -> [SleepSummary] {
        let completed = sessions.filter { $0.status == .completed }
        let grouped = Dictionary(grouping: completed, by: { SleepCalendar.nightDate(for: $0.confirmedSleepStartAt, calendar: calendar) })
        let start = calendar.startOfDay(for: Date.now)

        return (0..<days).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: start) else { return nil }
            let nightly = grouped[date] ?? []
            return summary(for: date, sessions: nightly, allSessions: completed, naps: naps, workouts: workouts, settings: settings, calendar: calendar)
        }
    }

    func latestSummary(from sessions: [SleepSession], settings: SleepSettings) -> SleepSummary {
        latestSummary(from: sessions, naps: [], workouts: [], settings: settings)
    }

    func latestSummary(from sessions: [SleepSession], naps: [NapSession], workouts: [WorkoutSession], settings: SleepSettings) -> SleepSummary {
        summaries(from: sessions, naps: naps, workouts: workouts, settings: settings, days: 14).first { $0.primarySession != nil }
            ?? Self.emptySummary()
    }

    static func emptySummary(calendar: Calendar = .current) -> SleepSummary {
        SleepSummary(
            date: SleepCalendar.nightDate(for: .now, calendar: calendar),
            primarySession: nil,
            totalSleepMinutes: 0,
            timeInBedMinutes: nil,
            qualityRating: nil,
            source: nil,
            sleepScore: nil,
            recoveryState: .unknown,
            confidence: .low,
            sourceConflict: nil,
            stageBreakdown: nil,
            napCreditMinutes: 0,
            recoveryBreakdown: nil
        )
    }

    func score(for session: SleepSession, recentSessions: [SleepSession], settings: SleepSettings) -> Int {
        score(
            durationMinutes: session.durationMinutes,
            qualityRating: session.qualityRating,
            confidence: session.confidence,
            source: session.source,
            recentSessions: recentSessions,
            settings: settings
        )
    }

    func score(for resolvedSession: ResolvedSleepSession, recentSessions: [SleepSession], settings: SleepSettings) -> Int {
        score(
            durationMinutes: Int(resolvedSession.asleepDuration / 60),
            qualityRating: resolvedSession.qualityRating,
            confidence: resolvedSession.confidence,
            source: resolvedSession.dataSource,
            recentSessions: recentSessions,
            settings: settings
        )
    }

    private func score(
        durationMinutes: Int,
        qualityRating: Int?,
        confidence: SleepConfidence,
        source: SleepSource,
        recentSessions: [SleepSession],
        settings: SleepSettings
    ) -> Int {
        let duration = durationScore(minutes: durationMinutes, targetMinutes: settings.targetSleepMinutes)
        let quality = qualityScore(qualityRating)
        let confidence = confidenceScore(confidence, source: source)
        let completedCount = recentSessions.filter { $0.status == .completed }.count

        if completedCount < 3 {
            return Int((Double(duration) * 0.60 + Double(quality) * 0.30 + Double(confidence) * 0.10).rounded())
        }

        let consistency = consistencyScore(from: recentSessions)
        return Int((Double(duration) * 0.50 + Double(quality) * 0.25 + Double(consistency) * 0.15 + Double(confidence) * 0.10).rounded())
    }

    func recoveryState(for score: Int?) -> RecoveryState {
        guard let score else { return .unknown }
        switch score {
        case 85...100:
            return .high
        case 70..<85:
            return .good
        case 55..<70:
            return .moderate
        case 40..<55:
            return .low
        default:
            return .veryLow
        }
    }

    func durationScore(minutes: Int, targetMinutes: Int) -> Int {
        let target = max(360, targetMinutes)
        let ratio = Double(minutes) / Double(target)

        if ratio >= 1 { return 100 }
        if minutes >= 420 { return 85 }
        if minutes >= 360 { return 65 }
        if minutes >= 300 { return 45 }
        return 25
    }

    func consistencyScore(from sessions: [SleepSession], calendar: Calendar = .current) -> Int {
        let recent = sessions
            .filter { $0.status == .completed }
            .sorted { $0.confirmedSleepStartAt > $1.confirmedSleepStartAt }
            .prefix(7)

        guard recent.count >= 3 else { return 65 }

        let bedMinutes = recent.map { minutesSinceStartOfDay($0.confirmedSleepStartAt, calendar: calendar) }
        let wakeMinutes = recent.map { minutesSinceStartOfDay($0.wakeAt, calendar: calendar) }
        let variation = max(circularRange(of: bedMinutes), circularRange(of: wakeMinutes))

        if variation <= 45 { return 90 }
        if variation <= 90 { return 70 }
        return 45
    }

    func qualityScore(_ quality: Int?) -> Int {
        guard let quality else { return 60 }
        return min(100, max(20, quality * 20))
    }

    func confidenceScore(_ confidence: SleepConfidence, source: SleepSource) -> Int {
        switch (confidence, source) {
        case (.high, .appleHealth):
            return 90
        case (.high, .merged):
            return 88
        case (.medium, .appleHealth), (.estimatedConfirmed, .inAppTimer):
            return 80
        case (.medium, .manual):
            return 70
        case (.low, _):
            return 45
        default:
            return 65
        }
    }

    func sleepDebtMinutes(summaries: [SleepSummary], targetMinutes: Int) -> Int {
        summaries.filter { $0.primarySession != nil }.reduce(0) { total, summary in
            total + max(0, targetMinutes - summary.totalSleepMinutes)
        }
    }

    func consistencyText(summaries: [SleepSummary]) -> String {
        let tracked = summaries.compactMap(\.primarySession)
        guard tracked.count >= 3 else {
            return "Track a few more nights to unlock consistency insights."
        }

        let wakeVariation = circularRange(of: tracked.map { minutesSinceStartOfDay($0.wakeAt) })
        if wakeVariation < 45 {
            return "Sleep consistency is strong this week."
        }

        return "Sleep consistency is moderate. Your wake time varies by around \(Self.durationText(minutes: wakeVariation)) across the week."
    }

    func averageBedtime(sessions: [SleepSession]) -> Date? {
        averageClockTime(sessions.map(\.confirmedSleepStartAt))
    }

    func averageWakeTime(sessions: [SleepSession]) -> Date? {
        averageClockTime(sessions.map(\.wakeAt))
    }

    static func durationText(minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        if hours <= 0 {
            return "\(mins)m"
        }
        if mins == 0 {
            return "\(hours)h"
        }
        return "\(hours)h \(mins)m"
    }

    private func summary(for date: Date, sessions: [SleepSession], allSessions: [SleepSession], naps: [NapSession], workouts: [WorkoutSession], settings: SleepSettings, calendar: Calendar) -> SleepSummary {
        let primary = primarySession(from: sessions)
        let resolved = resolver.resolvedSession(for: date, sessions: allSessions, settings: settings)
        let recentSleep = resolver.resolvedSessions(from: allSessions, settings: settings, days: 28, calendar: calendar)
        let dayNaps = naps.filter { calendar.isDate($0.startDate, inSameDayAs: date) }
        let recoveryBreakdown = advancedRecovery.calculateRecovery(
            sleep: resolved,
            naps: dayNaps,
            recentSleep: recentSleep,
            recentNaps: naps,
            recentWorkouts: workouts,
            settings: settings,
            calendar: calendar
        )
        let total = resolved.map { Int($0.asleepDuration / 60) } ?? primary?.durationMinutes ?? 0
        let sleepScore: Int?
        if resolved != nil {
            sleepScore = recoveryBreakdown.finalScore
        } else if let primary {
            sleepScore = score(for: primary, recentSessions: allSessions, settings: settings)
        } else {
            sleepScore = nil
        }
        let inBed = resolved?.inBedDuration.map { Int($0 / 60) } ?? primary.flatMap { session -> Int? in
            guard let started = session.sleepModeStartedAt else { return nil }
            return SleepSessionRepository().durationMinutes(start: started, wake: session.wakeAt)
        }

        return SleepSummary(
            date: date,
            primarySession: primary,
            totalSleepMinutes: total,
            timeInBedMinutes: inBed,
            qualityRating: resolved?.qualityRating ?? primary?.qualityRating,
            source: resolved?.dataSource ?? primary?.source,
            sleepScore: sleepScore,
            recoveryState: recoveryState(for: sleepScore),
            confidence: resolved?.confidence ?? primary?.confidence ?? .low,
            sourceConflict: resolved?.conflict,
            stageBreakdown: resolved?.stageBreakdown,
            napCreditMinutes: recoveryBreakdown.contributingFactors.contains(.napImprovedRecovery) ? NapRecoveryCalculator().calculateNapCredit(naps: dayNaps, overnightSleep: resolved, sleepTarget: TimeInterval(settings.targetSleepMinutes * 60), calendar: calendar).cappedCreditMinutes : 0,
            recoveryBreakdown: resolved == nil ? nil : recoveryBreakdown
        )
    }

    private func primarySession(from sessions: [SleepSession]) -> SleepSession? {
        sessions.sorted { lhs, rhs in
            if lhs.source == .appleHealth, rhs.source != .appleHealth { return true }
            if rhs.source == .appleHealth, lhs.source != .appleHealth { return false }
            return lhs.durationMinutes > rhs.durationMinutes
        }.first
    }

    private func minutesSinceStartOfDay(_ date: Date, calendar: Calendar = .current) -> Int {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    private func range(of values: [Int]) -> Int {
        guard let min = values.min(), let max = values.max() else { return 0 }
        return max - min
    }

    func circularRange(of values: [Int], minutesPerDay: Int = 1_440) -> Int {
        guard values.count > 1 else { return 0 }
        let sorted = values.map { (($0 % minutesPerDay) + minutesPerDay) % minutesPerDay }.sorted()
        let gaps = sorted.indices.map { index -> Int in
            let nextIndex = sorted.index(after: index)
            if nextIndex < sorted.endIndex {
                return sorted[nextIndex] - sorted[index]
            }
            return sorted[0] + minutesPerDay - sorted[index]
        }
        return minutesPerDay - (gaps.max() ?? 0)
    }

    private func averageClockTime(_ dates: [Date], calendar: Calendar = .current) -> Date? {
        guard !dates.isEmpty else { return nil }
        let minutes = dates.map { minutesSinceStartOfDay($0, calendar: calendar) }
        let average = minutes.reduce(0, +) / minutes.count
        return calendar.date(bySettingHour: average / 60, minute: average % 60, second: 0, of: .now)
    }
}

struct SleepAnalyticsInputSignature: Equatable {
    private struct SessionFingerprint: Equatable {
        let id: UUID
        let status: SleepSessionStatus
        let updatedAt: Date
        let start: Date
        let wake: Date
        let durationMinutes: Int
        let qualityRating: Int?
        let source: SleepSource
        let confidence: SleepConfidence
    }

    private struct WorkoutFingerprint: Equatable {
        let id: UUID
        let date: Date
        let completed: Bool
        let durationMinutes: Int?
        let perceivedDifficulty: Int?
        let energyLevel: Int?
        let sorenessLevel: Int?
    }

    private struct NapFingerprint: Equatable {
        let id: UUID
        let start: Date
        let end: Date
        let durationMinutes: Int
        let qualityRating: Int?
        let source: NapSource
        let updatedAt: Date
    }

    private struct SettingsFingerprint: Equatable {
        let targetSleepMinutes: Int
        let recoveryCoachingEnabled: Bool
        let preferredSource: PreferredSleepSource
        let coachingPreferences: SleepCoachingPreferences

        init(settings: SleepSettings) {
            targetSleepMinutes = settings.targetSleepMinutes
            recoveryCoachingEnabled = settings.recoveryCoachingEnabled
            preferredSource = settings.preferredSource
            coachingPreferences = settings.coachingPreferences
        }
    }

    let sessionLimit: Int
    let workoutLimit: Int
    private let settings: SettingsFingerprint
    private let sessions: [SessionFingerprint]
    private let workouts: [WorkoutFingerprint]
    private let naps: [NapFingerprint]

    init(sessions: [SleepSession], naps: [NapSession] = [], workouts: [WorkoutSession], settings: SleepSettings, sessionLimit: Int = 90, workoutLimit: Int = 28) {
        self.sessionLimit = sessionLimit
        self.workoutLimit = workoutLimit
        self.settings = SettingsFingerprint(settings: settings)
        self.sessions = sessions.prefix(sessionLimit).map {
            SessionFingerprint(
                id: $0.id,
                status: $0.status,
                updatedAt: $0.updatedAt,
                start: $0.confirmedSleepStartAt,
                wake: $0.wakeAt,
                durationMinutes: $0.durationMinutes,
                qualityRating: $0.qualityRating,
                source: $0.source,
                confidence: $0.confidence
            )
        }
        self.workouts = workouts.prefix(workoutLimit).map {
            return WorkoutFingerprint(
                id: $0.id,
                date: $0.date,
                completed: $0.completed,
                durationMinutes: $0.durationMinutes,
                perceivedDifficulty: $0.perceivedDifficulty,
                energyLevel: $0.energyLevel,
                sorenessLevel: $0.sorenessLevel
            )
        }
        self.naps = naps.prefix(sessionLimit).map {
            NapFingerprint(
                id: $0.id,
                start: $0.startDate,
                end: $0.endDate,
                durationMinutes: $0.durationMinutes,
                qualityRating: $0.qualityRating,
                source: $0.source,
                updatedAt: $0.updatedAt
            )
        }
    }
}

struct SleepAnalyticsSnapshot {
    var summaries: [SleepSummary]
    var latestSummary: SleepSummary
    var dashboardSummary: SleepDashboardSummary
    var generatedAt: Date
}

struct SleepWorkoutReadinessSnapshot {
    var latestSummary: SleepSummary
    var adaptiveRecommendation: AdaptiveTrainingRecommendation?
    var generatedAt: Date
}

final class SleepAnalyticsSnapshotStore {
    static let shared = SleepAnalyticsSnapshotStore()

    private let service = SleepAnalyticsService()
    private var cachedSignature: SleepAnalyticsInputSignature?
    private var cachedSnapshot: SleepAnalyticsSnapshot?

    private init() {}

    func snapshot(sessions: [SleepSession], naps: [NapSession] = [], workouts: [WorkoutSession], settings: SleepSettings, sessionLimit: Int = 90, workoutLimit: Int = 28, force: Bool = false) -> SleepAnalyticsSnapshot {
        PerformanceTracer.mark(.unsafeBreadcrumb, "sleep.analytics.cache before_signature sessions=\(min(sessions.count, sessionLimit)) workouts=\(min(workouts.count, workoutLimit))")
        let signature = SleepAnalyticsInputSignature(sessions: sessions, naps: naps, workouts: workouts, settings: settings, sessionLimit: sessionLimit, workoutLimit: workoutLimit)

        if !force, signature == cachedSignature, let cachedSnapshot {
            PerformanceTracer.mark(.sleepAnalyticsCache, "hit sessions=\(min(sessions.count, sessionLimit)) workouts=\(min(workouts.count, workoutLimit))")
            let refreshedSnapshot = snapshotForCacheHit(cachedSnapshot, settings: settings)
            self.cachedSnapshot = refreshedSnapshot
            return refreshedSnapshot
        }

        PerformanceTracer.mark(.sleepAnalyticsCache, force ? "miss force=true" : "miss signature_changed")
        let limitedSessions = Array(sessions.prefix(sessionLimit))
        let limitedNaps = Array(naps.prefix(sessionLimit))
        let limitedWorkouts = Array(workouts.prefix(workoutLimit))
        let snapshot = service.snapshot(sessions: limitedSessions, naps: limitedNaps, workouts: limitedWorkouts, settings: settings)
        cachedSignature = signature
        cachedSnapshot = snapshot
        return snapshot
    }

    private func snapshotForCacheHit(_ snapshot: SleepAnalyticsSnapshot, settings: SleepSettings) -> SleepAnalyticsSnapshot {
        var snapshot = snapshot
        snapshot.dashboardSummary.lastHealthKitSleepSyncAt = settings.lastHealthKitSleepSyncAt
        return snapshot
    }
}

final class SleepWorkoutReadinessSnapshotStore {
    static let shared = SleepWorkoutReadinessSnapshotStore()

    private let service = SleepAnalyticsService()
    private var cachedSignature: SleepAnalyticsInputSignature?
    private var cachedSnapshot: SleepWorkoutReadinessSnapshot?

    private init() {}

    func snapshot(sessions: [SleepSession], naps: [NapSession] = [], workouts: [WorkoutSession], settings: SleepSettings, sessionLimit: Int = 45, workoutLimit: Int = 12, force: Bool = false) -> SleepWorkoutReadinessSnapshot {
        PerformanceTracer.mark(.unsafeBreadcrumb, "sleep.readiness.cache before_signature sessions=\(min(sessions.count, sessionLimit)) workouts=\(min(workouts.count, workoutLimit))")
        let signature = SleepAnalyticsInputSignature(sessions: sessions, naps: naps, workouts: workouts, settings: settings, sessionLimit: sessionLimit, workoutLimit: workoutLimit)

        if !force, signature == cachedSignature, let cachedSnapshot {
            PerformanceTracer.mark(.sleepReadinessCache, "hit sessions=\(min(sessions.count, sessionLimit)) workouts=\(min(workouts.count, workoutLimit))")
            return cachedSnapshot
        }

        PerformanceTracer.mark(.sleepReadinessCache, force ? "miss force=true" : "miss signature_changed")
        let limitedSessions = Array(sessions.prefix(sessionLimit))
        let limitedNaps = Array(naps.prefix(sessionLimit))
        let limitedWorkouts = Array(workouts.prefix(workoutLimit))
        let snapshot = service.workoutReadinessSnapshot(sessions: limitedSessions, naps: limitedNaps, workouts: limitedWorkouts, settings: settings)
        cachedSignature = signature
        cachedSnapshot = snapshot
        return snapshot
    }
}

struct SleepAnalyticsService {
    private let scoring = SleepScoringService()
    private let coaching = SleepCoachingService()
    private let resolver = SleepSourceResolver()
    private let correlationService = SleepWorkoutCorrelationService()
    private let interventionService = RecoveryInterventionService()
    private let adaptiveService = AdaptiveTrainingRecommendationService()
    private let insightService = SleepCoachingInsightService()

    func snapshot(sessions: [SleepSession], naps: [NapSession] = [], workouts: [WorkoutSession], settings: SleepSettings, calendar: Calendar = .current) -> SleepAnalyticsSnapshot {
        SleepAnalyticsSnapshot(
            summaries: scoring.summaries(from: sessions, naps: naps, workouts: workouts, settings: settings, days: 7, calendar: calendar),
            latestSummary: scoring.latestSummary(from: sessions, naps: naps, workouts: workouts, settings: settings),
            dashboardSummary: dashboardSummary(sessions: sessions, naps: naps, workouts: workouts, settings: settings, calendar: calendar),
            generatedAt: .now
        )
    }

    func workoutReadinessSnapshot(sessions: [SleepSession], naps: [NapSession] = [], workouts: [WorkoutSession], settings: SleepSettings, calendar: Calendar = .current) -> SleepWorkoutReadinessSnapshot {
        let sevenDaySummaries = scoring.summaries(from: sessions, naps: naps, workouts: workouts, settings: settings, days: 7, calendar: calendar)
        let lastNight = scoring.latestSummary(from: sessions, naps: naps, workouts: workouts, settings: settings)
        let resolvedSleep = resolver.resolvedSessions(from: sessions, settings: settings, days: 14, calendar: calendar)
        let correlations = correlationService.correlate(
            workouts: Array(workouts.prefix(12)),
            sleepSessions: resolvedSleep,
            historicalSleepSessions: sessions,
            settings: settings,
            calendar: calendar
        )
        let interventions = interventionService.interventions(
            summaries: sevenDaySummaries,
            correlations: correlations,
            workouts: Array(workouts.prefix(12)),
            settings: settings,
            calendar: calendar
        )
        let recommendation = adaptiveService.recommendation(
            sleep: lastNight,
            summaries: sevenDaySummaries,
            correlations: correlations,
            interventions: interventions,
            settings: settings
        )
        let advancedRecommendation = lastNight.recoveryBreakdown.map {
            RecoveryCoachingRecommendationService().buildRecommendation(
                recovery: $0,
                plannedWorkout: workouts.first { !$0.completed },
                naps: naps.filter { calendar.isDate($0.startDate, inSameDayAs: lastNight.date) }
            )
        }

        return SleepWorkoutReadinessSnapshot(
            latestSummary: lastNight,
            adaptiveRecommendation: advancedRecommendation.map(Self.adaptiveRecommendation(from:)) ?? recommendation,
            generatedAt: .now
        )
    }

    static func emptySnapshot(settings: SleepSettings = .default, calendar: Calendar = .current) -> SleepAnalyticsSnapshot {
        let latestSummary = SleepScoringService.emptySummary(calendar: calendar)
        return SleepAnalyticsSnapshot(
            summaries: [],
            latestSummary: latestSummary,
            dashboardSummary: emptyDashboardSummary(settings: settings, calendar: calendar),
            generatedAt: .now
        )
    }

    static func emptyReadinessSnapshot(calendar: Calendar = .current) -> SleepWorkoutReadinessSnapshot {
        SleepWorkoutReadinessSnapshot(
            latestSummary: SleepScoringService.emptySummary(calendar: calendar),
            adaptiveRecommendation: nil,
            generatedAt: .now
        )
    }

    static func emptyDashboardSummary(settings: SleepSettings = .default, calendar: Calendar = .current) -> SleepDashboardSummary {
        let latestSummary = SleepScoringService.emptySummary(calendar: calendar)
        return SleepDashboardSummary(
            lastNightSession: nil,
            lastNightDurationMinutes: nil,
            lastNightQualityRating: nil,
            sleepScore: nil,
            recoveryState: .unknown,
            recommendation: SleepCoachingService().recommendation(for: latestSummary, settings: settings),
            sevenDaySummaries: [],
            averageSleepMinutes: nil,
            weeklySleepDebtMinutes: nil,
            trackedNightCount: 0,
            consistencySummary: SleepConsistencySummary(
                status: .notEnoughData,
                averageSleepStart: nil,
                averageWakeTime: nil,
                approximateVariationMinutes: nil,
                message: "Track at least 3 nights to unlock sleep consistency insights."
            ),
            sourceLabel: nil,
            confidence: nil,
            sourceConflict: nil,
            lastHealthKitSleepSyncAt: settings.lastHealthKitSleepSyncAt,
            coachingInsights: [],
            adaptiveRecommendation: nil,
            napCreditMinutes: 0,
            recentNaps: [],
            recoveryBreakdown: nil
        )
    }

    func dashboardSummary(sessions: [SleepSession], workouts: [WorkoutSession], settings: SleepSettings, calendar: Calendar = .current) -> SleepDashboardSummary {
        dashboardSummary(sessions: sessions, naps: [], workouts: workouts, settings: settings, calendar: calendar)
    }

    func dashboardSummary(sessions: [SleepSession], naps: [NapSession], workouts: [WorkoutSession], settings: SleepSettings, calendar: Calendar = .current) -> SleepDashboardSummary {
        let sevenDaySummaries = scoring.summaries(from: sessions, naps: naps, workouts: workouts, settings: settings, days: 7, calendar: calendar)
        let twentyEightDaySummaries = scoring.summaries(from: sessions, naps: naps, workouts: workouts, settings: settings, days: 28, calendar: calendar)
        let lastNight = scoring.latestSummary(from: sessions, naps: naps, workouts: workouts, settings: settings)
        let resolvedSleep = resolver.resolvedSessions(from: sessions, settings: settings, days: 28, calendar: calendar)
        let correlations = correlationService.correlate(
            workouts: Array(workouts.prefix(28)),
            sleepSessions: resolvedSleep,
            historicalSleepSessions: sessions,
            settings: settings,
            calendar: calendar
        )
        let interventions = interventionService.interventions(
            summaries: sevenDaySummaries,
            correlations: correlations,
            workouts: workouts,
            settings: settings,
            calendar: calendar
        )
        let adaptiveRecommendation = adaptiveService.recommendation(
            sleep: lastNight,
            summaries: sevenDaySummaries,
            correlations: correlations,
            interventions: interventions,
            settings: settings
        )
        let advancedRecommendation = lastNight.recoveryBreakdown.map {
            RecoveryCoachingRecommendationService().buildRecommendation(
                recovery: $0,
                plannedWorkout: workouts.first { !$0.completed },
                naps: naps.filter { calendar.isDate($0.startDate, inSameDayAs: lastNight.date) }
            )
        }
        let insights = insightService.generateInsights(
            correlations: correlations,
            sleepSummaries: twentyEightDaySummaries,
            interventions: interventions,
            settings: settings
        )
        let daily = sevenDaySummaries.map { summary in
            DailySleepSummary(
                date: summary.date,
                durationMinutes: summary.primarySession == nil ? nil : summary.totalSleepMinutes,
                qualityRating: summary.qualityRating,
                source: summary.source,
                isBelowTarget: summary.primarySession != nil && summary.totalSleepMinutes < settings.targetSleepMinutes,
                isUnderSixHours: summary.primarySession != nil && summary.totalSleepMinutes < 360
            )
        }
        let tracked = sevenDaySummaries.filter { $0.primarySession != nil }
        let average = tracked.isEmpty ? nil : tracked.map(\.totalSleepMinutes).reduce(0, +) / tracked.count
        let debt = tracked.isEmpty ? nil : scoring.sleepDebtMinutes(summaries: sevenDaySummaries, targetMinutes: settings.targetSleepMinutes)
        let consistency = consistencySummary(from: tracked.compactMap(\.primarySession), calendar: calendar)

        return SleepDashboardSummary(
            lastNightSession: lastNight.primarySession,
            lastNightDurationMinutes: lastNight.primarySession == nil ? nil : lastNight.totalSleepMinutes,
            lastNightQualityRating: lastNight.qualityRating,
            sleepScore: lastNight.sleepScore,
            recoveryState: lastNight.recoveryState,
            recommendation: coaching.recommendation(for: lastNight, settings: settings),
            sevenDaySummaries: daily,
            averageSleepMinutes: average,
            weeklySleepDebtMinutes: debt,
            trackedNightCount: tracked.count,
            consistencySummary: consistency,
            sourceLabel: lastNight.source?.displayName,
            confidence: lastNight.primarySession == nil ? nil : lastNight.confidence,
            sourceConflict: lastNight.sourceConflict,
            lastHealthKitSleepSyncAt: settings.lastHealthKitSleepSyncAt,
            coachingInsights: insights,
            adaptiveRecommendation: advancedRecommendation.map(Self.adaptiveRecommendation(from:)) ?? adaptiveRecommendation,
            napCreditMinutes: lastNight.napCreditMinutes,
            recentNaps: Array(naps.sorted { $0.startDate > $1.startDate }.prefix(7)),
            recoveryBreakdown: lastNight.recoveryBreakdown
        )
    }

    private static func adaptiveRecommendation(from recovery: RecoveryCoachingRecommendation) -> AdaptiveTrainingRecommendation {
        AdaptiveTrainingRecommendation(
            level: recovery.readiness,
            title: recovery.title,
            message: recovery.message,
            suggestedActions: recovery.suggestedAdjustments,
            confidence: recovery.confidence == .high ? .high : recovery.confidence == .medium ? .medium : .low,
            basedOn: recovery.reasons.compactMap { reason in
                switch reason {
                case .sleptAboveTarget, .sleptBelowTarget:
                    return .lastNightSleep
                case .sleepDebtHigh:
                    return .sevenDaySleepDebt
                case .sleepConsistent, .sleepInconsistent:
                    return .sleepConsistency
                case .poorSleepQuality, .strongSleepQuality:
                    return .sleepQuality
                case .highTrainingLoad:
                    return .trainingFrequency
                case .recentPerformanceDip, .recentPerformanceStrong:
                    return .recentPerformance
                case .lowConfidenceData:
                    return .sleepSourceConflict
                case .napImprovedRecovery, .lateNapMayAffectSleep, .missingSleepData:
                    return .recoveryScore
                }
            }
        )
    }

    func consistencySummary(from sessions: [SleepSession], calendar: Calendar = .current) -> SleepConsistencySummary {
        let recent = sessions
            .filter { $0.status == .completed }
            .sorted { $0.confirmedSleepStartAt > $1.confirmedSleepStartAt }
            .prefix(7)

        guard recent.count >= 3 else {
            return SleepConsistencySummary(
                status: .notEnoughData,
                averageSleepStart: nil,
                averageWakeTime: nil,
                approximateVariationMinutes: nil,
                message: "Track at least 3 nights to unlock sleep consistency insights."
            )
        }

        let bedTimes = recent.map { minutesSinceStartOfDay($0.confirmedSleepStartAt, calendar: calendar) }
        let wakeTimes = recent.map { minutesSinceStartOfDay($0.wakeAt, calendar: calendar) }
        let variation = max(scoring.circularRange(of: bedTimes), scoring.circularRange(of: wakeTimes))
        let status: SleepConsistencyStatus
        let message: String

        if variation <= 45 {
            status = .strong
            message = "Your sleep schedule has been steady across tracked nights."
        } else if variation <= 90 {
            status = .moderate
            message = "Your wake time varies by around \(SleepScoringService.durationText(minutes: variation)) this week."
        } else {
            status = .inconsistent
            message = "Your sleep timing has varied recently. Keep an eye on recovery around heavy sessions."
        }

        return SleepConsistencySummary(
            status: status,
            averageSleepStart: averageClockTime(Array(recent.map(\.confirmedSleepStartAt)), calendar: calendar),
            averageWakeTime: averageClockTime(Array(recent.map(\.wakeAt)), calendar: calendar),
            approximateVariationMinutes: variation,
            message: message
        )
    }

    private func minutesSinceStartOfDay(_ date: Date, calendar: Calendar) -> Int {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    private func averageClockTime(_ dates: [Date], calendar: Calendar) -> Date? {
        guard !dates.isEmpty else { return nil }
        let values = dates.map { minutesSinceStartOfDay($0, calendar: calendar) }
        let average = values.reduce(0, +) / values.count
        return calendar.date(bySettingHour: average / 60, minute: average % 60, second: 0, of: .now)
    }
}

struct SleepNotificationID {
    static let bedtimeReminder = "sleep.bedtimeReminder"
    static let windDownReminder = "sleep.windDownReminder"
    static let missedSleepReminder = "sleep.missedSleepReminder"

    static func morningConfirmation(sessionID: UUID) -> String {
        "sleep.morningConfirmation.\(sessionID.uuidString)"
    }

    static func unfinishedSession(sessionID: UUID) -> String {
        "sleep.unfinishedSession.\(sessionID.uuidString)"
    }

    static func trainingAware(date: Date) -> String {
        let value = date.formatted(.iso8601.year().month().day())
        return "sleep.trainingAware.\(value)"
    }

    static let allStable = [bedtimeReminder, windDownReminder, missedSleepReminder]
}

struct SleepNotificationService {
    private let center = UNUserNotificationCenter.current()

    func authorizationStatus() async -> UNAuthorizationStatus {
        PerformanceTracer.mark(.unsafeBreadcrumb, "notification.authorizationStatus before_continuation")
        return await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                PerformanceTracer.mark(.unsafeBreadcrumb, "notification.authorizationStatus callback")
                continuation.resume(returning: settings.authorizationStatus)
            }
        }
    }

    func requestAuthorization() async throws -> UNAuthorizationStatus {
        let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        let status = await authorizationStatus()
        guard granted || status == .authorized || status == .provisional else {
            throw HealthKitSyncError.authorizationDenied
        }
        return status
    }
}

struct SleepNotificationScheduler {
    private let center = UNUserNotificationCenter.current()

    func refreshAllSleepNotifications(
        settings: SleepSettings,
        sessions: [SleepNotificationSessionSnapshot],
        workouts: [SleepNotificationWorkoutSnapshot],
        calendar: Calendar = .current
    ) async {
        PerformanceTracer.mark(.unsafeBreadcrumb, "root.notification.scheduler begin enabled=\(settings.notificationPreferences.isEnabled)")
        guard settings.notificationPreferences.isEnabled else {
            await cancelSleepNotificationsAsync(sessions: sessions, workouts: workouts, calendar: calendar)
            PerformanceTracer.mark(.unsafeBreadcrumb, "root.notification.scheduler end disabled")
            return
        }

        let status = await PerformanceTracer.traceAsync(.rootNotificationPermissionStatus) {
            await SleepNotificationService().authorizationStatus()
        }
        guard status == .authorized || status == .provisional || status == .ephemeral else {
            PerformanceTracer.mark(.unsafeBreadcrumb, "root.notification.scheduler end unauthorized status=\(status.rawValue)")
            return
        }

        await cancelSleepNotificationsAsync(sessions: sessions, workouts: workouts, calendar: calendar)

        PerformanceTracer.mark(.unsafeBreadcrumb, "root.notification.scheduler before_schedule")
        PerformanceTracer.trace(.rootNotificationScheduling) {
            scheduleBedtimeReminder(settings: settings, sessions: sessions, calendar: calendar)
            scheduleWindDownReminder(settings: settings, sessions: sessions, calendar: calendar)

            if let session = sessions.first(where: { $0.status == .active }) {
                scheduleMorningConfirmationReminder(for: session, settings: settings, calendar: calendar)
                scheduleUnfinishedSessionReminder(for: session)
            }

            scheduleMissedSleepReminder(settings: settings, sessions: sessions, calendar: calendar)
            scheduleTrainingAwareReminder(settings: settings, sessions: sessions, workouts: workouts, calendar: calendar)
        }
        PerformanceTracer.mark(.unsafeBreadcrumb, "root.notification.scheduler end")
    }

    func scheduleBedtimeReminder(settings: SleepSettings, sessions: [SleepNotificationSessionSnapshot], calendar: Calendar = .current) {
        let preferences = settings.notificationPreferences
        guard preferences.bedtimeReminderEnabled, !preferences.isQuietDay(.now, calendar: calendar) else { return }
        guard !sessions.contains(where: { $0.status == .active }) else { return }
        guard !hasSessionForUpcomingNight(sessions: sessions, calendar: calendar) else { return }

        scheduleCalendarNotification(
            id: SleepNotificationID.bedtimeReminder,
            title: "Recovery starts tonight",
            body: "Start Sleep Mode so tomorrow's workout guidance is more accurate.",
            components: preferences.bedtimeReminderTime,
            repeats: true,
            destination: .sleepMode
        )
    }

    func scheduleWindDownReminder(settings: SleepSettings, sessions: [SleepNotificationSessionSnapshot], calendar: Calendar = .current) {
        let preferences = settings.notificationPreferences
        guard preferences.windDownReminderEnabled, !preferences.isQuietDay(.now, calendar: calendar) else { return }
        guard !sessions.contains(where: { $0.status == .active }) else { return }
        let bedtime = date(from: preferences.bedtimeReminderTime, on: .now, calendar: calendar)
        let reminderDate = bedtime.addingTimeInterval(TimeInterval(-preferences.windDownOffsetMinutes * 60))
        let components = calendar.dateComponents([.hour, .minute], from: reminderDate)

        scheduleCalendarNotification(
            id: SleepNotificationID.windDownReminder,
            title: "Start winding down",
            body: "A consistent bedtime can improve recovery and training performance.",
            components: components,
            repeats: true,
            destination: .sleepMode
        )
    }

    func scheduleMorningConfirmationReminder(for session: SleepNotificationSessionSnapshot, settings: SleepSettings, calendar: Calendar = .current) {
        let preferences = settings.notificationPreferences
        guard preferences.morningConfirmationEnabled else { return }
        guard session.morningReminderSentAt == nil else { return }

        scheduleCalendarNotification(
            id: SleepNotificationID.morningConfirmation(sessionID: session.id),
            title: "Confirm your sleep",
            body: "Review your wake time to update today's recovery score.",
            components: preferences.morningConfirmationTime,
            repeats: false,
            destination: .wakeConfirmation(sessionID: session.id)
        )
    }

    func scheduleUnfinishedSessionReminder(for session: SleepNotificationSessionSnapshot) {
        guard session.unfinishedReminderSentAt == nil else { return }
        let start = session.sleepModeStartedAt ?? session.confirmedSleepStartAt
        let fireDate = start.addingTimeInterval(12 * 3_600)
        let interval = max(60, fireDate.timeIntervalSinceNow)

        scheduleTimeIntervalNotification(
            id: SleepNotificationID.unfinishedSession(sessionID: session.id),
            title: "Still tracking sleep?",
            body: "Confirm your wake time so your recovery score does not overestimate sleep.",
            interval: interval,
            destination: .wakeConfirmation(sessionID: session.id)
        )
    }

    func scheduleMissedSleepReminder(settings: SleepSettings, sessions: [SleepNotificationSessionSnapshot], calendar: Calendar = .current) {
        let preferences = settings.notificationPreferences
        guard preferences.missedSleepReminderEnabled else { return }
        guard recentTrackedCount(sessions: sessions, calendar: calendar) >= 3 else { return }
        guard !hasSessionForLastNight(sessions: sessions, calendar: calendar) else { return }

        var components = DateComponents()
        components.hour = 11
        components.minute = 30
        scheduleCalendarNotification(
            id: SleepNotificationID.missedSleepReminder,
            title: "Forgot to track sleep?",
            body: "Add an estimate so today's recovery score stays useful.",
            components: components,
            repeats: false,
            destination: .manualBackfill
        )
    }

    func scheduleTrainingAwareReminder(
        settings: SleepSettings,
        sessions: [SleepNotificationSessionSnapshot],
        workouts: [SleepNotificationWorkoutSnapshot],
        calendar: Calendar = .current
    ) {
        let preferences = settings.notificationPreferences
        guard preferences.trainingAwareRemindersEnabled, !preferences.isQuietDay(.now, calendar: calendar) else { return }
        guard !sessions.contains(where: { $0.status == .active }) else { return }
        guard likelyWorkoutTomorrow(workouts: workouts, calendar: calendar) else { return }

        let bedtime = date(from: preferences.bedtimeReminderTime, on: .now, calendar: calendar)
        let reminderDate = bedtime.addingTimeInterval(-20 * 60)
        let components = calendar.dateComponents([.hour, .minute], from: reminderDate)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: .now) ?? .now

        scheduleCalendarNotification(
            id: SleepNotificationID.trainingAware(date: tomorrow),
            title: "Big session tomorrow",
            body: "Start Sleep Mode tonight so your recovery guidance is more accurate.",
            components: components,
            repeats: false,
            destination: .sleepMode
        )
    }

    func cancelSleepNotifications() {
        center.removePendingNotificationRequests(withIdentifiers: SleepNotificationID.allStable)
        center.getPendingNotificationRequests { requests in
            let ids = requests.map(\.identifier).filter { $0.hasPrefix("sleep.") }
            center.removePendingNotificationRequests(withIdentifiers: ids)
        }
    }

    func cancelSleepNotificationsAsync(
        sessions: [SleepNotificationSessionSnapshot] = [],
        workouts: [SleepNotificationWorkoutSnapshot] = [],
        calendar: Calendar = .current
    ) async {
        await PerformanceTracer.traceAsync(.rootNotificationCancellation) {
            var ids = Set(SleepNotificationID.allStable)
            ids.formUnion(dynamicNotificationIDs(sessions: sessions, workouts: workouts, calendar: calendar))
            let pendingSleepIds = await pendingSleepNotificationIDs()
            ids.formUnion(pendingSleepIds)
            center.removePendingNotificationRequests(withIdentifiers: Array(ids))
        }
    }

    func cancelNotifications(for sessionID: UUID) {
        center.removePendingNotificationRequests(withIdentifiers: [
            SleepNotificationID.morningConfirmation(sessionID: sessionID),
            SleepNotificationID.unfinishedSession(sessionID: sessionID)
        ])
    }

    static func sessionSnapshots(from sessions: [SleepSession]) -> [SleepNotificationSessionSnapshot] {
        sessions.map { SleepNotificationSessionSnapshot(session: $0) }
    }

    static func workoutSnapshots(from workouts: [WorkoutSession]) -> [SleepNotificationWorkoutSnapshot] {
        workouts.map { SleepNotificationWorkoutSnapshot(workout: $0) }
    }

    private func scheduleCalendarNotification(id: String, title: String, body: String, components: DateComponents, repeats: Bool, destination: SleepNotificationDestination) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = destination.userInfo
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: repeats)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    private func scheduleTimeIntervalNotification(id: String, title: String, body: String, interval: TimeInterval, destination: SleepNotificationDestination) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = destination.userInfo
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    private func pendingSleepNotificationIDs() async -> [String] {
        await PerformanceTracer.traceAsync(.rootNotificationPendingFetch) {
            PerformanceTracer.mark(.unsafeBreadcrumb, "notification.pending_fetch before_continuation")
            return await withCheckedContinuation { continuation in
                center.getPendingNotificationRequests { requests in
                    PerformanceTracer.mark(.unsafeBreadcrumb, "notification.pending_fetch callback count=\(requests.count)")
                    continuation.resume(returning: requests.map(\.identifier).filter { $0.hasPrefix("sleep.") })
                }
            }
        }
    }

    private func dynamicNotificationIDs(
        sessions: [SleepNotificationSessionSnapshot],
        workouts: [SleepNotificationWorkoutSnapshot],
        calendar: Calendar
    ) -> [String] {
        var ids = sessions.flatMap { session in
            [
                SleepNotificationID.morningConfirmation(sessionID: session.id),
                SleepNotificationID.unfinishedSession(sessionID: session.id)
            ]
        }

        if likelyWorkoutTomorrow(workouts: workouts, calendar: calendar) {
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: .now) ?? .now
            ids.append(SleepNotificationID.trainingAware(date: tomorrow))
        }

        return ids
    }

    private func hasSessionForUpcomingNight(sessions: [SleepNotificationSessionSnapshot], calendar: Calendar) -> Bool {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: .now) ?? .now
        let night = SleepCalendar.nightDate(for: tomorrow, calendar: calendar)
        return sessions.contains { $0.status == .completed && calendar.isDate($0.nightDate, inSameDayAs: night) }
    }

    private func hasSessionForLastNight(sessions: [SleepNotificationSessionSnapshot], calendar: Calendar) -> Bool {
        let yesterday = calendar.date(byAdding: .day, value: -1, to: .now) ?? .now
        let night = SleepCalendar.nightDate(for: yesterday, calendar: calendar)
        return sessions.contains { $0.status == .completed && calendar.isDate($0.nightDate, inSameDayAs: night) }
    }

    private func recentTrackedCount(sessions: [SleepNotificationSessionSnapshot], calendar: Calendar) -> Int {
        let cutoff = calendar.date(byAdding: .day, value: -7, to: .now) ?? .now.addingTimeInterval(-7 * 86_400)
        return Set(sessions.filter { $0.status == .completed && $0.confirmedSleepStartAt >= cutoff }.map(\.nightDate)).count
    }

    private func likelyWorkoutTomorrow(workouts: [SleepNotificationWorkoutSnapshot], calendar: Calendar) -> Bool {
        let tomorrowWeekday = calendar.component(.weekday, from: calendar.date(byAdding: .day, value: 1, to: .now) ?? .now)
        let cutoff = calendar.date(byAdding: .day, value: -56, to: .now) ?? .now.addingTimeInterval(-56 * 86_400)
        return workouts.contains { workout in
            workout.date >= cutoff && calendar.component(.weekday, from: workout.date) == tomorrowWeekday
        }
    }

    private func date(from components: DateComponents, on date: Date, calendar: Calendar) -> Date {
        calendar.date(
            bySettingHour: components.hour ?? 22,
            minute: components.minute ?? 30,
            second: 0,
            of: date
        ) ?? date
    }
}

struct SleepNotificationSessionSnapshot: Sendable {
    let id: UUID
    let status: SleepSessionStatus
    let nightDate: Date
    let confirmedSleepStartAt: Date
    let sleepModeStartedAt: Date?
    let morningReminderSentAt: Date?
    let unfinishedReminderSentAt: Date?

    init(session: SleepSession) {
        self.id = session.id
        self.status = session.status
        self.nightDate = session.nightDate
        self.confirmedSleepStartAt = session.confirmedSleepStartAt
        self.sleepModeStartedAt = session.sleepModeStartedAt
        self.morningReminderSentAt = session.morningReminderSentAt
        self.unfinishedReminderSentAt = session.unfinishedReminderSentAt
    }
}

struct SleepNotificationWorkoutSnapshot: Sendable {
    let date: Date

    init(workout: WorkoutSession) {
        self.date = workout.date
    }
}

struct SleepCoachingService {
    static let estimatedDataDisclaimer = "This is based on your Sleep Mode estimate and morning confirmation, so treat it as a guide rather than an exact measurement."

    func recommendation(for summary: SleepSummary, settings: SleepSettings) -> String {
        guard settings.recoveryCoachingEnabled else {
            return "Recovery coaching is off in Sleep settings."
        }

        switch summary.recoveryState {
        case .high:
            return "You slept well and your recovery trend looks strong. Today is suitable for normal progression if warm-ups feel good."
        case .good:
            return "Sleep looks solid. Continue with your planned session and adjust based on how your first working sets feel."
        case .moderate:
            return "Sleep was slightly below target. Train normally, but keep one rep in reserve on heavier sets."
        case .low:
            return "Sleep was low last night. Consider reducing accessory volume or avoiding extra failure sets today."
        case .veryLow:
            return "Recovery is low today. A lighter session, mobility work, or rest may be more productive than forcing intensity."
        case .unknown:
            return "Start Sleep Mode tonight to improve recovery coaching."
        }
    }

    func preWorkoutHint(for summary: SleepSummary?) -> (title: String, suggestion: String)? {
        guard let summary, let score = summary.sleepScore else { return nil }

        switch summary.recoveryState {
        case .high:
            return ("Sleep recovery: High", "Normal progression is suitable if warm-ups feel good.")
        case .good:
            return ("Sleep recovery: Good", "Continue with the planned session and adjust from your first working sets.")
        case .moderate:
            return ("Sleep recovery: Moderate", "Keep top sets controlled today.")
        case .low:
            return ("Sleep recovery: Low", "Avoid extra failure sets and reduce accessory volume if needed.")
        case .veryLow:
            return ("Sleep recovery: Very low", "A lighter session or rest may be more productive today.")
        case .unknown:
            return score > 0 ? ("Sleep recovery", "Use warm-ups to decide how hard to push today.") : nil
        }
    }

    func historyImpact(for score: Int?) -> String {
        switch SleepScoringService().recoveryState(for: score) {
        case .high, .good:
            return "Normal training support"
        case .moderate:
            return "Slightly reduced"
        case .low:
            return "Reduced recovery"
        case .veryLow:
            return "Recovery focus"
        case .unknown:
            return "Not scored"
        }
    }

    func trainingInsight(summaries: [SleepSummary], workouts: [WorkoutSession]) -> String {
        let tracked = summaries.filter { $0.primarySession != nil }
        guard tracked.count >= 5, workouts.count >= 5 else {
            return "Log more sleep and workouts to see how recovery affects your performance."
        }

        let strongNights = tracked.filter { $0.totalSleepMinutes >= 420 }.count
        if strongNights >= 3 {
            return "Your strongest recent sessions may follow nights with 7h+ sleep."
        }

        if tracked.contains(where: { $0.totalSleepMinutes < 360 }) {
            return "Low sleep may make heavy sets feel harder. Use your warm-up sets to decide whether to push today."
        }

        return "Your sleep trend is building a useful recovery baseline for coaching."
    }
}
