import FirebaseCore
import FirebaseMessaging
import Foundation
import UserNotifications

/// Friend alerts arrive through Firebase Cloud Messaging, the same as on Android, so the backend's send-alert
/// function needs no changes. No-op until a GoogleService-Info.plist is added (see TODO.md).
enum Push {
    nonisolated(unsafe) private static let delegate = TokenDelegate()

    static var isConfigured: Bool { FirebaseApp.app() != nil }

    static func configure() {
        guard Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else { return }
        FirebaseApp.configure()
        Messaging.messaging().delegate = delegate
    }

    static func didRegister(apnsToken: Data) {
        guard isConfigured else { return }
        Messaging.messaging().apnsToken = apnsToken
    }

    /// Asks for notification permission. Returns whether it was granted.
    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Saves the current FCM token for the signed-in user.
    static func sync() async {
        guard isConfigured, let token = try? await Messaging.messaging().token() else { return }
        try? await Account.savePushToken(token)
    }

    private final class TokenDelegate: NSObject, MessagingDelegate {
        func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
            guard let fcmToken else { return }
            Task { try? await Account.savePushToken(fcmToken) }
        }
    }
}
