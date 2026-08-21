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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var workoutWarmStartInvalidation = WorkoutWarmStartInvalidation.shared

    @Query private var observedExercises: [Exercise]
    @Query private var observedCompletedSessions: [WorkoutSession]
    @Query private var observedActiveSplits: [TrainingSplit]

    @State private var exercises: [Exercise] = []
    @State private var exercisesLoaded = false
    @State private var selectedExercise: Exercise?
    @State private var isExerciseChartsPresented = false
    @State private var isPRTimelinePresented = false
    @State private var weeklySummary: WeeklyTrainingSummary?
    @State private var splitConsistency: SplitConsistencySummary?
    @State private var lastExercisesSignature: String?
    @State private var lastSummarySignature: String?
    @State private var summaryTask: Task<Void, Never>?
    @State private var progressRefreshTask: Task<Void, Never>?
    @State private var isProgressVisible = false

    private let analytics = TrainingAnalyticsService()

    init() {
        _observedExercises = Query(Self.exercisesDescriptor)
        _observedCompletedSessions = Query(Self.completedSessionsDescriptor)
        _observedActiveSplits = Query(Self.activeSplitsDescriptor)
    }

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

    private static var activeSplitsDescriptor: FetchDescriptor<TrainingSplit> {
        FetchDescriptor<TrainingSplit>(
            predicate: #Predicate<TrainingSplit> { $0.isActive }
        )
    }

    private var displayedWeeklySummary: WeeklyTrainingSummary {
        weeklySummary ?? analytics.weeklySummary(from: [WorkoutAnalyticsSession]())
    }

    private var displayedSplitConsistency: SplitConsistencySummary {
        splitConsistency ?? analytics.splitConsistency(from: [WorkoutAnalyticsSession]())
    }

    var body: some View {
        FitnessScreen {
            if weeklySummary == nil || splitConsistency == nil {
                progressLoadingCard
            } else {
                progressWeekCard
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
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) {
                            exerciseChartsButton
                            prTimelineButton
                        }

                        VStack(spacing: 12) {
                            exerciseChartsButton
                            prTimelineButton
                        }
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
                                navigate(
                                    key: "progress.exercise.\(exercise.id.uuidString)",
                                    destinationClass: .deep
                                ) {
                                    selectedExercise = exercise
                                }
                            } label: {
                                FitnessCard(padding: 16) {
                                    HStack(alignment: .top, spacing: 12) {
                                        ExerciseIconView(
                                            iconKey: ExerciseIconMapper.iconKey(for: exercise),
                                            size: 40,
                                            showBackground: true,
                                            isDecorative: true
                                        )

                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(exercise.name)
                                                .font(AppTypography.sectionTitle)
                                                .foregroundStyle(appTheme.colors.textPrimary)
                                                .lineLimit(2)
                                                .minimumScaleFactor(0.85)
                                                .fixedSize(horizontal: false, vertical: true)
                                            Text(exercise.primaryMuscleGroup.displayName)
                                                .font(AppTypography.body)
                                                .foregroundStyle(appTheme.colors.textSecondary)
                                        }

                                        Spacer()

                                        Image(systemName: "chevron.right")
                                            .font(AppTypography.eyebrow)
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
        .accessibilityIdentifier("progress-screen")
        .navigationDestination(isPresented: $isExerciseChartsPresented) {
            ExerciseProgressChartsIndexView(exercises: exercises, selectedExercise: $selectedExercise)
                .onAppear {
                    NavigationInteraction.destinationDidAppear(key: "progress.exercise-charts")
                }
        }
        .navigationDestination(isPresented: $isPRTimelinePresented) {
            PRTimelineView()
                .onAppear {
                    NavigationInteraction.destinationDidAppear(key: "progress.pr-timeline")
                }
        }
        .navigationDestination(item: $selectedExercise) { exercise in
            ExerciseProgressDetailView(exercise: exercise)
                .onAppear {
                    NavigationInteraction.destinationDidAppear(
                        key: "progress.exercise.\(exercise.id.uuidString)"
                    )
                }
        }
        .onAppear {
            isProgressVisible = true
            scheduleProgressRefresh(
                force: lastExercisesSignature == nil || lastSummarySignature == nil
            )
        }
        .onChange(of: progressSignatureForObservation) { oldSignature, newSignature in
            guard oldSignature != nil, newSignature != nil else { return }
            scheduleProgressRefresh()
        }
        .onDisappear {
            isProgressVisible = false
            progressRefreshTask?.cancel()
            progressRefreshTask = nil
            summaryTask?.cancel()
        }
    }

    private var progressSignatureForObservation: String? {
        isProgressVisible ? progressSourceSignature : nil
    }

    private var progressSourceSignature: String {
        let activeSplitNames = TrainingRotationService()
            .orderedActiveSplits(observedActiveSplits)
            .map(\.name)
        let scalarSignature = ProgressAnalyticsInputSignature(
            sessions: Array(observedCompletedSessions.prefix(40)),
            exerciseIDs: observedExercises.map(\.id),
            activeSplitNames: activeSplitNames
        ).rawValue
        let exerciseScalarSignature = observedExercises
            .map {
                "\($0.id.uuidString):\($0.name):\($0.primaryMuscleGroup.rawValue):\($0.updatedAt.timeIntervalSince1970)"
            }
            .joined(separator: ",")

        return "\(workoutWarmStartInvalidation.revision)||\(exerciseScalarSignature)||\(scalarSignature)"
    }

    private func scheduleProgressRefresh(force: Bool = false) {
        progressRefreshTask?.cancel()
        progressRefreshTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled, isProgressVisible else { return }
            refreshExercises(force: force)
            refreshSummary(force: force)
        }
    }

    private func navigate(
        key: String,
        destinationClass: NavigationDestinationClass,
        action: @escaping @MainActor () -> Void
    ) {
        NavigationInteraction.perform(
            key: key,
            destinationClass: destinationClass,
            haptic: .selection,
            action: action
        )
    }

    private var exerciseChartsButton: some View {
        Button {
            navigate(key: "progress.exercise-charts", destinationClass: .deep) {
                isExerciseChartsPresented = true
            }
        } label: {
            ProgressActionCard(title: "Exercise Charts", subtitle: "Open lift trends", systemImage: "chart.xyaxis.line")
        }
        .buttonStyle(PressableCardButtonStyle())
    }

    private var prTimelineButton: some View {
        Button {
            navigate(key: "progress.pr-timeline", destinationClass: .deep) {
                isPRTimelinePresented = true
            }
        } label: {
            ProgressActionCard(title: "PR Timeline", subtitle: "Review new bests", systemImage: "trophy.fill")
        }
        .buttonStyle(PressableCardButtonStyle())
        .accessibilityIdentifier("progress-pr-timeline-open")
    }

    private var progressWeekCard: some View {
        FitnessCard(style: .hero) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    FitnessIconBadge(
                        systemImage: progressSignalSystemImage,
                        size: 42,
                        tint: progressSignalTint,
                        background: progressSignalTint.opacity(0.14)
                    )

                    VStack(alignment: .leading, spacing: 4) {
                        Text("This Week")
                            .font(AppTypography.eyebrow)
                            .foregroundStyle(appTheme.colors.textSecondary)
                            .textCase(.uppercase)

                        Text(progressSignalTitle)
                            .font(AppTypography.cardTitle)
                            .foregroundStyle(appTheme.colors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 8)

                    Text(progressSignalBadge)
                        .font(AppTypography.badge)
                        .foregroundStyle(progressSignalTint)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(progressSignalTint.opacity(0.14), in: Capsule())
                }

                Text(progressSignalMessage)
                    .font(AppTypography.body)
                    .foregroundStyle(appTheme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .bottom, spacing: 16) {
                        ProgressWeekPrimaryMetric(value: displayedWeeklySummary.completedWorkouts)

                        Divider()
                            .overlay(appTheme.colors.cardBorder)
                            .frame(height: 62)

                        HStack(alignment: .bottom, spacing: 16) {
                            ProgressWeekSupportingMetric(label: "Working sets", value: displayedWeeklySummary.workingSets)
                            ProgressWeekSupportingMetric(label: "PRs", value: displayedWeeklySummary.prCount)
                        }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        ProgressWeekPrimaryMetric(value: displayedWeeklySummary.completedWorkouts)
                        HStack(alignment: .bottom, spacing: 16) {
                            ProgressWeekSupportingMetric(label: "Working sets", value: displayedWeeklySummary.workingSets)
                            ProgressWeekSupportingMetric(label: "PRs", value: displayedWeeklySummary.prCount)
                        }
                    }
                }

                Text(
                    PeaklineText.joinedMetadata([
                        "\(format(displayedWeeklySummary.totalTonnage)) kg tonnage",
                        "\(format(displayedWeeklySummary.bestSetVolumeTotal)) kg best-set volume",
                        displayedSplitConsistency.countDescription()
                    ])
                )
                    .font(AppTypography.metadata)
                    .foregroundStyle(appTheme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(displayedSplitConsistency.balanceDescription)
                    .font(AppTypography.metadataEmphasis)
                    .foregroundStyle(appTheme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var progressSignalTitle: String {
        if displayedWeeklySummary.completedWorkouts == 0 {
            return "No trend yet this week"
        }
        if let missedSplitName = displayedSplitConsistency.missedSplitName {
            return "\(missedSplitName) needs attention"
        }
        if displayedWeeklySummary.prCount > 0 {
            return "Progress is moving"
        }
        if displayedWeeklySummary.workingSets >= 12 {
            return "Solid training week"
        }
        return "Keep building the week"
    }

    private var progressSignalMessage: String {
        if displayedWeeklySummary.completedWorkouts == 0 {
            return "Finish a workout to start this week's progress signal."
        }
        if let missedSplitName = displayedSplitConsistency.missedSplitName {
            return "\(displayedSplitConsistency.countDescription()). Prioritise \(missedSplitName) to rebalance the week."
        }
        if displayedWeeklySummary.prCount > 0 {
            return "\(PeaklineText.count(displayedWeeklySummary.prCount, singular: "PR")) logged this week. Open the PR timeline to review what moved."
        }
        if displayedWeeklySummary.workingSets >= 12 {
            return "\(PeaklineText.count(displayedWeeklySummary.workingSets, singular: "working set")) logged. Check exercise charts for lift-specific changes."
        }
        return "\(PeaklineText.count(displayedWeeklySummary.completedWorkouts, singular: "workout")) logged. Add more working sets to make trends clearer."
    }

    private var progressSignalBadge: String {
        if displayedWeeklySummary.completedWorkouts == 0 {
            return "Build"
        }
        if displayedSplitConsistency.missedSplitName != nil {
            return "Balance"
        }
        if displayedWeeklySummary.prCount > 0 {
            return "\(displayedWeeklySummary.prCount) PR"
        }
        return "Review"
    }

    private var progressSignalSystemImage: String {
        if displayedWeeklySummary.completedWorkouts == 0 {
            return "calendar.badge.plus"
        }
        if displayedSplitConsistency.missedSplitName != nil {
            return "scale.3d"
        }
        if displayedWeeklySummary.prCount > 0 {
            return "trophy.fill"
        }
        return "chart.line.uptrend.xyaxis"
    }

    private var progressSignalTint: Color {
        if displayedWeeklySummary.completedWorkouts == 0 || displayedSplitConsistency.missedSplitName != nil {
            return appTheme.colors.warning
        }
        if displayedWeeklySummary.prCount > 0 {
            return appTheme.colors.success
        }
        return appTheme.colors.accent
    }

    private var progressLoadingCard: some View {
        FitnessCard(style: .compact) {
            HStack(spacing: 10) {
                Image(systemName: "hourglass")
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(appTheme.colors.textAccent)
                Text("Loading progress data")
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(appTheme.colors.textSecondary)
            }
        }
    }

    private func refreshExercises(force: Bool = false) {
        let signature = observedExercises
            .map {
                "\($0.id.uuidString):\($0.name):\($0.primaryMuscleGroup.rawValue):\($0.updatedAt.timeIntervalSince1970)"
            }
            .joined(separator: ",")
        guard force || signature != lastExercisesSignature else { return }

        AppMotion.withoutAnimation {
            exercises = observedExercises
        }
        AppMotion.withoutAnimation {
            exercisesLoaded = true
            lastExercisesSignature = signature
        }
    }

    private func refreshSummary(force: Bool = false) {
        let recentSessions = Array(observedCompletedSessions.prefix(40))
        let activeSplitNames = TrainingRotationService()
            .orderedActiveSplits(observedActiveSplits)
            .map(\.name)
        let scalarSignature = ProgressAnalyticsInputSignature(
            sessions: recentSessions,
            exerciseIDs: observedExercises.map(\.id),
            activeSplitNames: activeSplitNames
        ).rawValue
        let generation = workoutWarmStartInvalidation.revision
        let signature = "\(generation)||\(scalarSignature)"
        guard force || signature != lastSummarySignature else { return }
        summaryTask?.cancel()

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
                    let consistency = analytics.splitConsistency(
                        from: snapshots,
                        activeSplitNames: activeSplitNames
                    )
                    return (weekly, consistency)
                }
            }.value

            guard !Task.isCancelled,
                  generation == workoutWarmStartInvalidation.revision else { return }
            AppMotion.withoutAnimation {
                weeklySummary = result.0
                splitConsistency = result.1
                lastSummarySignature = signature
            }
        }
    }

    private func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(value.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 1)))
    }
}

