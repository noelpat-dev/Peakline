import Observation
import SwiftData
import SwiftUI

struct RootTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var appTheme
    @Environment(\.scenePhase) private var scenePhase

    @ObservedObject private var workoutWarmStartInvalidation = WorkoutWarmStartInvalidation.shared
    @ObservedObject private var sleepDeepLinkRouter = SleepDeepLinkRouter.shared
    @ObservedObject private var readinessRefreshClock = ReadinessRefreshClock.shared

    @Query
    private var sleepSessions: [SleepSession]

    @Query
    private var workouts: [WorkoutSession]

    @Query
    private var previewSplits: [TrainingSplit]

    @Query
    private var previewExercises: [Exercise]

    @Query
    private var naps: [NapSession]

    @Query
    private var hydrationEntries: [HydrationEntry]

    @Query
    private var foodLogs: [FoodLogEntry]

    @Query
    private var checkIns: [DailyCoachCheckIn]

    @State private var tabSelectionState = RootTabSelectionState(selectedTab: .launchArgumentSelection)
    @State private var sleepSettings = SleepSettingsStore().load()
    @State private var sleepDestination: SleepNotificationDestination?
    @State private var tabSelectionStateBeforeSleepDeepLink: RootTab?
    @State private var isSettingsPresented = false
    @State private var didStartRootTabPrewarm = false
    @State private var didStartDeferredServices = false
    @State private var sleepNotificationRefreshTask: Task<Void, Never>?
    @State private var cachedSleepNotificationRefreshInputs: SleepNotificationRefreshInputs?
    @State private var lastSleepNotificationRefreshSignature: String?
    @State private var queuedSleepNotificationRefreshSignature: String?
    @State private var lastSleepNotificationRefreshAt: Date?
    @State private var fullAppBackupTask: Task<Void, Never>?
    @State private var lastPreviewWarmSourceSignature: String?
    @State private var lastOverallReadinessSourceSignature: String?
    @State private var warmSleepRefreshTask: Task<Void, Never>?
    // Keep this coordination flag outside SwiftUI's observation graph. A tab
    // selection must cancel/suppress warm work without invalidating the root
    // view and reevaluating every root query signature on the measured path.
    @State private var rootTabTransitionGate = RootTabTransitionGate()
    @State private var isWorkoutCompletionPresentationActive = false

    private let sleepSettingsStore = SleepSettingsStore()
    private let hydrationSettingsStore = HydrationSettingsStore()
    private let nutritionGoalService = NutritionGoalService()
    private let backupCoordinator = BackupCoordinator()
    private let startupSnapshot: StartupSnapshotBundle
    private let startupRevealComplete: Bool

    init(
        startupSnapshot: StartupSnapshotBundle,
        startupRevealComplete: Bool = true
    ) {
        self.startupSnapshot = startupSnapshot
        self.startupRevealComplete = startupRevealComplete
        _sleepSessions = Query(Self.sleepSessionsDescriptor)
        _workouts = Query(Self.workoutsDescriptor)
        _previewSplits = Query(Self.previewSplitsDescriptor)
        _previewExercises = Query(Self.previewExercisesDescriptor)
        _naps = Query(Self.napsDescriptor)
        _hydrationEntries = Query(Self.hydrationDescriptor)
        _foodLogs = Query(Self.foodDescriptor)
        _checkIns = Query(Self.checkInDescriptor)
    }

    private static var sleepSessionsDescriptor: FetchDescriptor<SleepSession> {
        var descriptor = FetchDescriptor<SleepSession>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        // Match SleepDashboardView's analytics signature window so a root
        // warm refresh produces the exact signature the dashboard compares
        // against on push.
        descriptor.fetchLimit = 90
        return descriptor
    }

    private static var workoutsDescriptor: FetchDescriptor<WorkoutSession> {
        var descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate<WorkoutSession> { $0.completed },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = 40
        return descriptor
    }

    private static var previewSplitsDescriptor: FetchDescriptor<TrainingSplit> {
        var descriptor = FetchDescriptor<TrainingSplit>(
            predicate: #Predicate<TrainingSplit> { $0.isActive },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 12
        return descriptor
    }

    private static var previewExercisesDescriptor: FetchDescriptor<Exercise> {
        var descriptor = FetchDescriptor<Exercise>(
            predicate: #Predicate<Exercise> { !$0.isArchived },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 180
        return descriptor
    }

    private static var napsDescriptor: FetchDescriptor<NapSession> {
        var descriptor = FetchDescriptor<NapSession>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        // Matches the sleep dashboard's nap window for warm-signature parity.
        descriptor.fetchLimit = 90
        return descriptor
    }

    private static var hydrationDescriptor: FetchDescriptor<HydrationEntry> {
        var descriptor = FetchDescriptor<HydrationEntry>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 120
        return descriptor
    }

    private static var foodDescriptor: FetchDescriptor<FoodLogEntry> {
        var descriptor = FetchDescriptor<FoodLogEntry>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 160
        return descriptor
    }

    private static var checkInDescriptor: FetchDescriptor<DailyCoachCheckIn> {
        var descriptor = FetchDescriptor<DailyCoachCheckIn>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 30
        return descriptor
    }

    var body: some View {
        RootTabContainer(
            startupSnapshot: startupSnapshot,
            selectionState: tabSelectionState,
            onTabSelectionStarted: rootTabSelectionStarted,
            onTabSelectionSettled: rootTabSelectionSettled,
            onSettingsRequested: { isSettingsPresented = true }
        )
        .tint(appTheme.colors.accent)
        .sheet(item: $sleepDestination) { destination in
            sleepDestinationView(destination)
                .onDisappear { restoreTabAfterSleepDeepLinkDismissal() }
        }
        .sheet(isPresented: $isSettingsPresented) {
            SettingsView(initialProfileSnapshot: startupSnapshot.settingsProfileSnapshot)
        }
        .onChange(of: sleepDeepLinkRouter.pendingRequest) { _, request in
            presentSleepDeepLinkIfReady(request)
        }
        .onReceive(NotificationCenter.default.publisher(for: .appWillResignActiveForCleanup)) { _ in
            PerformanceTracer.mark(.appLifecycle, "willResignActive cleanup observed")
        }
        .onReceive(NotificationCenter.default.publisher(for: .appDidEnterBackgroundForCleanup)) { _ in
            PerformanceTracer.mark(.appLifecycle, "didEnterBackground cleanup observed")
        }
        .onReceive(NotificationCenter.default.publisher(for: .workoutCompletionPresentationBegan)) { _ in
            isWorkoutCompletionPresentationActive = true
            rootTabTransitionGate.previewWarmRefreshTask?.cancel()
            rootTabTransitionGate.previewWarmRefreshTask = nil
            warmSleepRefreshTask?.cancel()
            warmSleepRefreshTask = nil
            rootTabTransitionGate.warmSleepRefreshPending = true
            PerformanceTracer.mark(.workoutLoggerFinish, "root_warm_refresh_suspended")
        }
        .onReceive(NotificationCenter.default.publisher(for: .workoutCompletionPresentationEnded)) { _ in
            isWorkoutCompletionPresentationActive = false
            PerformanceTracer.mark(.workoutLoggerFinish, "root_warm_refresh_resumed")
            rootTabTransitionGate.warmSleepRefreshPending = false
            scheduleWarmSleepAnalyticsRefresh(reason: "workout_completion_ended")
            schedulePreviewWarmRefresh(for: previewWarmSourceSignature)
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification).receive(on: RunLoop.main)) { _ in
            guard startupRevealComplete else { return }
            let refreshedSettings = sleepSettingsStore.load()
            if refreshedSettings != sleepSettings {
                sleepSettings = refreshedSettings
            }
            refreshCachedSleepNotificationInputs(reason: "user_defaults_changed")
            refreshOverallReadinessIfNeeded(reason: "user_defaults_changed")
            scheduleWarmSleepAnalyticsRefresh(reason: "user_defaults_changed")
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard startupRevealComplete else { return }
            PerformanceTracer.mark(.appLifecycle, "scenePhase changed \(String(describing: newPhase))")
            switch newPhase {
            case .background:
                PerformanceTracer.mark(.appLifecycle, "background before notification refresh")
                refreshSleepNotifications(source: .sceneBackground)
                refreshFullAppBackup(reason: "scene_background")
                PerformanceTracer.mark(.appLifecycle, "background after notification refresh request")
            case .inactive:
                PerformanceTracer.mark(.appLifecycle, "inactive cancel pending notification refresh")
                cancelSleepNotificationRefreshTask(reason: "scene_inactive")
            case .active:
                PerformanceTracer.mark(.appLifecycle, "active refresh notification input cache")
                refreshCachedSleepNotificationInputs(reason: "scene_active")
                refreshOverallReadinessIfNeeded(reason: "scene_active")
                scheduleWarmSleepAnalyticsRefresh(reason: "scene_active")
            @unknown default:
                PerformanceTracer.mark(.appLifecycle, "unknown scenePhase no-op")
            }
        }
        .onChange(of: sleepSettings) { _, newValue in
            guard startupRevealComplete else { return }
            PerformanceTracer.mark(.appLifecycle, "sleepSettings changed save begin")
            sleepSettingsStore.save(newValue)
            PerformanceTracer.mark(.appLifecycle, "sleepSettings changed save end")
            refreshCachedSleepNotificationInputs(reason: "sleep_settings_changed")
            refreshOverallReadinessIfNeeded(reason: "sleep_settings_changed")
            scheduleWarmSleepAnalyticsRefresh(reason: "sleep_settings_changed")
        }
        .onChange(of: sleepNotificationRefreshSourceSignature) { _, _ in
            guard startupRevealComplete else { return }
            refreshCachedSleepNotificationInputs(reason: "source_inputs_changed")
        }
        .onChange(of: previewWarmSourceSignature) { _, newSignature in
            guard startupRevealComplete else { return }
            WorkoutPreviewWarmStartStore.shared.invalidateStaleSnapshots(
                reason: "root_preview_source_changed"
            )
            schedulePreviewWarmRefresh(for: newSignature)
            refreshOverallReadinessIfNeeded(reason: "workout_source_changed")
            scheduleWarmSleepAnalyticsRefresh(reason: "workout_source_changed")
        }
        .onChange(of: coachModifierSourceSignature) { _, _ in
            guard startupRevealComplete else { return }
            WorkoutPreviewWarmStartStore.shared.invalidateStaleSnapshots(
                reason: "root_coach_inputs_changed"
            )
            // Modifier-only changes do not require history or saved-food caches
            // to be rebuilt. Preview generations are invalidated above because
            // their embedded intelligence can depend on these inputs; the Coach
            // route refreshes its own bounded live queries when next opened.
            CoachRouteSnapshotStore.shared.invalidate(source: "root_modifier_change")
            refreshOverallReadinessIfNeeded(reason: "coach_inputs_changed")
            scheduleWarmSleepAnalyticsRefresh(reason: "coach_inputs_changed")
        }
        .onChange(of: workoutWarmStartInvalidation.revision) { _, _ in
            guard startupRevealComplete else { return }
            refreshOverallReadinessIfNeeded(reason: "workout_revision_changed")
            scheduleWarmSleepAnalyticsRefresh(reason: "workout_revision_changed")
        }
        .onChange(of: readinessRefreshClock.token) { _, _ in
            guard startupRevealComplete else { return }
            refreshOverallReadinessIfNeeded(reason: "readiness_boundary_changed")
            scheduleWarmSleepAnalyticsRefresh(reason: "readiness_boundary_changed")
        }
        .onChange(of: startupRevealComplete) { _, isComplete in
            guard isComplete else { return }
            startDeferredServicesIfNeeded()
            refreshOverallReadinessIfNeeded(reason: "startup_reveal_complete")
            scheduleWarmSleepAnalyticsRefresh(reason: "startup_reveal_complete")
            presentSleepDeepLinkIfReady(sleepDeepLinkRouter.pendingRequest)
        }
        .onAppear {
            startRootTabPrewarmIfNeeded()
            startDeferredServicesIfNeeded()
            readinessRefreshClock.start()
            presentSleepDeepLinkIfReady(sleepDeepLinkRouter.pendingRequest)
        }
        .onDisappear {
            PerformanceTracer.mark(.appLifecycle, "root onDisappear no_task_cancel")
        }
    }

    private func presentSleepDeepLinkIfReady(_ request: SleepDeepLinkRouter.Request?) {
        guard startupRevealComplete, let request else { return }
        PerformanceTracer.mark(.appLifecycle, "sleep_deep_link present begin destination=\(request.destination.id)")
        sleepSettings = sleepSettingsStore.load()
        switch request.destination {
        case .sleepDashboard, .recoverySummary:
            prepareSleepDeepLinkWarmData()
        case .wakeConfirmation(let sessionID) where sleepSession(withID: sessionID) == nil:
            prepareSleepDeepLinkWarmData()
        case .sleepMode, .manualBackfill, .wakeConfirmation(_):
            break
        }
        if tabSelectionState.selectedTab != .today {
            tabSelectionStateBeforeSleepDeepLink = tabSelectionState.selectedTab
        }
        tabSelectionState.selectedTab = .today
        sleepDestination = request.destination
        sleepDeepLinkRouter.consume(request)
        PerformanceTracer.mark(.appLifecycle, "sleep_deep_link present end destination=\(request.destination.id)")
    }

    private func restoreTabAfterSleepDeepLinkDismissal() {
        guard let previousTab = tabSelectionStateBeforeSleepDeepLink else { return }
        tabSelectionStateBeforeSleepDeepLink = nil
        tabSelectionState.selectedTab = previousTab
    }

    private func startDeferredServicesIfNeeded() {
        guard startupRevealComplete, !didStartDeferredServices else { return }
        PerformanceTracer.mark(.appLifecycle, "root deferred services begin")
        didStartDeferredServices = true
        refreshFullAppBackup(reason: "startup_reveal_complete")
        sleepSettings = sleepSettingsStore.load()
        refreshCachedSleepNotificationInputs(reason: "startup_reveal_complete")
        refreshSleepNotifications(deferred: true, source: .launchDeferred)
        lastPreviewWarmSourceSignature = previewWarmSourceSignature
        PerformanceTracer.mark(.appLifecycle, "root deferred services end")
    }

    /// Root is inserted while the startup splash still owns hit testing. Warm the
    /// small scalar projections used by Today/Workout while the startup
    /// splash owns hit testing. The workout-generation token is intentional: it
    /// keeps this hidden pass from traversing every exercise/set relationship on
    /// the root interaction path.
    private func startRootTabPrewarmIfNeeded() {
        guard !didStartRootTabPrewarm, !startupRevealComplete else { return }
        didStartRootTabPrewarm = true

        PerformanceTracer.mark(.appLifecycle, "root tab prewarm begin")
        _ = SleepAnalyticsInputSignature(
            sessions: sleepSessions,
            naps: naps,
            workouts: workouts,
            settings: sleepSettings,
            sessionLimit: 60,
            workoutLimit: 40,
            workoutRevision: workoutWarmStartInvalidation.revision
        )
        PerformanceTracer.mark(.appLifecycle, "root tab prewarm end")
    }

    private var previewWarmSourceSignature: String {
        WorkoutWarmStartSourceSignature.make(
            revision: workoutWarmStartInvalidation.revision,
            splitSignatures: previewSplits.map { WorkoutWarmStartSourceSignature.split($0) },
            workoutSignatures: workouts.map { WorkoutWarmStartSourceSignature.workout($0) },
            exerciseSignatures: previewExercises.map { WorkoutWarmStartSourceSignature.exercise($0) }
        )
    }

    private var coachModifierSourceSignature: String {
        [
            sleepSessions.map {
                "\($0.id.uuidString):\($0.updatedAt.timeIntervalSince1970)"
            }.joined(separator: ","),
            naps.map {
                "\($0.id.uuidString):\($0.updatedAt.timeIntervalSince1970)"
            }.joined(separator: ","),
            hydrationEntries.map {
                "\($0.id.uuidString):\($0.updatedAt.timeIntervalSince1970)"
            }.joined(separator: ","),
            foodLogs.map {
                "\($0.id.uuidString):\($0.updatedAt.timeIntervalSince1970)"
            }.joined(separator: ","),
            checkIns.map {
                "\($0.id.uuidString):\($0.updatedAt.timeIntervalSince1970)"
            }.joined(separator: ",")
        ].joined(separator: "|")
    }

    private func refreshOverallReadinessIfNeeded(reason: String) {
        guard startupRevealComplete else { return }
        guard !rootTabTransitionGate.isActive else {
            rootTabTransitionGate.overallReadinessRefreshPending = true
            PerformanceTracer.mark(.appLifecycle, "readiness refresh deferred reason=\(reason)")
            return
        }

        // The reveal callback can load a newer UserDefaults value into State
        // immediately before this function runs. Read the store here as well
        // so the handoff cannot validate against the pre-splash value while
        // SwiftUI is still committing that State mutation.
        let currentSleepSettings = sleepSettingsStore.load()
        if currentSleepSettings != sleepSettings {
            sleepSettings = currentSleepSettings
        }
        let hydrationTargetML = hydrationSettingsStore.dailyTargetML()
        let nutritionGoal = nutritionGoalService.loadGoal()
        let inputSignature = OverallReadinessInputSignature.make(
            sleepSessions: sleepSessions,
            napSessions: naps,
            completedWorkouts: workouts,
            hydrationEntries: hydrationEntries,
            foodLogs: foodLogs,
            checkIns: checkIns,
            sleepSettings: currentSleepSettings,
            hydrationTargetML: hydrationTargetML,
            nutritionGoal: nutritionGoal,
            workoutRevision: workoutWarmStartInvalidation.revision,
            dayStart: readinessRefreshClock.token.dayStart,
            hydrationPhase: readinessRefreshClock.token.hydrationPhase
        )
        let signature = [
            inputSignature,
            "readinessGeneration:\(readinessRefreshClock.token.generation)"
        ].joined(separator: "|")
        guard signature != lastOverallReadinessSourceSignature else { return }

        // Startup already computed and published this readiness generation
        // before the root becomes interactive. Reuse that immutable value on
        // the first root refresh instead of traversing all live SwiftData
        // inputs again during the first cold tab transition.
        if reason == "startup_reveal_complete",
           lastOverallReadinessSourceSignature == nil,
           startupSnapshot.overallReadinessInputSignature == inputSignature {
            let startupReadiness = startupSnapshot.coachSnapshot.readiness
            if OverallReadinessSnapshotStore.shared.snapshot.sourceSignature != signature {
                OverallReadinessSnapshotStore.shared.update(
                    readiness: startupReadiness,
                    sourceSignature: signature
                )
            }
            lastOverallReadinessSourceSignature = signature
            PerformanceTracer.mark(
                .appLifecycle,
                "readiness reused startup snapshot reason=\(reason) provisional=\(startupReadiness.isProvisional)"
            )
            return
        }

        let readiness = CoachIntelligenceService().readiness(
            sleepSessions: sleepSessions,
            napSessions: naps,
            hydrationEntries: hydrationEntries,
            completedWorkouts: workouts,
            foodLogs: foodLogs,
            checkIns: checkIns,
            sleepSettings: currentSleepSettings,
            hydrationTargetML: hydrationTargetML,
            nutritionGoal: nutritionGoal
        )
        OverallReadinessSnapshotStore.shared.update(
            readiness: readiness,
            sourceSignature: signature
        )
        lastOverallReadinessSourceSignature = signature
        PerformanceTracer.mark(.appLifecycle, "readiness refreshed reason=\(reason) provisional=\(readiness.isProvisional)")
    }

    private func schedulePreviewWarmRefresh(for signature: String) {
        guard signature != lastPreviewWarmSourceSignature else { return }
        guard startupRevealComplete else {
            PerformanceTracer.mark(.workoutPreviewWarmCache, "root_refresh_deferred_until_reveal")
            return
        }
        guard !rootTabTransitionGate.isActive else {
            PerformanceTracer.mark(.workoutPreviewWarmCache, "root_refresh_deferred_for_tab_transition")
            return
        }
        guard !isWorkoutCompletionPresentationActive else {
            PerformanceTracer.mark(.workoutLoggerFinish, "root_warm_refresh_deferred")
            return
        }
        rootTabTransitionGate.previewWarmRefreshTask?.cancel()
        rootTabTransitionGate.previewWarmRefreshGeneration &+= 1
        let requestedGeneration = rootTabTransitionGate.previewWarmRefreshGeneration
        let requestedWorkoutRevision = workoutWarmStartInvalidation.revision
        // Root refreshes must stay value-only. The startup bundle is already a
        // coherent snapshot; never re-enter the broad SwiftData projection
        // builder from a delayed root task, because tab selection can contend
        // with that main-actor work. A changed source is rebuilt by the owning
        // route when it becomes visible.
        let warmPayload = RootWarmRefreshPayload(
            sourceSignature: startupSnapshot.sourceSignature,
            trainingCall: startupSnapshot.trainingCall,
            previewWarmSnapshots: startupSnapshot.previewWarmSnapshots,
            savedFoodCatalogSnapshot: startupSnapshot.savedFoodCatalogSnapshot
        )
        rootTabTransitionGate.previewWarmRefreshTask = Task { @MainActor in
            defer {
                if rootTabTransitionGate.previewWarmRefreshGeneration == requestedGeneration {
                    rootTabTransitionGate.previewWarmRefreshTask = nil
                }
            }
            await Task.yield()
            guard !Task.isCancelled,
                  startupRevealComplete,
                  !rootTabTransitionGate.isActive,
                  !isWorkoutCompletionPresentationActive,
                  requestedGeneration == rootTabTransitionGate.previewWarmRefreshGeneration,
                  requestedWorkoutRevision == workoutWarmStartInvalidation.revision,
                  signature == previewWarmSourceSignature else { return }

            // Do not publish a startup generation after any source change. This
            // guard makes the bounded fallback stale-safe; the route's live
            // preparation remains responsible for producing a new generation.
            guard warmPayload.sourceSignature == signature else {
                PerformanceTracer.mark(.workoutPreviewWarmCache, "root_refresh_skip_stale_value_payload")
                lastPreviewWarmSourceSignature = signature
                return
            }

            guard !Task.isCancelled else { return }
            WorkoutDashboardWarmStartStore.shared.update(
                trainingCall: warmPayload.trainingCall,
                sourceSignature: warmPayload.sourceSignature
            )
            WorkoutPreviewWarmStartStore.shared.replaceActiveSnapshots(
                warmPayload.previewWarmSnapshots
            )
            SavedFoodWarmStartStore.shared.update(warmPayload.savedFoodCatalogSnapshot)
            lastPreviewWarmSourceSignature = signature
        }
    }

    /// Keeps the sleep analytics/readiness warm caches and the Progress
    /// summary seed aligned with live inputs while the app runs. Route
    /// destinations read these pre-computed values on push, so their first
    /// frame is fully populated instead of stale or loading. Coalesced and
    /// gated so it never contends with a tab transition or completion flow.
    private func scheduleWarmSleepAnalyticsRefresh(reason: String) {
        guard startupRevealComplete else {
            rootTabTransitionGate.warmSleepRefreshPending = true
            PerformanceTracer.mark(.appLifecycle, "warm_sleep_refresh deferred_until_reveal reason=\(reason)")
            return
        }
        if startupSnapshot.sourceSignature == previewWarmSourceSignature,
           SleepAnalyticsSnapshotStore.shared.cachedAnalytics(
               matching: deepLinkSleepAnalyticsSignature
           ) != nil,
           ProgressWarmStartStore.shared.payload(
               matching: previewWarmSourceSignature,
               workoutRevision: workoutWarmStartInvalidation.revision
           ) != nil,
           OverallReadinessSnapshotStore.shared.snapshot.sourceSignature
                == deepLinkOverallReadinessSourceSignature,
           NutritionWarmStartStore.shared.dashboard?.sourceSignature
                == warmNutritionSourceSignature,
           NutritionWarmStartStore.shared.insights?.sourceSignature
                == warmNutritionSourceSignature {
            // Startup has already published this exact bounded generation.
            // Rebuilding Sleep, Nutrition, and Progress immediately after the
            // reveal duplicates relationship work and contends with the first
            // user-selected root tab.
            rootTabTransitionGate.warmSleepRefreshPending = false
            PerformanceTracer.mark(.appLifecycle, "warm_routes reused startup generation")
            return
        }
        guard !isWorkoutCompletionPresentationActive else {
            rootTabTransitionGate.warmSleepRefreshPending = true
            PerformanceTracer.mark(.workoutLoggerFinish, "warm_sleep_refresh deferred_for_completion reason=\(reason)")
            return
        }
        guard !rootTabTransitionGate.isActive else {
            rootTabTransitionGate.warmSleepRefreshPending = true
            PerformanceTracer.mark(.appLifecycle, "warm_sleep_refresh deferred_for_tab_transition reason=\(reason)")
            return
        }
        warmSleepRefreshTask?.cancel()
        rootTabTransitionGate.warmSleepRefreshPending = false
        rootTabTransitionGate.warmSleepRefreshGeneration &+= 1
        let requestedGeneration = rootTabTransitionGate.warmSleepRefreshGeneration
        let requestedRevision = workoutWarmStartInvalidation.revision
        warmSleepRefreshTask = Task { @MainActor in
            defer {
                if rootTabTransitionGate.warmSleepRefreshGeneration == requestedGeneration {
                    warmSleepRefreshTask = nil
                }
            }

            // Let the current SwiftUI/model-update turn settle, then perform
            // the bounded value work immediately. A source change or tab
            // transition can cancel this generation without a fixed delay.
            await Task.yield()
            guard !Task.isCancelled,
                  startupRevealComplete,
                  !isWorkoutCompletionPresentationActive,
                  requestedGeneration == rootTabTransitionGate.warmSleepRefreshGeneration,
                  requestedRevision == workoutWarmStartInvalidation.revision else { return }

            // A tab transition can begin during the debounce window. Yield the
            // turn to it and replay after the native switch settles instead of
            // contending with its measured frame.
            guard !rootTabTransitionGate.isActive else {
                rootTabTransitionGate.warmSleepRefreshPending = true
                return
            }

            guard refreshWarmSleepAnalytics(reason: reason) else { return }
            guard !Task.isCancelled,
                  !rootTabTransitionGate.isActive,
                  !isWorkoutCompletionPresentationActive,
                  requestedGeneration == rootTabTransitionGate.warmSleepRefreshGeneration,
                  requestedRevision == workoutWarmStartInvalidation.revision else {
                rootTabTransitionGate.warmSleepRefreshPending = true
                return
            }
            await refreshWarmProgressSummaries(
                reason: reason,
                requestedRevision: requestedRevision,
                requestedGeneration: requestedGeneration
            )
        }
    }

    @discardableResult
    private func refreshWarmSleepAnalytics(reason: String) -> Bool {
        // The nap order matches SleepDashboardView's own query (startDate
        // descending) so the cached signature equals what the dashboard
        // recomputes on push and the warm snapshot is accepted without a
        // visible correction pass.
        let requestedRevision = workoutWarmStartInvalidation.revision
        let orderedNaps = naps.sorted { $0.startDate > $1.startDate }
        PerformanceTracer.mark(.appLifecycle, "warm_sleep_refresh begin reason=\(reason)")
        _ = SleepAnalyticsSnapshotStore.shared.snapshot(
            sessions: sleepSessions,
            naps: orderedNaps,
            workouts: workouts,
            settings: sleepSettingsStore.load(),
            workoutRevision: workoutWarmStartInvalidation.revision
        )
        _ = SleepWorkoutReadinessSnapshotStore.shared.snapshot(
            sessions: sleepSessions,
            naps: Array(orderedNaps.prefix(30)),
            workouts: Array(workouts.prefix(12)),
            settings: sleepSettingsStore.load(),
            sessionLimit: 45,
            workoutLimit: 12,
            workoutRevision: workoutWarmStartInvalidation.revision
        )
        refreshWarmNutritionSnapshots()
        PerformanceTracer.mark(.appLifecycle, "warm_sleep_refresh end reason=\(reason)")
        return requestedRevision == workoutWarmStartInvalidation.revision
    }

    private func refreshWarmNutritionSnapshots() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let todayEntries = foodLogs
            .filter { calendar.isDate($0.loggedAt, inSameDayAs: today) }
            .map(NutritionFoodLogSnapshot.init)
        let catalog = SavedFoodWarmStartStore.shared.catalog ?? .empty
        let recentFoods = foodLogs.prefix(160).reduce(into: [SavedFoodSnapshot]()) { result, entry in
            guard result.count < 3,
                  !result.contains(where: { $0.id == entry.foodItemId }),
                  let food = catalog.foods.first(where: { $0.id == entry.foodItemId }) else { return }
            result.append(food)
        }
        let goal = nutritionGoalService.loadGoal()
        let sourceSignature = warmNutritionSourceSignature
        let summaryService = NutritionSummaryService()
        let trendService = NutritionTrendService()
        let contextService = TrainingNutritionContextService()
        let insightService = NutritionInsightService()
        let todaySummary = summaryService.dailySummary(for: .now, foodLogs: foodLogs, workouts: workouts)
        let weekly = trendService.weeklySummary(
            dailySummaries: summaryService.dailySummaries(endingOn: .now, days: 7, foodLogs: foodLogs, workouts: workouts),
            goal: goal
        )
        let context = contextService.context(for: .now, foodLogs: foodLogs, workouts: workouts)
        NutritionWarmStartStore.shared.update(
            dashboard: NutritionDashboardWarmStartPayload(
                sourceSignature: sourceSignature,
                selectedDate: today,
                dayEntries: todayEntries,
                totals: NutritionMacroSnapshot(
                    calories: todayEntries.reduce(0) { $0 + $1.caloriesSnapshot },
                    protein: todayEntries.reduce(0) { $0 + $1.proteinSnapshot },
                    carbs: todayEntries.reduce(0) { $0 + $1.carbsSnapshot },
                    fat: todayEntries.reduce(0) { $0 + $1.fatSnapshot },
                    sugar: nil,
                    fibre: nil,
                    salt: nil
                ),
                readiness: OverallReadinessSnapshotStore.shared.latestReadiness ?? CoachIntelligenceService.emptySnapshot().readiness,
                recentlyLoggedFoods: recentFoods.isEmpty ? Array(catalog.foods.prefix(3)) : recentFoods,
                mealEntries: Dictionary(grouping: todayEntries, by: \.mealType),
                isTrainingDay: workouts.contains { calendar.isDate($0.date, inSameDayAs: today) },
                shouldShowHealthKitStatus: HealthKitPreferenceStore().load().isHealthKitEnabled,
                healthKitSyncRecordsByEntryId: [:]
            )
        )
        NutritionWarmStartStore.shared.update(
            insights: NutritionInsightsWarmStartPayload(
                sourceSignature: sourceSignature,
                goal: goal,
                todaySummary: todaySummary,
                weeklySummary: weekly,
                trainingContext: context,
                insights: insightService.insights(today: todaySummary, weekly: weekly, goal: goal, context: context)
            )
        )
    }

    private var warmNutritionSourceSignature: String {
        let goal = nutritionGoalService.loadGoal()
        return [
            "revision:\(workoutWarmStartInvalidation.revision)",
            foodLogs.prefix(160).map {
                "\($0.id.uuidString):\($0.updatedAt.timeIntervalSince1970)"
            }.joined(separator: ","),
            goal.updatedAt.timeIntervalSince1970.description
        ].joined(separator: "|")
    }

    private func refreshWarmProgressSummaries(
        reason: String,
        requestedRevision: Int,
        requestedGeneration: Int
    ) async {
        guard requestedRevision == workoutWarmStartInvalidation.revision,
              requestedGeneration == rootTabTransitionGate.warmSleepRefreshGeneration,
              !rootTabTransitionGate.isActive,
              !isWorkoutCompletionPresentationActive else {
            rootTabTransitionGate.warmSleepRefreshPending = true
            return
        }

        let recentSessions = Array(workouts.prefix(40))
        let activeSplitNames = TrainingRotationService()
            .orderedActiveSplits(previewSplits)
            .map(\.name)
        let sourceSignature = previewWarmSourceSignature
        let snapshots: [WorkoutAnalyticsSession]
        do {
            snapshots = try WorkoutAnalyticsSnapshotBuilder.snapshots(from: recentSessions, in: modelContext)
        } catch {
            PerformanceTracer.mark(.appLifecycle, "warm_progress_refresh failed reason=\(reason) error=\(error.localizedDescription)")
            return
        }
        let result = await Task.detached(priority: .utility) {
            let analytics = TrainingAnalyticsService()
            let records = analytics.prTimeline(from: snapshots)
            return (
                analytics.weeklySummary(from: snapshots, prRecords: records),
                analytics.splitConsistency(from: snapshots, activeSplitNames: activeSplitNames)
            )
        }.value
        guard !Task.isCancelled,
              requestedRevision == workoutWarmStartInvalidation.revision,
              requestedGeneration == rootTabTransitionGate.warmSleepRefreshGeneration,
              sourceSignature == previewWarmSourceSignature,
              !rootTabTransitionGate.isActive,
              !isWorkoutCompletionPresentationActive else {
            rootTabTransitionGate.warmSleepRefreshPending = true
            return
        }
        ProgressWarmStartStore.shared.update(
            sourceSignature: sourceSignature,
            workoutRevision: requestedRevision,
            weeklySummary: result.0,
            splitConsistency: result.1,
            exerciseRows: Array(previewExercises.map(ProgressExerciseRowSnapshot.init))
        )
        PerformanceTracer.mark(.appLifecycle, "warm_progress_refresh end reason=\(reason)")
    }

    private func rootTabSelectionStarted() {
        rootTabTransitionGate.isActive = true
        rootTabTransitionGate.previewWarmRefreshTask?.cancel()
        rootTabTransitionGate.previewWarmRefreshTask = nil
        if warmSleepRefreshTask != nil {
            warmSleepRefreshTask?.cancel()
            warmSleepRefreshTask = nil
            rootTabTransitionGate.warmSleepRefreshPending = true
        }
        PerformanceTracer.mark(.workoutPreviewWarmCache, "root_refresh_cancelled_for_tab_transition")
    }

    private func rootTabSelectionSettled() {
        rootTabTransitionGate.isActive = false
        if rootTabTransitionGate.overallReadinessRefreshPending {
            rootTabTransitionGate.overallReadinessRefreshPending = false
            refreshOverallReadinessIfNeeded(reason: "tab_transition_settled")
        }
        if rootTabTransitionGate.warmSleepRefreshPending {
            rootTabTransitionGate.warmSleepRefreshPending = false
            scheduleWarmSleepAnalyticsRefresh(reason: "tab_transition_settled")
        }
        schedulePreviewWarmRefresh(for: previewWarmSourceSignature)
    }

    private var deepLinkSleepAnalyticsSignature: SleepAnalyticsInputSignature {
        SleepAnalyticsInputSignature(
            sessions: sleepSessions,
            naps: naps.sorted { $0.startDate > $1.startDate },
            workouts: workouts,
            settings: sleepSettingsStore.load(),
            workoutRevision: workoutWarmStartInvalidation.revision
        )
    }

    private var deepLinkOverallReadinessSourceSignature: String {
        let currentSleepSettings = sleepSettingsStore.load()
        let inputSignature = OverallReadinessInputSignature.make(
            sleepSessions: sleepSessions,
            napSessions: naps,
            completedWorkouts: workouts,
            hydrationEntries: hydrationEntries,
            foodLogs: foodLogs,
            checkIns: checkIns,
            sleepSettings: currentSleepSettings,
            hydrationTargetML: hydrationSettingsStore.dailyTargetML(),
            nutritionGoal: nutritionGoalService.loadGoal(),
            workoutRevision: workoutWarmStartInvalidation.revision,
            dayStart: readinessRefreshClock.token.dayStart,
            hydrationPhase: readinessRefreshClock.token.hydrationPhase
        )
        return "\(inputSignature)|readinessGeneration:\(readinessRefreshClock.token.generation)"
    }

    private func prepareSleepDeepLinkWarmData() {
        warmSleepRefreshTask?.cancel()
        warmSleepRefreshTask = nil
        refreshOverallReadinessIfNeeded(reason: "sleep_deep_link")

        let signature = deepLinkSleepAnalyticsSignature
        guard SleepAnalyticsSnapshotStore.shared.cachedAnalytics(matching: signature) == nil else {
            return
        }

        _ = refreshWarmSleepAnalytics(reason: "sleep_deep_link")
    }

    private func sleepAnalyticsSeedForDeepLink(fallback: SleepAnalyticsSnapshot?) -> SleepAnalyticsSnapshot? {
        SleepAnalyticsSnapshotStore.shared.cachedAnalytics(matching: deepLinkSleepAnalyticsSignature)?.snapshot
            ?? fallback
    }

    private func overallReadinessSeedForDeepLink(fallback: ReadinessScore?) -> ReadinessScore {
        guard OverallReadinessSnapshotStore.shared.snapshot.sourceSignature == deepLinkOverallReadinessSourceSignature else {
            return fallback ?? CoachIntelligenceService.emptySnapshot().readiness
        }
        return OverallReadinessSnapshotStore.shared.latestReadiness
            ?? fallback
            ?? CoachIntelligenceService.emptySnapshot().readiness
    }

    @ViewBuilder
    private func sleepDestinationView(_ destination: SleepNotificationDestination) -> some View {
        switch destination {
        case .sleepMode:
            SleepModeView(settings: $sleepSettings)
        case .wakeConfirmation(let sessionID):
            if let session = sleepSession(withID: sessionID) {
                SleepMorningConfirmationView(session: session)
            } else {
                NavigationStack {
                    SleepDashboardView(
                        initialSnapshot: sleepAnalyticsSeedForDeepLink(
                            fallback: startupSnapshot.sleepAnalyticsSnapshot
                        ),
                        initialReadinessScore: overallReadinessSeedForDeepLink(
                            fallback: startupSnapshot.coachSnapshot.readiness
                        )
                    )
                }
            }
        case .manualBackfill:
            SleepSessionEditorView(mode: .manual)
        case .sleepDashboard, .recoverySummary:
            NavigationStack {
                SleepDashboardView(
                    initialSnapshot: sleepAnalyticsSeedForDeepLink(
                        fallback: startupSnapshot.sleepAnalyticsSnapshot
                    ),
                    initialReadinessScore: overallReadinessSeedForDeepLink(
                        fallback: startupSnapshot.coachSnapshot.readiness
                    )
                )
            }
        }
    }

    private func sleepSession(withID sessionID: UUID) -> SleepSession? {
        var descriptor = FetchDescriptor<SleepSession>(
            predicate: #Predicate<SleepSession> { $0.id == sessionID }
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    private func refreshFullAppBackup(reason: String) {
#if DEBUG
        guard !ProcessInfo.processInfo.arguments.contains("-UITestInMemoryStore")
                && !ProcessInfo.processInfo.arguments.contains("-SkipAccountGate") else { return }
#endif

        fullAppBackupTask?.cancel()
        fullAppBackupTask = Task { @MainActor in
            let outcome = await backupCoordinator.saveLatestBackup(in: modelContext)
            switch outcome {
            case .saved(let metadata):
                PerformanceTracer.mark(.appLifecycle, "full_app_backup saved reason=\(reason) records=\(metadata.counts.totalRecordCount)")
            case .keptExistingBackup(let metadata):
                PerformanceTracer.mark(.appLifecycle, "full_app_backup kept_existing reason=\(reason) records=\(metadata.counts.totalRecordCount)")
            case .passphraseRequired:
                PerformanceTracer.mark(.appLifecycle, "full_app_backup passphrase_required reason=\(reason)")
            case .unavailable(let message):
                PerformanceTracer.mark(.appLifecycle, "full_app_backup unavailable reason=\(reason) \(message)")
            case .failed(let message):
                PerformanceTracer.mark(.appLifecycle, "full_app_backup failed reason=\(reason) \(message)")
            }
        }
    }

    private func refreshSleepNotifications(
        deferred: Bool = false,
        source: SleepNotificationRefreshSource = .manual
    ) {
        PerformanceTracer.mark(.appLifecycle, "notification refresh request source=\(source.rawValue) deferred=\(deferred)")
        PerformanceTracer.trace(.rootNotificationRefresh) {
            let inputs: SleepNotificationRefreshInputs
            if source == .sceneBackground {
                guard let cachedSleepNotificationRefreshInputs else {
                    PerformanceTracer.mark(.rootNotificationRefresh, "skip missing_cached_inputs")
                    return
                }
                inputs = cachedSleepNotificationRefreshInputs
                PerformanceTracer.mark(.appLifecycle, "notification refresh source=\(source.rawValue) using_cached_inputs")
            } else {
                inputs = makeSleepNotificationRefreshInputs()
                cachedSleepNotificationRefreshInputs = inputs
            }

            if inputs.signature == lastSleepNotificationRefreshSignature {
                PerformanceTracer.mark(.rootNotificationRefresh, "skip unchanged_inputs")
                return
            }

            if inputs.signature == queuedSleepNotificationRefreshSignature, source != .sceneBackground {
                PerformanceTracer.mark(.rootNotificationRefresh, "skip already_queued")
                return
            }
            if inputs.signature == queuedSleepNotificationRefreshSignature, source == .sceneBackground {
                PerformanceTracer.mark(.appLifecycle, "background replacing already_queued notification task")
            }

            if !deferred,
               let lastSleepNotificationRefreshAt,
               Date.now.timeIntervalSince(lastSleepNotificationRefreshAt) < 30 {
                PerformanceTracer.mark(.rootNotificationRefresh, "skip debounced")
                return
            }

            cancelSleepNotificationRefreshTask(reason: "replacement_\(source.rawValue)")
            queuedSleepNotificationRefreshSignature = inputs.signature

            let job = SleepNotificationRefreshJob(
                source: source,
                deferred: deferred,
                inputs: inputs
            )

            sleepNotificationRefreshTask = Task(priority: .utility) {
                await job.run()
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    applySleepNotificationRefreshCompletion(signature: inputs.signature)
                }
            }
        }
    }

    private var sleepNotificationRefreshSourceSignature: String {
        Self.sleepNotificationRefreshSignature(
            settings: sleepSettings,
            sessions: SleepNotificationScheduler.sessionSnapshots(from: sleepSessions),
            workouts: SleepNotificationScheduler.workoutSnapshots(from: workouts)
        )
    }

    private func refreshCachedSleepNotificationInputs(reason: String) {
        let previousSignature = cachedSleepNotificationRefreshInputs?.signature
        let inputs = makeSleepNotificationRefreshInputs()
        cachedSleepNotificationRefreshInputs = inputs
        if previousSignature == inputs.signature {
            PerformanceTracer.mark(.appLifecycle, "notification input cache refreshed reason=\(reason) unchanged")
        } else {
            PerformanceTracer.mark(.appLifecycle, "notification input cache refreshed reason=\(reason) changed")
        }
    }

    private func makeSleepNotificationRefreshInputs() -> SleepNotificationRefreshInputs {
        let sessionSnapshots = PerformanceTracer.trace(.rootNotificationSnapshot) {
            SleepNotificationScheduler.sessionSnapshots(from: sleepSessions)
        }
        let workoutSnapshots = PerformanceTracer.trace(.rootNotificationSnapshot) {
            SleepNotificationScheduler.workoutSnapshots(from: workouts)
        }
        let settings = PerformanceTracer.trace(.rootNotificationSettingsLoad) {
            sleepSettingsStore.load()
        }
        let signature = PerformanceTracer.trace(.rootNotificationInputSignature) {
            Self.sleepNotificationRefreshSignature(
                settings: settings,
                sessions: sessionSnapshots,
                workouts: workoutSnapshots
            )
        }

        return SleepNotificationRefreshInputs(
            settings: settings,
            sessions: sessionSnapshots,
            workouts: workoutSnapshots,
            signature: signature
        )
    }

    private func applySleepNotificationRefreshCompletion(signature: String) {
        PerformanceTracer.mark(.unsafeBreadcrumb, "root.notification.deferred_task before_main_state")
        PerformanceTracer.trace(.rootNotificationMainState) {
            lastSleepNotificationRefreshSignature = signature
            queuedSleepNotificationRefreshSignature = nil
            lastSleepNotificationRefreshAt = .now
        }
        PerformanceTracer.mark(.unsafeBreadcrumb, "root.notification.deferred_task end")
    }

    private func cancelSleepNotificationRefreshTask(reason: String) {
        guard sleepNotificationRefreshTask != nil else { return }
        sleepNotificationRefreshTask?.cancel()
        sleepNotificationRefreshTask = nil
        queuedSleepNotificationRefreshSignature = nil
        PerformanceTracer.mark(.appLifecycle, "notification refresh task cancelled reason=\(reason)")
    }

    private static func sleepNotificationRefreshSignature(
        settings: SleepSettings,
        sessions: [SleepNotificationSessionSnapshot],
        workouts: [SleepNotificationWorkoutSnapshot],
        calendar: Calendar = .current
    ) -> String {
        let preferences = settings.notificationPreferences
        let dayKey = calendar.startOfDay(for: .now).timeIntervalSince1970
        let sessionSignature = sessions.map {
            "\($0.id.uuidString):\($0.status.rawValue):\($0.nightDate.timeIntervalSince1970):\($0.confirmedSleepStartAt.timeIntervalSince1970):\($0.sleepModeStartedAt?.timeIntervalSince1970 ?? 0):\($0.morningReminderSentAt?.timeIntervalSince1970 ?? 0):\($0.unfinishedReminderSentAt?.timeIntervalSince1970 ?? 0)"
        }.joined(separator: ",")
        let workoutSignature = workouts.map { "\($0.date.timeIntervalSince1970)" }.joined(separator: ",")
        let preferenceSignature = [
            "\(preferences.isEnabled)",
            "\(preferences.bedtimeReminderEnabled)",
            "\(preferences.bedtimeReminderTime.hour ?? -1):\(preferences.bedtimeReminderTime.minute ?? -1)",
            "\(preferences.windDownReminderEnabled)",
            "\(preferences.windDownOffsetMinutes)",
            "\(preferences.morningConfirmationEnabled)",
            "\(preferences.morningConfirmationTime.hour ?? -1):\(preferences.morningConfirmationTime.minute ?? -1)",
            "\(preferences.missedSleepReminderEnabled)",
            "\(preferences.trainingAwareRemindersEnabled)",
            "\(preferences.recoveryCoachingNotificationsEnabled)",
            preferences.quietWeekdays.map(String.init).joined(separator: ",")
        ].joined(separator: ":")

        return [String(dayKey), preferenceSignature, sessionSignature, workoutSignature].joined(separator: "|")
    }
}

