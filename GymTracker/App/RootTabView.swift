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
        .sheet(item: $sleepDestination) { destination in
            sleepDestinationView(destination)
        }
        .onReceive(NotificationCenter.default.publisher(for: .sleepNotificationTapped)) { notification in
            sleepSettings = sleepSettingsStore.load()
            selectedTab = .today
            sleepDestination = notification.object as? SleepNotificationDestination ?? .sleepDashboard
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                refreshSleepNotifications()
            }
        }
        .onChange(of: sleepSettings) { _, newValue in
            sleepSettingsStore.save(newValue)
        }
        .onAppear {
            guard !didPrepareRootData else { return }
            didPrepareRootData = true
            PerformanceTracer.trace(.appLaunchPreparation) {
                SeedDataService.seedIfNeeded(in: modelContext)
                WorkoutSessionDateService.repairCompletedSessionDates(in: modelContext)
            }
            sleepSettings = sleepSettingsStore.load()
            refreshSleepNotifications(deferred: true)
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

    private func refreshSleepNotifications(deferred: Bool = false) {
        let sessionSnapshots = SleepNotificationScheduler.sessionSnapshots(from: sleepSessions)
        let workoutSnapshots = SleepNotificationScheduler.workoutSnapshots(from: workouts)
        let settings = sleepSettingsStore.load()

        sleepNotificationRefreshTask?.cancel()
        sleepNotificationRefreshTask = Task(priority: .utility) {
            if deferred {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard !Task.isCancelled else { return }
            }

            await PerformanceTracer.traceAsync(.rootNotificationRefresh) {
                await SleepNotificationScheduler().refreshAllSleepNotifications(
                    settings: settings,
                    sessions: sessionSnapshots,
                    workouts: workoutSnapshots
                )
            }
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
