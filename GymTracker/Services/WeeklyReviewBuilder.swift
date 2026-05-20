import Foundation

struct WeeklyReview: Equatable {
    let title: String
    let dateRangeDescription: String
    let completedWorkouts: Int
    let workingSets: Int
    let prCount: Int
    let splitConsistency: SplitConsistencySummary
    let highlights: [CoachInsight]
    let watchlist: [CoachInsight]
    let nextDecision: TrainingDecision
}

struct CoachInsight: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let message: String
    let severity: CoachInsightSeverity
    let relatedExerciseName: String?
    let relatedSplitName: String?
}

enum CoachInsightSeverity: String, Codable {
    case info
    case positive
    case warning
    case recovery
}

struct TrainingDecision: Equatable {
    let recommendedSplitName: String?
    let recommendedMode: WorkoutMode
    let action: TrainingDecisionAction
    let title: String
    let reason: String
}

enum TrainingDecisionAction: String, Codable {
    case push
    case repeatTarget
    case recover
    case rebalance
    case buildBaseline

    var displayName: String {
        switch self {
        case .push:
            return "Push"
        case .repeatTarget:
            return "Repeat"
        case .recover:
            return "Recover"
        case .rebalance:
            return "Rebalance"
        case .buildBaseline:
            return "Build baseline"
        }
    }
}

struct WeeklyReviewBuilder {
    private let analytics = TrainingAnalyticsService()
    private let targetService = TargetSuggestionService()

    func build(activeSplits: [TrainingSplit], completedSessions: [WorkoutSession]) -> WeeklyReview {
        let weekly = analytics.weeklySummary(from: completedSessions)
        let consistency = analytics.splitConsistency(from: completedSessions)
        let decision = TrainingDecisionService().decision(activeSplits: activeSplits, completedSessions: completedSessions)
        let recentPRs = analytics.prTimeline(from: completedSessions).prefix(3)

        let highlights = recentPRs.map { pr in
            CoachInsight(
                title: pr.exerciseName,
                message: pr.improvementDescription,
                severity: .positive,
                relatedExerciseName: pr.exerciseName,
                relatedSplitName: pr.workoutSplitName
            )
        }

        let watchlist = makeWatchlist(activeSplits: activeSplits, completedSessions: completedSessions, consistency: consistency)

        return WeeklyReview(
            title: "This Week Review",
            dateRangeDescription: "\(weekly.weekStart.formatted(date: .abbreviated, time: .omitted)) - \(weekly.weekEnd.formatted(date: .abbreviated, time: .omitted))",
            completedWorkouts: weekly.completedWorkouts,
            workingSets: weekly.workingSets,
            prCount: weekly.prCount,
            splitConsistency: consistency,
            highlights: highlights,
            watchlist: watchlist,
            nextDecision: decision
        )
    }

    private func makeWatchlist(activeSplits: [TrainingSplit], completedSessions: [WorkoutSession], consistency: SplitConsistencySummary) -> [CoachInsight] {
        var insights: [CoachInsight] = []

        if let missed = consistency.missedSplitName {
            insights.append(
                CoachInsight(
                    title: "\(missed) due",
                    message: "Rebalance your week with \(missed) next.",
                    severity: .warning,
                    relatedExerciseName: nil,
                    relatedSplitName: missed
                )
            )
        }

        for split in activeSplits {
            for exercise in split.exercises.sorted(by: { $0.orderIndex < $1.orderIndex }).prefix(4) {
                let suggestion = targetService.suggestion(for: exercise, completedSessions: completedSessions)
                if suggestion.recommendationType == .fatigueRisk || suggestion.recommendationType == .possiblePlateau {
                    insights.append(
                        CoachInsight(
                            title: suggestion.exerciseName,
                            message: suggestion.reason,
                            severity: suggestion.recommendationType == .fatigueRisk ? .recovery : .warning,
                            relatedExerciseName: suggestion.exerciseName,
                            relatedSplitName: split.name
                        )
                    )
                }
            }
        }

        return Array(insights.prefix(5))
    }
}

struct TrainingDecisionService {
    private let coachEngine = CoachRecommendationEngine()
    private let targetService = TargetSuggestionService()
    private let analytics = TrainingAnalyticsService()

    func decision(activeSplits: [TrainingSplit], completedSessions: [WorkoutSession]) -> TrainingDecision {
        guard completedSessions.count >= 2 else {
            return TrainingDecision(
                recommendedSplitName: activeSplits.first?.name,
                recommendedMode: .full,
                action: .buildBaseline,
                title: "Build a baseline",
                reason: "Log clean sets so Peakline can make better targets."
            )
        }

        let consistency = analytics.splitConsistency(from: completedSessions)
        if let missed = consistency.missedSplitName, let split = activeSplits.first(where: { $0.name == missed }) {
            return TrainingDecision(
                recommendedSplitName: split.name,
                recommendedMode: .full,
                action: .rebalance,
                title: "Rebalance with \(split.name)",
                reason: "\(split.name) has not been trained this week."
            )
        }

        let summary = coachEngine.makeSummary(activeSplits: activeSplits, completedSessions: completedSessions)
        let split = summary.recommendedSplitName.flatMap { name in activeSplits.first { $0.name == name } } ?? activeSplits.first
        let suggestions = split?.exercises.map { targetService.suggestion(for: $0, completedSessions: completedSessions) } ?? []

        if suggestions.contains(where: { $0.recommendationType == .fatigueRisk }) || recentSkippedFatigue(in: completedSessions) {
            return TrainingDecision(
                recommendedSplitName: split?.name,
                recommendedMode: .recovery,
                action: .recover,
                title: "Recovery mode makes sense",
                reason: "Recent logs show fatigue risk or skipped work. Keep form clean and avoid forcing PRs."
            )
        }

        if suggestions.contains(where: { $0.recommendationType == .increaseLoad || $0.recommendationType == .addReps }) {
            return TrainingDecision(
                recommendedSplitName: split?.name,
                recommendedMode: .full,
                action: .push,
                title: "Push today",
                reason: "There are clear progression opportunities and no major drop-off on this split."
            )
        }

        return TrainingDecision(
            recommendedSplitName: split?.name,
            recommendedMode: .full,
            action: .repeatTarget,
            title: "Repeat targets",
            reason: "Aim for cleaner reps or one extra rep where possible."
        )
    }

    private func recentSkippedFatigue(in sessions: [WorkoutSession]) -> Bool {
        sessions.prefix(3).contains { session in
            session.exerciseLogs.contains { log in
                let notes = log.notes ?? ""
                return notes.localizedCaseInsensitiveContains("Too fatigued") || notes.localizedCaseInsensitiveContains("Pain / discomfort")
            }
        }
    }
}
