import Foundation
import SwiftData
import UserNotifications

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
