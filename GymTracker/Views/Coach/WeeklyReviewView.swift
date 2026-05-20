import SwiftData
import SwiftUI

struct WeeklyReviewView: View {
    @Environment(\.appTheme) private var appTheme

    @Query(filter: #Predicate<TrainingSplit> { $0.isActive }, sort: \TrainingSplit.name)
    private var activeSplits: [TrainingSplit]

    @Query(filter: #Predicate<WorkoutSession> { $0.completed }, sort: \WorkoutSession.date, order: .reverse)
    private var completedSessions: [WorkoutSession]

    private let builder = WeeklyReviewBuilder()

    private var review: WeeklyReview {
        builder.build(activeSplits: activeSplits, completedSessions: completedSessions)
    }

    var body: some View {
        FitnessScreen(title: "Weekly Review", subtitle: review.dateRangeDescription, systemImage: "calendar.badge.clock") {
            FitnessCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text(review.nextDecision.title)
                        .font(.title3.bold())
                    Text(review.nextDecision.reason)
                        .font(.subheadline)
                        .foregroundStyle(appTheme.colors.textSecondary)
                    HStack(spacing: 10) {
                        MetricTile(label: "Workouts", value: "\(review.completedWorkouts)", caption: "This week", systemImage: "figure.strengthtraining.traditional")
                        MetricTile(label: "PRs", value: "\(review.prCount)", caption: "Improved", systemImage: "trophy")
                    }
                }
            }

            FitnessCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Split Balance")
                        .font(.headline)
                    Text("Push \(review.splitConsistency.pushCount) - Pull \(review.splitConsistency.pullCount) - Legs \(review.splitConsistency.legsCount)")
                        .font(.subheadline.weight(.semibold))
                    Text(review.splitConsistency.balanceDescription)
                        .font(.subheadline)
                        .foregroundStyle(appTheme.colors.textSecondary)
                }
            }

            insightSection("Highlights", insights: review.highlights, empty: "No PR highlights yet this week.")
            insightSection("Watchlist", insights: review.watchlist, empty: "No major watchlist items right now.")
        }
        .navigationTitle("Weekly Review")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func insightSection(_ title: String, insights: [CoachInsight], empty: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)

            if insights.isEmpty {
                FitnessCard {
                    Text(empty)
                        .font(.subheadline)
                        .foregroundStyle(appTheme.colors.textSecondary)
                }
            } else {
                ForEach(insights) { insight in
                    FitnessCard {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(insight.title)
                                .font(.headline)
                            Text(insight.message)
                                .font(.subheadline)
                                .foregroundStyle(appTheme.colors.textSecondary)
                        }
                    }
                }
            }
        }
    }
}