struct ProgressAnalyticsInputSignature: Equatable {
    let rawValue: String

    init(
        sessions: [WorkoutSession],
        exerciseIDs: [UUID] = [],
        activeSplitNames: [String] = []
    ) {
        let sessionSignatures = sessions
            .prefix(160)
            .sorted { lhs, rhs in
                if lhs.date != rhs.date { return lhs.date > rhs.date }
                return lhs.id.uuidString < rhs.id.uuidString
            }
            .map { session in
                return [
                    session.id.uuidString,
                    "\(session.date.timeIntervalSince1970)",
                    session.splitId?.uuidString ?? "",
                    session.splitNameSnapshot,
                    Self.timestamp(session.startedAt),
                    Self.timestamp(session.endedAt),
                    "\(session.durationMinutes ?? -1)",
                    "\(session.durationSeconds ?? -1)",
                    Self.timestamp(session.pausedAt),
                    "\(session.accumulatedPausedSeconds)",
                    "\(session.perceivedDifficulty ?? -1)",
                    "\(session.energyLevel ?? -1)",
                    "\(session.sorenessLevel ?? -1)",
                    session.notes ?? "",
                    "\(session.completed)"
                ].joined(separator: ":")
            }
            .joined(separator: "|")

        rawValue = [
            exerciseIDs.map(\.uuidString).sorted().joined(separator: ","),
            sessionSignatures,
            activeSplitNames.joined(separator: "|")
        ].joined(separator: "||")
    }

