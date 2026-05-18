import SwiftData
import SwiftUI

struct RootTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var appTheme

    var body: some View {
        TabView {
            TodayView()
                .tabItem {
                    Label("Today", systemImage: "calendar")
                }

            StartWorkoutView()
                .tabItem {
                    Label("Workout", systemImage: "figure.strengthtraining.traditional")
                }

            SplitsView()
                .tabItem {
                    Label("Splits", systemImage: "list.bullet.rectangle")
                }

            HistoryView()
                .tabItem {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
        .tint(appTheme.colors.accent)
        .toolbarBackground(appTheme.colors.backgroundSecondary, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .task {
            await SeedDataService.seedIfNeeded(in: modelContext)
            WorkoutSessionDateService.repairCompletedSessionDates(in: modelContext)
        }
    }
}