/// A deliberately non-observable coordination object. Mutating the gate must
/// not invalidate RootTabView while a native tab transition is being measured.
private final class RootTabTransitionGate {
    var isActive = false
    var previewWarmRefreshTask: Task<Void, Never>?
    var previewWarmRefreshGeneration = 0
    var warmSleepRefreshGeneration = 0
    var overallReadinessRefreshPending = false
    var warmSleepRefreshPending = false
}

private enum SleepNotificationRefreshSource: String, Sendable {
    case launchDeferred
    case sceneBackground
    case manual
}

private struct SleepNotificationRefreshInputs: Sendable {
    let settings: SleepSettings
    let sessions: [SleepNotificationSessionSnapshot]
    let workouts: [SleepNotificationWorkoutSnapshot]
    let signature: String
}

private struct RootWarmRefreshPayload: Sendable {
    let sourceSignature: String
    let trainingCall: TrainingCallSnapshot
    let previewWarmSnapshots: [WorkoutPreviewWarmSnapshot]
    let savedFoodCatalogSnapshot: SavedFoodCatalogSnapshot
}

private struct SleepNotificationRefreshJob: Sendable {
    let source: SleepNotificationRefreshSource
    let deferred: Bool
    let inputs: SleepNotificationRefreshInputs

    func run() async {
        PerformanceTracer.mark(.unsafeBreadcrumb, "root.notification.deferred_task begin source=\(source.rawValue) deferred=\(deferred)")
        if deferred {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
        }

        PerformanceTracer.mark(.unsafeBreadcrumb, "root.notification.deferred_task before_refresh")
        await PerformanceTracer.traceAsync(.rootNotificationDeferredWork) {
            await SleepNotificationScheduler().refreshAllSleepNotifications(
                settings: inputs.settings,
                sessions: inputs.sessions,
                workouts: inputs.workouts
            )
        }
    }
}

