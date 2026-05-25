import Charts
import SwiftData
import SwiftUI

struct ProgressView: View {
    var body: some View {
        NavigationStack {
            ProgressContentView()
        }
    }
}

struct ProgressContentView: View {
    @Environment(\.appTheme) private var appTheme
    @Environment(\.modelContext) private var modelContext

    @State private var exercises: [Exercise] = []
    @State private var exercisesLoaded = false
    @State private var selectedExercise: Exercise?
    @State private var isExerciseChartsPresented = false
    @State private var isPRTimelinePresented = false
    @State private var didRequestInitialRefresh = false
    @State private var weeklySummary: WeeklyTrainingSummary?
    @State private var splitConsistency: SplitConsistencySummary?
    @State private var lastSummarySignature: String?
    @State private var summaryTask: Task<Void, Never>?

    private let analytics = TrainingAnalyticsService()

    private static var exercisesDescriptor: FetchDescriptor<Exercise> {
        var descriptor = FetchDescriptor<Exercise>(
            predicate: #Predicate<Exercise> { !$0.isArchived },
            sortBy: [SortDescriptor(\.name)]
        )
        descriptor.fetchLimit = 120
        return descriptor
    }

    private static var completedSessionsDescriptor: FetchDescriptor<WorkoutSession> {
        var descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate<WorkoutSession> { $0.completed },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = 40
        descriptor.includePendingChanges = true
        return descriptor
    }

    private var displayedWeeklySummary: WeeklyTrainingSummary {
        weeklySummary ?? analytics.weeklySummary(from: [WorkoutAnalyticsSession]())
    }

    private var displayedSplitConsistency: SplitConsistencySummary {
        splitConsistency ?? analytics.splitConsistency(from: [WorkoutAnalyticsSession]())
    }

