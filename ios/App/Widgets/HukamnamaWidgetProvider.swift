#if HUKAMNAMA_WIDGET
import WidgetKit
import SwiftUI

// The "Hukamnama · Sri Harmandir Sahib" widget. Compiled only where HUKAMNAMA_WIDGET is set
// (Debug), so a Release binary carries neither the widget nor its network read until the G3/G4
// gates are signed (ios/tests HukamnamaGates). Separate from the Hukam of the day (G3 R6).
//
// How fresh data arrives, most reliable first:
//   1. the Notification Service Extension writes the push into hukamnama-snapshot.json and
//      reloads this kind — works with the app closed;
//   2. this provider reads GET /v1/hukamnama/today while nothing is published for today, inside
//      05:30–14:00 IST (also covers readers who have the widget but not the notification);
//   3. the app writes the store and reloads this kind whenever it reads the service.
// The verse it shows was copied by our server from our own corpus; nothing here edits it.

/// The widget's one network read: today's entry from the Hukamnama service. Nothing is sent but
/// the request itself — no token, no identifier, no cookies, no cache.
enum HukamnamaWidgetFetch {
    static var base: URL? {
        (Bundle.main.object(forInfoDictionaryKey: "HukamnamaAPIBase") as? String)
            .flatMap { $0.isEmpty || $0.hasPrefix("$(") ? nil : URL(string: $0) }
            .flatMap { $0.scheme == "https" ? $0 : nil }
    }

    private static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.httpCookieStorage = nil
        c.httpShouldSetCookies = false
        c.urlCache = nil
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        c.timeoutIntervalForRequest = 10
        c.timeoutIntervalForResource = 15
        c.waitsForConnectivity = false
        return URLSession(configuration: c)
    }()

    /// Today's entry, or nil when offline, not found or malformed (never a partial result).
    static func today() async -> HukamnamaEntry? {
        guard let base else { return nil }
        var r = URLRequest(url: base.appendingPathComponent("v1/hukamnama/today"))
        r.httpMethod = "GET"
        r.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await session.data(for: r),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let entry = try? HukamnamaStore.decoder.decode(HukamnamaEntry.self, from: data),
              AmritsarDate.isValidKey(entry.amritsarDate),
              entry.status != .published || entry.isLocatable
        else { return nil }
        return entry
    }
}

struct HukamnamaWidgetEntry: TimelineEntry {
    let date: Date
    let timeline: HukamnamaTimeline.Entry
}

struct HukamnamaProvider: TimelineProvider {
    private static func sample(_ now: Date) -> HukamnamaWidgetEntry {
        let e = HukamnamaEntry(amritsarDate: AmritsarDate.key(now), status: .published, ang: 1)
        return HukamnamaWidgetEntry(date: now, timeline: .init(date: now, state: .today(e), verseShown: false))
    }

    func placeholder(in context: Context) -> HukamnamaWidgetEntry { Self.sample(.now) }

    func getSnapshot(in context: Context, completion: @escaping (HukamnamaWidgetEntry) -> Void) {
        let now = Date.now
        let t = HukamnamaTimeline.build(entries: HukamnamaStore.load(),
                                        localScripture: HukamnamaStore.localScriptureSHA256, now: now)
        completion(t.entries.first.map { HukamnamaWidgetEntry(date: $0.date, timeline: $0) } ?? Self.sample(now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HukamnamaWidgetEntry>) -> Void) {
        let done = Handoff(call: completion)
        Task {
            let now = Date.now
            var entries = HukamnamaStore.load()
            if HukamnamaTimeline.shouldFetch(entries: entries, now: now), let fresh = await HukamnamaWidgetFetch.today() {
                entries = HukamnamaStore.merge([fresh])
                if entries.isEmpty { entries = HukamnamaStore.load() }
            }
            let t = HukamnamaTimeline.build(entries: entries, localScripture: HukamnamaStore.localScriptureSHA256, now: now)
            done.call(Timeline(entries: t.entries.map { HukamnamaWidgetEntry(date: $0.date, timeline: $0) },
                               policy: .after(t.refresh)))
        }
    }
}

/// WidgetKit's completion handler predates Sendable; it is called exactly once, from the task.
private struct Handoff<T>: @unchecked Sendable { let call: (T) -> Void }

struct HukamnamaWidget: Widget {
    /// The kind the NSE and the app reload (NotificationService.widgetKind).
    static let kind = "Hukamnama"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: HukamnamaProvider()) { entry in
            HukamnamaFamilyView(entry: entry)
        }
        .configurationDisplayName(HukamnamaWidgetView.name)
        .description("The Hukamnama taken at Sri Harmandir Sahib, Amritsar, located by Ang from SGPC. Text from Sri Guru Granth Sahib Ji (not the Hukam of the day).")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge,
                            .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

private struct HukamnamaFamilyView: View {
    let entry: HukamnamaWidgetEntry
    @Environment(\.widgetFamily) private var family
    var body: some View {
        HukamnamaWidgetView(entry: entry.timeline, family: family)
            .containerBackground(for: .widget) { RaagNowGround() }
    }
}
#endif
