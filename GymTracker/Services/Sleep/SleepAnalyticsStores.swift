import Foundation
import SwiftData
import UserNotifications

private enum SleepAnalyticsWorkoutGeneration {
    // Keep the default readiness-store path aligned with the persisted
    // WorkoutWarmStartInvalidation generation without touching that service's
    // ownership boundary. Explicit SwiftUI callers pass the in-memory value.
    private static let revisionKey = "Peakline.WorkoutWarmStartInvalidation.revision"

    static var current: Int {
        UserDefaults.standard.integer(forKey: revisionKey)
    }
}

struct SleepAnalyticsInputSignature: Equatable, Sendable {
    private struct SessionFingerprint: Equatable, Sendable {
        let id: UUID
        let status: String
        let updatedAt: Date
        let start: Date
        let wake: Date
        let durationMinutes: Int
        let qualityRating: Int?
        let source: String
        let confidence: String
        let sleepModeStartedAt: Date?
        let estimatedSleepStartAt: Date?
        let windDownDurationMinutes: Int?
        let tags: String
        let notes: String?
        let healthKitSampleIDs: String
    }

    private struct WorkoutFingerprint: Equatable, Sendable {
        let id: UUID
        let date: Date
        let splitNameSnapshot: String
        let startedAt: Date?
        let endedAt: Date?
        let completed: Bool
        let durationMinutes: Int?
        let durationSeconds: Int?
        let accumulatedPausedSeconds: Int
        let perceivedDifficulty: Int?
        let energyLevel: Int?
        let sorenessLevel: Int?
        let notes: String?
        /// Kept for compatibility with callers that do not provide the
        /// workout-generation token. SwiftUI hot paths pass a generation and
        /// leave this nil so constructing a signature never faults the
        /// exerciseLogs/setLogs relationship graph.
        let relationshipFingerprint: String?
    }

    private struct NapFingerprint: Equatable, Sendable {
        let id: UUID
        let start: Date
        let end: Date
        let durationMinutes: Int
        let qualityRating: Int?
        let source: String
        let timingCategory: String
        let note: String?
        let healthKitSampleIDs: String
        let updatedAt: Date
    }

    private struct SettingsFingerprint: Equatable, Sendable {
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
    let localDayToken: Date
    /// The next wake boundary at which a completed future record becomes
    /// eligible for summaries. This changes only when that boundary is
    /// crossed, so cache reads do not churn with the current minute.
    let nextSleepEligibilityBoundary: Date?
    /// Monotonic source generation for workout and set edits. A generation is
    /// cheaper and safer for repeated observation than traversing every
    /// WorkoutSession relationship on each body evaluation.
    let workoutRevision: Int?
    private let settings: SettingsFingerprint
    private let sessions: [SessionFingerprint]
    private let workouts: [WorkoutFingerprint]
    private let naps: [NapFingerprint]

    init(
        sessions: [SleepSession],
        naps: [NapSession] = [],
        workouts: [WorkoutSession],
        settings: SleepSettings,
        sessionLimit: Int = 90,
        workoutLimit: Int = 28,
        workoutRevision: Int? = nil,
        now: Date = .now,
        calendar: Calendar = .current
    ) {
        self.sessionLimit = sessionLimit
        self.workoutLimit = workoutLimit
        self.localDayToken = calendar.startOfDay(for: now)
        self.nextSleepEligibilityBoundary = sessions
            .prefix(sessionLimit)
            .filter { $0.status == .completed && $0.wakeAt > now }
            .map(\.wakeAt)
            .min()
        self.workoutRevision = workoutRevision
        self.settings = SettingsFingerprint(settings: settings)
        self.sessions = sessions.prefix(sessionLimit).map {
            SessionFingerprint(
                id: $0.id,
                status: $0.status.rawValue,
                updatedAt: $0.updatedAt,
                start: $0.confirmedSleepStartAt,
                wake: $0.wakeAt,
                durationMinutes: $0.durationMinutes,
                qualityRating: $0.qualityRating,
                source: $0.source.rawValue,
                confidence: $0.confidence.rawValue,
                sleepModeStartedAt: $0.sleepModeStartedAt,
                estimatedSleepStartAt: $0.estimatedSleepStartAt,
                windDownDurationMinutes: $0.windDownDurationMinutes,
                tags: $0.tagRawValues.sorted().joined(separator: ","),
                notes: $0.notes,
                healthKitSampleIDs: $0.healthKitSampleIds.sorted().joined(separator: ",")
            )
        }
        self.workouts = workouts.prefix(workoutLimit).map {
            WorkoutFingerprint(
                id: $0.id,
                date: $0.date,
                splitNameSnapshot: $0.splitNameSnapshot,
                startedAt: $0.startedAt,
                endedAt: $0.endedAt,
                completed: $0.completed,
                durationMinutes: $0.durationMinutes,
                durationSeconds: $0.durationSeconds,
                accumulatedPausedSeconds: $0.accumulatedPausedSeconds,
                perceivedDifficulty: $0.perceivedDifficulty,
                energyLevel: $0.energyLevel,
                sorenessLevel: $0.sorenessLevel,
                notes: $0.notes,
                relationshipFingerprint: workoutRevision == nil
                    ? Self.relationshipFingerprint(for: $0)
                    : nil
            )
        }
        self.naps = naps.prefix(sessionLimit).map {
            NapFingerprint(
                id: $0.id,
                start: $0.startDate,
                end: $0.endDate,
                durationMinutes: $0.durationMinutes,
                qualityRating: $0.qualityRating,
                source: $0.source.rawValue,
                timingCategory: $0.timingCategory.rawValue,
                note: $0.note,
                healthKitSampleIDs: $0.healthKitSampleIds.sorted().joined(separator: ","),
                updatedAt: $0.updatedAt
            )
        }
    }

