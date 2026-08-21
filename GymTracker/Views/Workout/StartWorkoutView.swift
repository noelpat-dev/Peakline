import SwiftData
import SwiftUI

struct StartWorkoutView: View {
    @State private var navigationPath: [StartWorkoutRoute] = []
    @State private var pendingNavigationRoute: StartWorkoutRoute?
    private let initialReadinessSnapshot: WorkoutSleepReadinessSnapshot?
    private let initialReadinessSignature: SleepAnalyticsInputSignature?
    private let initialFirstFrameSnapshot: WorkoutStartFirstFrameSnapshot?
    private let initialOverallReadinessIsProvisional: Bool

    init(
        initialReadinessSnapshot: WorkoutSleepReadinessSnapshot? = nil,
        initialReadinessSignature: SleepAnalyticsInputSignature? = nil,
        initialFirstFrameSnapshot: WorkoutStartFirstFrameSnapshot? = nil,
        initialOverallReadinessIsProvisional: Bool = true
    ) {
        self.initialReadinessSnapshot = initialReadinessSnapshot
        self.initialReadinessSignature = initialReadinessSignature
        self.initialFirstFrameSnapshot = initialFirstFrameSnapshot
        self.initialOverallReadinessIsProvisional = initialOverallReadinessIsProvisional
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            StartWorkoutContentView(
                initialReadinessSnapshot: initialReadinessSnapshot,
                initialReadinessSignature: initialReadinessSignature,
                initialFirstFrameSnapshot: initialFirstFrameSnapshot,
                initialOverallReadinessIsProvisional: initialOverallReadinessIsProvisional
            ) { route in
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

/// Keeps dashboard item construction behind the lazy stack's visibility
/// boundary. `FitnessScreen` accepts an already-built `Content` value, so its
/// lazy stack cannot prevent every dashboard card from being constructed while
/// the root tab is mounting.
private struct StartWorkoutLazyScreen<Content: View>: View {
    @Environment(\.appTheme) private var appTheme

    let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(
                alignment: .leading,
                spacing: appTheme.metrics.screenContentSpacing
            ) {
                content()
            }
            .padding(appTheme.metrics.screenPadding)
            .padding(.bottom, appTheme.metrics.screenBottomPadding)
        }
        .scrollDismissesKeyboard(.interactively)
        .submitLabel(.done)
        .background(appTheme.colors.backgroundPrimary.ignoresSafeArea())
    }
}

struct StartWorkoutContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var appTheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var workoutWarmStartInvalidation = WorkoutWarmStartInvalidation.shared

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
    @State private var sleepReadinessSnapshot = WorkoutSleepReadinessSnapshot.empty
    @State private var lastSleepReadinessSignature: SleepAnalyticsInputSignature?
    @State private var dashboardSnapshot: StartWorkoutDashboardSnapshot?
    @State private var recentSessionSnapshot: StartWorkoutRecentSessionSnapshot?
    @State private var splitCardSnapshots: [StartWorkoutSplitCardSnapshot] = []
    @State private var lastDashboardSignature: String?
    @State private var dashboardRefreshTask: Task<Void, Never>?
    @State private var isWorkoutCompletionPresentationActive = false
    @State private var isDashboardVisible = false
    @State private var isSleepReadinessObservationEnabled = false
    @State private var hasSeededDashboardSnapshot = false
    @State private var isOverallReadinessProvisional = true
    @State private var showsSupportingDashboardItems = false
    @State private var supportingDashboardRevealTask: Task<Void, Never>?
    @ObservedObject private var overallReadinessSnapshotStore = OverallReadinessSnapshotStore.shared

    private let openRoute: ((StartWorkoutRoute) -> Void)?
    private let modePlanner = WorkoutModePlanner()
    private let summaryBuilder = SessionSummaryBuilder()
    private let reuseBuilder = WorkoutReuseBuilder()
    private let rotationService = TrainingRotationService()
    private let sleepSettingsStore = SleepSettingsStore()
    private let sleepReadinessStore = SleepWorkoutReadinessSnapshotStore.shared
    private let dashboardWarmStartStore = WorkoutDashboardWarmStartStore.shared

