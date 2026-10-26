import SwiftUI
import os
import GurbaniSearchKit
import GurbaniPahar

/// The whole theme sky, reduced to what a card needs to draw it: every theme as a star at the
/// SAME seeded layout the Sky screen settles on (`ForceLayout`, seed 54, 300 iterations), so the
/// card is a true thumbnail of the screen it opens. No verse text.
struct ExploreSky: Equatable, Sendable {
    let concepts: [String]
    let verses: [Int]
    /// Unit-square positions, parallel to `concepts`.
    let points: [CGPoint]
    /// Pairs drawn on the Sky screen (PPMI ≥ 0.7): (i, j, jaccard).
    let drawn: [Edge]

    struct Edge: Equatable, Sendable {
        let i: Int
        let j: Int
        let jaccard: Double
    }

    /// The Sky screen's own reduction of a `SkyGraph`: every pair is a spring, only PPMI ≥ 0.7 is drawn.
    static func make(_ graph: SkyGraph) async -> ExploreSky {
        let nodes = graph.nodes
        let index = Dictionary(nodes.enumerated().map { ($1.concept, $0) }, uniquingKeysWith: { a, _ in a })
        let maxP = max(graph.edges.map(\.ppmi).max() ?? 1, 1e-6)
        let springs = graph.edges.compactMap { e -> (Int, Int, Double)? in
            guard e.ppmi > 0, let i = index[e.source], let j = index[e.target] else { return nil }
            return (i, j, 3 * e.ppmi / maxP)
        }
        let drawn = graph.edges.compactMap { e -> Edge? in
            guard e.ppmi >= 0.7, let i = index[e.source], let j = index[e.target] else { return nil }
            return Edge(i: i, j: j, jaccard: e.jaccard)
        }
        let count = nodes.count
        let points = await Task.detached(priority: .utility) {
            ForceLayout.layout(nodeCount: count, edges: springs, iterations: 300, seed: 54)
        }.value
        return ExploreSky(concepts: nodes.map(\.concept), verses: nodes.map(\.n), points: points, drawn: drawn)
    }
}

/// The current watch, as the Raag Clock card states it. Built from the widgets' own timeline
/// entry (`RaagNowTimeline.entry`), so the card, the widgets and the Clock agree on the watch,
/// its window (fixed or solar) and its raags — and it needs no database read.
struct ExploreClockNow: Equatable {
    let pahar: Int
    let label: String
    let window: String
    let model: PaharDialModel
    /// Verbatim Gurmukhi raag names for this watch (parallel to `raagsRoman` when present).
    let raagsGurmukhi: [String]
    let raagsRoman: [String]
    /// False until the app has written the widget snapshot (the pahar→raags table).
    let hasSnapshot: Bool

    init(entry: RaagNowEntry, locale: Locale = .current, tz: TimeZone = .current) {
        pahar = entry.pahar
        label = Pahar.label(entry.pahar)
        let w = entry.windows.indices.contains(entry.pahar - 1) ? entry.windows[entry.pahar - 1] : Pahar.window(entry.pahar)
        window = PaharFormat.window(w, on: entry.date, locale: locale, tz: tz)
        model = entry.model
        raagsGurmukhi = entry.raagsGurmukhi
        raagsRoman = entry.raags
        hasSnapshot = entry.hasSnapshot
    }

    static func == (a: ExploreClockNow, b: ExploreClockNow) -> Bool {
        a.pahar == b.pahar && a.window == b.window && a.model == b.model
            && a.raagsGurmukhi == b.raagsGurmukhi && a.raagsRoman == b.raagsRoman && a.hasSnapshot == b.hasSnapshot
    }

    static func now(_ date: Date = NitnemClock.now()) -> ExploreClockNow {
        let snap = WidgetStore.load()
        return ExploreClockNow(entry: RaagNowTimeline.entry(at: date, config: .current(snapshot: snap), snapshot: snap))
    }

    var raagCount: Int { max(raagsRoman.count, raagsGurmukhi.count) }

    /// "3rd pahar of day · 12–3 PM"
    var caption: String { "\(label) · \(window)" }

    var spoken: String {
        var s = "\(label), \(window.replacingOccurrences(of: "–", with: " to "))"
        if !raagsRoman.isEmpty {
            s += ". Sung in this watch: " + ListFormatter.localizedString(byJoining: raagsRoman)
        }
        return s
    }
}

/// The hub's deferred previews: today's theme (with its verbatim verse) and the theme sky. Each
/// read runs once per process and is kept here (held by AppContainer), so returning to Explore
/// never queries again. They start after the first frame at utility priority, because the
/// corpus actor is serial and the Reader shares it; signposts measure them in Instruments.
@MainActor @Observable
final class ExploreLive {
    /// The day number `themeToday` was read for (`HukamOfTheDay.dayNumber`).
    private(set) var themeDay: Int?
    private(set) var themeToday: ThemeOfTheDay?
    private(set) var themeBins: [Int] = []
    private(set) var sky: ExploreSky?
    /// The day the newest `load` asked for. A read still in flight for an older day (the hub left
    /// open across midnight or a time-zone change) never publishes over it.
    private var requestedDay: Int?
    private var skyLoading = false

    private static let signposter = OSSignposter(subsystem: "org.sggs.app", category: "Explore")

    func load(corpus: CorpusActor?, day: Int) async {
        guard let corpus else { return }
        requestedDay = day
        let needsTheme = themeDay != day
        guard needsTheme || (sky == nil && !skyLoading) else { return }
        // Let the hub's first frame (and any page the reader opens from it) go first.
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled, requestedDay == day else { return }

        if needsTheme {
            let state = Self.signposter.beginInterval("themeOfTheDay")
            let theme = try? await corpus.themeOfTheDay(day: day)
            var bins: [Int] = []
            if let theme { bins = (try? await corpus.themeAngBins(theme.concept)) ?? [] }
            Self.signposter.endInterval("themeOfTheDay", state)
            // A newer day may have been asked for while this read was in flight.
            if let theme, requestedDay == day, !Task.isCancelled {
                themeToday = theme
                themeBins = bins
                themeDay = day
            }
        }
        // The sky is the same every day: one build per process, kept even if this task was
        // superseded meanwhile.
        if sky == nil, !skyLoading, !Task.isCancelled {
            skyLoading = true
            defer { skyLoading = false }
            let state = Self.signposter.beginInterval("constellationSky")
            if let graph = try? await corpus.constellationSky(minPPMI: 0), !graph.nodes.isEmpty {
                sky = await ExploreSky.make(graph)
            }
            Self.signposter.endInterval("constellationSky", state)
        }
    }
}
