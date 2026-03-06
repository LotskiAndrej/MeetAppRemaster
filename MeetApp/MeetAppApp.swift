import FirebaseCore
import SwiftUI

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        FirebaseApp.configure()
        return true
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
        }
    }
}
