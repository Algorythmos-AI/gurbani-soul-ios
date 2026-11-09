import Foundation
import SwiftUI
#if canImport(UserNotifications)
import UserNotifications
#endif

/// Reads the reminder preferences and keeps the pending local notifications in step with them.
/// All scheduling goes through a `NotificationScheduling` seam so tests never touch the real
/// center. Rescheduling is idempotent: it always clears the `nitnem.` prefix and re-adds the plan.
@MainActor
final class NitnemReminderController: ObservableObject {
    private let scheduler: NotificationScheduling

    static func prefKey(_ band: NitnemBand) -> String { "sggs_reminder_\(band.rawValue)" }
    static func minuteKey(_ band: NitnemBand) -> String { "sggs_reminder_\(band.rawValue)_min" }

    init(scheduler: NotificationScheduling) { self.scheduler = scheduler }

    /// Whether a band's reminder toggle is on.
    func isEnabled(_ band: NitnemBand, defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: Self.prefKey(band))
    }
    /// The reminder minute-of-day for a band (its default until the reader changes it).
    func minute(_ band: NitnemBand, defaults: UserDefaults = .standard) -> Int {
        defaults.object(forKey: Self.minuteKey(band)) as? Int ?? NitnemReminders.defaultMinute(band)
    }

    /// The enabled bands mapped to their times — the input to the pure planner.
    private func enabledMap(defaults: UserDefaults) -> [NitnemBand: Int] {
        var out: [NitnemBand: Int] = [:]
        for band in NitnemReminders.bands where defaults.bool(forKey: Self.prefKey(band)) {
            out[band] = minute(band, defaults: defaults)
        }
        return out
    }

    /// Turn a band's reminder on (asking permission the first time) or off. Returns the value the
    /// toggle should settle on: a denied permission snaps it back to off with a Settings nudge.
    @discardableResult
    func setEnabled(_ on: Bool, band: NitnemBand, defaults: UserDefaults = .standard,
                    completedToday: Set<NitnemBand> = []) async -> Bool {
        if on {
            let status = await scheduler.authorizationStatus()
            if status == .denied {
                defaults.set(false, forKey: Self.prefKey(band))
                await reschedule(defaults: defaults, completedToday: completedToday)
                return false
            }
            // `.provisional` is what builds up to 1.3.0 (7) were granted silently; it delivers
            // quietly, so it is upgraded with a real prompt the next time a reminder is turned on.
            if status == .notDetermined || status == .provisional {
                let granted = await scheduler.requestAuthorization()
                if !granted {
                    defaults.set(false, forKey: Self.prefKey(band))
                    await reschedule(defaults: defaults, completedToday: completedToday)
                    return false
                }
            }
        }
        defaults.set(on, forKey: Self.prefKey(band))
        await reschedule(defaults: defaults, completedToday: completedToday)
        return on
    }

    /// True when the OS has denied notifications for the app (so the UI can show a Settings link).
    func authStatusIsDenied() async -> Bool { await scheduler.authorizationStatus() == .denied }

    /// Rewrite the pending set from the current preferences. Cheap and safe to call on foreground,
    /// on a time change, and after a bani is marked read.
    func reschedule(defaults: UserDefaults = .standard, now: Date = NitnemClock.now(),
                    completedToday: Set<NitnemBand> = []) async {
        await scheduler.removeAll(withPrefix: NitnemReminders.idPrefix)
        let enabled = enabledMap(defaults: defaults)
        guard !enabled.isEmpty else { return }
        let plan = NitnemReminders.plan(now: now, enabled: enabled, completedToday: completedToday)
        await scheduler.add(plan)
    }
}

#if canImport(UserNotifications)
/// Routes a tapped notification and decides how one is shown while the app is foregrounded.
/// - Nitnem reminders: a tap opens `sggs://nitnem`; in the foreground nothing is shown (no
///   nudge over the page the reader is on).
/// - The Hukamnama from Sri Harmandir Sahib (`thread-id` "hukamnama"): a tap opens its sheet
///   (`sggs://hukamnama/<date>`, or the latest when the payload's URL is malformed); in the
///   foreground it goes to Notification Center only (`.list`), never a banner over the page.
///   Both paths also merge the payload into the shared store so the card and widget update.
/// One shared instance, set as the center's delegate at launch (early enough for a cold tap).
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    static let hukamnamaThread = "hukamnama"

    let onOpen: @MainActor @Sendable (URL) -> Void
    let onHukamnama: @MainActor @Sendable (HukamnamaEntry) -> Void
    init(onOpen: @escaping @MainActor @Sendable (URL) -> Void,
         onHukamnama: @escaping @MainActor @Sendable (HukamnamaEntry) -> Void = { _ in }) {
        self.onOpen = onOpen
        self.onHukamnama = onHukamnama
    }

    /// Foreground presentation, by thread: the Hukamnama → Notification Center only.
    static func presentationOptions(threadIdentifier: String) -> UNNotificationPresentationOptions {
        threadIdentifier == hukamnamaThread ? [.list] : []
    }

    /// Where a tap goes. A Hukamnama whose `url` is missing or fails the router's strict check
    /// falls back to the latest Hukamnama; anything else keeps the reminders' `sggs://nitnem`.
    static func openURL(threadIdentifier: String, userInfo: [AnyHashable: Any], now: Date = Date()) -> URL? {
        let raw = userInfo["url"] as? String
        if threadIdentifier == hukamnamaThread {
            if let raw, let url = URL(string: raw), Router.hukamnamaTarget(url, now: now) != nil { return url }
            return URL(string: "sggs://hukamnama")
        }
        return URL(string: raw ?? "sggs://nitnem")
    }

    /// The payload's entry, merged into the App Group store (the NSE normally did this already;
    /// merging twice is a no-op). Nil for any other notification.
    private func ingest(_ content: UNNotificationContent) -> HukamnamaEntry? {
        guard content.threadIdentifier == Self.hukamnamaThread,
              let entry = HukamnamaEntry(pushUserInfo: content.userInfo) else { return nil }
        HukamnamaStore.merge([entry])
        return entry
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        let content = notification.request.content
        if let entry = ingest(content) {
            let handle = onHukamnama
            await MainActor.run { handle(entry) }
        }
        return Self.presentationOptions(threadIdentifier: content.threadIdentifier)
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        let content = response.notification.request.content
        let entry = ingest(content)
        guard let url = Self.openURL(threadIdentifier: content.threadIdentifier, userInfo: content.userInfo) else { return }
        let open = onOpen, handle = onHukamnama
        await MainActor.run {
            if let entry { handle(entry) }
            open(url)
        }
    }
}
#endif
