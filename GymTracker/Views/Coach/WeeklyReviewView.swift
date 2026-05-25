import SwiftData
import SwiftUI

struct WeeklyReviewView: View {
    @Environment(\.appTheme) private var appTheme
    @Environment(\.modelContext) private var modelContext

    @State private var review: WeeklyReview?
    @State private var lastSignature: String?
    @State private var isLoading = false
    @State private var didRequestInitialRefresh = false
    @State private var refreshTask: Task<Void, Never>?

    private static var activeSplitsDescriptor: FetchDescriptor<TrainingSplit> {
        var descriptor = FetchDescriptor<TrainingSplit>(
            predicate: #Predicate<TrainingSplit> { $0.isActive },
            sortBy: [SortDescriptor(\.name)]
        )
        descriptor.fetchLimit = 12
        descriptor.includePendingChanges = true
        return descriptor
    }

    private static var completedSessionsDescriptor: FetchDescriptor<WorkoutSession> {
        var descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate<WorkoutSession> { $0.completed },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = 80
        descriptor.includePendingChanges = true
        return descriptor
    }

    var body: some View {
        FitnessScreen(title: "Weekly Review", subtitle: review?.dateRangeDescription ?? "This week", systemImage: "calendar.badge.clock") {
            if let review {
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
            } else {
                FitnessCard(style: .compact) {
                    HStack(spacing: 10) {
                        Image(systemName: "hourglass")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(appTheme.colors.accent)
                        Text("Preparing weekly review")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(appTheme.colors.textSecondary)
                    }
                }
            }
        }
        .navigationTitle("Weekly Review")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("weekly-review-screen")
        .onAppear {
            guard !didRequestInitialRefresh else { return }
            didRequestInitialRefresh = true
            refreshReview(force: true)
        }
        .onDisappear {
            refreshTask?.cancel()
            isLoading = false
        }
    }

    private func refreshReview(force: Bool = false) {
        guard !isLoading else { return }

        refreshTask?.cancel()

        let splits: [TrainingSplit]
        let sessions: [WorkoutSession]
        do {
            splits = try modelContext.fetch(Self.activeSplitsDescriptor)
            sessions = try modelContext.fetch(Self.completedSessionsDescriptor)
        } catch {
            review = nil
            isLoading = false
            return
        }

        let signature = Self.signature(activeSplits: splits, completedSessions: sessions)
        guard force || signature != lastSignature else {
            isLoading = false
            return
        }

        let splitSnapshots: [TrainingSplitSnapshot]
        let sessionSnapshots: [WorkoutAnalyticsSession]
        do {
            splitSnapshots = try TrainingSplitSnapshotBuilder.snapshots(from: splits, in: modelContext)
            sessionSnapshots = try WorkoutAnalyticsSnapshotBuilder.snapshots(from: sessions, in: modelContext)
        } catch {
            review = nil
            isLoading = false
            return
        }

        isLoading = true
        refreshTask = Task { @MainActor in
            guard !Task.isCancelled else {
                isLoading = false
                return
            }

            let result = await Task.detached(priority: .userInitiated) {
                WeeklyReviewBuilder().build(activeSplits: splitSnapshots, completedSessions: sessionSnapshots)
            }.value

            guard !Task.isCancelled else {
                isLoading = false
                return
            }
            review = result
            lastSignature = signature
            isLoading = false
        }
    }

    private static func signature(activeSplits: [TrainingSplit], completedSessions: [WorkoutSession]) -> String {
        [
            activeSplits
                .map { "\($0.id.uuidString):\($0.updatedAt.timeIntervalSince1970)" }
                .joined(separator: ","),
            completedSessions
                .map { "\($0.id.uuidString):\($0.date.timeIntervalSince1970):\($0.endedAt?.timeIntervalSince1970 ?? 0)" }
                .joined(separator: ",")
        ].joined(separator: "|")
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
