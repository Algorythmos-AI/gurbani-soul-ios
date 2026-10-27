import Foundation
import GurbaniSearchKit

/// Everything the Explore hub states, derived from the bundled data. Pure, so every number on the
/// page is unit-tested against the shipped DB (ExploreDigestTests) — the hub never carries a typed
/// count that a DB profile or roster change could silently falsify. Nil fields mean "not loaded
/// yet": the page then says less, never a placeholder number.
struct ExploreDigest: Equatable {

    struct VoiceLines: Equatable {
        let author: String
        let lines: Int
    }

    struct VaarMark: Equatable {
        let firstAng: Int
        let lastAng: Int
        let pauriAuthor: String?
    }

    struct ContinueVaar: Equatable {
        let vaarId: Int
        /// The verbatim corpus line id the reader stopped at (resumes exactly there).
        let lineId: Int
        let raag: String
        let fraction: Double
    }

    // masthead
    let raagCount: Int?
    let voiceCount: Int?
    let angCount: Int?
    let conceptCount: Int?
    let vaarCount: Int?

    // Index
    let ribbon: RibbonLayout?
    let pins: [Int]
    let lastAng: Int?
    /// English name of the raag holding `lastAng` (nil outside the raags or when unknown).
    let lastAngRaag: String?
    /// The strip's Ang range, from the data (Ang 1 … the last Ang the works cover).
    let angRange: ClosedRange<Int>?

    // Insights: verse lines per raag, in saroop order (never sorted by size)
    let raagMass: [Int]
    /// English names, parallel to `raagMass` (for the chart's spoken descriptor).
    let raagNames: [String]

    // Lineage
    let voices: [VoiceLines]
    let centurySpan: (first: Int, last: Int)?
    let kinds: [VoiceKind]

    // Vaars
    let vaarMarks: [VaarMark]
    let continueVaar: ContinueVaar?

    init(meta: CorpusMeta?, vaars: [VaarSummary]?, roster: [Contributor]?,
         lastAng: Int?, continueVaar: (vaarId: Int, lineId: Int, fraction: Double)? = nil,
         pins: [Int] = CompositionCatalog.heroes.map(\.ang)) {
        let map = meta.map(GranthMap.init(meta:))
        let ribbon = map.map(RibbonLayout.init(map:))
        self.ribbon = (ribbon?.segments.isEmpty ?? true) ? nil : ribbon
        raagCount = map.map(\.raags.count)
        angCount = self.ribbon.map { Int($0.length.rounded()) }
        conceptCount = meta.map(\.concepts.count)
        vaarCount = vaars?.count
        voiceCount = roster?.count

        let first = self.ribbon?.segments.map(\.firstAng).min()
        let last = self.ribbon?.segments.map(\.lastAng).max()
        angRange = first.flatMap { f in last.map { f...$0 } }
        self.pins = self.ribbon == nil ? [] : pins
        self.lastAng = lastAng
        lastAngRaag = lastAng.flatMap { a in map?.raag(containing: a) }
            .map { GranthNames.raag($0.name, roman: $0.roman) ?? $0.name }

        raagMass = map?.raags.map(\.nLines) ?? []
        raagNames = map?.raags.map { GranthNames.raag($0.name, roman: $0.roman) ?? $0.name } ?? []

        // Granth order = first Ang, then volume, then name (as the Voices dot field orders them).
        voices = (meta?.authors ?? [])
            .sorted { a, b in
                a.firstAng != b.firstAng ? a.firstAng < b.firstAng
                    : a.nLines != b.nLines ? a.nLines > b.nLines : a.name < b.name
            }
            .map { VoiceLines(author: $0.name, lines: $0.nLines) }
        let years = (roster ?? []).map(\.timelineYear).filter { $0 != 9999 }
        if let lo = years.min(), let hi = years.max() {
            centurySpan = (lo / 100 + 1, hi / 100 + 1)
        } else {
            centurySpan = nil
        }
        let present = Set((roster ?? []).compactMap { VoiceKind(rawValue: $0.kind) })
        kinds = VoiceKind.allCases.filter(present.contains)

        vaarMarks = (vaars ?? []).map { VaarMark(firstAng: $0.firstAng, lastAng: $0.lastAng, pauriAuthor: $0.pauriAuthor) }
        if let c = continueVaar, let v = vaars?.first(where: { $0.vaarId == c.vaarId }) {
            self.continueVaar = ContinueVaar(vaarId: v.vaarId, lineId: c.lineId, raag: v.roman ?? v.raag ?? "",
                                             fraction: c.fraction)
        } else {
            self.continueVaar = nil
        }
    }

