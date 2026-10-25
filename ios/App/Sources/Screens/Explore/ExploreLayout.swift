import Foundation

/// The Explore hub's destinations, in editorial order. Each one keeps exactly one card, whose
/// accessibility label and identifier are `title` (the UI tests tap `app.buttons["Index"]` …), so a
/// destination is reachable the same way whether it is today's Feature or sits in the grid.
enum ExploreDestination: String, CaseIterable, Identifiable, Sendable {
    case index, themes, lineage, vaars, constellation, insights, clock

    var id: String { rawValue }

    var route: Route {
        switch self {
        case .index: .index
        case .themes: .themes
        case .lineage: .lineage
        case .vaars: .vaars
        case .constellation: .constellation
        case .insights: .insights
        case .clock: .clock
        }
    }

    var title: String {
        switch self {
        case .index: "Index"
        case .themes: "Themes"
        case .lineage: "Lineage"
        case .vaars: "Vaars"
        case .constellation: "Constellation"
        case .insights: "Insights"
        case .clock: "Raag Clock"
        }
    }

    var symbol: String {
        switch self {
        case .index: "list.bullet"
        case .themes: "circle.grid.2x2"
        case .lineage: "person.2"
        case .vaars: "list.number"
        case .constellation: "circle.hexagongrid"
        case .insights: "chart.bar.xaxis"
        case .clock: "clock"
        }
    }

    /// Ribbons and bar runs read along a line, so they want a wide card; a dial, a sky, a dot
    /// field or a theme read as a block, so they sit two to a row.
    var prefersWide: Bool { [.index, .vaars, .insights].contains(self) }
}

/// One card in the grid: a destination and how many columns it spans.
struct ExploreCell: Equatable, Identifiable, Sendable {
    let destination: ExploreDestination
    let span: Int
    var id: String { destination.id }
}

/// Pure placement rules for the hub, unit-tested (ExploreLayoutTests): which destination is
/// today's Feature, and how the rest pack into rows.
enum ExploreLayout {

    /// Destinations that can lead the page. A destination joins once its card draws a real
    /// preview; `vaarsAvailable == false` (the DB holds no Vaars) drops the Vaars card.
    static func eligible(vaarsAvailable: Bool) -> [ExploreDestination] {
        [.index, .lineage, .vaars, .insights].filter { $0 != .vaars || vaarsAvailable }
    }

    /// Today's Feature: the day number (the Hukam's own day key, so the hub turns over with the rest
    /// of the app) indexes the eligible list. A pinned destination (DEBUG test hook) wins when
    /// eligible.
    static func feature(day: Int, eligible: [ExploreDestination], pinned: ExploreDestination? = nil) -> ExploreDestination? {
        if let pinned, eligible.contains(pinned) { return pinned }
        guard !eligible.isEmpty else { return nil }
        let n = eligible.count
        return eligible[((day % n) + n) % n]
    }

    /// Packs the destinations into rows `columns` wide. A wide card spans two columns (or the whole
    /// row when narrower); a square spans one. When the next card does not fit the room left in a
    /// row, the first later card that does is pulled forward (so squares pair up instead of each
    /// standing alone); when none does, the row's last card grows to fill it. Every row is full,
    /// every destination appears once, and the order changes only by those pulls. One column
    /// (accessibility sizes) gives one full-width card per row.
    static func pack(_ items: [ExploreDestination], columns: Int) -> [[ExploreCell]] {
        let columns = max(1, columns)
        func span(_ d: ExploreDestination) -> Int { min(d.prefersWide ? 2 : 1, columns) }
        var queue = items
        var rows: [[ExploreCell]] = []
        var row: [ExploreCell] = []
        var used = 0

        func close() {
            guard let last = row.popLast() else { return }
            row.append(ExploreCell(destination: last.destination, span: last.span + (columns - used)))
            rows.append(row)
            row = []
            used = 0
        }

        while !queue.isEmpty {
            let room = columns - used
            // An empty row takes the next card; a row already begun takes the first that fits.
            guard let i = queue.firstIndex(where: { span($0) <= room }) else { close(); continue }
            let d = queue.remove(at: i)
            row.append(ExploreCell(destination: d, span: span(d)))
            used += span(d)
            if used == columns { close() }
        }
        close()
        return rows
    }
}
