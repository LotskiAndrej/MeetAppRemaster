import FirebaseAuth
import FirebaseMessaging
import UIKit
import UserNotifications

final class NotificationService: NSObject {

    // Holds the latest FCM token so it can be saved once auth state is known.
    private var pendingToken: String?

    func configure() {
        UNUserNotificationCenter.current().delegate = self
        Messaging.messaging().delegate = self
        observeAuthState()
    }

    @MainActor
    func requestPermission() async {
        // Only requests authorization for visible alerts/sounds/badges.
        // APNs device token registration happens earlier in AppDelegate.
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .badge, .sound])
    }

    // When a user signs in (including on app relaunch with an existing session),
    // save the token if FCM has already delivered it.
    private func observeAuthState() {
        _ = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            guard let self, let uid = user?.uid, let token = self.pendingToken else { return }
            Task { try? await UserService().updateFCMToken(uid: uid, token: token) }
        }
    }

    // Called by MessagingDelegate once APNs token is set and FCM token is ready.
    private func saveFCMToken(_ token: String) {
        pendingToken = token
        guard let uid = Auth.auth().currentUser?.uid else { return }
        Task { try? await UserService().updateFCMToken(uid: uid, token: token) }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationService: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }
}

// MARK: - MessagingDelegate

extension NotificationService: MessagingDelegate {
    // Only called after the APNs token is set — no more timing warnings.
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let token = fcmToken else { return }
        saveFCMToken(token)
    }
}
