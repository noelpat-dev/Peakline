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

    @State private var selectedTab: RootTab = .today
    @State private var sleepSettings = SleepSettingsStore().load()
    @State private var sleepDestination: SleepNotificationDestination?
    @State private var didPrepareRootData = false
    @State private var sleepNotificationRefreshTask: Task<Void, Never>?
    @State private var cachedSleepNotificationRefreshInputs: SleepNotificationRefreshInputs?
    @State private var lastSleepNotificationRefreshSignature: String?
    @State private var queuedSleepNotificationRefreshSignature: String?
    @State private var lastSleepNotificationRefreshAt: Date?

    private let sleepSettingsStore = SleepSettingsStore()

    init() {
        _sleepSessions = Query(Self.sleepSessionsDescriptor)
        _workouts = Query(Self.workoutsDescriptor)
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

    var body: some View {
        TabView(selection: $selectedTab) {
            TodayView()
                .tabItem {
                    Label("Today", systemImage: "calendar")
                }
                .tag(RootTab.today)

            StartWorkoutView()
                .tabItem {
                    Label("Workout", systemImage: "figure.strengthtraining.traditional")
                }
                .tag(RootTab.workout)
                .accessibilityIdentifier("tab-workout")

            SplitsView()
                .tabItem {
                    Label("Splits", systemImage: "list.bullet.rectangle")
                }
                .tag(RootTab.splits)
                .accessibilityIdentifier("tab-splits")

            HistoryView()
                .tabItem {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }
                .tag(RootTab.history)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
                .tag(RootTab.settings)
                .accessibilityIdentifier("tab-settings")
        }
        .tint(appTheme.colors.accent)
        .toolbarBackground(appTheme.colors.backgroundSecondary, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        #if DEBUG
        .overlay(alignment: .topLeading) {
            PerformanceAcceptanceStatusView()
        }
        #endif
        .sheet(item: $sleepDestination) { destination in
            sleepDestinationView(destination)
        }
        .onReceive(NotificationCenter.default.publisher(for: .sleepNotificationTapped)) { notification in
            PerformanceTracer.mark(.appLifecycle, "sleepNotificationTapped begin")
            sleepSettings = sleepSettingsStore.load()
            selectedTab = .today
            sleepDestination = notification.object as? SleepNotificationDestination ?? .sleepDashboard
            PerformanceTracer.mark(.appLifecycle, "sleepNotificationTapped end")
        }
        .onReceive(NotificationCenter.default.publisher(for: .appWillResignActiveForCleanup)) { _ in
            PerformanceTracer.mark(.appLifecycle, "willResignActive cleanup observed")
        }
        .onReceive(NotificationCenter.default.publisher(for: .appDidEnterBackgroundForCleanup)) { _ in
            PerformanceTracer.mark(.appLifecycle, "didEnterBackground cleanup observed")
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification).receive(on: RunLoop.main)) { _ in
            let refreshedSettings = sleepSettingsStore.load()
            if refreshedSettings != sleepSettings {
                sleepSettings = refreshedSettings
            }
            refreshCachedSleepNotificationInputs(reason: "user_defaults_changed")
        }
        .onChange(of: scenePhase) { _, newPhase in
            PerformanceTracer.mark(.appLifecycle, "scenePhase changed \(String(describing: newPhase))")
            switch newPhase {
            case .background:
                PerformanceTracer.mark(.appLifecycle, "background before notification refresh")
                refreshSleepNotifications(source: .sceneBackground, updateMainStateAfterAwait: false)
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
            PerformanceTracer.mark(.appLifecycle, "sleepSettings changed save begin")
            sleepSettingsStore.save(newValue)
            PerformanceTracer.mark(.appLifecycle, "sleepSettings changed save end")
            refreshCachedSleepNotificationInputs(reason: "sleep_settings_changed")
        }
        .onChange(of: sleepNotificationRefreshSourceSignature) { _, _ in
            refreshCachedSleepNotificationInputs(reason: "source_inputs_changed")
        }
        .onAppear {
            guard !didPrepareRootData else { return }
            PerformanceTracer.mark(.appLifecycle, "root onAppear begin")
            didPrepareRootData = true
            PerformanceTracer.trace(.appLaunchPreparation) {
                SeedDataService.seedIfNeeded(in: modelContext)
                WorkoutSessionDateService.repairCompletedSessionDates(in: modelContext)
            }
            sleepSettings = sleepSettingsStore.load()
            refreshCachedSleepNotificationInputs(reason: "root_on_appear")
            refreshSleepNotifications(deferred: true, source: .launchDeferred)
            PerformanceTracer.mark(.appLifecycle, "root onAppear end")
        }
        .onDisappear {
            PerformanceTracer.mark(.appLifecycle, "root onDisappear no_task_cancel")
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
                    SleepDashboardView()
                }
            }
        case .manualBackfill:
            SleepSessionEditorView(mode: .manual)
        case .sleepDashboard, .recoverySummary:
            NavigationStack {
                SleepDashboardView()
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

private enum RootTab: Hashable {
    case today
    case workout
    case splits
    case history
    case settings
}

#if DEBUG
private struct PerformanceAcceptanceStatusView: View {
    @State private var summary = PerformanceAcceptanceState.summary

    private let timer = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    var body: some View {
        if PerformanceAcceptanceState.isEnabled {
            Text(summary)
                .font(.caption2)
                .frame(width: 1, height: 1)
                .opacity(0.01)
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier("performance-acceptance-summary")
                .accessibilityLabel(summary)
                .allowsHitTesting(false)
                .onReceive(timer) { _ in
                    summary = PerformanceAcceptanceState.summary
                }
        }
    }
}
#endif
