import Foundation
import GurbaniSearchKit

/// The Granth's own order, as the Index shows it: the banis before the raags (Ang 1–13), the 31
/// raags (Ang 14–1353), and the banis after the raags (Ang 1353–1430). Built only from the DB's
/// `raags` and `sections` tables — the movement boundaries are read from the data, never typed in.
struct GranthMap: Equatable, Sendable {
    static let totalAngs = 1430

    /// The raags in saroop order (`seq`).
    let raags: [RaagRow]
    /// Sections that begin before the first raag.
    let opening: [SectionRow]
    /// Sections that begin at or after the last raag's final Ang.
    let closing: [SectionRow]

    init(raags: [RaagRow], sections: [SectionRow]) {
        let ordered = raags.sorted { $0.seq < $1.seq }
        self.raags = ordered
        let firstRaagAng = ordered.first?.firstAng ?? Int.max
        let bySaroop = sections.sorted { ($0.firstAng, $0.lastAng) < ($1.firstAng, $1.lastAng) }
        opening = bySaroop.filter { $0.firstAng < firstRaagAng }
        closing = bySaroop.filter { $0.firstAng >= firstRaagAng }
    }

    init(meta: CorpusMeta) { self.init(raags: meta.raags, sections: meta.sections) }

    /// "Angs 14–1353" for the raag movement; nil when there are no raags.
    var raagSpan: ClosedRange<Int>? {
        guard let a = raags.map(\.firstAng).min(), let b = raags.map(\.lastAng).max() else { return nil }
        return a...b
    }
    var openingSpan: ClosedRange<Int>? { Self.span(opening) }
    var closingSpan: ClosedRange<Int>? { Self.span(closing) }

    private static func span(_ s: [SectionRow]) -> ClosedRange<Int>? {
        guard let a = s.map(\.firstAng).min(), let b = s.map(\.lastAng).max() else { return nil }
        return a...b
    }

    /// The raag whose span holds `ang` (nil before/after the raags).
    func raag(containing ang: Int) -> RaagRow? {
        raags.first { ($0.firstAng...$0.lastAng).contains(ang) }
    }

    /// Each raag's traditional PRIMARY pahars (1–8), from the cited timing claims. Variant,
    /// seasonal and ceremonial claims are not "the hour" and are left to the Raag page / Clock.
    static func primaryPahars(_ clock: TimingClock) -> [String: [Int]] {
        guard clock.available else { return [:] }
        var out: [String: [Int]] = [:]
        for c in clock.primary {
            guard let name = c.raagName, let p = c.pahar, (1...8).contains(p) else { continue }
            if !(out[name] ?? []).contains(p) { out[name, default: []].append(p) }
        }
        return out.mapValues { $0.sorted() }
    }
}

extension ClosedRange where Bound == Int {
    /// "Ang 12" or "Angs 1–8".
    var angLabel: String {
        lowerBound == upperBound ? "Ang \(String(lowerBound))" : "Angs \(String(lowerBound))–\(String(upperBound))"
    }
}