private enum RootTab: String, Hashable {
    case today
    case workout
    case splits
    case history

    static var launchArgumentSelection: RootTab {
#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-UITestInMemoryStore"),
           let flagIndex = arguments.firstIndex(of: "-UITestInitialTab"),
           arguments.indices.contains(flagIndex + 1) {
            return RootTab(rawValue: arguments[flagIndex + 1]) ?? .today
        }
#endif

        return .today
    }
}

@MainActor
@Observable
private final class RootTabSelectionState {
    var selectedTab: RootTab

    init(selectedTab: RootTab = .today) {
        self.selectedTab = selectedTab
    }
}

private struct RootTabContainer: View {
    let startupSnapshot: StartupSnapshotBundle
    @Bindable var selectionState: RootTabSelectionState
    let onTabSelectionStarted: () -> Void
    let onTabSelectionSettled: () -> Void
    let onSettingsRequested: () -> Void

    // Timing state must not participate in SwiftUI observation. Updating two
    // `@State` scalars here rebuilt every tab value on the selection-critical
    // turn, re-running their query initializers before the destination frame.
    @State private var transitionMeasurement = RootTabTransitionMeasurement()

    var body: some View {
        TabView(selection: selectedTabBinding) {
            RootTabContentHost(key: "today|\(startupSnapshot.sourceSignature)") {
                TodayView(
                    startupSnapshot: startupSnapshot,
                    openHistory: { selectedTabBinding.wrappedValue = .history },
                    openSettings: onSettingsRequested
                )
            }
                .equatable()
                .onAppear { scheduleStableFrame(for: .today) }
                .tabItem {
                    Label("Today", systemImage: "house")
                        .environment(\.symbolVariants, .none)
                }
                .tag(RootTab.today)
                .accessibilityIdentifier("tab-today")

            RootTabContentHost(key: "workout|\(startupSnapshot.sourceSignature)") {
                DeferredWorkoutTabHost(
                    initialReadinessSnapshot: startupSnapshot.workoutSleepReadinessSnapshot,
                    initialReadinessSignature: startupSnapshot.sleepReadinessInputSignature,
                    initialFirstFrameSnapshot: startupSnapshot.workoutFirstFrameSnapshot,
                    initialOverallReadinessIsProvisional: startupSnapshot.coachSnapshot.readiness.isProvisional
                )
            }
                .equatable()
                .onAppear { scheduleStableFrame(for: .workout) }
                .tabItem {
                    Label("Workout", systemImage: "dumbbell")
                        .environment(\.symbolVariants, .none)
                }
                .tag(RootTab.workout)
                .accessibilityIdentifier("tab-workout")

            RootTabContentHost(key: "splits|\(startupSnapshot.sourceSignature)") {
                DeferredSplitsTabHost(
                    preparedRows: startupSnapshot.workoutFirstFrameSnapshot.splitCards
                )
            }
                .equatable()
                .onAppear { scheduleStableFrame(for: .splits) }
                .tabItem {
                    Label("Splits", systemImage: "list.bullet.rectangle")
                        .environment(\.symbolVariants, .none)
                }
                .tag(RootTab.splits)
                .accessibilityIdentifier("tab-splits")

            RootTabContentHost(key: "history|\(startupSnapshot.sourceSignature)") {
                DeferredHistoryTabHost(startupSnapshot: startupSnapshot.historySnapshot)
            }
                .equatable()
                .onAppear { scheduleStableFrame(for: .history) }
                .tabItem {
                    Label("History", systemImage: "clock.arrow.circlepath")
                        .environment(\.symbolVariants, .none)
                }
                .tag(RootTab.history)
                .accessibilityIdentifier("tab-history")

        }
    }

