import FirebaseCore
import FirebaseMessaging
import SwiftUI

class AppDelegate: NSObject, UIApplicationDelegate {
    let notificationService = NotificationService()

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        FirebaseApp.configure()
        notificationService.configure()
        // Register with APNs immediately so the device token is available
        // before FCM tries to fetch its token. No permission prompt is shown here.
        application.registerForRemoteNotifications()
        return true
    }

    // Forward APNs device token to Firebase so it can map it to an FCM token.
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Messaging.messaging().apnsToken = deviceToken
    }
}

@main
struct MeetAppApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    @StateObject private var navigationManager = NavigationManager()
    @StateObject private var tabManager = TabManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(navigationManager)
                .environmentObject(tabManager)
                .task {
                    await delegate.notificationService.requestPermission()
                }
        }
    }
}
