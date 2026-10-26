import Foundation

/// Constellation v2 read models — serve.py /api/analytics/constellation (the Focus fields),
/// /sky, /pair and /theme, pinned by contract/golden_constellation.ndjson. Descriptive structure
/// over the verified theme tags (a verse carries a theme when it contains one of the theme's
/// Gurmukhi words), NEVER a ranking of scripture.

/// The filters every constellation read shares (serve.py `_lens`), compiled into one WHERE.
public struct ConstellationLens: Sendable, Equatable, Hashable {
    public var author: String?
    public var raag: String?
    /// The "This hour" lens: the raags whose attributed timing claim covers the current watch.
    public var raags: [String]
    public var rahaoOnly: Bool
    /// Verses carrying at least this many themes (0 or 1 = off). "Brightest stars" is 5.
    public var minThemes: Int
    public var angMin: Int
    public var angMax: Int

    public init(author: String? = nil, raag: String? = nil, raags: [String] = [], rahaoOnly: Bool = false,
                minThemes: Int = 0, angMin: Int = 1, angMax: Int = GranthAngs.count) {
        self.author = author; self.raag = raag; self.raags = raags; self.rahaoOnly = rahaoOnly
        self.minThemes = minThemes; self.angMin = angMin; self.angMax = angMax
    }
    public static let none = ConstellationLens()
    public var isActive: Bool { self != .none }
}

/// One companion theme of a Focus: how many of the centre's verses also carry it (under the
/// lens), and the corpus bond between the two themes over shabads (lens-independent).
public struct ConstellationCompanion: Sendable, Equatable, Identifiable {
    public let co: String
    public let n: Int
    public let ppmi: Double
    public let jaccard: Double
    public let shabadCount: Int
    public var id: String { co }
    public init(co: String, n: Int, ppmi: Double, jaccard: Double, shabadCount: Int) {
        self.co = co; self.n = n; self.ppmi = ppmi; self.jaccard = jaccard; self.shabadCount = shabadCount
    }
}

/// The Focus model. Additive by construction: total = solo + shared. Companion counts overlap
/// (a verse with three themes counts under two companions), which the UI says.
public struct ConstellationFocus: Sendable, Equatable {
    public let concept: String
    public let lens: ConstellationLens
    public let total: Int
    public let solo: Int
    public let shared: Int
    /// Sorted by n descending, then theme key — "Most shared".
    public let companions: [ConstellationCompanion]
    /// 15 bins of 100 Angs (the last holds Angs 1401–1430): the theme in reading order.
    public let angBins: [Int]
    public init(concept: String, lens: ConstellationLens, total: Int, solo: Int, shared: Int,
                companions: [ConstellationCompanion], angBins: [Int]) {
        self.concept = concept; self.lens = lens; self.total = total; self.solo = solo; self.shared = shared
        self.companions = companions; self.angBins = angBins
    }
    /// "Most distinctive": by PPMI (base-rate controlled), then verse count, then key.
    public var distinctive: [ConstellationCompanion] {
        companions.sorted { a, b in
            a.ppmi != b.ppmi ? a.ppmi > b.ppmi : (a.n != b.n ? a.n > b.n : a.co < b.co)
        }
    }
    public static let binCount = 15
    public static let binWidth = 100
    /// The Ang range of bin `i` (1-based, inclusive).
    public static func angRange(bin i: Int) -> ClosedRange<Int> { (i * binWidth + 1)...min(GranthAngs.count, i * binWidth + binWidth) }
}

public struct PairVerse: Sendable, Equatable, Identifiable {
    public let id: Int
    public let ang: Int
    public let isRahao: Bool
    public let gurmukhi: String
    public let translit: String
    /// The matched Gurmukhi word of each theme, in the order (concept, with); one word for `alone`.
    public let terms: [String]
    public init(id: Int, ang: Int, isRahao: Bool, gurmukhi: String, translit: String, terms: [String]) {
        self.id = id; self.ang = ang; self.isRahao = isRahao; self.gurmukhi = gurmukhi
        self.translit = translit; self.terms = terms
    }
}

/// Consecutive verses of one shabad on a page (ids are in reading order).
public struct PairShabad: Sendable, Equatable, Identifiable {
    public let compId: Int
    public let ang: Int
    public let raag: String?
    public let author: String?
    public let verses: [PairVerse]
    public var id: Int { verses.first?.id ?? compId }
    public init(compId: Int, ang: Int, raag: String?, author: String?, verses: [PairVerse]) {
        self.compId = compId; self.ang = ang; self.raag = raag; self.author = author; self.verses = verses
    }
}

public struct ThemeBond: Sendable, Equatable {
    public let ppmi: Double
    public let jaccard: Double
    public let shabadCount: Int
    public init(ppmi: Double, jaccard: Double, shabadCount: Int) {
        self.ppmi = ppmi; self.jaccard = jaccard; self.shabadCount = shabadCount
    }
}

/// One page of the verses two themes share (`with`), or of a theme's verses that carry no other
/// theme (`with == nil`, serve.py alone=1).
public struct PairPage: Sendable, Equatable {
    public let concept: String
    public let with: String?
    public let lens: ConstellationLens
    public let total: Int
    public let offset: Int
    public let bond: ThemeBond?
    public let shabads: [PairShabad]
    public init(concept: String, with: String?, lens: ConstellationLens, total: Int, offset: Int,
                bond: ThemeBond?, shabads: [PairShabad]) {
        self.concept = concept; self.with = with; self.lens = lens; self.total = total; self.offset = offset
        self.bond = bond; self.shabads = shabads
    }
    public var verseCount: Int { shabads.reduce(0) { $0 + $1.verses.count } }
}

public struct SkyNode: Sendable, Equatable, Identifiable {
    public let concept: String
    public let n: Int
    public var id: String { concept }
    public init(concept: String, n: Int) { self.concept = concept; self.n = n }
}

/// Every theme at once, and the theme pairs whose PPMI clears the threshold.
public struct SkyGraph: Sendable, Equatable {
    public let nodes: [SkyNode]
    public let edges: [ThemeEdge]
    public init(nodes: [SkyNode], edges: [ThemeEdge]) { self.nodes = nodes; self.edges = edges }
}

/// A raag or voice where a theme concentrates: lift = entity rate / corpus rate (reliable only).
public struct ThemeConcentration: Sendable, Equatable, Identifiable {
    public let entityId: String
    public let nTagged: Int
    public let entityRate: Double
    public let corpusRate: Double
    public let lift: Double
    public var id: String { entityId }
    public init(entityId: String, nTagged: Int, entityRate: Double, corpusRate: Double, lift: Double) {
        self.entityId = entityId; self.nTagged = nTagged; self.entityRate = entityRate
        self.corpusRate = corpusRate; self.lift = lift
    }
}

public struct ThemeCard: Sendable, Equatable {
    public let concept: String
    public let description: String
    /// The verified Gurmukhi words that tag the theme, verbatim.
    public let terms: [String]
    public let nVerses: Int
    public let nShabads: Int
    public let nRahao: Int
    public let raags: [ThemeConcentration]
    public let authors: [ThemeConcentration]
    public init(concept: String, description: String, terms: [String], nVerses: Int, nShabads: Int,
                nRahao: Int, raags: [ThemeConcentration], authors: [ThemeConcentration]) {
        self.concept = concept; self.description = description; self.terms = terms
        self.nVerses = nVerses; self.nShabads = nShabads; self.nRahao = nRahao
        self.raags = raags; self.authors = authors
    }
}
