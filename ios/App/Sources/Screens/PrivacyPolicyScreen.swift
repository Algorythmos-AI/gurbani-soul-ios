import SwiftUI

/// The links the app exposes to the outside world. The two web URLs are the SAME ones entered in
/// App Store Connect as the Privacy Policy and Support URLs (docs/ios/app-store-listing.md), so a
/// repo gate asserts they never drift. Opening one hands the URL to Safari; the app's only network
/// use is the Hukamnama service (HukamnamaAPI.swift), which the policy screen describes.
enum AppLinks {
    static let privacy = URL(string: "https://gurbanisoul.com/en/privacy")!
    static let support = URL(string: "https://gurbanisoul.com/en/support")!
    /// The App Store page (Apple ID 6812982384) and its write-a-review sheet.
    static let appStore = URL(string: "https://apps.apple.com/app/id6812982384")!
    static let writeReview = URL(string: "https://apps.apple.com/app/id6812982384?action=write-review")!
    /// What "Share Gurbani Soul" sends: the site, which unfurls as Gurbani Soul's own card and
    /// offers the App Store from there (the App Store link unfurls as Apple's generic card).
    static let website = URL(string: "https://gurbanisoul.com")!
}

/// The in-app Privacy Policy (Guideline 5.1.1(i): reachable inside the app). Deliberately static
/// and offline — it renders in Airplane Mode, true to the app's promise — and mirrors the web
/// policy at AppLinks.privacy fact-for-fact. Update both together.
struct PrivacyPolicyScreen: View {
    var body: some View {
        List {
            Section {
                Text("We collect one thing, and only if you turn on the Hukamnama notification. Here is exactly what that means.")
                    .font(Brand.heading(.title3))
                Text("This applies to the Gurbani Soul app for iPhone and iPad, including its widgets and Live Activity.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            .inkRow()

            policy("The short version", [
                "No accounts. Nothing to sign up for, nothing to log in to.",
                "The app makes no network connections and works fully in Airplane Mode, with one exception: the daily Hukamnama from Sri Harmandir Sahib, described below.",
                "No analytics, no advertising, no tracking, no third-party SDKs.",
                "Everything you do — saved verses, settings, reading position, Nitnem progress and reminders — stays on your device.",
                "Location is optional, used only on your device, and never transmitted.",
            ])

            policy("What stays on your device", [
                "Saved verses are stored in the app's own database, and added to your device's Spotlight index so you can find them from Home Screen search; unsaving removes them.",
                "The 54 theme names (with their Gurmukhi words and verse counts — nothing about you) are also added to Spotlight, so a theme can be opened from Home Screen search.",
                "\u{201C}Your themes\u{201D} on the Themes page is worked out on your device from your saved verses; it is never sent anywhere, and can be turned off in Settings.",
                "Settings (accent, transliteration, traditional rendering, last Ang read) are stored in the app's local preferences.",
                "Nitnem progress, your own sets and your reading journey are stored in the app's App Group container so the Nitnem widget can show them.",
                "Reminders are optional local notifications, scheduled on your device at times you choose. No reminder comes from a server.",
                "The reading Live Activity is optional and off by default. It runs on your device with no push updates and never shows a verse.",
                "Widgets read a small snapshot the app writes into its App Group container: the raag watch, the Hukam of the day for the next two weeks with their Angs, today's Nitnem progress, and — if you use solar mode — your clock-mode choice and your location rounded to about 1 km. Nothing about you leaves the device; the Hukamnama widget, if you add it, reads the day's Hukamnama the same way the app does.",
            ])

            policy("The Hukamnama from Sri Harmandir Sahib", [
                "To show the Hukamnama card, page and widget, the app asks our Hukamnama service which shabad is the day's Hukamnama. That request carries no token, no identifier and nothing about you, and the text itself always comes from the copy of Sri Guru Granth Sahib Ji inside the app.",
                "The Hukamnama notification is optional and off by default. If you turn it on, the app asks for notification permission and registers with Apple's push notification service. It then sends our Hukamnama service three things: the device token Apple issues, when you asked to be notified, and which edition of the text the app holds. Nothing else is sent: no account, no name, no location and nothing about what you read. The service stores no IP address and keeps no access log. The token is used only to send that one daily notification. Turning the notification off deletes the token from our service, and a token that has not been used for 180 days is deleted as well. The service runs on Render, and Apple delivers the notification under its own privacy policy.",
            ])

            policy("Location", [
                "Location is used only by the Raag Clock's optional solar mode, and only after you tap “Use my location”.",
                "The fix is rounded to about 1 km before it is stored in the app's App Group container — shared only with the app's own widgets — and the raw position is never kept.",
                "You can enter a location manually instead, or deny the permission; the clock still works.",
            ])

            policy("Integrity & diagnostics", [
                "To verify the bundled scripture is unaltered, the app reads the database file's size and modification date. Nothing is displayed or transmitted.",
                "If the app ever crashes or hangs, iOS may hand it a diagnostic report, which the app writes to a local folder. You can see how many there are, share them via the system share sheet, or delete them under More → About & credits → Integrity. Nothing is sent unless you choose to share it.",
            ])

            Section {
                Text("The app's App Store privacy label lists one item, Device ID: the notification token, collected only if you turn the Hukamnama notification on, used only to deliver it, not linked to you and never used for tracking.")
                    .font(.footnote).foregroundStyle(.secondary)
                Link("Read the full policy online", destination: AppLinks.privacy)
                    .accessibilityIdentifier("privacyWebLink")
                Link("Support", destination: AppLinks.support)
                    .accessibilityIdentifier("supportWebLink")
            } footer: {
                Text("Opening a link hands it to Safari.")
            }
            .inkRow()
        }
        .inkGroupedList()
        .navigationTitle("Privacy Policy")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func policy(_ title: String, _ points: [String]) -> some View {
        Section(title) {
            ForEach(points, id: \.self) { p in
                Label { Text(p) } icon: { Image(systemName: "circle.fill").font(.system(size: 5)).foregroundStyle(.tertiary) }
                    .labelStyle(.titleAndIcon)
            }
        }
        .inkRow()
    }
}
