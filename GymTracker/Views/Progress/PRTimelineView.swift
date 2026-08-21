import SwiftData
import SwiftUI

struct PRTimelineView: View {
    @Environment(\.appTheme) private var appTheme
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var workoutWarmStartInvalidation = WorkoutWarmStartInvalidation.shared

    @State private var selectedSplit: String?
    @State private var allRecords: [PRRecord] = []
    @State private var weeklySummary: WeeklyTrainingSummary?
    @State private var lastSignature: String?
    @State private var observedSplitNames: [String] = []
    @State private var isLoading = false
    @State private var didRequestInitialRefresh = false
    @State private var refreshTask: Task<Void, Never>?
    @State private var refreshPending = false

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
        return allRecords.filter {
            guard let splitName = $0.workoutSplitName else { return false }
            return splitName.caseInsensitiveCompare(selectedSplit) == .orderedSame
        }
    }

    private var splitFilterOptions: [String] {
        PRTimelineFilterOptions.options(from: observedSplitNames)
    }

    var body: some View {
        FitnessScreen(title: "PR Timeline", subtitle: "See what improved and when.", systemImage: "trophy.fill") {
            HStack(spacing: 10) {
                MetricTile(label: "Total PRs", value: isLoading ? "—" : "\(allRecords.count)", caption: "Recent sessions", systemImage: "trophy")
                MetricTile(label: "This week", value: isLoading ? "—" : "\(weeklySummary?.prCount ?? 0)", caption: "Recent", systemImage: "calendar")
            }

            if isLoading {
                FitnessCard(style: .compact) {
                    HStack(spacing: 10) {
                        Image(systemName: "hourglass")
                            .font(AppTypography.bodyEmphasis)
                            .foregroundStyle(appTheme.colors.textAccent)
                        Text("Loading PR timeline")
                            .font(AppTypography.bodyEmphasis)
                            .foregroundStyle(appTheme.colors.textSecondary)
                    }
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(splitFilterOptions, id: \.self) { split in
                        let isAll = split == PRTimelineFilterOptions.all
                        FilterChip(split, isSelected: isAll ? selectedSplit == nil : selectedSplit == split) {
                            if isAll {
                                selectedSplit = nil
                            } else {
                                selectedSplit = selectedSplit == split ? nil : split
                            }
                        }
                    }
                }
            }

            if records.isEmpty && !isLoading {
                FitnessCard {
                    Text("No PRs found yet. Log a few completed working sets and improvements will appear here.")
                        .font(AppTypography.body)
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
                                        .font(AppTypography.sectionTitle)
                                    Text(record.improvementDescription)
                                        .font(AppTypography.bodyEmphasis)
                                    Text(
                                        PeaklineText.joinedMetadata([
                                            record.prType.displayName,
                                            record.date.formatted(date: .abbreviated, time: .omitted)
                                        ])
                                    )
                                        .font(AppTypography.metadata)
                                        .foregroundStyle(appTheme.colors.textSecondary)
                                    if let previous = record.previousDisplayValue {
                                        Text("Previous: \(previous) → New: \(record.displayValue)")
                                            .font(AppTypography.metadata)
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
        .accessibilityIdentifier("pr-timeline-screen")
        .onAppear {
            let force = !didRequestInitialRefresh
            didRequestInitialRefresh = true
            refreshRecords(force: force)
        }
        .onChange(of: workoutWarmStartInvalidation.revision) { _, _ in
            refreshRecords()
        }
        .onDisappear {
            refreshTask?.cancel()
            isLoading = false
            refreshPending = false
        }
    }

    private func refreshRecords(force: Bool = false) {
        guard !isLoading else {
            refreshPending = true
            return
        }

        refreshTask?.cancel()

        let recentSessions: [WorkoutSession]
        do {
            recentSessions = try modelContext.fetch(Self.completedSessionsDescriptor)
        } catch {
            allRecords = []
            weeklySummary = nil
            observedSplitNames = []
            selectedSplit = nil
            isLoading = false
            return
        }

        let nextObservedSplitNames = PRTimelineFilterOptions.splitNames(
            from: recentSessions.map(\.splitNameSnapshot)
        )
        self.observedSplitNames = nextObservedSplitNames
        if let selectedSplit,
           !nextObservedSplitNames.contains(where: { $0.caseInsensitiveCompare(selectedSplit) == .orderedSame }) {
            self.selectedSplit = nil
        }

        let signature = Self.signature(
            for: recentSessions,
            invalidationRevision: workoutWarmStartInvalidation.revision
        )
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
            self.observedSplitNames = []
            selectedSplit = nil
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
            if refreshPending {
                refreshPending = false
                refreshRecords()
            }
        }
    }

    private static func signature(
        for sessions: [WorkoutSession],
        invalidationRevision: Int
    ) -> String {
        [
            "revision:\(invalidationRevision)",
            sessions
                .map { "\($0.id.uuidString):\($0.date.timeIntervalSince1970):\($0.endedAt?.timeIntervalSince1970 ?? 0):\($0.splitNameSnapshot)" }
                .joined(separator: "|")
        ]
        .joined(separator: "|")
    }
}

enum PRTimelineFilterOptions {
    static let all = "All"

    static func options(from splitNameSnapshots: [String]) -> [String] {
        [all] + splitNames(from: splitNameSnapshots)
    }

    static func splitNames(from splitNameSnapshots: [String]) -> [String] {
        var namesByKey: [String: String] = [:]

        for snapshot in splitNameSnapshots {
            let baseName = snapshot
                .components(separatedBy: " - ")
                .first?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !baseName.isEmpty,
                  baseName.caseInsensitiveCompare(all) != .orderedSame else { continue }

            let key = baseName.lowercased()
            if let existing = namesByKey[key] {
                namesByKey[key] = min(existing, baseName)
            } else {
                namesByKey[key] = baseName
            }
        }

        return namesByKey.values.sorted {
            let comparison = $0.localizedCaseInsensitiveCompare($1)
            return comparison == .orderedSame ? $0 < $1 : comparison == .orderedAscending
        }
    }
}
