import SwiftData
import SwiftUI

struct CoachView: View {
    var body: some View {
        NavigationStack {
            CoachContentView()
        }
    }
}

struct CoachContentView: View {
    @Environment(\.appTheme) private var appTheme

    @Query(filter: #Predicate<TrainingSplit> { $0.isActive }, sort: \TrainingSplit.name)
    private var activeSplits: [TrainingSplit]

    @Query(filter: #Predicate<WorkoutSession> { $0.completed }, sort: \WorkoutSession.date, order: .reverse)
    private var completedSessions: [WorkoutSession]

    private let coachEngine = CoachRecommendationEngine()
    private let targetService = TargetSuggestionService()
    private let reviewBuilder = WeeklyReviewBuilder()
    private let analytics = TrainingAnalyticsService()

    private var recentCompletedSessions: [WorkoutSession] {
        Array(completedSessions.prefix(20))
    }

    private var summary: CoachRecommendationSummary {
        coachEngine.makeSummary(activeSplits: activeSplits, completedSessions: recentCompletedSessions)
    }

    private var weeklyReview: WeeklyReview {
        reviewBuilder.build(activeSplits: activeSplits, completedSessions: recentCompletedSessions)
    }

    private var recentPRs: [PRRecord] {
        Array(analytics.prTimeline(from: recentCompletedSessions).prefix(3))
    }

    private var recommendedSplit: TrainingSplit? {
        guard let splitName = summary.recommendedSplitName else { return nil }
        return activeSplits.first { $0.name == splitName }
    }

    private var targetSuggestions: [TargetSuggestion] {
        guard let recommendedSplit else { return [] }

        return recommendedSplit.exercises
            .sorted { $0.orderIndex < $1.orderIndex }
            .prefix(4)
            .map { targetService.suggestion(for: $0, completedSessions: recentCompletedSessions) }
    }

    private var weeklyWorkoutCount: Int {
        recentCompletedSessions.filter { Calendar.current.isDate($0.date, equalTo: .now, toGranularity: .weekOfYear) }.count
    }

    private var weeklyWorkingSetCount: Int {
        recentCompletedSessions
            .filter { Calendar.current.isDate($0.date, equalTo: .now, toGranularity: .weekOfYear) }
            .reduce(0) { total, session in
                total + session.exerciseLogs.flatMap(\.setLogs).filter { $0.completed && !$0.isWarmup }.count
            }
    }

    var body: some View {
        FitnessScreen(
            title: "Coach",
            subtitle: "Readiness, targets, and recovery.",
            systemImage: "sparkles"
        ) {
            FitnessCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top) {
                        ExerciseIconTile(
                            iconKey: ExerciseIconMapper.splitIconKey(for: summary.recommendedSplitName ?? ""),
                            title: nil,
                            size: 58,
                            style: .compact
                        )

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Next Workout")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(appTheme.mutedText)
                                .textCase(.uppercase)

                            Text(summary.recommendedSplitName ?? "No recommendation yet")
                                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                        }

                        Spacer()
                        CoachBadgeView(state: summary.recommendedSplitName == nil ? .baseline : .ready)
                    }

                    Text(summary.reason)
                        .font(.subheadline)
                        .foregroundStyle(appTheme.mutedText)
                }
            }

            FitnessCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Next Training Decision")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(appTheme.mutedText)
                                .textCase(.uppercase)
                            Text(weeklyReview.nextDecision.title)
                                .font(.title2.bold())
                        }
                        Spacer()
                        CoachBadgeView(state: badgeState(for: weeklyReview.nextDecision.action))
                    }

                    Text("Next: \(weeklyReview.nextDecision.recommendedSplitName ?? "Any split") - \(weeklyReview.nextDecision.recommendedMode.displayName)")
                        .font(.subheadline.weight(.semibold))
                    Text(weeklyReview.nextDecision.reason)
                        .font(.subheadline)
                        .foregroundStyle(appTheme.mutedText)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Today's Targets")
                    .font(.headline)

                if targetSuggestions.isEmpty {
                    FitnessCard {
                        Text("Complete a workout from your split to get load and rep targets.")
                            .font(.subheadline)
                            .foregroundStyle(appTheme.mutedText)
                    }
                } else {
                    ForEach(targetSuggestions, id: \.self) { suggestion in
                        FitnessCard {
                            ExerciseTargetRow(suggestion: suggestion)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Recovery Warnings")
                    .font(.headline)

                if summary.recoveryWarnings.isEmpty {
                    FitnessCard {
                        HStack(spacing: 10) {
                            CoachBadgeView(state: .ready)
                            Text("No major recovery warnings right now.")
                                .font(.subheadline)
                                .foregroundStyle(appTheme.mutedText)
                        }
                    }
                } else {
                    ForEach(summary.recoveryWarnings) { warning in
                        FitnessCard {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(warning.title)
                                        .font(.headline)
                                    Spacer()
                                    CoachBadgeView(state: warningBadgeState(for: warning.severity))
                                }

                                Text(warning.message)
                                    .font(.subheadline)
                                    .foregroundStyle(appTheme.mutedText)
                            }
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("This Week Review")
                        .font(.headline)
                    Spacer()
                    NavigationLink {
                        WeeklyReviewView()
                    } label: {
                        Text("Details")
                            .font(.subheadline.weight(.semibold))
                    }
                }

                FitnessCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 10) {
                            MetricTile(
                                label: "Workouts",
                                value: "\(weeklyWorkoutCount)",
                                caption: "This week",
                                systemImage: "figure.strengthtraining.traditional"
                            )

                            MetricTile(
                                label: "Sets",
                                value: "\(weeklyWorkingSetCount)",
                                caption: "Working sets",
                                systemImage: "checkmark.circle"
                            )
                        }

                        HStack(spacing: 10) {
                            MetricTile(label: "PRs", value: "\(weeklyReview.prCount)", caption: "This week", systemImage: "trophy")
                            MetricTile(label: "Balance", value: splitBalanceText, caption: nil, systemImage: "scale.3d")
                        }

                        if summary.weeklyInsights.isEmpty {
                            Text("Finish workouts to build a weekly summary.")
                                .font(.subheadline)
                                .foregroundStyle(appTheme.mutedText)
                        } else {
                            ForEach(summary.weeklyInsights, id: \.self) { insight in
                                Text(insight)
                                    .font(.subheadline)
                                    .foregroundStyle(appTheme.mutedText)
                            }
                        }
                    }
                }
            }

            insightList(title: "Progress Opportunities", insights: progressOpportunityInsights, empty: "No obvious load jumps yet. Repeat targets and build clean reps.")
            insightList(title: "Watchlist", insights: weeklyReview.watchlist, empty: "No major fatigue or plateau warnings right now.")

            VStack(alignment: .leading, spacing: 10) {
                Text("Recent PRs")
                    .font(.headline)

                if recentPRs.isEmpty {
                    FitnessCard {
                        Text("PRs will appear here when a completed working set beats prior history.")
                            .font(.subheadline)
                            .foregroundStyle(appTheme.mutedText)
                    }
                } else {
                    ForEach(recentPRs) { pr in
                        FitnessCard {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(pr.exerciseName)
                                        .font(.headline)
                                    Text(pr.improvementDescription)
                                        .font(.subheadline)
                                        .foregroundStyle(appTheme.mutedText)
                                }
                                Spacer()
                                CoachBadgeView(state: .pr)
                            }
                        }
                    }
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private var progressOpportunityInsights: [CoachInsight] {
        targetSuggestions
            .filter { $0.recommendationType == .increaseLoad || $0.recommendationType == .addReps }
            .prefix(4)
            .map { suggestion in
                CoachInsight(
                    title: suggestion.exerciseName,
                    message: suggestion.reason,
                    severity: .positive,
                    relatedExerciseName: suggestion.exerciseName,
                    relatedSplitName: recommendedSplit?.name
                )
            }
    }

    private var splitBalanceText: String {
        let split = weeklyReview.splitConsistency
        return "\(split.pushCount)/\(split.pullCount)/\(split.legsCount)"
    }

    private func warningBadgeState(for priority: CoachPriority) -> CoachBadgeState {
        switch priority {
        case .low:
            return .repeatTarget
        case .medium:
            return .fatigueRisk
        case .high:
            return .possiblePlateau
        }
    }

    private func badgeState(for action: TrainingDecisionAction) -> CoachBadgeState {
        switch action {
        case .push:
            return .ready
        case .repeatTarget:
            return .repeatTarget
        case .recover:
            return .recovery
        case .rebalance:
            return .missedSplit
        case .buildBaseline:
            return .baseline
        }
    }

    private func insightList(title: String, insights: [CoachInsight], empty: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)

            if insights.isEmpty {
                FitnessCard {
                    Text(empty)
                        .font(.subheadline)
                        .foregroundStyle(appTheme.mutedText)
                }
            } else {
                ForEach(insights) { insight in
                    FitnessCard {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(insight.title)
                                    .font(.headline)
                                Text(insight.message)
                                    .font(.subheadline)
                                    .foregroundStyle(appTheme.mutedText)
                            }
                            Spacer()
                            CoachBadgeView(state: badgeState(for: insight.severity))
                        }
                    }
                }
            }
        }
    }

    private func badgeState(for severity: CoachInsightSeverity) -> CoachBadgeState {
        switch severity {
        case .info:
            return .repeatTarget
        case .positive:
            return .ready
        case .warning:
            return .possiblePlateau
        case .recovery:
            return .fatigueRisk
        }
    }
}
