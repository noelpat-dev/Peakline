import SwiftData
import SwiftUI

@main
struct GymTrackerApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            UserProfile.self,
            TrainingSplit.self,
            SplitExercise.self,
            Exercise.self,
            WorkoutSession.self,
            ExerciseLog.self,
            SetLog.self,
            Recommendation.self,
            BodyweightLog.self
        ])

        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Could not create SwiftData container: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            AppThemeProvider {
                RootTabView()
            }
        }
        .modelContainer(sharedModelContainer)
    }
}
