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
                        NavigationInteraction.destinationDidAppear(
                            key: "workout.\(route.analyticsName)"
                        )
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
            WorkoutPreviewRouteView(preparedRoute: route.preparedRoute) {
                navigationPath.removeAll()
                pendingNavigationRoute = nil
            }
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

        let navigationKey = "workout.\(route.analyticsName)"
        guard NavigationInteraction.perform(
            key: navigationKey,
            destinationClass: route.destinationClass,
            haptic: .selection,
            action: {
            pendingNavigationRoute = route
            navigationPath.append(route)
        }) else {
            return
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
    @State private var activeSessionNavigationKey: String?
    @State private var pendingNewSessionSaveID: UUID?
    @State private var pendingDiscardSession: WorkoutSession?
    @State private var fallbackRoute: StartWorkoutRoute?
    @State private var sleepSettings = SleepSettingsStore().load()
    @State private var sleepReadinessSnapshot = SleepAnalyticsService.emptyReadinessSnapshot()
    @State private var lastSleepReadinessSignature: SleepAnalyticsInputSignature?
    @State private var dashboardSnapshot: StartWorkoutDashboardSnapshot?
    @State private var recentSessionSnapshot: StartWorkoutRecentSessionSnapshot?
    @State private var splitCardSnapshots: [StartWorkoutSplitCardSnapshot] = []
    @State private var lastDashboardSignature: String?
    @State private var dashboardRefreshTask: Task<Void, Never>?
    @State private var isWorkoutCompletionPresentationActive = false
    @State private var isDashboardVisible = false

    private let openRoute: ((StartWorkoutRoute) -> Void)?
    private let modePlanner = WorkoutModePlanner()
    private let summaryBuilder = SessionSummaryBuilder()
    private let reuseBuilder = WorkoutReuseBuilder()
    private let rotationService = TrainingRotationService()
    private let sleepCoaching = SleepCoachingService()
    private let sleepSettingsStore = SleepSettingsStore()
    private let sleepReadinessStore = SleepWorkoutReadinessSnapshotStore.shared
    private let dashboardWarmStartStore = WorkoutDashboardWarmStartStore.shared

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
        if let dashboardSnapshot {
            return dashboardSnapshot
        }

        if let warmTrainingCall = dashboardWarmStartStore.trainingCall,
           let splitName = warmTrainingCall.recommendedSplitName,
           activeSplits.contains(where: { $0.name == splitName }) {
            return StartWorkoutDashboardSnapshot(trainingCall: warmTrainingCall)
        }

        return .placeholder
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
        guard let name = currentDashboardSnapshot.trainingCall.recommendedSplitName else { return nil }
        return activeSplits.first { $0.name == name }
    }

    private var displayedSplits: [TrainingSplit] {
        rotationService.orderedActiveSplits(activeSplits)
    }

    private var currentSleepReadinessSignature: SleepAnalyticsInputSignature {
        SleepAnalyticsInputSignature(sessions: sleepSessions, naps: napSessions, workouts: completedSessions, settings: sleepSettings, sessionLimit: 45, workoutLimit: 12)
    }

    private var sleepReadinessSignatureForObservation: SleepAnalyticsInputSignature? {
        isWorkoutCompletionPresentationActive || !isDashboardVisible ? nil : currentSleepReadinessSignature
    }

    private var currentDashboardSignature: String {
        [
            activeSplits.map { split in
                "\(split.id.uuidString):\(split.name):\(split.activeRotationIndex ?? -1):\(split.updatedAt.timeIntervalSince1970)"
            }
            .joined(separator: "|"),
            completedSessions.prefix(20).map { session in
                "\(session.id.uuidString):\(session.date.timeIntervalSince1970):\(session.endedAt?.timeIntervalSince1970 ?? 0):\(session.durationSeconds ?? 0):\(session.perceivedDifficulty ?? 0)"
            }
            .joined(separator: "|")
        ].joined(separator: "||")
    }

    private var dashboardSignatureForObservation: String? {
        isWorkoutCompletionPresentationActive || !isDashboardVisible ? nil : currentDashboardSignature
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
        FitnessScreen {
            if let unfinishedSession = unfinishedSessions.first {
                activeWorkoutCard(unfinishedSession)
            } else if let recommendedSplit {
                recommendedWorkoutCard(recommendedSplit)
            }

            if let recommendation = adaptiveSleepRecommendation {
                DashboardSection(title: "Readiness") {
                    workoutRecoveryBanner(recommendation)
                }
            } else if let hint = sleepCoaching.preWorkoutHint(for: sleepSummary) {
                DashboardSection(title: "Readiness") {
                    sleepReadinessCard(title: hint.title, suggestion: hint.suggestion)
                }
            }

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
            WorkoutLoggerView(session: session) {
                activeSession = nil
            }
            .onAppear {
                if let activeSessionNavigationKey {
                    NavigationInteraction.destinationDidAppear(
                        key: activeSessionNavigationKey
                    )
                    self.activeSessionNavigationKey = nil
                }
                persistNewSessionIfNeeded(session)
            }
        }
        .navigationDestination(item: $fallbackRoute) { route in
            Group {
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
                    WorkoutPreviewRouteView(preparedRoute: route.preparedRoute) {
                        fallbackRoute = nil
                    }
                }
            }
            .onAppear {
                NavigationInteraction.destinationDidAppear(
                    key: "workout.fallback.\(route.analyticsName)"
                )
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
            isDashboardVisible = true
            sleepSettings = sleepSettingsStore.load()
            restoreWarmedDashboardIfNeeded()
            scheduleDashboardSnapshotRefresh(force: dashboardSnapshot == nil)
            if lastSleepReadinessSignature == nil {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(50))
                    guard !Task.isCancelled, isDashboardVisible else { return }
                    refreshSleepReadiness()
                }
            }
        }
        .onChange(of: dashboardSignatureForObservation) { _, signature in
            guard signature != nil else { return }
            scheduleDashboardSnapshotRefresh()
        }
        .onChange(of: sleepReadinessSignatureForObservation) { _, signature in
            guard signature != nil else { return }
            refreshSleepReadiness()
        }
        .onReceive(NotificationCenter.default.publisher(for: .workoutCompletionPresentationBegan)) { _ in
            isWorkoutCompletionPresentationActive = true
            dashboardRefreshTask?.cancel()
            dashboardRefreshTask = nil
            PerformanceTracer.mark(.workoutLoggerFinish, "workout_dashboard_refresh_suspended")
        }
        .onReceive(NotificationCenter.default.publisher(for: .workoutCompletionPresentationEnded)) { _ in
            isWorkoutCompletionPresentationActive = false
            PerformanceTracer.mark(.workoutLoggerFinish, "workout_dashboard_refresh_resumed")
        }
        .onDisappear {
            isDashboardVisible = false
            dashboardRefreshTask?.cancel()
        }
    }

    private func scheduleDashboardSnapshotRefresh(force: Bool = false) {
        guard isDashboardVisible, !isWorkoutCompletionPresentationActive else { return }
        let signature = currentDashboardSignature
        guard force || signature != lastDashboardSignature else { return }

        dashboardRefreshTask?.cancel()
        dashboardRefreshTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled, !isWorkoutCompletionPresentationActive else { return }
            await refreshDashboardSnapshot(signature: signature)
        }
    }

    private func refreshDashboardSnapshot(signature: String) async {
        guard isDashboardVisible, !isWorkoutCompletionPresentationActive else { return }
        let orderedActiveSplits = rotationService.orderedActiveSplits(activeSplits)
        let activeSnapshots = orderedActiveSplits.map(TrainingSplitSnapshot.init)
        let completedSnapshots = completedSessions.prefix(20).map(WorkoutAnalyticsSession.init)
        let call = await Task.detached(priority: .userInitiated) {
            let summary = CoachRecommendationEngine().makeSummary(
                activeSplits: activeSnapshots,
                completedSessions: completedSnapshots
            )
            return TrainingCallSnapshotBuilder().make(
                decision: summary.trainingDecision,
                activeSplits: activeSnapshots,
                completedSessions: completedSnapshots
            )
        }.value
        guard !Task.isCancelled,
              isDashboardVisible,
              !isWorkoutCompletionPresentationActive,
              signature == currentDashboardSignature else { return }

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
        guard isDashboardVisible, !isWorkoutCompletionPresentationActive else { return }
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

    private func restoreWarmedDashboardIfNeeded() {
        guard dashboardSnapshot == nil,
              let trainingCall = dashboardWarmStartStore.trainingCall else { return }

        // Startup already prepared the recommendation. Keep the first Workout
        // frame value-only and do not compete with an immediately requested
        // Preview push by recomputing the same dashboard relationships.
        AppMotion.withoutAnimation {
            dashboardSnapshot = StartWorkoutDashboardSnapshot(trainingCall: trainingCall)
            recentSessionSnapshot = completedSessions.first.map(StartWorkoutRecentSessionSnapshot.placeholder)
            splitCardSnapshots = displayedSplits.map(StartWorkoutSplitCardSnapshot.placeholder)
            lastDashboardSignature = currentDashboardSignature
        }
    }

    private func activeWorkoutCard(_ session: WorkoutSession) -> some View {
        FitnessCard(style: .hero) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
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

                    Spacer(minLength: 8)

                    VStack(alignment: .trailing, spacing: 3) {
                        Label("Elapsed", systemImage: "timer")
                            .font(AppTypography.metadataEmphasis)
                            .foregroundStyle(appTheme.colors.textSecondary)
                        Text(activeElapsedText(for: session))
                            .font(AppTypography.largeMetric)
                            .foregroundStyle(appTheme.colors.textPrimary)
                            .monospacedDigit()
                    }
                }

                Text(resumeSummary(for: session))
                    .font(AppTypography.body)
                    .foregroundStyle(appTheme.mutedText)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        resumeButton(session)
                        discardButton(session)
                    }

                    VStack(spacing: 10) {
                        resumeButton(session)
                        discardButton(session)
                    }
                }
            }
        }
    }

    private func resumeButton(_ session: WorkoutSession) -> some View {
        Button {
            openSession(session)
        } label: {
            Label("Resume", systemImage: "play.circle.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(PrimaryFitnessButtonStyle())
    }

    private func discardButton(_ session: WorkoutSession) -> some View {
        Button {
            pendingDiscardSession = session
        } label: {
            Label("Discard", systemImage: "xmark.circle")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(NeutralFitnessButtonStyle())
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

                Label(
                    PeaklineText.joinedMetadata([
                        "\(currentDashboardSnapshot.trainingCall.recommendedMode.displayName) mode",
                        currentDashboardSnapshot.trainingCall.confidence.displayName.lowercased()
                    ]),
                    systemImage: currentDashboardSnapshot.trainingCall.recommendedMode.systemImage
                )
                    .font(AppTypography.metadataEmphasis)
                    .foregroundStyle(appTheme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        recommendedPreviewButton(split)
                        coachButton
                    }

                    VStack(spacing: 10) {
                        recommendedPreviewButton(split)
                        coachButton
                    }
                }
            }
        }
    }

    private func recommendedPreviewButton(_ split: TrainingSplit) -> some View {
        Button {
            preview(split, mode: currentDashboardSnapshot.trainingCall.recommendedMode)
        } label: {
            Label("Preview", systemImage: "target")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(PrimaryFitnessButtonStyle())
        .accessibilityIdentifier("workout-recommended-preview")
    }

    private var coachButton: some View {
        Button {
            navigate(to: .coach)
        } label: {
            Label("Coach", systemImage: "sparkles")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(SecondaryFitnessButtonStyle())
    }

    private func sleepReadinessCard(title: String, suggestion: String) -> some View {
        FitnessCard(style: .compact) {
            HStack(alignment: .top, spacing: 12) {
                FitnessIconBadge(systemImage: "moon.stars.fill", size: 40)

                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(AppTypography.sectionTitle)
                        .foregroundStyle(appTheme.colors.textPrimary)

                    Text(suggestion)
                        .font(AppTypography.metadata)
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
                FitnessIconBadge(
                    systemImage: recoveryIcon(for: recommendation),
                    size: 40,
                    tint: recoveryTint(for: recommendation),
                    background: recoveryTint(for: recommendation).opacity(0.14)
                )

                VStack(alignment: .leading, spacing: 5) {
                    Text(recommendation.title)
                        .font(AppTypography.sectionTitle)
                        .foregroundStyle(appTheme.colors.textPrimary)

                    Text(recommendation.message)
                        .font(AppTypography.body)
                        .foregroundStyle(appTheme.colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let action = recommendation.suggestedActions.first {
                        Text(action.displayName)
                            .font(AppTypography.metadataEmphasis)
                            .foregroundStyle(recoveryTint(for: recommendation))
                    }
                }

                Spacer(minLength: 8)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func recoveryTint(for recommendation: AdaptiveTrainingRecommendation) -> Color {
        if requestsMissingSleep(recommendation) {
            return appTheme.colors.accent
        }

        switch recommendation.level {
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

    private func recoveryIcon(for recommendation: AdaptiveTrainingRecommendation) -> String {
        if requestsMissingSleep(recommendation) {
            return "moon.stars.fill"
        }

        switch recommendation.level {
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

    private func requestsMissingSleep(_ recommendation: AdaptiveTrainingRecommendation) -> Bool {
        recommendation.title.localizedCaseInsensitiveContains("sleep")
            && recommendation.title.localizedCaseInsensitiveContains("add")
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
        Button {
            openSession(createEmptyWorkout(), requiresSave: true)
        } label: {
            DashboardActionTile(
                title: "Empty workout",
                subtitle: "Build a one-off session from scratch",
                systemImage: "plus",
                status: nil,
                layout: .horizontal,
                showsChevron: true,
                minHeight: appTheme.metrics.largeRowMinHeight
            )
        }
        .buttonStyle(PressableCardButtonStyle())
        .accessibilityIdentifier("start-empty-workout")
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
        return "\(duration.lowerBound)–\(duration.upperBound) min"
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
        return PeaklineText.joinedMetadata([
            "Started \(started)",
            PeaklineText.count(completedSets, singular: "completed set")
        ])
    }

    private func createEmptyWorkout() -> WorkoutSession {
        let startDate = Date()
        let session = WorkoutSession(date: startDate, startedAt: startDate)
        modelContext.insert(session)
        return session
    }

    private func baseSplitName(_ snapshot: String) -> String {
        snapshot.components(separatedBy: " - ").first ?? snapshot
    }

    private func navigate(to route: StartWorkoutRoute) {
        if let openRoute {
            suspendDashboardRefreshForNavigation()
            PerformanceTracer.mark(.workoutRouteNavigation, "delegate_request route=\(route.analyticsName)")
            openRoute(route)
        } else {
            let activeRoute = fallbackRoute?.analyticsName ?? "none"
            PerformanceTracer.mark(.workoutRouteNavigation, "fallback_request route=\(route.analyticsName) active=\(activeRoute)")
            guard fallbackRoute != route else {
                PerformanceTracer.mark(.workoutRouteNavigation, "skip fallback route=\(route.analyticsName) already_active")
                return
            }

            let navigationKey = "workout.fallback.\(route.analyticsName)"
            guard NavigationInteraction.perform(
                key: navigationKey,
                destinationClass: route.destinationClass,
                haptic: .selection,
                action: {
                suspendDashboardRefreshForNavigation()
                fallbackRoute = route
            }) else {
                return
            }
            PerformanceTracer.mark(.workoutRouteNavigation, "fallback_set route=\(route.analyticsName)")
        }
    }

    private func openSession(
        _ session: WorkoutSession,
        requiresSave: Bool = false
    ) {
        let navigationKey = requiresSave
            ? "workout.session.new"
            : "workout.session.\(session.id.uuidString)"
        guard NavigationInteraction.perform(
            key: navigationKey,
            destinationClass: .warm,
            haptic: .medium,
            action: {
                suspendDashboardRefreshForNavigation()
                if requiresSave {
                    pendingNewSessionSaveID = session.id
                }
                activeSessionNavigationKey = navigationKey
                activeSession = session
            }
        ) else {
            if requiresSave {
                modelContext.delete(session)
            }
            return
        }
    }

    private func persistNewSessionIfNeeded(_ session: WorkoutSession) {
        guard pendingNewSessionSaveID == session.id else { return }
        pendingNewSessionSaveID = nil

        Task { @MainActor in
            await Task.yield()
            PerformanceTracer.trace(.navigationPersistence) {
                try? modelContext.save()
            }
        }
    }

    private func openPreview(_ preview: WorkoutPreviewSplit, mode: WorkoutMode = .full) {
        PerformanceTracer.mark(.previewRouteTap, "source=workout split=\(preview.name) mode=\(mode.rawValue)")
        PerformanceTracer.mark(.workoutPreviewRenderSnapshot, "navigation request source=workout split=\(preview.id.uuidString)")
        navigate(to: .preview(StartWorkoutPreviewRoute(split: preview, mode: mode)))
    }

    private func suspendDashboardRefreshForNavigation() {
        isDashboardVisible = false
        dashboardRefreshTask?.cancel()
        dashboardRefreshTask = nil
    }
}

struct StartWorkoutPreviewRoute: Hashable {
    let preparedRoute: WorkoutPreviewPreparedRoute

    var split: WorkoutPreviewSplit { preparedRoute.split }
    var mode: WorkoutMode { preparedRoute.initialMode }

    @MainActor
    init(split: WorkoutPreviewSplit, mode: WorkoutMode) {
        preparedRoute = WorkoutPreviewWarmStartStore.shared.prepareRoute(
            for: split,
            initialMode: mode
        )
    }

    static func == (lhs: StartWorkoutPreviewRoute, rhs: StartWorkoutPreviewRoute) -> Bool {
        lhs.preparedRoute == rhs.preparedRoute
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(preparedRoute)
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

    var destinationClass: NavigationDestinationClass {
        switch self {
        case .coach:
            return .warm
        case .templates, .preview:
            return .deep
        }
    }
}

private struct StartWorkoutDashboardSnapshot {
    let trainingCall: TrainingCallSnapshot

    static let placeholder = StartWorkoutDashboardSnapshot(trainingCall: .placeholder)
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
