import Foundation

/// One page of a theme's verses in reading order (line id), with the true total under the same
/// filter, so a screen can always say "Showing X of N" and keep loading until X == N.
/// Keyset-paged: pass `nextAfterId` back as `afterId`; it is nil on the last page.
public struct ThemePage: Sendable, Equatable {
    public let concept: String
    public let total: Int
    public let lines: [SearchLine]
    public let nextAfterId: Int?
    public init(concept: String, total: Int, lines: [SearchLine], nextAfterId: Int?) {
        self.concept = concept; self.total = total; self.lines = lines; self.nextAfterId = nextAfterId
    }
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
    /// The word that tags the most verses (ties: the earlier word in `terms`); nil if untagged.
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