    private static func relationshipFingerprint(for workout: WorkoutSession) -> String {
        workout.exerciseLogs
            .sorted { lhs, rhs in lhs.id.uuidString < rhs.id.uuidString }
            .map { log in
                let sets = log.setLogs
                    .sorted { lhs, rhs in lhs.id.uuidString < rhs.id.uuidString }
                    .map { set in
                        [
                            set.id.uuidString,
                            set.exerciseLogId.uuidString,
                            "\(set.setNumber)",
                            "\(set.weight)",
                            "\(set.reps)",
                            set.rpe.map { "\($0)" } ?? "nil",
                            String(set.isWarmup),
                            String(set.completed)
                        ].joined(separator: ":")
                    }
                    .joined(separator: ",")

                return [
                    log.id.uuidString,
                    log.workoutSessionId.uuidString,
                    log.exerciseId.uuidString,
                    log.exerciseNameSnapshot,
                    String(log.orderIndex),
                    String(log.targetSets),
                    String(log.minReps),
                    String(log.maxReps),
                    log.notes ?? "nil",
                    sets
                ].joined(separator: "|")
            }
            .joined(separator: ";")
    }
}

struct SleepAnalyticsSnapshot {
    var summaries: [SleepSummary]
    var latestSummary: SleepSummary
    var dashboardSummary: SleepDashboardSummary
    var generatedAt: Date
    var inputSignature: SleepAnalyticsInputSignature? = nil
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