    private var selectedTabBinding: Binding<RootTab> {
        Binding {
            selectionState.selectedTab
        } set: { newTab in
            guard selectionState.selectedTab != newTab else { return }
            transitionMeasurement.pendingTab = newTab
            transitionMeasurement.startedAt = .now
            onTabSelectionStarted()
            PerformanceTracer.mark(.motionTabSelect, "requested tab=\(newTab.rawValue)")
            PerformanceTracer.trace(.motionTabSelect) {
                AppMotion.withoutAnimation {
                    selectionState.selectedTab = newTab
                }
            }
#if !targetEnvironment(simulator)
            Task { @MainActor in
                await Task.yield()
                AppHaptics.selection()
            }
#endif
        }
    }

    private func markStableFrame(for tab: RootTab) {
        guard transitionMeasurement.pendingTab == tab,
              let pendingSelectionStartedAt = transitionMeasurement.startedAt else { return }
        let elapsedMilliseconds = max(
            0,
            Int(Date.now.timeIntervalSince(pendingSelectionStartedAt) * 1_000)
        )
        PerformanceTracer.mark(
            .motionTabSelect,
            "stable_frame tab=\(tab.rawValue) elapsed_ms=\(elapsedMilliseconds)"
        )
        onTabSelectionSettled()
        transitionMeasurement.pendingTab = nil
        transitionMeasurement.startedAt = nil
    }

