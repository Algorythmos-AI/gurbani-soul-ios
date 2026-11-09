import UserNotifications
#if canImport(WidgetKit)
import WidgetKit
#endif

/// The Hukamnama push's Notification Service Extension: a PASS-THROUGH data writer.
///
/// It never edits the notification — the title, the date, the verse (copied by the server from
/// our corpus) and the Ang citation reach the lock screen exactly as sent. All it does is merge
/// the payload's fields into `hukamnama-snapshot.json` (App Group) and ask WidgetKit to reload
/// the "Hukamnama" widget kind, so the widget is current without the app being opened.
/// Budget: no network, no corpus DB, one small coordinated file write — far inside the 30 s and
/// few-MB limits. Any other notification is passed through untouched.
final class NotificationService: UNNotificationServiceExtension {
    static let widgetKind = "Hukamnama"

    override func didReceive(_ request: UNNotificationRequest,
                             withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        let content = request.content
        if content.threadIdentifier == "hukamnama", let entry = HukamnamaEntry(pushUserInfo: content.userInfo) {
            HukamnamaStore.merge([entry])
            #if canImport(WidgetKit)
            WidgetCenter.shared.reloadTimelines(ofKind: Self.widgetKind)
            #endif
        }
        contentHandler(content)   // unchanged
    }

    /// Nothing is ever pending: `didReceive` finishes synchronously.
    override func serviceExtensionTimeWillExpire() {}
}