    init(
        initialReadinessSnapshot: WorkoutSleepReadinessSnapshot? = nil,
        initialReadinessSignature: SleepAnalyticsInputSignature? = nil,
        initialFirstFrameSnapshot: WorkoutStartFirstFrameSnapshot? = nil,
        initialOverallReadinessIsProvisional: Bool = true,
        openRoute: ((StartWorkoutRoute) -> Void)? = nil
    ) {
        self.openRoute = openRoute
        let usableInitialSnapshot: WorkoutStartFirstFrameSnapshot?
        if let initialFirstFrameSnapshot,
           initialFirstFrameSnapshot.workoutRevision == WorkoutWarmStartInvalidation.shared.revision {
            usableInitialSnapshot = initialFirstFrameSnapshot
        } else {
            usableInitialSnapshot = nil
        }
        _sleepReadinessSnapshot = State(
            initialValue: initialReadinessSnapshot ?? .empty
        )
        _lastSleepReadinessSignature = State(
            initialValue: initialReadinessSignature
        )
        _dashboardSnapshot = State(
            initialValue: usableInitialSnapshot?.dashboard
        )
        _recentSessionSnapshot = State(
            initialValue: usableInitialSnapshot?.recentSession
        )
        _splitCardSnapshots = State(
            initialValue: usableInitialSnapshot?.splitCards ?? []
        )
        _lastDashboardSignature = State(
            initialValue: usableInitialSnapshot?.dashboardSignature
        )
        _hasSeededDashboardSnapshot = State(
            initialValue: usableInitialSnapshot != nil
        )
        _isOverallReadinessProvisional = State(
            initialValue: initialOverallReadinessIsProvisional
        )
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
        // Readiness uses the newest 45 sessions; avoid fetching an extra cold
        // page into the root tab before the deferred sleep refresh runs.
        descriptor.fetchLimit = 45
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
            return presentationSafeDashboardSnapshot(dashboardSnapshot)
        }

        if warmDashboardSourceIsCurrent,
           let warmTrainingCall = dashboardWarmStartStore.trainingCall,
           let splitName = warmTrainingCall.recommendedSplitName,
           let split = activeSplits.first(where: { $0.name == splitName }) {
            let presentationCall = warmTrainingCall.neutralizedForProvisionalReadiness(
                if: currentOverallReadinessIsProvisional
            )
            return StartWorkoutDashboardSnapshot(
                trainingCall: presentationCall,
                recommendedSplit: StartWorkoutRecommendedSplitSnapshot(
                    id: split.id,
                    name: split.name
                )
            )
        }

