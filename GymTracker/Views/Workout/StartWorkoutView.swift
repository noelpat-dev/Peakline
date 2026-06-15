import SwiftData
import SwiftUI

struct StartWorkoutView: View {
    @State private var navigationPath: [StartWorkoutRoute] = []
    @State private var pendingNavigationRoute: StartWorkoutRoute?

    var body: some View {
        NavigationStack(path: $navigationPath) {
            StartWorkoutContentView { route in
                push(route)
            }
            .navigationDestination(for: StartWorkoutRoute.self) { route in
                destination(for: route)
                    .onAppear {
                        PerformanceTracer.mark(.workoutRouteNavigation, "destination_onAppear route=\(route.analyticsName) path_depth=\(navigationPath.count)")
                        if pendingNavigationRoute == route {
                            pendingNavigationRoute = nil
                            PerformanceTracer.mark(.workoutRouteNavigation, "transition_cleared route=\(route.analyticsName)")
                        }
                    }
            }
        }
        .onChange(of: navigationPath) { _, newPath in
            let topRoute = newPath.last?.analyticsName ?? "none"
            PerformanceTracer.mark(.workoutRouteNavigation, "path_changed depth=\(newPath.count) top=\(topRoute)")
            if let pendingNavigationRoute, !newPath.contains(pendingNavigationRoute) {
                PerformanceTracer.mark(.workoutRouteNavigation, "transition_cleared_missing route=\(pendingNavigationRoute.analyticsName)")
                self.pendingNavigationRoute = nil
            }
        }
    }

    @ViewBuilder
    private func destination(for route: StartWorkoutRoute) -> some View {
        switch route {
        case .coach:
            CoachRouteDestinationView(
                backButtonTitle: "Workout",
                onBack: {
                    pop(route)
                }
            )
        case .templates:
            WorkoutTemplateLibraryView()
        case let .preview(route):
            WorkoutPreviewRouteView(split: route.split, initialMode: route.mode)
        }
    }

    private func push(_ route: StartWorkoutRoute) {
        let topRoute = navigationPath.last?.analyticsName ?? "none"
        let pendingRoute = pendingNavigationRoute?.analyticsName ?? "none"
        PerformanceTracer.mark(.workoutRouteNavigation, "request route=\(route.analyticsName) path_depth=\(navigationPath.count) top=\(topRoute) pending=\(pendingRoute)")

        guard navigationPath.last != route else {
            PerformanceTracer.mark(.workoutRouteNavigation, "skip route=\(route.analyticsName) already_active")
            return
        }

        guard pendingNavigationRoute != route else {
            PerformanceTracer.mark(.workoutRouteNavigation, "skip route=\(route.analyticsName) transition_in_flight")
            return
        }

        pendingNavigationRoute = route
        PerformanceTracer.trace(.workoutRouteNavigation) {
            navigationPath.append(route)
        }
        PerformanceTracer.mark(.workoutRouteNavigation, "appended route=\(route.analyticsName) path_depth=\(navigationPath.count)")
    }

    private func pop(_ route: StartWorkoutRoute) {
        let topRoute = navigationPath.last?.analyticsName ?? "none"
        PerformanceTracer.mark(.workoutRouteNavigation, "pop_request route=\(route.analyticsName) path_depth=\(navigationPath.count) top=\(topRoute)")

        guard navigationPath.last == route else {
            PerformanceTracer.mark(.workoutRouteNavigation, "pop_skip route=\(route.analyticsName) top=\(topRoute)")
            return
        }

        navigationPath.removeLast()
        pendingNavigationRoute = nil
        PerformanceTracer.mark(.workoutRouteNavigation, "pop_complete route=\(route.analyticsName) path_depth=\(navigationPath.count)")
    }
}

