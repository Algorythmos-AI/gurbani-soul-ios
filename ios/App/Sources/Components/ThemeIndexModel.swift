import Foundation
import GurbaniSearchKit

/// Pure helpers behind the Themes index: search, arrangement, the one-line gloss, and the phrase
/// that says where a theme concentrates in reading order. No view state, so every rule is tested.
enum ThemeIndexModel {

    enum Arrangement: String, CaseIterable, Identifiable {
        case family, alphabetical, size
        var id: String { rawValue }
        var title: String {
            switch self {
            case .family: "By family"
            case .alphabetical: "A to Z"
            case .size: "By number of verses"
            }
        }
    }

    /// The local calendar day number the Today hero is drawn for — the same day the Hukam of the
    /// day uses, so the two always agree and both turn over at local midnight.
    static func dayNumber(_ date: Date, calendar: Calendar = .current) -> Int {
        HukamOfTheDay.dayNumber(of: date, calendar: calendar)
    }

    // MARK: search

    /// Case-, diacritic- and width-insensitive fold for Roman text ("Kāl" == "kal"), NFC first so
    /// a decomposed Gurmukhi query compares equal to the stored words.
    static func fold(_ s: String) -> String {
        s.precomposedStringWithCanonicalMapping
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func isGurmukhi(_ s: String) -> Bool {
        s.unicodeScalars.contains { (0x0A00...0x0A7F).contains($0.value) }
    }

    /// Themes matching a query, best first: name starts with it, then name contains it; for a
    /// Gurmukhi word, the theme whose headword it is, then themes that list it as one of their
    /// words, then words that contain it; then the description. Stable within each tier (the
    /// incoming order). An empty query matches nothing (the caller shows the full index instead).
    /// (A word can belong to several themes — ਹਉਮੈ is one of Garab's words too — so the theme it
    /// heads comes first.)
    static func search(_ rows: [ThemeIndexRow], _ query: String) -> [ThemeIndexRow] {
        let q = fold(query)
        guard !q.isEmpty else { return [] }
        let gurmukhi = isGurmukhi(q)
        func tier(_ r: ThemeIndexRow) -> Int? {
            let name = fold(ConceptName.display(r.concept))
            let slug = fold(r.concept.replacingOccurrences(of: "_", with: " "))
            if !gurmukhi {
                if name.hasPrefix(q) || slug.hasPrefix(q) { return 0 }
                if name.contains(q) || slug.contains(q) { return 1 }
            }
            if let head = r.headword, fold(head) == q { return 2 }
            if r.terms.contains(where: { fold($0) == q }) { return 3 }
            if r.terms.contains(where: { fold($0).contains(q) }) { return 4 }
            if fold(r.description).contains(q) { return 5 }
            return nil
        }
        return rows.enumerated()
            .compactMap { i, r in tier(r).map { (t: $0, i: i, r: r) } }
            .sorted { $0.t != $1.t ? $0.t < $1.t : $0.i < $1.i }
            .map(\.r)
    }

    // MARK: arrangement

    /// Size order is by verse count (most first), ties by name — labelled as a count, never rank.
    static func arranged(_ rows: [ThemeIndexRow], _ a: Arrangement) -> [ThemeIndexRow] {
        switch a {
        case .family, .alphabetical:
            return rows.sorted { ConceptName.display($0.concept) < ConceptName.display($1.concept) }
        case .size:
            return rows.sorted { $0.nVerses != $1.nVerses ? $0.nVerses > $1.nVerses
                                 : ConceptName.display($0.concept) < ConceptName.display($1.concept) }
        }
    }

    /// The six groups in order, each with its themes in the group's own order; any theme no group
    /// names lands in a trailing "More Themes" group, so a theme is never dropped.
    static func grouped(_ rows: [ThemeIndexRow]) -> [(group: ThemeGroup?, rows: [ThemeIndexRow])] {
        let byKey = Dictionary(rows.map { ($0.concept, $0) }, uniquingKeysWith: { a, _ in a })
        var out: [(group: ThemeGroup?, rows: [ThemeIndexRow])] = ThemeGroup.all.compactMap { g in
            let r = g.keys.compactMap { byKey[$0] }
            return r.isEmpty ? nil : (g, r)
        }
        let placed = Set(ThemeGroup.all.flatMap(\.keys))
        let leftover = rows.filter { !placed.contains($0.concept) }
        if !leftover.isEmpty { out.append((nil, leftover)) }
        return out
    }

    // MARK: text

    /// The description's opening phrase: up to its first " — ", "; ", ": " or ". " (the house style
    /// puts the gloss first), whichever comes first. Embedded Gurmukhi stays verbatim.
    static func gloss(_ description: String) -> String {
        let d = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let cut = [" — ", " – ", "; ", ": ", ". "].compactMap { d.range(of: $0)?.lowerBound }
            .filter { d.distance(from: d.startIndex, to: $0) >= 3 }
            .min()
        if let cut { return d[..<cut].trimmingCharacters(in: .whitespaces) }
        return d.hasSuffix(".") ? String(d.dropLast()) : d
    }

    /// "Most in Angs 1101–1200" — the 100-Ang stretch with the most verses (earliest on a tie);
    /// nil when the theme tags nothing.
    static func peakPhrase(_ bins: [Int]) -> String? {
        guard let peak = bins.max(), peak > 0, let i = bins.firstIndex(of: peak) else { return nil }
        let r = ConstellationFocus.angRange(bin: i)
        return "Most in Angs \(r.lowerBound)–\(r.upperBound)"
    }

    /// The VoiceOver summary of a card: the counts a sighted reader gets from the card's text.
    static func accessibilitySummary(_ r: ThemeIndexRow) -> String {
        var parts = [ConceptName.display(r.concept)]
        if let head = r.headword { parts.append(head) }          // VoiceOver reads it in Punjabi
        parts.append("\(r.nVerses.formatted()) \(r.nVerses == 1 ? "verse" : "verses") in \(r.nShabads.formatted()) \(r.nShabads == 1 ? "shabad" : "shabads")")
        if let p = peakPhrase(r.angBins) { parts.append(p.prefix(1).lowercased() + p.dropFirst()) }
        let g = gloss(r.description)
        if !g.isEmpty { parts.append(g) }
        return parts.joined(separator: ", ")
    }
}
