import SwiftData
import SwiftUI
import UserNotifications
import UIKit

@MainActor
final class SleepDeepLinkRouter: ObservableObject {
    struct Request: Identifiable, Equatable {
        let id = UUID()
        let destination: SleepNotificationDestination
    }

    static let shared = SleepDeepLinkRouter()

    @Published private(set) var pendingRequest: Request?

    private init() {}

    func receive(_ destination: SleepNotificationDestination) {
        pendingRequest = Request(destination: destination)
    }

    func consume(_ request: Request) {
        guard pendingRequest?.id == request.id else { return }
        pendingRequest = nil
    }
}

final class AppNotificationDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Firebase must be configured after UIKit has installed the real app
        // delegate. Configuring it from the SwiftUI App initializer causes
        // Firebase's delegate swizzler to inspect the property-wrapper proxy.
        FirebaseBootstrap.configureIfPossible()
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let destination = SleepNotificationDestination(userInfo: response.notification.request.content.userInfo) else { return }
        await MainActor.run {
            SleepDeepLinkRouter.shared.receive(destination)
        }
    }

    func applicationWillResignActive(_ application: UIApplication) {
        PerformanceTracer.mark(.appLifecycle, "UIApplication willResignActive")
        NotificationCenter.default.post(name: .appWillResignActiveForCleanup, object: nil)
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        PerformanceTracer.mark(.appLifecycle, "UIApplication didEnterBackground")
        NotificationCenter.default.post(name: .appDidEnterBackgroundForCleanup, object: nil)
    }
}

@main
struct GymTrackerApp: App {
    @UIApplicationDelegateAdaptor(AppNotificationDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            PeaklineModelContainerHost()
        }
    }
}
