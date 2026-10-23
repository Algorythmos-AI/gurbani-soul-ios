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