    var body: some View {
        FitnessScreen(
            title: "Progress",
            subtitle: "Lift trends, PRs, and weekly training balance.",
            systemImage: "chart.xyaxis.line"
        ) {
            DashboardSection(title: "This Week") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        MetricTile(label: "Workouts", value: "\(displayedWeeklySummary.completedWorkouts)", caption: "Completed", systemImage: "figure.strengthtraining.traditional")
                        MetricTile(label: "Sets", value: "\(displayedWeeklySummary.workingSets)", caption: "Working", systemImage: "checkmark.circle")
                    }
                    HStack(spacing: 10) {
                        MetricTile(label: "Best-set vol", value: format(displayedWeeklySummary.bestSetVolumeTotal), caption: "kg total", systemImage: "chart.bar")
                        MetricTile(label: "Tonnage", value: format(displayedWeeklySummary.totalTonnage), caption: "kg total", systemImage: "sum")
                    }
                    FitnessCard(style: .compact, padding: 16) {
                        Text("Push \(displayedSplitConsistency.pushCount) - Pull \(displayedSplitConsistency.pullCount) - Legs \(displayedSplitConsistency.legsCount). \(displayedSplitConsistency.balanceDescription)")
                            .font(.subheadline)
                            .foregroundStyle(appTheme.colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            DashboardSection(title: "Progress Charts") {
                if !exercisesLoaded {
                    progressLoadingCard
                } else if exercises.isEmpty {
                    DashboardEmptyStateCard(
                        title: "More data needed",
                        message: "Add exercises and finish workouts to unlock progress charts.",
                        systemImage: "chart.xyaxis.line"
                    )
                } else {
                    HStack(spacing: 12) {
                        Button {
                            isExerciseChartsPresented = true
                        } label: {
                            ProgressActionCard(title: "Exercise Charts", subtitle: "Open lazy-loaded trends", systemImage: "chart.xyaxis.line")
                        }
                        .buttonStyle(PressableCardButtonStyle())

                        Button {
                            isPRTimelinePresented = true
                        } label: {
                            ProgressActionCard(title: "PR Timeline", subtitle: "Review best-set jumps", systemImage: "trophy.fill")
                        }
                        .buttonStyle(PressableCardButtonStyle())
                        .accessibilityIdentifier("progress-pr-timeline-open")
                    }
                }
            }

            DashboardSection(title: "Exercises") {
                if !exercisesLoaded {
                    progressLoadingCard
                } else if exercises.isEmpty {
                    DashboardEmptyStateCard(
                        title: "No exercises yet",
                        message: "Create split exercises to build a progress dashboard.",
                        systemImage: "dumbbell"
                    )
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(exercises) { exercise in
                            Button {
                                selectedExercise = exercise
                            } label: {
                                FitnessCard(padding: 16) {
                                    HStack(spacing: 12) {
                                        ExerciseIconView(
                                            iconKey: ExerciseIconMapper.iconKey(for: exercise),
                                            size: 40,
                                            showBackground: true,
                                            isDecorative: true
                                        )

                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(exercise.name)
                                                .font(.headline)
                                                .foregroundStyle(appTheme.colors.textPrimary)
                                                .lineLimit(1)
                                                .minimumScaleFactor(0.8)
                                            Text(exercise.primaryMuscleGroup.displayName)
                                                .font(.subheadline)
                                                .foregroundStyle(appTheme.colors.textSecondary)
                                        }

                                        Spacer()

                                        Image(systemName: "chevron.right")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(appTheme.colors.textTertiary)
                                    }
                                }
                            }
                            .buttonStyle(PressableCardButtonStyle())
                        }
                    }
                }
            }
        }
        .navigationTitle("Progress")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .navigationDestination(isPresented: $isExerciseChartsPresented) {
            ExerciseProgressChartsIndexView(exercises: exercises, selectedExercise: $selectedExercise)
        }
        .navigationDestination(isPresented: $isPRTimelinePresented) {
            PRTimelineView()
        }
        .navigationDestination(item: $selectedExercise) { exercise in
            ExerciseProgressDetailView(exercise: exercise)
        }
        .onAppear {
            guard !didRequestInitialRefresh else { return }
            didRequestInitialRefresh = true
            refreshExercises(force: true)
            refreshSummary(force: true)
        }
        .onDisappear {
            summaryTask?.cancel()
        }
    }

    private var progressLoadingCard: some View {
        FitnessCard(style: .compact) {
            HStack(spacing: 10) {
                Image(systemName: "hourglass")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(appTheme.colors.accent)
                Text("Loading progress data")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(appTheme.colors.textSecondary)
            }
        }
    }

    private func refreshExercises(force: Bool = false) {
        guard force || !exercisesLoaded else { return }

        do {
            exercises = try PerformanceTracer.trace(.progressFetchExercises) {
                try modelContext.fetch(Self.exercisesDescriptor)
            }
        } catch {
            exercises = []
        }
        exercisesLoaded = true
    }

    private func refreshSummary(force: Bool = false) {
        summaryTask?.cancel()

        let recentSessions: [WorkoutSession]
        do {
            recentSessions = try modelContext.fetch(Self.completedSessionsDescriptor)
        } catch {
            weeklySummary = nil
            splitConsistency = nil
            return
        }

        let signature = Self.summarySignature(for: recentSessions)
        guard force || signature != lastSummarySignature else { return }

        let snapshots: [WorkoutAnalyticsSession]
        do {
            snapshots = try WorkoutAnalyticsSnapshotBuilder.snapshots(from: recentSessions, in: modelContext)
        } catch {
            weeklySummary = nil
            splitConsistency = nil
            return
        }

        summaryTask = Task { @MainActor in
            guard !Task.isCancelled else { return }
            let result = await Task.detached(priority: .userInitiated) {
                PerformanceTracer.trace(.progressAnalytics) {
                    let analytics = TrainingAnalyticsService()
                    let records = analytics.prTimeline(from: snapshots)
                    let weekly = analytics.weeklySummary(from: snapshots, prRecords: records)
                    let consistency = analytics.splitConsistency(from: snapshots)
                    return (weekly, consistency)
                }
            }.value

            guard !Task.isCancelled else { return }
            weeklySummary = result.0
            splitConsistency = result.1
            lastSummarySignature = signature
        }
    }

    private static func summarySignature(for sessions: [WorkoutSession]) -> String {
        sessions
            .map { "\($0.id.uuidString):\($0.date.timeIntervalSince1970):\($0.endedAt?.timeIntervalSince1970 ?? 0)" }
            .joined(separator: "|")
    }

    private func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(value.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 1)))
    }
}

