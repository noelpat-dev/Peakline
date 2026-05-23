import SwiftData
import SwiftUI

struct RootTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var appTheme
    @Environment(\.scenePhase) private var scenePhase

    @Query(sort: \SleepSession.createdAt, order: .reverse)
    private var sleepSessions: [SleepSession]

    @Query(filter: #Predicate<WorkoutSession> { $0.completed }, sort: \WorkoutSession.date, order: .reverse)
    private var workouts: [WorkoutSession]

    @State private var selectedTab: RootTab = .today
    @State private var sleepSettings = SleepSettingsStore().load()
    @State private var sleepDestination: SleepNotificationDestination?

    private let sleepSettingsStore = SleepSettingsStore()

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
            if newPhase == .background || newPhase == .inactive {
                refreshSleepNotifications()
            }
        }
        .onChange(of: sleepSettings) { _, newValue in
            sleepSettingsStore.save(newValue)
        }
        .task {
            await SeedDataService.seedIfNeeded(in: modelContext)
            WorkoutSessionDateService.repairCompletedSessionDates(in: modelContext)
            sleepSettings = sleepSettingsStore.load()
            refreshSleepNotifications()
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

    private func refreshSleepNotifications() {
        Task {
            await SleepNotificationScheduler().refreshAllSleepNotifications(
                settings: sleepSettingsStore.load(),
                sessions: sleepSessions,
                workouts: workouts
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