    static func == (a: ExploreDigest, b: ExploreDigest) -> Bool {
        a.raagCount == b.raagCount && a.voiceCount == b.voiceCount && a.angCount == b.angCount
            && a.conceptCount == b.conceptCount && a.vaarCount == b.vaarCount && a.ribbon == b.ribbon
            && a.pins == b.pins && a.lastAng == b.lastAng && a.raagMass == b.raagMass && a.raagNames == b.raagNames && a.voices == b.voices
            && a.centurySpan?.first == b.centurySpan?.first && a.centurySpan?.last == b.centurySpan?.last
            && a.kinds == b.kinds && a.vaarMarks == b.vaarMarks && a.continueVaar == b.continueVaar
    }

    // MARK: words

    /// "31 raags · 36 voices · 1,430 Angs" — only the parts already loaded.
    var mastheadLine: String {
        [raagCount.map { "\($0.formatted()) raags" },
         voiceCount.map { "\($0.formatted()) voices" },
         angCount.map { "\($0.formatted()) Angs" }]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    /// "12th–17th century", from the roster's dates.
    var centuryLabel: String? {
        guard let s = centurySpan else { return nil }
        let a = Self.ordinal(s.first), b = Self.ordinal(s.last)
        return a == b ? "\(a) century" : "\(a)–\(b) century"
    }

    /// The visible line under a card's title. Data-derived, or the shipped caption.
    func caption(_ d: ExploreDestination) -> String {
        switch d {
        case .index:
            if let a = lastAng { return "You were at Ang \(a.formatted(.number.grouping(.never)))" }
            return raagCount.map { "\($0.formatted()) raags, in the Granth's own order" } ?? Self.legacyCaption(d)
        case .themes:
            return conceptCount.map { "\($0.formatted()) concepts, every tagged verse" } ?? Self.legacyCaption(d)
        case .lineage:
            let parts = [voiceCount.map { "\($0.formatted()) voices" }, centuryLabel].compactMap { $0 }
            return parts.isEmpty ? Self.legacyCaption(d) : parts.joined(separator: " · ")
        case .vaars:
            if let c = continueVaar, !c.raag.isEmpty { return "Continue · Raag \(c.raag)" }
            return vaarCount.map { "\($0.formatted()) ballads — their voices, woven" } ?? Self.legacyCaption(d)
        case .insights:
            return raagMass.isEmpty ? Self.legacyCaption(d) : "Verse lines per raag, in the Granth's order"
        case .constellation, .clock:
            return Self.legacyCaption(d)
        }
    }

    /// What VoiceOver reads as the card's value: the facts its preview shows.
    func spokenSummary(_ d: ExploreDestination) -> String {
        switch d {
        case .index:
            var s = [raagCount.map { "\($0) raags" }, angCount.map { "\($0) Angs" }]
                .compactMap { $0 }.joined(separator: " across ")
            if let a = lastAng {
                s += (s.isEmpty ? "" : ". ") + "You last read Ang \(String(a))"
                if let r = lastAngRaag { s += ", in Raag \(r)" }
            }
            return s
        case .themes:
            return conceptCount.map { "\($0) concepts" } ?? ""
        case .lineage:
            var s = [voiceCount.map { "\($0) voices" }, centuryLabel?.replacingOccurrences(of: "–", with: " to ")]
                .compactMap { $0 }.joined(separator: ", ")
            if !kinds.isEmpty { s += (s.isEmpty ? "" : ": ") + ListFormatter.localizedString(byJoining: kinds.map(\.legend)) }
            return s
        case .vaars:
            var s = vaarCount.map { "\($0) Vaars, marked where each sits in the Granth" } ?? ""
            if let c = continueVaar, !c.raag.isEmpty {
                s += (s.isEmpty ? "" : ". ") + "Continue the Vaar in Raag \(c.raag), \(Int((c.fraction * 100).rounded())) percent"
            }
            return s
        case .insights:
            return raagMass.isEmpty ? "" : "Verse lines in each of \(raagMass.count) raags, in the Granth's order"
        case .constellation, .clock:
            return ""
        }
    }

    /// The hub's shipped captions — kept as each card's accessibility hint, and shown at
    /// accessibility sizes where previews give way to words.
    static func legacyCaption(_ d: ExploreDestination) -> String {
        switch d {
        case .index: "Raags, sections & authors — jump anywhere"
        case .themes: "Every concept, every tagged verse"
        case .lineage: "The voices of the Granth"
        case .insights: "Contributors, network, resonance & flow"
        case .constellation: "Which other themes a theme's verses carry"
        case .vaars: "The ballads — their voices, woven"
        case .clock: "Which raags are sung in this watch"
        }
    }

    private static func ordinal(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .ordinal
        return f.string(from: NSNumber(value: n)) ?? String(n)
    }
}
