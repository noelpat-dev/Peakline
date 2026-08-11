import Observation
import SwiftData
import SwiftUI

struct RootTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var appTheme
    @Environment(\.scenePhase) private var scenePhase

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
    @State private var didStartDeferredServices = false
    @State private var sleepNotificationRefreshTask: Task<Void, Never>?
    @State private var cachedSleepNotificationRefreshInputs: SleepNotificationRefreshInputs?
    @State private var lastSleepNotificationRefreshSignature: String?
    @State private var queuedSleepNotificationRefreshSignature: String?
    @State private var lastSleepNotificationRefreshAt: Date?
    @State private var fullAppBackupTask: Task<Void, Never>?
    @State private var previewWarmRefreshTask: Task<Void, Never>?
    @State private var lastPreviewWarmSourceSignature: String?
    @State private var isWorkoutCompletionPresentationActive = false

    private let sleepSettingsStore = SleepSettingsStore()
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
        descriptor.fetchLimit = 60
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
        FetchDescriptor<TrainingSplit>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
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
        descriptor.fetchLimit = 60
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
            selectionState: tabSelectionState
        )
        .tint(appTheme.colors.accent)
        .sheet(item: $sleepDestination) { destination in
            sleepDestinationView(destination)
        }
        .onReceive(NotificationCenter.default.publisher(for: .sleepNotificationTapped)) { notification in
            PerformanceTracer.mark(.appLifecycle, "sleepNotificationTapped begin")
            sleepSettings = sleepSettingsStore.load()
            tabSelectionState.selectedTab = .today
            sleepDestination = notification.object as? SleepNotificationDestination ?? .sleepDashboard
            PerformanceTracer.mark(.appLifecycle, "sleepNotificationTapped end")
        }
        .onReceive(NotificationCenter.default.publisher(for: .appWillResignActiveForCleanup)) { _ in
            PerformanceTracer.mark(.appLifecycle, "willResignActive cleanup observed")
        }
        .onReceive(NotificationCenter.default.publisher(for: .appDidEnterBackgroundForCleanup)) { _ in
            PerformanceTracer.mark(.appLifecycle, "didEnterBackground cleanup observed")
        }
        .onReceive(NotificationCenter.default.publisher(for: .workoutCompletionPresentationBegan)) { _ in
            isWorkoutCompletionPresentationActive = true
            previewWarmRefreshTask?.cancel()
            previewWarmRefreshTask = nil
            PerformanceTracer.mark(.workoutLoggerFinish, "root_warm_refresh_suspended")
        }
        .onReceive(NotificationCenter.default.publisher(for: .workoutCompletionPresentationEnded)) { _ in
            isWorkoutCompletionPresentationActive = false
            PerformanceTracer.mark(.workoutLoggerFinish, "root_warm_refresh_resumed")
            schedulePreviewWarmRefresh(for: previewWarmSourceSignature)
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification).receive(on: RunLoop.main)) { _ in
            guard startupRevealComplete else { return }
            let refreshedSettings = sleepSettingsStore.load()
            if refreshedSettings != sleepSettings {
                sleepSettings = refreshedSettings
            }
            refreshCachedSleepNotificationInputs(reason: "user_defaults_changed")
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard startupRevealComplete else { return }
            PerformanceTracer.mark(.appLifecycle, "scenePhase changed \(String(describing: newPhase))")
            switch newPhase {
            case .background:
                PerformanceTracer.mark(.appLifecycle, "background before notification refresh")
                refreshSleepNotifications(source: .sceneBackground, updateMainStateAfterAwait: false)
                refreshFullAppBackup(reason: "scene_background")
                PerformanceTracer.mark(.appLifecycle, "background after notification refresh request")
            case .inactive:
                PerformanceTracer.mark(.appLifecycle, "inactive cancel pending notification refresh")
                cancelSleepNotificationRefreshTask(reason: "scene_inactive")
            case .active:
                PerformanceTracer.mark(.appLifecycle, "active refresh notification input cache")
                refreshCachedSleepNotificationInputs(reason: "scene_active")
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
        }
        .onChange(of: sleepNotificationRefreshSourceSignature) { _, _ in
            guard startupRevealComplete else { return }
            refreshCachedSleepNotificationInputs(reason: "source_inputs_changed")
        }
        .onChange(of: previewWarmSourceSignature) { _, newSignature in
            guard startupRevealComplete else { return }
            schedulePreviewWarmRefresh(for: newSignature)
        }
        .onChange(of: coachModifierSourceSignature) { _, _ in
            guard startupRevealComplete else { return }
            // Modifier-only changes do not require history, saved-food, and workout
            // preview caches to be rebuilt. The coach route will refresh its own
            // bounded live queries when it is next opened.
            CoachRouteSnapshotStore.shared.invalidate(source: "root_modifier_change")
        }
        .onChange(of: startupRevealComplete) { _, isComplete in
            guard isComplete else { return }
            startDeferredServicesIfNeeded()
        }
        .onAppear {
            startDeferredServicesIfNeeded()
        }
        .onDisappear {
            PerformanceTracer.mark(.appLifecycle, "root onDisappear no_task_cancel")
        }
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

    private var previewWarmSourceSignature: String {
        [
            previewSplits.map {
                "\($0.id.uuidString):\($0.updatedAt.timeIntervalSince1970):\($0.activeRotationIndex ?? -1)"
            }.joined(separator: ","),
            workouts.map {
                "\($0.id.uuidString):\($0.date.timeIntervalSince1970):\($0.completed)"
            }.joined(separator: ","),
            previewExercises.map {
                "\($0.id.uuidString):\($0.updatedAt.timeIntervalSince1970)"
            }.joined(separator: ",")
        ].joined(separator: "|")
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

    private func schedulePreviewWarmRefresh(for signature: String) {
        guard signature != lastPreviewWarmSourceSignature else { return }
        guard !isWorkoutCompletionPresentationActive else {
            PerformanceTracer.mark(.workoutLoggerFinish, "root_warm_refresh_deferred")
            return
        }
        previewWarmRefreshTask?.cancel()
        previewWarmRefreshTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled,
                  !isWorkoutCompletionPresentationActive,
                  signature == previewWarmSourceSignature else { return }

            do {
                let snapshot = try await StartupSnapshotBuilder.make(in: modelContext)
                guard !Task.isCancelled,
                      signature == previewWarmSourceSignature else { return }

                WorkoutDashboardWarmStartStore.shared.update(
                    trainingCall: snapshot.trainingCall,
                    sourceSignature: snapshot.sourceSignature
                )
                CoachRouteSnapshotStore.shared.update(
                    snapshot: snapshot.coachRouteSnapshot,
                    signature: snapshot.sourceSignature,
                    source: "root_preload"
                )
                WorkoutPreviewWarmStartStore.shared.replaceActiveSnapshots(
                    snapshot.previewWarmSnapshots
                )
                SavedFoodWarmStartStore.shared.update(snapshot.savedFoodCatalogSnapshot)
                lastPreviewWarmSourceSignature = signature
            } catch {
                PerformanceTracer.mark(
                    .workoutPreviewWarmCache,
                    "root_refresh_failed error=\(error.localizedDescription)"
                )
            }
        }
    }

    @ViewBuilder
    private func sleepDestinationView(_ destination: SleepNotificationDestination) -> some View {
        switch destination {
        case .sleepMode:
            SleepModeView(settings: $sleepSettings)
        case .wakeConfirmation(let sessionID):
            if let session = sleepSessions.first(where: { $0.id == sessionID }) {
                SleepMorningConfirmationView(session: session)
            } else {
                NavigationStack {
                    SleepDashboardView(
                        initialSnapshot: startupSnapshot.sleepAnalyticsSnapshot,
                        initialReadinessScore: startupSnapshot.coachSnapshot.readiness
                    )
                }
            }
        case .manualBackfill:
            SleepSessionEditorView(mode: .manual)
        case .sleepDashboard, .recoverySummary:
            NavigationStack {
                SleepDashboardView(
                    initialSnapshot: startupSnapshot.sleepAnalyticsSnapshot,
                    initialReadinessScore: startupSnapshot.coachSnapshot.readiness
                )
            }
        }
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
        source: SleepNotificationRefreshSource = .manual,
        updateMainStateAfterAwait: Bool = true
    ) {
        PerformanceTracer.mark(.appLifecycle, "notification refresh request source=\(source.rawValue) deferred=\(deferred) updateMainStateAfterAwait=\(updateMainStateAfterAwait)")
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

            if updateMainStateAfterAwait {
                sleepNotificationRefreshTask = Task(priority: .utility) {
                    await job.run()
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        applySleepNotificationRefreshCompletion(signature: inputs.signature)
                    }
                }
            } else {
                sleepNotificationRefreshTask = Task(priority: .utility) {
                    await job.run()
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        applySleepNotificationRefreshCompletion(signature: inputs.signature)
                    }
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
    case settings

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

    @State private var pendingTab: RootTab?
    @State private var pendingSelectionStartedAt: Date?

    var body: some View {
        TabView(selection: selectedTabBinding) {
            TodayView(startupSnapshot: startupSnapshot)
                .onAppear { markStableFrame(for: .today) }
                .tabItem {
                    Label("Today", systemImage: "calendar")
                }
                .tag(RootTab.today)
                .accessibilityIdentifier("tab-today")

            StartWorkoutView()
                .onAppear { markStableFrame(for: .workout) }
                .tabItem {
                    Label("Workout", systemImage: "figure.strengthtraining.traditional")
                }
                .tag(RootTab.workout)
                .accessibilityIdentifier("tab-workout")

            SplitsView()
                .onAppear { markStableFrame(for: .splits) }
                .tabItem {
                    Label("Splits", systemImage: "list.bullet.rectangle")
                }
                .tag(RootTab.splits)
                .accessibilityIdentifier("tab-splits")

            HistoryView(startupSnapshot: startupSnapshot.historySnapshot)
                .onAppear { markStableFrame(for: .history) }
                .tabItem {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }
                .tag(RootTab.history)
                .accessibilityIdentifier("tab-history")

            SettingsView()
                .onAppear { markStableFrame(for: .settings) }
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
                .tag(RootTab.settings)
                .accessibilityIdentifier("tab-settings")
        }
    }

    private var selectedTabBinding: Binding<RootTab> {
        Binding {
            selectionState.selectedTab
        } set: { newTab in
            guard selectionState.selectedTab != newTab else { return }
            pendingTab = newTab
            pendingSelectionStartedAt = .now
            PerformanceTracer.mark(.motionTabSelect, "requested tab=\(newTab.rawValue)")
            PerformanceTracer.trace(.motionTabSelect) {
                selectionState.selectedTab = newTab
            }
            AppHaptics.selection()
        }
    }

    private func markStableFrame(for tab: RootTab) {
        guard pendingTab == tab, let pendingSelectionStartedAt else { return }
        let elapsedMilliseconds = max(
            0,
            Int(Date.now.timeIntervalSince(pendingSelectionStartedAt) * 1_000)
        )
        PerformanceTracer.mark(
            .motionTabSelect,
            "stable_frame tab=\(tab.rawValue) elapsed_ms=\(elapsedMilliseconds)"
        )
        pendingTab = nil
        self.pendingSelectionStartedAt = nil
    }
}
