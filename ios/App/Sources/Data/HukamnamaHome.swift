import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// What the Nitnem home card and the sheet know about the Hukamnama from Sri Harmandir Sahib:
/// the shared store first (written by the NSE, the app and the widget), then the read API —
/// fetched only while the card is visible, at most every 10 minutes.
@MainActor @Observable
final class HukamnamaHome {
    static let fetchInterval: TimeInterval = 10 * 60
    /// After 14:00 IST with nothing new, the day's Hukamnama is late, not merely "not yet".
    static let lateAfterMinuteIST = 14 * 60

    private let service: HukamnamaServing?
    private let storeURL: URL?
    private(set) var entries: [HukamnamaEntry] = []
    private var lastFetch: Date?

    init(service: HukamnamaServing?, storeURL: URL? = HukamnamaStore.defaultURL()) {
        self.service = service
        self.storeURL = storeURL
        reloadFromStore()
    }

    func reloadFromStore() { entries = HukamnamaStore.load(url: storeURL) }

    func entry(for date: String) -> HukamnamaEntry? { entries.first { $0.amritsarDate == date } }
    var latestPublished: HukamnamaEntry? { entries.first { $0.status == .published } }

    /// A payload from a foreground push or a tap.
    func ingest(_ entry: HukamnamaEntry) {
        let before = entries
        entries = HukamnamaStore.merge([entry], url: storeURL)
        if entries.isEmpty { reloadFromStore() }
        if entries != before { Self.reloadWidget() }
    }

    /// The widget kind the NSE also reloads (Widgets/HukamnamaWidgetProvider.swift). App-side
    /// reloads are not counted against the widget's budget while the app is in the foreground.
    static let widgetKind = "Hukamnama"

    static func reloadWidget() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
        #endif
    }

    /// The card is on screen: fetch today's status unless that happened in the last 10 minutes.
    func refreshIfDue(now: Date = Date()) async {
        if let lastFetch, now.timeIntervalSince(lastFetch) < Self.fetchInterval { return }
        lastFetch = now
        _ = await fetch(date: nil)
    }

    /// One read from the service, merged into the store. Nil when offline or not found.
    func fetch(date: String?) async -> HukamnamaEntry? {
        guard let service, let e = try? await service.fetch(date: date) else { return nil }
        ingest(e)
        return e
    }

    enum CardState: Equatable, Sendable {
        /// Today's (Amritsar) Hukamnama is published.
        case published(HukamnamaEntry)
        /// Not yet published today; the last one we have (dated), if any.
        case notYet(previous: HukamnamaEntry?)
        /// Held for a check, or past 14:00 IST with nothing new.
        case late(previous: HukamnamaEntry?)
    }

    func cardState(now: Date = Date()) -> CardState {
        let today = AmritsarDate.key(now)
        let previous = entries.first { $0.status == .published && $0.amritsarDate < today }
        if let e = entry(for: today) {
            switch e.status {
            case .published: return .published(e)
            case .held: return .late(previous: previous)
            case .pending: break
            }
        }
        let cal = AmritsarDate.calendar
        let c = cal.dateComponents([.hour, .minute], from: now)
        let minuteIST = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        return minuteIST >= Self.lateAfterMinuteIST ? .late(previous: previous) : .notYet(previous: previous)
    }
}