    private func scheduleStableFrame(for tab: RootTab) {
        // `onAppear` can run before the replacement hierarchy is committed.
        // Queue exactly one main-run-loop turn; unlike a yielding unstructured
        // task, this cannot sit behind unrelated utility warm jobs.
        DispatchQueue.main.async {
            markStableFrame(for: tab)
        }
    }
}

private struct RootTabContentHost<Content: View>: View, Equatable {
    let key: String
    let content: () -> Content

    init(key: String, @ViewBuilder content: @escaping () -> Content) {
        self.key = key
        self.content = content
    }

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.key == rhs.key
    }

    var body: some View {
        content()
    }
}

@MainActor
private final class RootTabTransitionMeasurement {
    var pendingTab: RootTab?
    var startedAt: Date?
}

private struct DeferredWorkoutTabHost: View {
    let initialReadinessSnapshot: WorkoutSleepReadinessSnapshot
    let initialReadinessSignature: SleepAnalyticsInputSignature
    let initialFirstFrameSnapshot: WorkoutStartFirstFrameSnapshot
    let initialOverallReadinessIsProvisional: Bool

    @State private var isLiveMounted = false
    @State private var isVisible = false

    var body: some View {
        Group {
            if isLiveMounted {
                StartWorkoutView(
                    initialReadinessSnapshot: initialReadinessSnapshot,
                    initialReadinessSignature: initialReadinessSignature,
                    initialFirstFrameSnapshot: initialFirstFrameSnapshot,
                    initialOverallReadinessIsProvisional: initialOverallReadinessIsProvisional
                )
            } else {
                NavigationStack {
                    FitnessScreen {
                        FitnessCard(style: .hero) {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Recommended workout")
                                    .font(AppTypography.eyebrow)
                                Text(
                                    initialFirstFrameSnapshot.dashboard.recommendedSplit?.name
                                        ?? initialFirstFrameSnapshot.dashboard.trainingCall.title
                                )
                                .font(AppTypography.cardTitle)
                                Text(initialFirstFrameSnapshot.dashboard.trainingCall.reason)
                                    .font(AppTypography.body)
                                    .foregroundStyle(.secondary)

                                Button("Open Preview") {
                                    isLiveMounted = true
                                }
                                .buttonStyle(.borderedProminent)
                                .accessibilityIdentifier("workout-recommended-preview")
                            }
                        }
                    }
                    .navigationTitle("Workout")
                    .navigationBarTitleDisplayMode(.inline)
                    .accessibilityIdentifier("workout-screen")
                }
            }
        }
        .onAppear {
            isVisible = true
            mountAfterPreparedFrame()
        }
        .onDisappear { isVisible = false }
    }

    private func mountAfterPreparedFrame() {
        guard !isLiveMounted else { return }
        DispatchQueue.main.async {
            DispatchQueue.main.async {
                guard isVisible else { return }
                isLiveMounted = true
            }
        }
    }
}

