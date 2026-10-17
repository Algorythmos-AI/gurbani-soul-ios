import Foundation

/// When the app asks for an App Store rating. The system decides whether a prompt is shown (at most
/// three times a year, never in TestFlight); the app only chooses the moment, and chooses it with
/// care: right after a bani is marked read — a moment of fulfilment, never in the middle of reading
/// — once the reader has read on at least `minReadingDays` different days, and at most once per
/// app version. "Rate Gurbani Soul" in More is always there for anyone who wants it.
enum ReviewPrompt {
    static let minReadingDays = 3
    static let lastVersionKey = "sggs_review_prompted_version"

    static func shouldAsk(readingDays: Int, lastPromptedVersion: String?, currentVersion: String) -> Bool {
        readingDays >= minReadingDays && lastPromptedVersion != currentVersion && !currentVersion.isEmpty
    }

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }
}