    func snapshot(
        sessions: [SleepSession],
        naps: [NapSession] = [],
        workouts: [WorkoutSession],
        settings: SleepSettings,
        sessionLimit: Int = 90,
        workoutLimit: Int = 28,
        workoutRevision: Int? = nil,
        force: Bool = false
    ) -> SleepAnalyticsSnapshot {
        PerformanceTracer.mark(.unsafeBreadcrumb, "sleep.analytics.cache before_signature sessions=\(min(sessions.count, sessionLimit)) workouts=\(min(workouts.count, workoutLimit))")
        let signature = SleepAnalyticsInputSignature(
            sessions: sessions,
            naps: naps,
            workouts: workouts,
            settings: settings,
            sessionLimit: sessionLimit,
            workoutLimit: workoutLimit,
            workoutRevision: workoutRevision
        )

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
        var snapshot = service.snapshot(sessions: limitedSessions, naps: limitedNaps, workouts: limitedWorkouts, settings: settings)
        snapshot.inputSignature = signature
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

    func snapshot(
        sessions: [SleepSession],
        naps: [NapSession] = [],
        workouts: [WorkoutSession],
        settings: SleepSettings,
        sessionLimit: Int = 45,
        workoutLimit: Int = 12,
        workoutRevision: Int? = nil,
        force: Bool = false
    ) -> SleepWorkoutReadinessSnapshot {
        PerformanceTracer.mark(.unsafeBreadcrumb, "sleep.readiness.cache before_signature sessions=\(min(sessions.count, sessionLimit)) workouts=\(min(workouts.count, workoutLimit))")
        let effectiveWorkoutRevision = workoutRevision ?? SleepAnalyticsWorkoutGeneration.current
        let signature = SleepAnalyticsInputSignature(
            sessions: sessions,
            naps: naps,
            workouts: workouts,
            settings: settings,
            sessionLimit: sessionLimit,
            workoutLimit: workoutLimit,
            workoutRevision: effectiveWorkoutRevision
        )

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

    func snapshot(
        sessions: [SleepSession],
        naps: [NapSession] = [],
        workouts: [WorkoutSession],
        settings: SleepSettings,
        endingOn date: Date = .now,
        calendar: Calendar = .current
    ) -> SleepAnalyticsSnapshot {
        let sevenDaySummaries = scoring.summaries(
            from: sessions,
            naps: naps,
            workouts: workouts,
            settings: settings,
            days: 7,
            endingOn: date,
            calendar: calendar
        )
        let twentyEightDaySummaries = scoring.summaries(
            from: sessions,
            naps: naps,
            workouts: workouts,
            settings: settings,
            days: 28,
            endingOn: date,
            calendar: calendar
        )
        let lastNight = scoring.latestSummary(
            from: sessions,
            naps: naps,
            workouts: workouts,
            settings: settings,
            endingOn: date,
            calendar: calendar
        )

        return SleepAnalyticsSnapshot(
            summaries: sevenDaySummaries,
            latestSummary: lastNight,
            dashboardSummary: makeDashboardSummary(
                sessions: sessions,
                naps: naps,
                workouts: workouts,
                settings: settings,
                endingOn: date,
                calendar: calendar,
                sevenDaySummaries: sevenDaySummaries,
                twentyEightDaySummaries: twentyEightDaySummaries,
                lastNight: lastNight
            ),
            generatedAt: .now
        )
    }

    func workoutReadinessSnapshot(
        sessions: [SleepSession],
        naps: [NapSession] = [],
        workouts: [WorkoutSession],
        settings: SleepSettings,
        endingOn date: Date = .now,
        calendar: Calendar = .current
    ) -> SleepWorkoutReadinessSnapshot {
        let sevenDaySummaries = scoring.summaries(
            from: sessions,
            naps: naps,
            workouts: workouts,
            settings: settings,
            days: 7,
            endingOn: date,
            calendar: calendar
        )
        let lastNight = scoring.latestSummary(
            from: sessions,
            naps: naps,
            workouts: workouts,
            settings: settings,
            endingOn: date,
            calendar: calendar
        )
        let resolvedSleep = resolver.resolvedSessions(
            from: sessions,
            settings: settings,
            days: 14,
            endingOn: date,
            calendar: calendar
        )
        let correlations = correlationService.correlate(
            workouts: Array(workouts.prefix(12)),
            sleepSessions: resolvedSleep,
            historicalSleepSessions: sessions,
            settings: settings,
            endingOn: date,
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

    func dashboardSummary(
        sessions: [SleepSession],
        workouts: [WorkoutSession],
        settings: SleepSettings,
        endingOn date: Date = .now,
        calendar: Calendar = .current
    ) -> SleepDashboardSummary {
        dashboardSummary(
            sessions: sessions,
            naps: [],
            workouts: workouts,
            settings: settings,
            endingOn: date,
            calendar: calendar
        )
    }

    func dashboardSummary(
        sessions: [SleepSession],
        naps: [NapSession],
        workouts: [WorkoutSession],
        settings: SleepSettings,
        endingOn date: Date = .now,
        calendar: Calendar = .current
    ) -> SleepDashboardSummary {
        let sevenDaySummaries = scoring.summaries(
            from: sessions,
            naps: naps,
            workouts: workouts,
            settings: settings,
            days: 7,
            endingOn: date,
            calendar: calendar
        )
        let twentyEightDaySummaries = scoring.summaries(
            from: sessions,
            naps: naps,
            workouts: workouts,
            settings: settings,
            days: 28,
            endingOn: date,
            calendar: calendar
        )
        let lastNight = scoring.latestSummary(
            from: sessions,
            naps: naps,
            workouts: workouts,
            settings: settings,
            endingOn: date,
            calendar: calendar
        )
        return makeDashboardSummary(
            sessions: sessions,
            naps: naps,
            workouts: workouts,
            settings: settings,
            endingOn: date,
            calendar: calendar,
            sevenDaySummaries: sevenDaySummaries,
            twentyEightDaySummaries: twentyEightDaySummaries,
            lastNight: lastNight
        )
    }

    private func makeDashboardSummary(
        sessions: [SleepSession],
        naps: [NapSession],
        workouts: [WorkoutSession],
        settings: SleepSettings,
        endingOn evaluationDate: Date,
        calendar: Calendar,
        sevenDaySummaries: [SleepSummary],
        twentyEightDaySummaries: [SleepSummary],
        lastNight: SleepSummary
    ) -> SleepDashboardSummary {
        let resolvedSleep = resolver.resolvedSessions(
            from: sessions,
            settings: settings,
            days: 28,
            endingOn: evaluationDate,
            calendar: calendar
        )
        let correlations = correlationService.correlate(
            workouts: Array(workouts.prefix(28)),
            sleepSessions: resolvedSleep,
            historicalSleepSessions: sessions,
            settings: settings,
            endingOn: evaluationDate,
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