struct StartWorkoutContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var appTheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Query
    private var activeSplits: [TrainingSplit]

    @Query
    private var unfinishedSessions: [WorkoutSession]

    @Query
    private var completedSessions: [WorkoutSession]

    @Query
    private var sleepSessions: [SleepSession]

    @Query
    private var napSessions: [NapSession]

    @State private var activeSession: WorkoutSession?
    @State private var pendingDiscardSession: WorkoutSession?
    @State private var fallbackRoute: StartWorkoutRoute?
    @State private var templateCount = 0
    @State private var sleepSettings = SleepSettingsStore().load()
    @State private var sleepReadinessSnapshot = SleepAnalyticsService.emptyReadinessSnapshot()
    @State private var lastSleepReadinessSignature: SleepAnalyticsInputSignature?
    @State private var dashboardSnapshot: StartWorkoutDashboardSnapshot?
    @State private var recentSessionSnapshot: StartWorkoutRecentSessionSnapshot?
    @State private var splitCardSnapshots: [StartWorkoutSplitCardSnapshot] = []
    @State private var lastDashboardSignature: String?
    @State private var dashboardRefreshTask: Task<Void, Never>?

    private let openRoute: ((StartWorkoutRoute) -> Void)?
    private let coachEngine = CoachRecommendationEngine()
    private let trainingCallBuilder = TrainingCallSnapshotBuilder()
    private let modePlanner = WorkoutModePlanner()
    private let summaryBuilder = SessionSummaryBuilder()
    private let reuseBuilder = WorkoutReuseBuilder()
    private let templateStore = WorkoutTemplateStore()
    private let sleepCoaching = SleepCoachingService()
    private let sleepSettingsStore = SleepSettingsStore()
    private let sleepReadinessStore = SleepWorkoutReadinessSnapshotStore.shared

    init(openRoute: ((StartWorkoutRoute) -> Void)? = nil) {
        self.openRoute = openRoute
        _activeSplits = Query(Self.activeSplitsDescriptor)
        _unfinishedSessions = Query(Self.unfinishedSessionsDescriptor)
        _completedSessions = Query(Self.completedSessionsDescriptor)
        _sleepSessions = Query(Self.sleepSessionsDescriptor)
        _napSessions = Query(Self.napSessionsDescriptor)
    }

    private static var activeSplitsDescriptor: FetchDescriptor<TrainingSplit> {
        var descriptor = FetchDescriptor<TrainingSplit>(
            predicate: #Predicate<TrainingSplit> { $0.isActive },
            sortBy: [SortDescriptor(\.name)]
        )
        descriptor.fetchLimit = 12
        return descriptor
    }

    private static var unfinishedSessionsDescriptor: FetchDescriptor<WorkoutSession> {
        var descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate<WorkoutSession> { !$0.completed },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = 3
        return descriptor
    }

    private static var completedSessionsDescriptor: FetchDescriptor<WorkoutSession> {
        var descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate<WorkoutSession> { $0.completed },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = 40
        return descriptor
    }

    private static var sleepSessionsDescriptor: FetchDescriptor<SleepSession> {
        var descriptor = FetchDescriptor<SleepSession>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 60
        return descriptor
    }

    private static var napSessionsDescriptor: FetchDescriptor<NapSession> {
        var descriptor = FetchDescriptor<NapSession>(
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        descriptor.fetchLimit = 30
        return descriptor
    }

    private var currentDashboardSnapshot: StartWorkoutDashboardSnapshot {
        dashboardSnapshot ?? StartWorkoutDashboardSnapshot.placeholder(activeSplits: activeSplits)
    }

    private var currentRecentSessionSnapshot: StartWorkoutRecentSessionSnapshot? {
        recentSessionSnapshot ?? completedSessions.first.map(StartWorkoutRecentSessionSnapshot.placeholder)
    }

    private var currentSplitCardSnapshots: [StartWorkoutSplitCardSnapshot] {
        if !splitCardSnapshots.isEmpty {
            return splitCardSnapshots
        }

        return displayedSplits.map(StartWorkoutSplitCardSnapshot.placeholder)
    }

    private var recommendedSplit: TrainingSplit? {
        guard let name = currentDashboardSnapshot.trainingCall.recommendedSplitName else {
            return activeSplits.first
        }
        return activeSplits.first { $0.name == name } ?? activeSplits.first
    }

    private var displayedSplits: [TrainingSplit] {
        let pplNames = ["Push", "Pull", "Legs"]
        let pplSplits = pplNames.compactMap { name in activeSplits.first { $0.name == name } }
        return pplSplits.isEmpty ? activeSplits : pplSplits
    }

    private var currentSleepReadinessSignature: SleepAnalyticsInputSignature {
        SleepAnalyticsInputSignature(sessions: sleepSessions, naps: napSessions, workouts: completedSessions, settings: sleepSettings, sessionLimit: 45, workoutLimit: 12)
    }

    private var sleepReadinessSignatureForObservation: SleepAnalyticsInputSignature? {
        return currentSleepReadinessSignature
    }

    private var currentDashboardSignature: String {
        [
            activeSplits.map { split in
                "\(split.id.uuidString):\(split.name):\(split.updatedAt.timeIntervalSince1970)"
            }
            .joined(separator: "|"),
            completedSessions.prefix(20).map { session in
                "\(session.id.uuidString):\(session.date.timeIntervalSince1970):\(session.endedAt?.timeIntervalSince1970 ?? 0):\(session.durationSeconds ?? 0):\(session.perceivedDifficulty ?? 0)"
            }
            .joined(separator: "|")
        ].joined(separator: "||")
    }

    private var dashboardSignatureForObservation: String? {
        return currentDashboardSignature
    }

    private var sleepSummary: SleepSummary? {
        sleepReadinessSnapshot.latestSummary.primarySession == nil ? nil : sleepReadinessSnapshot.latestSummary
    }

    private var adaptiveSleepRecommendation: AdaptiveTrainingRecommendation? {
        guard sleepSettings.coachingPreferences.adaptiveWorkoutRecommendationsEnabled else { return nil }
        return sleepReadinessSnapshot.adaptiveRecommendation
    }

    var body: some View {
        workoutDashboard
    }

    private var workoutDashboard: some View {
        FitnessScreen(
            title: "Workout",
            subtitle: "Prepare the right session, then log fast.",
            systemImage: "figure.strengthtraining.traditional"
        ) {
            if let unfinishedSession = unfinishedSessions.first {
                activeWorkoutCard(unfinishedSession)
            }

            if let recommendation = adaptiveSleepRecommendation {
                workoutRecoveryBanner(recommendation)
            } else if let hint = sleepCoaching.preWorkoutHint(for: sleepSummary) {
                sleepReadinessCard(title: hint.title, suggestion: hint.suggestion)
            }

            if let recommendedSplit {
                recommendedWorkoutCard(recommendedSplit)
            }

            reuseCard

            DashboardSection(title: "Start") {
                ForEach(currentSplitCardSnapshots) { snapshot in
                    splitStartCard(snapshot)
                }

                emptyWorkoutCard
            }

            if let recentSnapshot = currentRecentSessionSnapshot {
                recentSessionCard(recentSnapshot)
            }
        }
        .navigationTitle("Workout")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("workout-screen")
        .navigationDestination(item: $activeSession) { session in
            WorkoutLoggerView(session: session)
        }
        .navigationDestination(item: $fallbackRoute) { route in
            switch route {
            case .coach:
                CoachRouteDestinationView(
                    backButtonTitle: "Workout",
                    onBack: {
                        fallbackRoute = nil
                    }
                )
            case .templates:
                WorkoutTemplateLibraryView()
            case let .preview(route):
                WorkoutPreviewRouteView(split: route.split, initialMode: route.mode)
            }
        }
        .alert("Discard active workout?", isPresented: discardAlertBinding) {
            Button("Cancel", role: .cancel) {
                pendingDiscardSession = nil
            }
            Button("Discard", role: .destructive) {
                discardPendingWorkout()
            }
        } message: {
            Text("This removes the unfinished workout and its logged sets.")
        }
        .onAppear {
            templateCount = templateStore.loadTemplates().count
            sleepSettings = sleepSettingsStore.load()
            scheduleDashboardSnapshotRefresh(force: dashboardSnapshot == nil)
            refreshSleepReadiness()
        }
        .onChange(of: dashboardSignatureForObservation) { _, signature in
            guard signature != nil else { return }
            scheduleDashboardSnapshotRefresh()
        }
        .onChange(of: sleepReadinessSignatureForObservation) { _, signature in
            guard signature != nil else { return }
            refreshSleepReadiness()
        }
        .onDisappear {
            dashboardRefreshTask?.cancel()
        }
    }

    private func scheduleDashboardSnapshotRefresh(force: Bool = false) {
        let signature = currentDashboardSignature
        guard force || signature != lastDashboardSignature else { return }

        dashboardRefreshTask?.cancel()
        dashboardRefreshTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: dashboardRefreshDelayNanoseconds)
            guard !Task.isCancelled else { return }
            refreshDashboardSnapshot(signature: signature)
        }
    }

    private var dashboardRefreshDelayNanoseconds: UInt64 {
        #if DEBUG
        if PerformanceAcceptanceState.isEnabled {
            return 8_000_000_000
        }
        #endif
        return 500_000_000
    }

    private func refreshDashboardSnapshot(signature: String) {
        let activeSnapshots = activeSplits.map(TrainingSplitSnapshot.init)
        let completedSnapshots = completedSessions.prefix(20).map(WorkoutAnalyticsSession.init)
        let summary = coachEngine.makeSummary(activeSplits: activeSnapshots, completedSessions: completedSnapshots)
        let call = trainingCallBuilder.make(
            decision: summary.trainingDecision,
            activeSplits: activeSnapshots,
            completedSessions: completedSnapshots
        )

        AppMotion.withoutAnimation {
            dashboardSnapshot = StartWorkoutDashboardSnapshot(trainingCall: call)
            recentSessionSnapshot = makeRecentSessionSnapshot()
            splitCardSnapshots = displayedSplits.map(makeSplitCardSnapshot)
            lastDashboardSignature = signature
        }
    }

    private func makeRecentSessionSnapshot() -> StartWorkoutRecentSessionSnapshot? {
        guard let session = completedSessions.first else { return nil }

        let summary = summaryBuilder.build(from: session, completedSessions: completedSessions, activeSplits: activeSplits)
        return StartWorkoutRecentSessionSnapshot(
            sessionId: session.id,
            splitName: session.splitNameSnapshot,
            durationText: summary.durationText,
            ratingText: summary.ratingText ?? "-",
            highlightText: summary.bestSetImprovements.first ?? summary.takeaway,
            badgeState: summary.bestSetImprovements.isEmpty ? .ready : .pr
        )
    }

    private func makeSplitCardSnapshot(_ split: TrainingSplit) -> StartWorkoutSplitCardSnapshot {
        StartWorkoutSplitCardSnapshot(
            splitId: split.id,
            splitName: split.name,
            lastTrainedText: lastTrainedText(for: split),
            estimatedDurationText: estimatedDurationText(for: split),
            exerciseCount: split.exercises.count,
            badgeState: badgeState(for: split)
        )
    }

    private func refreshSleepReadiness(force: Bool = false) {
        let signature = currentSleepReadinessSignature
        guard force || signature != lastSleepReadinessSignature else { return }

        sleepReadinessSnapshot = PerformanceTracer.trace(.workoutStartSleepReadiness) {
            sleepReadinessStore.snapshot(
                sessions: sleepSessions,
                naps: napSessions,
                workouts: completedSessions,
                settings: sleepSettings,
                force: force
            )
        }
        lastSleepReadinessSignature = signature
    }

    private func activeWorkoutCard(_ session: WorkoutSession) -> some View {
        FitnessCard(style: .hero) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    ExerciseIconView(
                        iconKey: ExerciseIconMapper.splitIconKey(for: session.splitNameSnapshot),
                        size: 46,
                        showBackground: true,
                        isDecorative: true
                    )

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Active Workout")
                            .font(AppTypography.metadataEmphasis)
                            .foregroundStyle(appTheme.mutedText)
                            .textCase(.uppercase)
                        Text(session.splitNameSnapshot)
                            .font(AppTypography.largeMetric)
                    }

                    Spacer()

                    MetricTile(label: "Elapsed", value: activeElapsedText(for: session), caption: nil, systemImage: "timer")
                        .frame(maxWidth: 150)
                }

                Text(resumeSummary(for: session))
                    .font(AppTypography.body)
                    .foregroundStyle(appTheme.mutedText)

                HStack {
                    Button {
                        openSession(session)
                    } label: {
                        Label("Resume", systemImage: "play.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryFitnessButtonStyle())

                    Button {
                        pendingDiscardSession = session
                    } label: {
                        Label("Discard", systemImage: "xmark.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(NeutralFitnessButtonStyle())
                }
            }
        }
    }

    private func recommendedWorkoutCard(_ split: TrainingSplit) -> some View {
        FitnessCard(style: .hero) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    ExerciseIconTile(
                        iconKey: ExerciseIconMapper.splitIconKey(for: split.name),
                        title: nil,
                        size: 58,
                        style: .compact
                    )

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Recommended Today")
                            .font(AppTypography.metadataEmphasis)
                            .foregroundStyle(appTheme.mutedText)
                            .textCase(.uppercase)
                        Text(split.name)
                            .font(AppTypography.screenTitle)
                    }

                    Spacer()
                    CoachBadgeView(state: .ready)
                }

                Text(currentDashboardSnapshot.trainingCall.reason)
                    .font(AppTypography.body)
                    .foregroundStyle(appTheme.mutedText)

                Label("\(currentDashboardSnapshot.trainingCall.recommendedMode.displayName) mode - \(currentDashboardSnapshot.trainingCall.confidence.displayName.lowercased())", systemImage: currentDashboardSnapshot.trainingCall.recommendedMode.systemImage)
                    .font(AppTypography.metadataEmphasis)
                    .foregroundStyle(appTheme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Button {
                        preview(split, mode: currentDashboardSnapshot.trainingCall.recommendedMode)
                    } label: {
                        Label("Preview", systemImage: "target")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryFitnessButtonStyle())
                    .accessibilityIdentifier("workout-recommended-preview")

                    Button {
                        navigate(to: .coach)
                    } label: {
                        Label("Coach", systemImage: "sparkles")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SecondaryFitnessButtonStyle())
                }
            }
        }
    }

    private func sleepReadinessCard(title: String, suggestion: String) -> some View {
        FitnessCard(style: .compact) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "moon.stars.fill")
                    .font(AppTypography.cardTitle)
                    .foregroundStyle(appTheme.colors.accent)
                    .frame(width: 44, height: 44)
                    .background(appTheme.colors.accentSurface, in: Circle())

                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(AppTypography.sectionTitle)
                        .foregroundStyle(appTheme.colors.textPrimary)

                    Text("Suggestion: \(suggestion)")
                        .font(AppTypography.body)
                        .foregroundStyle(appTheme.colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func workoutRecoveryBanner(_ recommendation: AdaptiveTrainingRecommendation) -> some View {
        FitnessCard(style: .compact) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: recoveryIcon(for: recommendation.level))
                    .font(AppTypography.cardTitle)
                    .foregroundStyle(recoveryTint(for: recommendation.level))
                    .frame(width: 44, height: 44)
                    .background(recoveryTint(for: recommendation.level).opacity(0.16), in: Circle())

                VStack(alignment: .leading, spacing: 5) {
                    Text(recommendation.title)
                        .font(AppTypography.sectionTitle)
                        .foregroundStyle(appTheme.colors.textPrimary)

                    Text(recommendation.message)
                        .font(.subheadline)
                        .foregroundStyle(appTheme.colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let action = recommendation.suggestedActions.first {
                        Text(action.displayName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(recoveryTint(for: recommendation.level))
                    }
                }

                Spacer(minLength: 8)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func recoveryTint(for level: TrainingReadinessRecommendation) -> Color {
        switch level {
        case .push, .normal:
            return appTheme.colors.success
        case .moderate:
            return appTheme.colors.accent
        case .light, .recovery:
            return appTheme.colors.warning
        case .rest:
            return appTheme.colors.danger
        }
    }

    private func recoveryIcon(for level: TrainingReadinessRecommendation) -> String {
        switch level {
        case .push:
            return "bolt.fill"
        case .normal:
            return "checkmark.seal.fill"
        case .moderate:
            return "dial.medium.fill"
        case .light:
            return "arrow.down.forward.circle.fill"
        case .recovery:
            return "figure.cooldown"
        case .rest:
            return "moon.fill"
        }
    }

    private func splitStartCard(_ snapshot: StartWorkoutSplitCardSnapshot) -> some View {
        Button {
            guard let split = activeSplits.first(where: { $0.id == snapshot.splitId }) else { return }
            preview(split)
        } label: {
            SplitCardView(
                splitName: snapshot.splitName,
                lastTrainedText: snapshot.lastTrainedText,
                estimatedDurationText: snapshot.estimatedDurationText,
                exerciseCount: snapshot.exerciseCount,
                badgeState: snapshot.badgeState,
                actionTitle: nil,
                action: nil
            )
        }
        .buttonStyle(PressableCardButtonStyle())
        .accessibilityIdentifier("start-split-\(snapshot.splitName)")
    }

    private func preview(_ split: TrainingSplit, mode: WorkoutMode = .full) {
        openPreview(WorkoutPreviewSplit(split), mode: mode)
    }

    private var emptyWorkoutCard: some View {
        FitnessCard(style: .compact) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    ExerciseIconView(
                        iconKey: .genericExercise,
                        size: 44,
                        showBackground: true,
                        isDecorative: true
                    )

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Empty Workout")
                            .font(AppTypography.cardTitle)
                        Text("Build a one-off session from scratch.")
                            .font(AppTypography.body)
                            .foregroundStyle(appTheme.mutedText)
                    }

                    Spacer()
                    CoachBadgeView(state: .baseline)
                }

                Button {
                    openSession(createEmptyWorkout())
                } label: {
                    Label("Start Empty", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(NeutralFitnessButtonStyle())
            }
        }
    }

    private var reuseCard: some View {
        FitnessCard(style: .compact) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    ExerciseIconView(
                        iconKey: .genericExercise,
                        size: 44,
                        showBackground: true,
                        isDecorative: true
                    )

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Reuse")
                            .font(AppTypography.metadataEmphasis)
                            .foregroundStyle(appTheme.mutedText)
                            .textCase(.uppercase)
                        Text("Repeat or start from a template")
                            .font(AppTypography.cardTitle)
                        Text(templateCount == 0 ? "No saved templates yet" : "\(templateCount) saved templates")
                            .font(AppTypography.body)
                            .foregroundStyle(appTheme.mutedText)
                    }

                    Spacer()
                }

                HStack {
                    Button {
                        if let lastSession = completedSessions.first {
                            openPreview(reuseBuilder.previewSplit(from: lastSession))
                        }
                    } label: {
                        Label("Repeat Last", systemImage: "repeat")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SecondaryFitnessButtonStyle())
                    .disabled(completedSessions.isEmpty)

                    Button {
                        navigate(to: .templates)
                    } label: {
                        Label("Templates", systemImage: "rectangle.stack")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SecondaryFitnessButtonStyle())
                }
            }
        }
    }

    private func recentSessionCard(_ snapshot: StartWorkoutRecentSessionSnapshot) -> some View {
        FitnessCard(style: .compact) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    ExerciseIconView(
                        iconKey: snapshot.iconKey,
                        size: 44,
                        showBackground: true,
                        isDecorative: true
                    )

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Recent Session")
                            .font(AppTypography.metadataEmphasis)
                            .foregroundStyle(appTheme.mutedText)
                            .textCase(.uppercase)
                        Text(snapshot.splitName)
                            .font(AppTypography.cardTitle)
                    }

                    Spacer()
                    CoachBadgeView(state: snapshot.badgeState)
                }

                HStack(spacing: 10) {
                    MetricTile(label: "Duration", value: snapshot.durationText, caption: nil, systemImage: "timer")
                    MetricTile(label: "Rating", value: snapshot.ratingText, caption: nil, systemImage: "face.smiling")
                }

                Text(snapshot.highlightText)
                    .font(.subheadline)
                    .foregroundStyle(appTheme.mutedText)

                Button {
                    guard let session = completedSessions.first(where: { $0.id == snapshot.sessionId }) else { return }
                    openPreview(reuseBuilder.previewSplit(from: session))
                } label: {
                    Label("Repeat Last Workout", systemImage: "repeat")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryFitnessButtonStyle())
                .disabled(completedSessions.first { $0.id == snapshot.sessionId } == nil)
            }
        }
    }

    private func lastTrainedText(for split: TrainingSplit) -> String {
        guard let session = completedSessions.first(where: { baseSplitName($0.splitNameSnapshot) == split.name }) else {
            return "No history yet"
        }

        return "Last trained \(session.date.formatted(date: .abbreviated, time: .omitted))"
    }

    private func estimatedDurationText(for split: TrainingSplit) -> String {
        let selectable = split.exercises.sorted { $0.orderIndex < $1.orderIndex }.map(WorkoutSelectableExercise.init)
        let planned = modePlanner.plannedExercises(from: selectable, mode: .full)
        let duration = modePlanner.estimatedDurationMinutes(for: planned, mode: .full)
        return "\(duration.lowerBound)-\(duration.upperBound)m"
    }

    private func badgeState(for split: TrainingSplit) -> CoachBadgeState {
        guard let recommendedName = currentDashboardSnapshot.trainingCall.recommendedSplitName else { return .baseline }
        return recommendedName == split.name ? .ready : .repeatTarget
    }

    private func activeElapsedText(for session: WorkoutSession) -> String {
        guard let startedAt = session.startedAt else { return "0:00" }
        let elapsed = max(0, Int(Date().timeIntervalSince(startedAt)) - session.accumulatedPausedSeconds)
        return "\(elapsed / 60):\(String(format: "%02d", elapsed % 60))"
    }

    private var discardAlertBinding: Binding<Bool> {
        Binding {
            pendingDiscardSession != nil
        } set: { showing in
            if !showing {
                pendingDiscardSession = nil
            }
        }
    }

    private func discardPendingWorkout() {
        guard let pendingDiscardSession else { return }
        modelContext.delete(pendingDiscardSession)
        try? modelContext.save()
        self.pendingDiscardSession = nil
    }

    private func resumeSummary(for session: WorkoutSession) -> String {
        let started = (session.startedAt ?? session.date).formatted(date: .abbreviated, time: .shortened)
        let completedSets = session.exerciseLogs.flatMap(\.setLogs).filter(\.completed).count
        return "Started \(started) - \(completedSets) completed sets"
    }

    private func createEmptyWorkout() -> WorkoutSession {
        let startDate = Date()
        let session = WorkoutSession(date: startDate, startedAt: startDate)
        modelContext.insert(session)
        try? modelContext.save()
        return session
    }

    private func baseSplitName(_ snapshot: String) -> String {
        snapshot.components(separatedBy: " - ").first ?? snapshot
    }

    private func navigate(to route: StartWorkoutRoute) {
        if let openRoute {
            PerformanceTracer.mark(.workoutRouteNavigation, "delegate_request route=\(route.analyticsName)")
            openRoute(route)
        } else {
            let activeRoute = fallbackRoute?.analyticsName ?? "none"
            PerformanceTracer.mark(.workoutRouteNavigation, "fallback_request route=\(route.analyticsName) active=\(activeRoute)")
            guard fallbackRoute != route else {
                PerformanceTracer.mark(.workoutRouteNavigation, "skip fallback route=\(route.analyticsName) already_active")
                return
            }

            fallbackRoute = route
            PerformanceTracer.mark(.workoutRouteNavigation, "fallback_set route=\(route.analyticsName)")
        }
    }

    private func openSession(_ session: WorkoutSession) {
        AppMotion.smoothNavigate(reduceMotion: reduceMotion) {
            activeSession = session
        }
    }

    private func openPreview(_ preview: WorkoutPreviewSplit, mode: WorkoutMode = .full) {
        PerformanceTracer.mark(.previewRouteTap, "source=workout split=\(preview.name) mode=\(mode.rawValue)")
        PerformanceTracer.mark(.workoutPreviewRenderSnapshot, "navigation request source=workout split=\(preview.id.uuidString)")
        navigate(to: .preview(StartWorkoutPreviewRoute(split: preview, mode: mode)))
    }
}