        return .placeholder
    }

    private func presentationSafeDashboardSnapshot(
        _ snapshot: StartWorkoutDashboardSnapshot
    ) -> StartWorkoutDashboardSnapshot {
        StartWorkoutDashboardSnapshot(
            trainingCall: snapshot.trainingCall.neutralizedForProvisionalReadiness(
                if: currentOverallReadinessIsProvisional
            ),
            recommendedSplit: snapshot.recommendedSplit
        )
    }

    private var currentRecentSessionSnapshot: StartWorkoutRecentSessionSnapshot? {
        if hasSeededDashboardSnapshot {
            return recentSessionSnapshot
        }

        return recentSessionSnapshot ?? completedSessions.first.map(StartWorkoutRecentSessionSnapshot.placeholder)
    }

    private var currentSplitCardSnapshots: [StartWorkoutSplitCardSnapshot] {
        if hasSeededDashboardSnapshot || !splitCardSnapshots.isEmpty {
            return splitCardSnapshots
        }

        return displayedSplits.map(StartWorkoutSplitCardSnapshot.placeholder)
    }

    private var displayedSplits: [TrainingSplit] {
        rotationService.orderedActiveSplits(activeSplits)
    }

    private var currentSleepReadinessSignature: SleepAnalyticsInputSignature {
        SleepAnalyticsInputSignature(
            sessions: sleepSessions,
            naps: napSessions,
            workouts: completedSessions,
            settings: sleepSettings,
            sessionLimit: 45,
            workoutLimit: 12,
            workoutRevision: workoutWarmStartInvalidation.revision
        )
    }

    private var sleepReadinessSignatureForObservation: SleepAnalyticsInputSignature? {
        guard isSleepReadinessObservationEnabled,
              !isWorkoutCompletionPresentationActive,
              isDashboardVisible else {
            return nil
        }
        return currentSleepReadinessSignature
    }

    private var currentDashboardSignature: String {
        WorkoutDashboardInputSignature(
            splits: activeSplits.map {
                .init(
                    id: $0.id,
                    name: $0.name,
                    activeRotationIndex: $0.activeRotationIndex,
                    updatedAt: $0.updatedAt
                )
            },
            sessions: completedSessions.prefix(20).map {
                .init(
                    id: $0.id,
                    date: $0.date,
                    endedAt: $0.endedAt,
                    durationSeconds: $0.durationSeconds,
                    perceivedDifficulty: $0.perceivedDifficulty
                )
            },
            workoutRevision: workoutWarmStartInvalidation.revision
        ).value
    }

    private var warmDashboardSourceIsCurrent: Bool {
        guard let sourceSignature = dashboardWarmStartStore.sourceSignature else { return false }
        return sourceSignature.hasPrefix("revision:\(workoutWarmStartInvalidation.revision)|")
    }

    private var dashboardSignatureForObservation: String? {
        isWorkoutCompletionPresentationActive || !isDashboardVisible ? nil : currentDashboardSignature
    }

    private var sleepSummary: WorkoutSleepReadinessSnapshot? {
        sleepReadinessSnapshot.hasPrimarySession ? sleepReadinessSnapshot : nil
    }

    private var adaptiveSleepRecommendation: AdaptiveTrainingRecommendation? {
        guard !currentOverallReadinessIsProvisional else { return nil }
        guard sleepSettings.coachingPreferences.adaptiveWorkoutRecommendationsEnabled else { return nil }
        return sleepReadinessSnapshot.adaptiveRecommendation
    }

    private var provisionalSleepSupport: (title: String, suggestion: String)? {
        guard currentOverallReadinessIsProvisional, sleepSummary != nil else { return nil }
        return (
            "Sleep context",
            "Sleep is one supportive signal. Training guidance waits until daily readiness has enough evidence."
        )
    }

    private var currentOverallReadinessIsProvisional: Bool {
        let snapshot = overallReadinessSnapshotStore.snapshot
        return snapshot.revision > 0 ? snapshot.isProvisional : isOverallReadinessProvisional
    }

    private func preWorkoutSleepHint(
        for summary: WorkoutSleepReadinessSnapshot?
    ) -> (title: String, suggestion: String)? {
        guard let summary, let score = summary.sleepScore else { return nil }

        switch summary.recoveryState {
        case .high:
            return ("Sleep recovery: High", "Normal progression is suitable if warm-ups feel good.")
        case .good:
            return ("Sleep recovery: Good", "Continue with the planned session and adjust from your first working sets.")
        case .moderate:
            return ("Sleep recovery: Moderate", "Keep top sets controlled today.")
        case .low:
            return ("Sleep recovery: Low", "Avoid extra failure sets and reduce accessory volume if needed.")
        case .veryLow:
            return ("Sleep recovery: Very low", "A lighter session or rest may be more productive today.")
        case .unknown:
            return score > 0 ? ("Sleep recovery", "Use warm-ups to decide how hard to push today.") : nil
        }
    }

    var body: some View {
        workoutDashboard
    }

    private var workoutDashboard: some View {
        StartWorkoutLazyScreen {
            if let unfinishedSession = unfinishedSessions.first {
                activeWorkoutCard(unfinishedSession)
            } else if let recommendedSplit = currentDashboardSnapshot.recommendedSplit {
                recommendedWorkoutCard(recommendedSplit)
            }

            if let recommendation = adaptiveSleepRecommendation {
                DashboardSection(title: "Readiness") {
                    workoutRecoveryBanner(recommendation)
                }
            } else if !currentOverallReadinessIsProvisional,
                      let hint = preWorkoutSleepHint(for: sleepSummary) {
                DashboardSection(title: "Readiness") {
                    sleepReadinessCard(title: hint.title, suggestion: hint.suggestion)
                }
            } else if let support = provisionalSleepSupport {
                DashboardSection(title: "Readiness") {
                    sleepReadinessCard(title: support.title, suggestion: support.suggestion)
                }
            }

            if showsSupportingDashboardItems {
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
            if !showsSupportingDashboardItems {
                supportingDashboardRevealTask?.cancel()
                supportingDashboardRevealTask = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(150))
                    guard !Task.isCancelled, isDashboardVisible else { return }
                    showsSupportingDashboardItems = true
                    supportingDashboardRevealTask = nil
                }
            }
            let readinessSnapshot = overallReadinessSnapshotStore.snapshot
            if readinessSnapshot.revision > 0 {
                isOverallReadinessProvisional = readinessSnapshot.isProvisional
            }
            sleepSettings = sleepSettingsStore.load()
            restoreWarmedDashboardIfNeeded()
            scheduleDashboardSnapshotRefresh(force: dashboardSnapshot == nil)
            if lastSleepReadinessSignature == nil {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(50))
                    guard !Task.isCancelled, isDashboardVisible else { return }
                    refreshSleepReadiness()
                    isSleepReadinessObservationEnabled = true
                }
            } else {
                Task { @MainActor in
                    await Task.yield()
                    guard !Task.isCancelled, isDashboardVisible else { return }
                    isSleepReadinessObservationEnabled = true
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
        .onChange(of: overallReadinessSnapshotStore.snapshot) { _, snapshot in
            guard snapshot.revision > 0 else { return }
            isOverallReadinessProvisional = snapshot.isProvisional
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
            supportingDashboardRevealTask?.cancel()
            supportingDashboardRevealTask = nil
            isSleepReadinessObservationEnabled = false
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

        let presentationCall = call.neutralizedForProvisionalReadiness(
            if: currentOverallReadinessIsProvisional
        )
        AppMotion.withoutAnimation {
            dashboardSnapshot = StartWorkoutDashboardSnapshot(
                trainingCall: presentationCall,
                recommendedSplit: activeSplits.first {
                    $0.name == presentationCall.recommendedSplitName
                }.map {
                    StartWorkoutRecommendedSplitSnapshot(id: $0.id, name: $0.name)
                }
            )
            recentSessionSnapshot = makeRecentSessionSnapshot()
            splitCardSnapshots = displayedSplits.map(makeSplitCardSnapshot)
            lastDashboardSignature = signature
            hasSeededDashboardSnapshot = true
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

        let nextSnapshot = PerformanceTracer.trace(.workoutStartSleepReadiness) {
            sleepReadinessStore.snapshot(
                sessions: sleepSessions,
                naps: napSessions,
                workouts: completedSessions,
                settings: sleepSettings,
                workoutRevision: workoutWarmStartInvalidation.revision,
                force: force
            )
        }
        sleepReadinessSnapshot = WorkoutSleepReadinessSnapshot(nextSnapshot)
        lastSleepReadinessSignature = signature
    }

    private func restoreWarmedDashboardIfNeeded() {
        guard !hasSeededDashboardSnapshot,
              dashboardSnapshot == nil,
              warmDashboardSourceIsCurrent,
              let trainingCall = dashboardWarmStartStore.trainingCall else { return }

        let presentationCall = trainingCall.neutralizedForProvisionalReadiness(
            if: currentOverallReadinessIsProvisional
        )

        // Startup already prepared the recommendation. Keep the first Workout
        // frame value-only and do not compete with an immediately requested
        // Preview push by recomputing the same dashboard relationships.
        AppMotion.withoutAnimation {
            dashboardSnapshot = StartWorkoutDashboardSnapshot(
                trainingCall: presentationCall,
                recommendedSplit: activeSplits.first {
                    $0.name == presentationCall.recommendedSplitName
                }.map {
                    StartWorkoutRecommendedSplitSnapshot(id: $0.id, name: $0.name)
                }
            )
            recentSessionSnapshot = completedSessions.first.map(StartWorkoutRecentSessionSnapshot.placeholder)
            splitCardSnapshots = displayedSplits.map(StartWorkoutSplitCardSnapshot.placeholder)
            lastDashboardSignature = currentDashboardSignature
            hasSeededDashboardSnapshot = true
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

    private func recommendedWorkoutCard(_ split: StartWorkoutRecommendedSplitSnapshot) -> some View {
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

    private func recommendedPreviewButton(_ split: StartWorkoutRecommendedSplitSnapshot) -> some View {
        Button {
            guard let liveSplit = activeSplits.first(where: { $0.id == split.id }) else { return }
            preview(liveSplit, mode: currentDashboardSnapshot.trainingCall.recommendedMode)
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
                    .font(AppTypography.body)
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

struct WorkoutDashboardInputSignature: Sendable, Equatable {
    struct Split: Sendable, Equatable {
        let id: UUID
        let name: String
        let activeRotationIndex: Int?
        let updatedAt: Date
    }

    struct Session: Sendable, Equatable {
        let id: UUID
        let date: Date
        let endedAt: Date?
        let durationSeconds: Int?
        let perceivedDifficulty: Int?
    }

    let splits: [Split]
    let sessions: [Session]
    let workoutRevision: Int

    init(
        splits: [Split],
        sessions: [Session],
        workoutRevision: Int
    ) {
        self.splits = splits
        self.sessions = sessions
        self.workoutRevision = workoutRevision
    }

    var value: String {
        [
            "revision:\(workoutRevision)",
            splits.map { split in
                "\(split.id.uuidString):\(split.name):\(split.activeRotationIndex ?? -1):\(split.updatedAt.timeIntervalSince1970)"
            }
            .joined(separator: "|"),
            sessions.map { session in
                "\(session.id.uuidString):\(session.date.timeIntervalSince1970):\(session.endedAt?.timeIntervalSince1970 ?? 0):\(session.durationSeconds ?? 0):\(session.perceivedDifficulty ?? 0)"
            }
            .joined(separator: "|")
        ].joined(separator: "||")
    }
}

struct WorkoutStartFirstFrameSnapshot: Sendable {
    let dashboard: StartWorkoutDashboardSnapshot
    let recentSession: StartWorkoutRecentSessionSnapshot?
    let splitCards: [StartWorkoutSplitCardSnapshot]
    let dashboardSignature: String
    let workoutRevision: Int

    static func make(
        trainingCall: TrainingCallSnapshot,
        activeSplits: [TrainingSplitSnapshot],
        historyWorkouts: [HistoryWorkoutSnapshot],
        previewWarmSnapshots: [WorkoutPreviewWarmSnapshot],
        dashboardSignature: String,
        workoutRevision: Int
    ) -> WorkoutStartFirstFrameSnapshot {
        let splitCards = activeSplits.map { split in
            let preparedFullWorkout = previewWarmSnapshots.first {
                $0.splitID == split.id && $0.mode == .full
            }
            let estimatedDurationText = preparedFullWorkout.map {
                "\($0.estimatedDuration.lowerBound)–\($0.estimatedDuration.upperBound) min"
            } ?? "Plan ready"
            let lastTrainedText = historyWorkouts.first {
                baseSplitName($0.splitName) == split.name
            }.map {
                "Last trained \($0.date.formatted(date: .abbreviated, time: .omitted))"
            } ?? "No history yet"
            let badgeState: CoachBadgeState
            if let recommendedSplitName = trainingCall.recommendedSplitName {
                badgeState = recommendedSplitName == split.name ? .ready : .repeatTarget
            } else {
                badgeState = .baseline
            }

            return StartWorkoutSplitCardSnapshot(
                splitId: split.id,
                splitName: split.name,
                lastTrainedText: lastTrainedText,
                estimatedDurationText: estimatedDurationText,
                exerciseCount: split.exercises.count,
                badgeState: badgeState
            )
        }

        return WorkoutStartFirstFrameSnapshot(
            dashboard: StartWorkoutDashboardSnapshot(
                trainingCall: trainingCall,
                recommendedSplit: activeSplits.first {
                    $0.name == trainingCall.recommendedSplitName
                }.map {
                    StartWorkoutRecommendedSplitSnapshot(id: $0.id, name: $0.name)
                }
            ),
            recentSession: historyWorkouts.first.map(StartWorkoutRecentSessionSnapshot.placeholder),
            splitCards: splitCards,
            dashboardSignature: dashboardSignature,
            workoutRevision: workoutRevision
        )
    }

    private static func baseSplitName(_ snapshot: String) -> String {
        snapshot.components(separatedBy: " - ").first ?? snapshot
    }
}

struct StartWorkoutRecommendedSplitSnapshot: Sendable {
    let id: UUID
    let name: String
}

struct StartWorkoutDashboardSnapshot: Sendable {
    let trainingCall: TrainingCallSnapshot
    let recommendedSplit: StartWorkoutRecommendedSplitSnapshot?

    init(
        trainingCall: TrainingCallSnapshot,
        recommendedSplit: StartWorkoutRecommendedSplitSnapshot? = nil
    ) {
        self.trainingCall = trainingCall
        self.recommendedSplit = recommendedSplit
    }

    static let placeholder = StartWorkoutDashboardSnapshot(
        trainingCall: .placeholder,
        recommendedSplit: nil
    )
}

struct StartWorkoutRecentSessionSnapshot: Sendable {
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

    static func placeholder(_ workout: HistoryWorkoutSnapshot) -> StartWorkoutRecentSessionSnapshot {
        StartWorkoutRecentSessionSnapshot(
            sessionId: workout.id,
            splitName: workout.splitName,
            durationText: durationText(for: workout),
            ratingText: ratingText(for: workout.rating),
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

    private static func durationText(for workout: HistoryWorkoutSnapshot) -> String {
        if let durationSeconds = workout.durationSeconds {
            return durationText(seconds: durationSeconds)
        }

        if let startedAt = workout.startedAt, let endedAt = workout.endedAt {
            return durationText(seconds: max(0, Int(endedAt.timeIntervalSince(startedAt))))
        }

        if let durationMinutes = workout.durationMinutes {
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

struct StartWorkoutSplitCardSnapshot: Identifiable, Sendable {
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
