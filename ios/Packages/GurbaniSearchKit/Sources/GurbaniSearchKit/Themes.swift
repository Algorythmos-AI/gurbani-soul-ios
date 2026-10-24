import Foundation

/// One page of a theme's verses in reading order (line id), with the true total under the same
/// filter, so a screen can always say "Showing X of N" and keep loading until X == N.
/// Keyset-paged: pass `nextAfterId` back as `afterId`; it is nil on the last page.
public struct ThemePage: Sendable, Equatable {
    public let concept: String
    public let total: Int
    public let lines: [SearchLine]
    public let nextAfterId: Int?
    /// For each listed verse, the theme's words it contains (verbatim, printed order) — the
    /// reason it is listed. Every verse listed has at least one.
    public let matched: [Int: [String]]
    public init(concept: String, total: Int, lines: [SearchLine], nextAfterId: Int?, matched: [Int: [String]] = [:]) {
        self.concept = concept; self.total = total; self.lines = lines; self.nextAfterId = nextAfterId
        self.matched = matched
    }
}

/// One of a theme's Gurmukhi words with how many verses it tags (as printed, verbatim).
public struct ThemeWord: Sendable, Equatable, Identifiable {
    public let term: String
    public let n: Int
    public var id: String { term }
    public init(term: String, n: Int) { self.term = term; self.n = n }
}

/// A shabad steeped in a theme: at least `minLines` verses, at least half of which carry it.
public struct SteepedShabad: Sendable, Equatable, Identifiable {
    public let compId: Int
    public let ang: Int
    public let raag: String?
    public let author: String?
    /// Verses of the shabad that carry the theme, and its verses in all (headings excluded).
    public let n: Int
    public let total: Int
    /// The shabad's first verse, verbatim, and its line id (to open the shabad there).
    public let firstLineId: Int
    public let firstVerse: String
    public var id: Int { compId }
    public init(compId: Int, ang: Int, raag: String?, author: String?, n: Int, total: Int, firstLineId: Int, firstVerse: String) {
        self.compId = compId; self.ang = ang; self.raag = raag; self.author = author
        self.n = n; self.total = total; self.firstLineId = firstLineId; self.firstVerse = firstVerse
    }
    /// The rule, in one place: a shabad of `minLines`+ verses where half or more carry the theme.
    public static let minLines = 6
    public static func qualifies(n: Int, total: Int) -> Bool { total >= minLines && 2 * n >= total }
}

/// What narrows a theme's verses: one of its Gurmukhi words (as printed) and/or a Constellation
/// lens (voice, raag, refrains, Ang range). `.none` is the whole theme.
public struct ThemeFilter: Sendable, Equatable, Hashable {
    public var term: String?
    public var lens: ConstellationLens
    public init(term: String? = nil, lens: ConstellationLens = .none) { self.term = term; self.lens = lens }
    public static let none = ThemeFilter()
    public var isActive: Bool { self != .none }
}

/// One theme as the Themes index shows it: its verified Gurmukhi words, the headword (the form
/// that tags the most verses), honest counts, and where it falls in reading order (the same 15
/// bins of 100 Angs as the Constellation's Ang strip).
public struct ThemeIndexRow: Sendable, Equatable, Identifiable {
    public let concept: String
    public let description: String
    /// The theme's words in `concepts.gurmukhi_terms` order, verbatim.
    public let terms: [String]
    /// The theme's lead word: the first word of its printed list that tags a verse; nil if untagged.
    public let headword: String?
    public let nVerses: Int
    public let nShabads: Int
    /// Verses that are a shabad's Rahao (refrain) line.
    public let nRahao: Int
    public let angBins: [Int]
    public var id: String { concept }
    public init(concept: String, description: String, terms: [String], headword: String?,
                nVerses: Int, nShabads: Int, nRahao: Int, angBins: [Int]) {
        self.concept = concept; self.description = description; self.terms = terms; self.headword = headword
        self.nVerses = nVerses; self.nShabads = nShabads; self.nRahao = nRahao; self.angBins = angBins
    }
}

/// How many of a set of verses carry each theme (e.g. today's Hukam, or a reader's saved verses).
public struct ThemeTally: Sendable, Equatable, Identifiable {
    public let concept: String
    public let n: Int
    public var id: String { concept }
    public init(concept: String, n: Int) { self.concept = concept; self.n = n }
}

/// The theme of the day and one verse that carries it, chosen deterministically from the day.
public struct ThemeOfTheDay: Sendable, Equatable {
    public let concept: String
    public let line: SearchLine
    /// True when the verse is a Rahao line (the theme has refrains); false for a fallback verse.
    public var isRefrain: Bool { line.isRahao }
    public init(concept: String, line: SearchLine) { self.concept = concept; self.line = line }

    /// Index into the alphabetically sorted themes for a day number (`HukamOfTheDay.dayNumber`).
    public static func index(day: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return ((day % count) + count) % count
    }
}