struct StartWorkoutPreviewRoute: Hashable {
    let split: WorkoutPreviewSplit
    let mode: WorkoutMode

    static func == (lhs: StartWorkoutPreviewRoute, rhs: StartWorkoutPreviewRoute) -> Bool {
        lhs.split == rhs.split && lhs.mode.rawValue == rhs.mode.rawValue
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(split)
        hasher.combine(mode.rawValue)
    }
}

enum StartWorkoutRoute: Hashable, Identifiable {
    case coach
    case templates
    case preview(StartWorkoutPreviewRoute)

    var id: Self { self }

    var analyticsName: String {
        switch self {
        case .coach:
            return "coach"
        case .templates:
            return "templates"
        case let .preview(route):
            return "preview-\(route.split.id.uuidString)-\(route.mode.rawValue)"
        }
    }
}

private struct StartWorkoutDashboardSnapshot {
    let trainingCall: TrainingCallSnapshot

    static func placeholder(activeSplits: [TrainingSplit]) -> StartWorkoutDashboardSnapshot {
        let splitName = activeSplits.first?.name
        return StartWorkoutDashboardSnapshot(
            trainingCall: TrainingCallSnapshot(
                recommendedSplitName: splitName,
                recommendedMode: .full,
                action: .buildBaseline,
                title: splitName.map { "\($0) preview ready" } ?? "Preview ready",
                reason: "Preview is ready while Peakline prepares the latest local training call.",
                confidence: .low,
                targetSummary: nil,
                sourceSignals: ["Workout route loaded before deeper history analytics."],
                missingOrStaleInputs: ["Coach summary is still preparing."],
                guardrailNotes: ["Start controls stay available while richer guidance loads."],
                isConservative: true
            )
        )
    }
}

