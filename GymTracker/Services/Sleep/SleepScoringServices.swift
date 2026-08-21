import Foundation
import SwiftData
import UserNotifications

struct SleepSourceResolver {
    private let toleranceMinutes = 45
    private let largeConflictMinutes = 120

    func resolvedSession(
        for date: Date,
        sessions: [SleepSession],
        settings: SleepSettings,
        endingOn evaluationDate: Date = .now,
        calendar: Calendar = .current
    ) -> ResolvedSleepSession? {
        let completed = sessions.filter { $0.status == .completed && $0.wakeAt <= evaluationDate }
        let appleHealth = bestSession(
            from: completed.filter {
                $0.source == .appleHealth
                    && calendar.isDate(
                        SleepCalendar.nightDate(for: $0.confirmedSleepStartAt, calendar: calendar),
                        inSameDayAs: date
                    )
            }
        )
        let sleepMode = bestSession(
            from: completed.filter {
                $0.source == .inAppTimer
                    && calendar.isDate(
                        SleepCalendar.nightDate(for: $0.confirmedSleepStartAt, calendar: calendar),
                        inSameDayAs: date
                    )
            }
        )
        let manual = bestSession(
            from: completed.filter {
                $0.source == .manual
                    && calendar.isDate(
                        SleepCalendar.nightDate(for: $0.confirmedSleepStartAt, calendar: calendar),
                        inSameDayAs: date
                    )
            }
        )

        switch settings.preferredSource {
        case .appleHealth:
            return appleHealth.map { resolved(from: $0, source: .appleHealth, calendar: calendar) }
                ?? sleepMode.map { resolved(from: $0, source: .inAppTimer, calendar: calendar) }
                ?? manual.map { resolved(from: $0, source: .manual, calendar: calendar) }
        case .sleepMode:
            return sleepMode.map { resolved(from: $0, source: .inAppTimer, calendar: calendar) }
                ?? appleHealth.map { resolved(from: $0, source: .appleHealth, calendar: calendar) }
                ?? manual.map { resolved(from: $0, source: .manual, calendar: calendar) }
        case .manual:
            return manual.map { resolved(from: $0, source: .manual, calendar: calendar) }
                ?? appleHealth.map { resolved(from: $0, source: .appleHealth, calendar: calendar) }
                ?? sleepMode.map { resolved(from: $0, source: .inAppTimer, calendar: calendar) }
        case .automatic:
            return automaticResolved(
                date: date,
                appleHealth: appleHealth,
                sleepMode: sleepMode,
                manual: manual,
                calendar: calendar
            )
        }
    }

