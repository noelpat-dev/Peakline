import SwiftData
import SwiftUI

struct PRTimelineView: View {
    @Environment(\.appTheme) private var appTheme
    @Environment(\.modelContext) private var modelContext

    @State private var selectedSplit: String?
    @State private var allRecords: [PRRecord] = []
    @State private var weeklySummary: WeeklyTrainingSummary?
    @State private var lastSignature: String?
    @State private var isLoading = false
    @State private var didRequestInitialRefresh = false
    @State private var refreshTask: Task<Void, Never>?

    private static var completedSessionsDescriptor: FetchDescriptor<WorkoutSession> {
        var descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate<WorkoutSession> { $0.completed },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = 80
        descriptor.includePendingChanges = true
        return descriptor
    }

    private var records: [PRRecord] {
        guard let selectedSplit else { return allRecords }
        return allRecords.filter { $0.workoutSplitName == selectedSplit }
    }

    var body: some View {
        FitnessScreen(title: "PR Timeline", subtitle: "See what improved and when.", systemImage: "trophy.fill") {
            HStack(spacing: 10) {
                MetricTile(label: "Total PRs", value: "\(allRecords.count)", caption: "All time", systemImage: "trophy")
                MetricTile(label: "This week", value: "\(weeklySummary?.prCount ?? 0)", caption: "Recent", systemImage: "calendar")
            }

            if isLoading {
                FitnessCard(style: .compact) {
                    HStack(spacing: 10) {
                        Image(systemName: "hourglass")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(appTheme.colors.accent)
                        Text("Loading PR timeline")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(appTheme.colors.textSecondary)
                    }
                }
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
        .toolbar(.visible, for: .navigationBar)
        .accessibilityIdentifier("pr-timeline-screen")
        .onAppear {
            guard !didRequestInitialRefresh else { return }
            didRequestInitialRefresh = true
            refreshRecords(force: true)
        }
        .onDisappear {
            refreshTask?.cancel()
            isLoading = false
        }
    }

    private func refreshRecords(force: Bool = false) {
        guard !isLoading else { return }

        refreshTask?.cancel()

        let recentSessions: [WorkoutSession]
        do {
            recentSessions = try modelContext.fetch(Self.completedSessionsDescriptor)
        } catch {
            allRecords = []
            weeklySummary = nil
            isLoading = false
            return
        }

        let signature = Self.signature(for: recentSessions)
        guard force || signature != lastSignature else {
            isLoading = false
            return
        }

        let snapshots: [WorkoutAnalyticsSession]
        do {
            snapshots = try WorkoutAnalyticsSnapshotBuilder.snapshots(from: recentSessions, in: modelContext)
        } catch {
            allRecords = []
            weeklySummary = nil
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
                PerformanceTracer.trace(.prTimelineAnalytics) {
                    let analytics = TrainingAnalyticsService()
                    let records = analytics.prTimeline(from: snapshots)
                    let weekly = analytics.weeklySummary(from: snapshots, prRecords: records)
                    return (records, weekly)
                }
            }.value

            guard !Task.isCancelled else {
                isLoading = false
                return
            }
            allRecords = result.0
            weeklySummary = result.1
            lastSignature = signature
            isLoading = false
        }
    }

    private static func signature(for sessions: [WorkoutSession]) -> String {
        sessions
            .map { "\($0.id.uuidString):\($0.date.timeIntervalSince1970):\($0.endedAt?.timeIntervalSince1970 ?? 0)" }
            .joined(separator: "|")
    }
}
