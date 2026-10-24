import Foundation

/// Insight-Engine read models (serve.py /api/analytics/*, /api/themes/network). All precomputed,
/// descriptive — NEVER a ranking or judgement of scripture.

public struct AuthorStat: Sendable, Equatable, Identifiable {
    public let author: String
    public let nLines: Int
    public let nShabads: Int
    public let nRaags: Int
    public let mattr100: Double      // moving-average type-token ratio (lexical diversity)
    public let avgWordsLine: Double
    public let isReliable: Bool
    public var id: String { author }
    public init(author: String, nLines: Int, nShabads: Int, nRaags: Int, mattr100: Double,
                avgWordsLine: Double, isReliable: Bool) {
        self.author = author; self.nLines = nLines; self.nShabads = nShabads; self.nRaags = nRaags
        self.mattr100 = mattr100; self.avgWordsLine = avgWordsLine; self.isReliable = isReliable
    }
}

public struct RaagStat: Sendable, Equatable, Identifiable {
    public let raag: String
    public let nLines: Int
    public let nShabads: Int
    public let nAuthors: Int
    public let dominantAuthor: String?
    public let dominantAuthorPct: Double
    public let nThemes: Int
    public var id: String { raag }
    public init(raag: String, nLines: Int, nShabads: Int, nAuthors: Int, dominantAuthor: String?,
                dominantAuthorPct: Double, nThemes: Int) {
        self.raag = raag; self.nLines = nLines; self.nShabads = nShabads; self.nAuthors = nAuthors
        self.dominantAuthor = dominantAuthor; self.dominantAuthorPct = dominantAuthorPct; self.nThemes = nThemes
    }
}

public struct ThemeEdge: Sendable, Equatable, Identifiable {
    public let source: String
    public let target: String
    public let shabadCount: Int
    public let ppmi: Double
    public let jaccard: Double
    public var id: String { "\(source)~\(target)" }
    public init(source: String, target: String, shabadCount: Int, ppmi: Double, jaccard: Double) {
        self.source = source; self.target = target; self.shabadCount = shabadCount
        self.ppmi = ppmi; self.jaccard = jaccard
    }
}

public struct ConstellationVerse: Sendable, Equatable, Identifiable {
    public let id: Int; public let ang: Int; public let compId: Int; public let gurmukhi: String
    public init(id: Int, ang: Int, compId: Int, gurmukhi: String) {
        self.id = id; self.ang = ang; self.compId = compId; self.gurmukhi = gurmukhi
    }
}
public struct ConstellationCluster: Sendable, Equatable, Identifiable {
    public let co: String; public let n: Int; public let verses: [ConstellationVerse]
    public var id: String { co }
    public init(co: String, n: Int, verses: [ConstellationVerse]) { self.co = co; self.n = n; self.verses = verses }
}
public struct ConstellationResult: Sendable, Equatable {
    public let concept: String; public let total: Int; public let clusters: [ConstellationCluster]
    public init(concept: String, total: Int, clusters: [ConstellationCluster]) {
        self.concept = concept; self.total = total; self.clusters = clusters
    }
}

public protocol AnalyticsSource: Sendable {
    /// `SELECT author,n_lines,n_shabads,n_raags,mattr_100,avg_words_line,is_reliable FROM author_analytics ORDER BY n_lines DESC`.
    func authorAnalytics() throws -> [AuthorStat]
    /// `SELECT … FROM raag_analytics ORDER BY n_lines DESC`.
    func raagAnalytics() throws -> [RaagStat]
    /// `SELECT source,target,shabad_count,ppmi,jaccard FROM theme_network WHERE source<target AND ppmi>=? ORDER BY ppmi DESC LIMIT ?`.
    func themeNetwork(minPPMI: Double, limit: Int) throws -> [ThemeEdge]
    /// A concept's verses grouped by their most-shared co-theme (top-9 clusters). serve.py constellation.
    func constellation(concept: String, author: String?, raag: String?) throws -> ConstellationResult
}

// MARK: Voices of the Granth (computed from `lines` by SQLiteCandidateSource.voicesAtlas())

/// Where one voice sings: a raag, or — after Ang 1353, where the Granth leaves the raag
/// framework — the section (`isRaag == false`, e.g. ਸਵਈਏ). Counts are verse lines.
public struct VoicePlace: Sendable, Equatable, Identifiable {
    public let name: String
    public let isRaag: Bool
    public let nLines: Int
    public let nShabads: Int
    public var id: String { name }
    public init(name: String, isRaag: Bool, nLines: Int, nShabads: Int) {
        self.name = name; self.isRaag = isRaag; self.nLines = nLines; self.nShabads = nShabads
    }
}

/// A voice's first verse line in Granth order ("begin with") — never a heading.
public struct VoiceEntry: Sendable, Equatable {
    public let compId: Int
    public let ang: Int
    public let lineId: Int
    public init(compId: Int, ang: Int, lineId: Int) { self.compId = compId; self.ang = ang; self.lineId = lineId }
}

/// The Granth as a ribbon: verse lines per voice in 143 buckets of 10 Angs, plus each voice's
/// places and entry point.
public struct VoicesAtlas: Sendable, Equatable {
    public static let bucketSize = 10
    public static let bucketCount = 143                  // 1,430 Angs / 10
    /// author → 143 verse-line counts (bucket b covers Angs 10b+1 … 10b+10).
    public let histogram: [String: [Int]]
    /// author → places, most lines first.
    public let places: [String: [VoicePlace]]
    public let entries: [String: VoiceEntry]

    public init(histogram: [String: [Int]], places: [String: [VoicePlace]], entries: [String: VoiceEntry]) {
        self.histogram = histogram; self.places = places; self.entries = entries
    }

    public static func bucket(forAng ang: Int) -> Int { min(max((ang - 1) / bucketSize, 0), bucketCount - 1) }
    public static func angs(inBucket b: Int) -> ClosedRange<Int> {
        let lo = b * bucketSize + 1
        return lo...min(lo + bucketSize - 1, 1430)
    }
    /// Verse lines in one bucket, over every voice.
    public func total(inBucket b: Int) -> Int { histogram.values.reduce(0) { $0 + ($1.indices.contains(b) ? $1[b] : 0) } }
}