    private static func timestamp(_ date: Date?) -> String {
        date.map { String($0.timeIntervalSince1970) } ?? ""
    }
}

private struct ProgressWeekPrimaryMetric: View {
    @Environment(\.appTheme) private var appTheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let value: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            AnimatedMetricNumber(value: Double(value))
                .font(AppTypography.heroMetric)
                .foregroundStyle(appTheme.colors.textPrimary)
                .lineLimit(1)
                .animation(
                    reduceMotion ? .easeOut(duration: 0.01) : AppMotion.expressive,
                    value: value
                )
            Text("Workouts")
                .font(AppTypography.metadataEmphasis)
                .foregroundStyle(appTheme.colors.textSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Workouts")
        .accessibilityValue("\(value)")
    }
}

private struct ProgressWeekSupportingMetric: View {
    @Environment(\.appTheme) private var appTheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let label: String
    let value: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            AnimatedMetricNumber(value: Double(value))
                .font(AppTypography.largeMetric)
                .foregroundStyle(appTheme.colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .animation(
                    reduceMotion ? .easeOut(duration: 0.01) : AppMotion.expressive,
                    value: value
                )
            Text(label)
                .font(AppTypography.metadata)
                .foregroundStyle(appTheme.colors.textSecondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue("\(value)")
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
    @ObservedObject private var workoutWarmStartInvalidation = WorkoutWarmStartInvalidation.shared

    let exercise: Exercise

    @Query
    private var sessions: [WorkoutSession]
    @State private var entries: [ExerciseProgressEntry] = []
    @State private var lastEntriesSignature: String?
    @State private var entriesLoaded = false
    @State private var didRevealTrendChart = false

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

    private var entriesSignature: String {
        let input = ProgressAnalyticsInputSignature(
            sessions: Array(sessions.prefix(160)),
            exerciseIDs: [exercise.id]
        )
        return "\(workoutWarmStartInvalidation.revision)||\(input.rawValue)"
    }

    private func makeEntries() -> [ExerciseProgressEntry] {
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
            if !entriesLoaded {
                progressDetailLoadingCard
            } else if let latest = entries.first {
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
                if !entriesLoaded {
                    progressDetailLoadingCard
                } else if entries.count < 2 {
                    DashboardEmptyStateCard(
                        title: "More data needed",
                        message: "Log this exercise in at least two sessions to show a trend.",
                        systemImage: "chart.line.uptrend.xyaxis"
                    )
                } else {
                    FitnessCard {
                        ExerciseTrendChart(
                            entries: entries.reversed(),
                            revealOnAppear: !didRevealTrendChart,
                            markRevealed: { didRevealTrendChart = true }
                        )
                            .frame(height: 220)
                    }
                }
            }

            DashboardSection(title: "History") {
                if !entriesLoaded {
                    progressDetailLoadingCard
                } else if entries.isEmpty {
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
                                        .font(AppTypography.sectionTitle)
                                    Text(entry.setsText)
                                        .font(AppTypography.body)
                                        .foregroundStyle(appTheme.colors.textSecondary)
                                        .lineLimit(2)
                                    Text("Best-set volume \(entry.bestSetVolumeText) · est. 1RM \(entry.estimatedOneRepMaxText)")
                                        .font(AppTypography.metadata)
                                        .foregroundStyle(appTheme.colors.textSecondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(exercise.name)
        .onAppear {
            refreshEntries()
        }
        .onChange(of: entriesSignature) { _, _ in
            refreshEntries()
        }
    }

    private var progressDetailLoadingCard: some View {
        FitnessCard(style: .compact) {
            HStack(spacing: 10) {
                Image(systemName: "hourglass")
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(appTheme.colors.textAccent)
                Text("Loading exercise data")
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(appTheme.colors.textSecondary)
            }
        }
    }

    private func refreshEntries() {
        let signature = entriesSignature
        guard signature != lastEntriesSignature else { return }

        let nextEntries = PerformanceTracer.trace(.exerciseProgressEntries) {
            makeEntries()
        }
        AppMotion.withoutAnimation {
            entries = nextEntries
            lastEntriesSignature = signature
            entriesLoaded = true
        }
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
                        NavigationInteraction.perform(
                            key: "progress.exercise.\(exercise.id.uuidString)",
                            destinationClass: .deep,
                            haptic: .selection
                        ) {
                            selectedExercise = exercise
                        }
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
                                        .font(AppTypography.sectionTitle)
                                    Text(exercise.primaryMuscleGroup.displayName)
                                        .font(AppTypography.body)
                                        .foregroundStyle(appTheme.colors.textSecondary)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(AppTypography.eyebrow)
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
    }
}

private struct ExerciseTrendChart: View {
    @Environment(\.appTheme) private var appTheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let entries: ReversedCollection<[ExerciseProgressEntry]>
    let revealOnAppear: Bool
    let markRevealed: () -> Void

    @State private var revealProgress = 0.0

    var body: some View {
        Chart(Array(entries)) { entry in
            LineMark(
                x: .value("Date", entry.session.date),
                y: .value("Estimated 1RM", entry.estimatedOneRepMax)
            )
            .foregroundStyle(appTheme.colors.textAccent)

            PointMark(
                x: .value("Date", entry.session.date),
                y: .value("Estimated 1RM", entry.estimatedOneRepMax)
            )
                .foregroundStyle(appTheme.colors.textAccent)
        }
        .chartPlotStyle { plotArea in
            plotArea.mask(alignment: .leading) {
                GeometryReader { proxy in
                    Rectangle()
                        .frame(width: reduceMotion ? proxy.size.width : proxy.size.width * revealProgress)
                }
            }
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Estimated 1RM trend")
        .accessibilityValue(accessibilityValue)
        .onAppear {
            guard revealOnAppear else {
                revealProgress = 1
                return
            }

            if reduceMotion {
                revealProgress = 1
                markRevealed()
                return
            }

            revealProgress = 0
            withAnimation(AppMotion.chartDrawIn(reduceMotion: false)) {
                revealProgress = 1
            }
            markRevealed()
        }
    }

    private var accessibilityValue: String {
        guard let latest = Array(entries).last else {
            return "No trend data"
        }
        return "Latest estimated 1RM \(latest.estimatedOneRepMax.formatted(.number.precision(.fractionLength(0...1)))) kilograms"
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
        PeaklineText.loadReps(weight: format(bestSet.weight), reps: bestSet.reps)
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
        sets.map { PeaklineText.loadReps(weight: format($0.weight), reps: $0.reps) }.joined(separator: ", ")
    }

    private func estimatedOneRepMax(for set: SetLog) -> Double {
        set.weight * (1 + Double(set.reps) / 30)
    }

    private func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(value.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 1)))
    }
}
