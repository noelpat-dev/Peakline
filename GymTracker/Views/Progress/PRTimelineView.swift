import SwiftData
import SwiftUI

struct PRTimelineView: View {
    @Environment(\.appTheme) private var appTheme

    @Query(filter: #Predicate<WorkoutSession> { $0.completed }, sort: \WorkoutSession.date, order: .reverse)
    private var sessions: [WorkoutSession]

    @State private var selectedSplit: String?

    private let analytics = TrainingAnalyticsService()

    private var records: [PRRecord] {
        let all = analytics.prTimeline(from: sessions)
        guard let selectedSplit else { return all }
        return all.filter { $0.workoutSplitName == selectedSplit }
    }

    private var weeklySummary: WeeklyTrainingSummary {
        analytics.weeklySummary(from: sessions)
    }

    var body: some View {
        FitnessScreen(title: "PR Timeline", subtitle: "See what improved and when.", systemImage: "trophy.fill") {
            HStack(spacing: 10) {
                MetricTile(label: "Total PRs", value: "\(analytics.prTimeline(from: sessions).count)", caption: "All time", systemImage: "trophy")
                MetricTile(label: "This week", value: "\(weeklySummary.prCount)", caption: "Recent", systemImage: "calendar")
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    FilterChip("All", isSelected: selectedSplit == nil) {
                        selectedSplit = nil
                    }
                    ForEach(["Push", "Pull", "Legs"], id: \.self) { split in
                        FilterChip(split, isSelected: selectedSplit == split) {
                            selectedSplit = selectedSplit == split ? nil : split
                        }
                    }
                }
            }

            if records.isEmpty {
                FitnessCard {
                    Text("No PRs found yet. Log a few completed working sets and improvements will appear here.")
                        .font(.subheadline)
                        .foregroundStyle(appTheme.colors.textSecondary)
                }
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(records) { record in
                        FitnessCard {
                            HStack(alignment: .top, spacing: 12) {
                                ExerciseIconView(
                                    iconKey: ExerciseIconMapper.iconKey(forName: record.exerciseName),
                                    size: 36,
                                    showBackground: true,
                                    isDecorative: true
                                )

                                VStack(alignment: .leading, spacing: 5) {
                                    Text(record.exerciseName)
                                        .font(.headline)
                                    Text(record.improvementDescription)
                                        .font(.subheadline.weight(.semibold))
                                    Text("\(record.prType.displayName) - \(record.date.formatted(date: .abbreviated, time: .omitted))")
                                        .font(.caption)
                                        .foregroundStyle(appTheme.colors.textSecondary)
                                    if let previous = record.previousDisplayValue {
                                        Text("Previous: \(previous) -> New: \(record.displayValue)")
                                            .font(.caption)
                                            .foregroundStyle(appTheme.colors.textSecondary)
                                    }
                                }

                                Spacer()
                                CoachBadgeView(state: .pr)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("PR Timeline")
        .navigationBarTitleDisplayMode(.inline)
    }
}
