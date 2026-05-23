import SwiftData
import SwiftUI
import UserNotifications
import UIKit

final class AppNotificationDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let destination = SleepNotificationDestination(userInfo: response.notification.request.content.userInfo) else { return }
        await MainActor.run {
            NotificationCenter.default.post(name: .sleepNotificationTapped, object: destination)
        }
    }
}

@main
struct GymTrackerApp: App {
    @UIApplicationDelegateAdaptor(AppNotificationDelegate.self) private var appDelegate

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
            BodyweightLog.self,
            FoodItem.self,
            FoodLogEntry.self,
            HydrationEntry.self,
            SleepSession.self,
            NapSession.self,
            DailyCoachCheckIn.self,
            CoachActionHistoryEntry.self,
            SavedCoachDeloadBlock.self,
            CoachExerciseMetadata.self,
            CoachRecommendationFeedback.self,
            CoachPreferences.self,
            CoachSplitMetadata.self
        ])

        let useInMemoryStore = ProcessInfo.processInfo.arguments.contains("-UITestInMemoryStore")
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: useInMemoryStore)

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