/// Keeps the native Splits tab's first frame lightweight. The tab still owns
/// the real `SplitsView` and its navigation routes; only its relationship-heavy
/// construction is moved past the root tab's stable-frame turn.
private struct DeferredSplitsTabHost: View {
    let preparedRows: [StartWorkoutSplitCardSnapshot]
    @State private var isSplitsMounted = false
    @State private var isVisible = false

    var body: some View {
        Group {
            if isSplitsMounted {
                SplitsView()
            } else {
                NavigationStack {
                    FitnessScreen {
                        ForEach(preparedRows.prefix(5)) { row in
                            FitnessCard(style: .compact) {
                                HStack {
                                    Text(row.splitName)
                                        .font(AppTypography.cardTitle)
                                    Spacer()
                                    Text(row.estimatedDurationText)
                                        .font(AppTypography.metadata)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .accessibilityIdentifier("split-card-\(row.splitName)")
                        }
                    }
                    .accessibilityIdentifier("splits-screen")
                    .navigationTitle("Splits")
                    .navigationBarTitleDisplayMode(.inline)
                }
            }
        }
        .onAppear {
            isVisible = true
            guard !isSplitsMounted else { return }
            DispatchQueue.main.async {
                DispatchQueue.main.async {
                    guard isVisible else { return }
                    isSplitsMounted = true
                }
            }
        }
        .onDisappear {
            // Keep the tab mounted after its first appearance so pushed
            // navigation state survives tab switches like the other roots.
            isVisible = false
        }
    }
}
