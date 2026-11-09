import UIKit

/// Receives the APNs registration callbacks for the Hukamnama push and hands them to
/// `PushTokenBroker`. Nothing else lives here: the notification-center delegate stays set in
/// `AppContainer.init()` (early enough for a cold-launch tap), and launch work stays in SGGSApp.
@MainActor
final class SGGSAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        PushTokenBroker.shared.deliver(token: deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        PushTokenBroker.shared.deliverFailure()
    }
}