    func resolvedSessions(
        from sessions: [SleepSession],
        settings: SleepSettings,
        days: Int = 28,
        endingOn evaluationDate: Date = .now,
        calendar: Calendar = .current
    ) -> [ResolvedSleepSession] {
        let eligibleSessions = sessions.filter { $0.status == .completed && $0.wakeAt <= evaluationDate }
        let start = calendar.startOfDay(for: evaluationDate)
        return (0..<days).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: start) else { return nil }
            return resolvedSession(
                for: date,
                sessions: eligibleSessions,
                settings: settings,
                endingOn: evaluationDate,
                calendar: calendar
            )
        }
    }

    private func automaticResolved(
        date: Date,
        appleHealth: SleepSession?,
        sleepMode: SleepSession?,
        manual: SleepSession?,
        calendar: Calendar
    ) -> ResolvedSleepSession? {
        guard let appleHealth else {
            return sleepMode.map { resolved(from: $0, source: .inAppTimer, calendar: calendar) }
                ?? manual.map { resolved(from: $0, source: .manual, calendar: calendar) }
        }

        guard let sleepMode else {
            return resolved(from: appleHealth, source: .appleHealth, calendar: calendar)
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
            return resolved(from: appleHealth, source: .appleHealth, conflict: conflict, calendar: calendar)
        }

        if sleepMode.confidence == .estimatedConfirmed {
            return resolved(from: sleepMode, source: .inAppTimer, conflict: .lowConfidenceHealthKit, calendar: calendar)
        }

        return resolved(from: appleHealth, source: .appleHealth, conflict: conflict, calendar: calendar)
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

    private func resolved(
        from session: SleepSession,
        source: SleepSource,
        conflict: SleepSourceConflict? = nil,
        calendar: Calendar
    ) -> ResolvedSleepSession {
        ResolvedSleepSession(
            id: session.id,
            sleepDate: SleepCalendar.nightDate(for: session.confirmedSleepStartAt, calendar: calendar),
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

struct SleepScoringService {
    private let resolver = SleepSourceResolver()
    private let advancedRecovery = AdvancedRecoveryScoreService()

    func summaries(from sessions: [SleepSession], settings: SleepSettings, days: Int = 7, endingOn evaluationDate: Date = .now, calendar: Calendar = .current) -> [SleepSummary] {
        summaries(from: sessions, naps: [], workouts: [], settings: settings, days: days, endingOn: evaluationDate, calendar: calendar)
    }

    func summaries(from sessions: [SleepSession], naps: [NapSession], workouts: [WorkoutSession], settings: SleepSettings, days: Int = 7, endingOn evaluationDate: Date = .now, calendar: Calendar = .current) -> [SleepSummary] {
        // A restored/imported record can be marked completed before its wake
        // time. It must not enter an evaluated snapshot until the overnight
        // has actually finished at the evaluation instant.
        let completed = sessions.filter {
            $0.status == .completed && $0.wakeAt <= evaluationDate
        }
        let grouped = Dictionary(grouping: completed, by: { SleepCalendar.nightDate(for: $0.confirmedSleepStartAt, calendar: calendar) })
        let start = calendar.startOfDay(for: evaluationDate)

        return (0..<days).compactMap { offset in
            guard let summaryDate = calendar.date(byAdding: .day, value: -offset, to: start) else { return nil }
            let nightly = grouped[summaryDate] ?? []
            return summary(
                for: summaryDate,
                sessions: nightly,
                allSessions: completed,
                naps: naps,
                workouts: workouts,
                settings: settings,
                endingOn: evaluationDate,
                calendar: calendar
            )
        }
    }

    func latestSummary(
        from sessions: [SleepSession],
        settings: SleepSettings,
        endingOn date: Date = .now,
        calendar: Calendar = .current
    ) -> SleepSummary {
        latestSummary(
            from: sessions,
            naps: [],
            workouts: [],
            settings: settings,
            endingOn: date,
            calendar: calendar
        )
    }

    func latestSummary(
        from sessions: [SleepSession],
        naps: [NapSession],
        workouts: [WorkoutSession],
        settings: SleepSettings,
        endingOn date: Date = .now,
        calendar: Calendar = .current
    ) -> SleepSummary {
        let recentSummaries = summaries(
            from: sessions,
            naps: naps,
            workouts: workouts,
            settings: settings,
            days: 14,
            endingOn: date,
            calendar: calendar
        )
        guard let lastNightDate = calendar.date(
            byAdding: .day,
            value: -1,
            to: calendar.startOfDay(for: date)
        ) else {
            return Self.emptySummary(calendar: calendar)
        }

        // Sessions are grouped by bedtime date. On Monday, last night's
        // completed overnight therefore belongs to Sunday's summary, not
        // Monday's current-day summary and not the first populated day in the
        // recent history window.
        return recentSummaries.first {
            calendar.isDate($0.date, inSameDayAs: lastNightDate)
        } ?? Self.emptySummary(calendar: calendar)
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

    private func summary(for date: Date, sessions: [SleepSession], allSessions: [SleepSession], naps: [NapSession], workouts: [WorkoutSession], settings: SleepSettings, endingOn evaluationDate: Date, calendar: Calendar) -> SleepSummary {
        let primary = primarySession(from: sessions)
        let resolved = resolver.resolvedSession(
            for: date,
            sessions: allSessions,
            settings: settings,
            endingOn: evaluationDate,
            calendar: calendar
        )
        let recentSleep = resolver.resolvedSessions(
            from: allSessions,
            settings: settings,
            days: 28,
            endingOn: evaluationDate,
            calendar: calendar
        )
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

struct SleepSessionScoreSnapshot: Equatable, Sendable, Identifiable {
    let id: UUID
    let score: Int
    let contextSessionIDs: [UUID]
}

/// Canonical score values for a bounded history context.
///
/// History rows and the detail route can consume the same value map instead of
/// independently choosing different `recentSessions` arrays. The map retains
/// only UUIDs and scores, never SwiftData models.
struct SleepSessionScoreMap: Equatable, Sendable {
    let contextSessionIDs: [UUID]
    private let values: [UUID: Int]

    init(
        sessions: [SleepSession],
        settings: SleepSettings,
        limit: Int = 90,
        scoring: SleepScoringService = SleepScoringService()
    ) {
        let context = Array(
            sessions
                .filter { $0.status == .completed }
                .prefix(max(0, limit))
        )
        contextSessionIDs = context.map(\.id)
        values = Dictionary(
            uniqueKeysWithValues: context.map { session in
                (
                    session.id,
                    scoring.score(for: session, recentSessions: context, settings: settings)
                )
            }
        )
    }

    func score(for sessionID: UUID) -> Int? {
        values[sessionID]
    }

    func snapshot(for sessionID: UUID) -> SleepSessionScoreSnapshot? {
        guard let score = values[sessionID] else { return nil }
        return SleepSessionScoreSnapshot(
            id: sessionID,
            score: score,
            contextSessionIDs: contextSessionIDs
        )
    }
}