private struct ProgressActionCard: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        DashboardActionTile(title: title, subtitle: subtitle, systemImage: systemImage, showsChevron: false)
    }
}

private struct ExerciseProgressDetailView: View {
    @Environment(\.appTheme) private var appTheme

    let exercise: Exercise

    @Query
    private var sessions: [WorkoutSession]

    init(exercise: Exercise) {
        self.exercise = exercise
        _sessions = Query(Self.completedSessionsDescriptor)
    }

    private static var completedSessionsDescriptor: FetchDescriptor<WorkoutSession> {
        var descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate<WorkoutSession> { $0.completed },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = 160
        return descriptor
    }

    private var entries: [ExerciseProgressEntry] {
        sessions.compactMap { session in
            guard let exerciseLog = session.exerciseLogs.first(where: { $0.exerciseId == exercise.id }) else {
                return nil
            }

            let sets = exerciseLog.setLogs
                .filter { $0.completed && !$0.isWarmup }
                .sorted { $0.setNumber < $1.setNumber }

            guard !sets.isEmpty else { return nil }
            return ExerciseProgressEntry(session: session, sets: sets)
        }
    }

    var body: some View {
        FitnessScreen(
            title: exercise.name,
            subtitle: exercise.primaryMuscleGroup.displayName,
            systemImage: "chart.xyaxis.line"
        ) {
            if let latest = entries.first {
                DashboardSection(title: "Latest") {
                    HStack(spacing: 10) {
                        MetricTile(label: "Best set", value: latest.bestSetText, caption: nil, systemImage: "dumbbell")
                        MetricTile(label: "Est. 1RM", value: latest.estimatedOneRepMaxText, caption: nil, systemImage: "gauge.with.dots.needle.67percent")
                    }
                    HStack(spacing: 10) {
                        MetricTile(label: "Best-set vol", value: latest.bestSetVolumeText, caption: nil, systemImage: "chart.bar")
                        MetricTile(label: "Sets", value: "\(latest.completedSets)", caption: "Latest session", systemImage: "checkmark.circle")
                    }
                }
            }

            DashboardSection(title: "Chart") {
                if entries.count < 2 {
                    DashboardEmptyStateCard(
                        title: "More data needed",
                        message: "Log this exercise in at least two sessions to show a trend.",
                        systemImage: "chart.line.uptrend.xyaxis"
                    )
                } else {
                    FitnessCard {
                        ExerciseTrendChart(entries: entries.reversed())
                            .frame(height: 220)
                    }
                }
            }

            DashboardSection(title: "History") {
                if entries.isEmpty {
                    DashboardEmptyStateCard(
                        title: "No completed working sets yet",
                        message: "Finish a set for this exercise to start its progress history.",
                        systemImage: "checkmark.circle"
                    )
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(entries) { entry in
                            FitnessCard(padding: 16) {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(entry.session.date.formatted(date: .abbreviated, time: .omitted))
                                        .font(.headline)
                                    Text(entry.setsText)
                                        .font(.subheadline)
                                        .foregroundStyle(appTheme.colors.textSecondary)
                                        .lineLimit(2)
                                    Text("Best-set volume \(entry.bestSetVolumeText) - est. 1RM \(entry.estimatedOneRepMaxText)")
                                        .font(.caption)
                                        .foregroundStyle(appTheme.colors.textSecondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(exercise.name)
    }
}

private struct ExerciseProgressChartsIndexView: View {
    @Environment(\.appTheme) private var appTheme

    let exercises: [Exercise]
    @Binding var selectedExercise: Exercise?

    var body: some View {
        FitnessScreen(
            title: "Progress Charts",
            subtitle: "Open one exercise at a time to keep charts fast.",
            systemImage: "chart.xyaxis.line"
        ) {
            LazyVStack(spacing: 12) {
                ForEach(exercises) { exercise in
                    Button {
                        selectedExercise = exercise
                    } label: {
                        FitnessCard(padding: 16) {
                            HStack(spacing: 12) {
                                ExerciseIconView(
                                    iconKey: ExerciseIconMapper.iconKey(for: exercise),
                                    size: 40,
                                    showBackground: true,
                                    isDecorative: true
                                )

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(exercise.name)
                                        .font(.headline)
                                    Text(exercise.primaryMuscleGroup.displayName)
                                        .font(.subheadline)
                                        .foregroundStyle(appTheme.colors.textSecondary)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(appTheme.colors.textTertiary)
                            }
                        }
                    }
                    .buttonStyle(PressableCardButtonStyle())
                }
            }
        }
        .navigationTitle("Progress Charts")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }
}

private struct ExerciseTrendChart: View {
    @Environment(\.appTheme) private var appTheme
    let entries: ReversedCollection<[ExerciseProgressEntry]>

    var body: some View {
        Chart(Array(entries)) { entry in
            LineMark(
                x: .value("Date", entry.session.date),
                y: .value("Estimated 1RM", entry.estimatedOneRepMax)
            )
            .foregroundStyle(appTheme.colors.accent)

            PointMark(
                x: .value("Date", entry.session.date),
                y: .value("Estimated 1RM", entry.estimatedOneRepMax)
            )
            .foregroundStyle(appTheme.colors.accent)
        }
        .chartYAxisLabel("Est. 1RM kg")
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine()
                    .foregroundStyle(appTheme.colors.cardBorder)
                AxisTick()
                    .foregroundStyle(appTheme.colors.cardBorder)
                AxisValueLabel()
                    .foregroundStyle(appTheme.colors.textSecondary)
            }
        }
        .chartYAxis {
            AxisMarks { _ in
                AxisGridLine()
                    .foregroundStyle(appTheme.colors.cardBorder)
                AxisTick()
                    .foregroundStyle(appTheme.colors.cardBorder)
                AxisValueLabel()
                    .foregroundStyle(appTheme.colors.textSecondary)
            }
        }
    }
}

private struct ExerciseProgressEntry: Identifiable {
    let session: WorkoutSession
    let sets: [SetLog]

    var id: UUID {
        session.id
    }

    var completedSets: Int {
        sets.count
    }

    var bestSet: SetLog {
        sets.max { estimatedOneRepMax(for: $0) < estimatedOneRepMax(for: $1) } ?? sets[0]
    }

    var bestSetText: String {
        "\(format(bestSet.weight))kg x \(bestSet.reps)"
    }

    var estimatedOneRepMaxText: String {
        "\(format(estimatedOneRepMax))kg"
    }

    var estimatedOneRepMax: Double {
        estimatedOneRepMax(for: bestSet)
    }

    var bestSetVolumeText: String {
        "\(format(bestSetVolume))kg"
    }

    var bestSetVolume: Double {
        bestSet.weight * Double(bestSet.reps)
    }

    var setsText: String {
        sets.map { "\(format($0.weight))kg x \($0.reps)" }.joined(separator: ", ")
    }

    private func estimatedOneRepMax(for set: SetLog) -> Double {
        set.weight * (1 + Double(set.reps) / 30)
    }

    private func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(value.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 1)))
    }
}