private struct StartWorkoutRecentSessionSnapshot {
    let sessionId: UUID
    let splitName: String
    let durationText: String
    let ratingText: String
    let highlightText: String
    let badgeState: CoachBadgeState

    var iconKey: ExerciseIconKey {
        ExerciseIconMapper.splitIconKey(for: splitName)
    }

    static func placeholder(_ session: WorkoutSession) -> StartWorkoutRecentSessionSnapshot {
        StartWorkoutRecentSessionSnapshot(
            sessionId: session.id,
            splitName: session.splitNameSnapshot,
            durationText: durationText(for: session),
            ratingText: ratingText(for: session.perceivedDifficulty),
            highlightText: "Last session is ready to repeat while Peakline prepares the full summary.",
            badgeState: .ready
        )
    }

    private static func durationText(for session: WorkoutSession) -> String {
        if let durationSeconds = session.durationSeconds {
            return durationText(seconds: durationSeconds)
        }

        if let startedAt = session.startedAt, let endedAt = session.endedAt {
            return durationText(seconds: max(0, Int(endedAt.timeIntervalSince(startedAt))))
        }

        if let durationMinutes = session.durationMinutes {
            return "\(durationMinutes)m"
        }

        return "Recorded"
    }

    private static func durationText(seconds totalSeconds: Int) -> String {
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }

        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }

        return "\(seconds)s"
    }

    private static func ratingText(for score: Int?) -> String {
        guard let score else { return "-" }

        switch score {
        case 1:
            return "Rough"
        case 2:
            return "Okay"
        case 3:
            return "Good"
        case 4:
            return "Great"
        case 5:
            return "Excellent"
        default:
            return "\(score)/5"
        }
    }
}

private struct StartWorkoutSplitCardSnapshot: Identifiable {
    let splitId: UUID
    let splitName: String
    let lastTrainedText: String
    let estimatedDurationText: String
    let exerciseCount: Int
    let badgeState: CoachBadgeState

    var id: UUID { splitId }

    static func placeholder(_ split: TrainingSplit) -> StartWorkoutSplitCardSnapshot {
        StartWorkoutSplitCardSnapshot(
            splitId: split.id,
            splitName: split.name,
            lastTrainedText: "Ready to start",
            estimatedDurationText: "Plan ready",
            exerciseCount: 0,
            badgeState: .baseline
        )
    }
}
