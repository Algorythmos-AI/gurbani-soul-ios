import Foundation
import GurbaniSearchKit
import GurbaniDB

/// Serializes all access to the read-only corpus DB + the search/verify engines, returning only
/// Sendable value types. The single boundary where SQLite is touched (the handle is not
/// thread-safe; the actor makes it correct under Swift 6 strict concurrency).
actor CorpusActor {
    private let db: SQLiteCandidateSource
    private let searchEngine: SearchEngine
    private let verifyEngine: VerifyEngine
    /// Bundle path of the corpus DB (read-only; safe to read off the actor for the integrity hash).
    nonisolated let dbPath: String
    /// The linked (pinned) SQLite version — provenance, safe to read off-actor.
    nonisolated var sqliteVersion: String { SQLiteCandidateSource.sqliteVersion }
    /// Which optional layers this DB build carries (English/timing) — detected from
    /// sqlite_master at init, immutable, Sendable → safe to read off-actor. UI surfaces gate
    /// on these bits so the public (Gurmukhi-only) profile degrades to today's behavior.
    nonisolated let capabilities: CorpusCapabilities
    private var vaarTextCache: [Int: VaarText]?

    enum CorpusError: LocalizedError {
        case databaseMissing
        var errorDescription: String? { "Scripture database not found in the app bundle." }
    }

    init() throws {
        guard let url = Bundle.main.url(forResource: "sggs-ios", withExtension: "sqlite") else {
            throw CorpusError.databaseMissing
        }
        self.dbPath = url.path
        self.db = try SQLiteCandidateSource(path: url.path)
        self.searchEngine = SearchEngine(source: db)
        self.verifyEngine = VerifyEngine(source: db)
        self.capabilities = db.detectCapabilities()
    }

    func search(_ q: String, mode: String, limit: Int = 50, offset: Int = 0) throws -> SearchOutput {
        let out = try searchEngine.search(q, mode: mode, limit: limit, offset: offset)
        // serve.py:798 — en attaches to EVERY search mode's results (no-op on the public profile)
        return SearchOutput(mode: out.mode, results: db.attachTranslations(out.results),
                            concept: out.concept, relatedThemes: out.relatedThemes)
    }
    func verify(_ claim: String, ang: Int?) throws -> VerifyResult { try verifyEngine.verify(claim: claim, ang: ang) }
    /// English of one line (display layer — e.g. under the verify verdict's canonical line).
    func english(forLine id: Int) throws -> String? { db.english(forLine: id) }
    func ang(_ n: Int) throws -> AngPage { try db.fetchAng(n) }
    func shabad(compId: Int) throws -> Shabad { try db.fetchShabad(compId: compId) }
    func randomHukam() throws -> HukamUnit { try db.hukamUnit(seed: db.randomSeedCompId()) }
    /// The Hukam of the day for a day number (`HukamOfTheDay.dayNumber`): the same unit all day.
    func hukamOfTheDay(day: Int) throws -> HukamUnit { try db.hukamUnit(seed: db.hukamOfTheDaySeed(day: day)) }
    func meta() throws -> CorpusMeta { try db.fetchMeta() }
    func neighbors(lineId: Int, limit: Int = 12) throws -> NeighborsResult { try db.neighbors(lineId: lineId, limit: limit) }
    func authorAnalytics() throws -> [AuthorStat] { try db.authorAnalytics() }
    func raagAnalytics() throws -> [RaagStat] { try db.raagAnalytics() }
    func themeNetwork(minPPMI: Double = 0.7, limit: Int = 40) throws -> [ThemeEdge] { try db.themeNetwork(minPPMI: minPPMI, limit: limit) }
    func constellation(concept: String, author: String? = nil, raag: String? = nil) throws -> ConstellationResult {
        try db.constellation(concept: concept, author: author, raag: raag)
    }
    // Constellation v2 (serve.py /api/analytics/constellation v2 fields, /sky, /pair, /theme).
    func constellationFocus(concept: String, lens: ConstellationLens = .none) throws -> ConstellationFocus {
        try db.constellationFocus(concept: concept, lens: lens)
    }
    func constellationSky(minPPMI: Double = 0.7) throws -> SkyGraph { try db.constellationSky(minPPMI: minPPMI) }
    func constellationPair(concept: String, with other: String?, lens: ConstellationLens = .none,
                           offset: Int = 0, limit: Int = 50) throws -> PairPage {
        try db.constellationPair(concept: concept, with: other, lens: lens, offset: offset, limit: limit)
    }
    func themeCard(concept: String) throws -> ThemeCard? { try db.themeCard(concept: concept) }
    // Insight-Engine deep reads (Lineage profiles, chord, streamgraph, vaar anatomy).
    func authorProfile(_ author: String, full: Bool = false) -> AuthorProfile { db.authorProfile(author, full: full) }
    func resonance(minLines: Int = 250, minLift: Double = 1.0, minEdges: Int = 8) -> ResonanceGraph {
        db.resonance(minLines: minLines, minLift: minLift, minEdges: minEdges)
    }
    func progression(raag: String, bins: Int = 36, top: Int = 7) -> Progression? {
        db.progression(raag: raag, bins: bins, top: top)
    }
    func vaars() -> [VaarSummary] { db.vaars() }
    func vaar(id: Int) -> VaarAnatomy { db.vaar(id: id) }
    /// The 22 Vaars' printed text (heading, saloks and pauris), built once and kept: ~9k lines,
    /// read by the Vaars home (voice strips) and every Vaar screen. A Vaar whose structure cannot
    /// be proven is absent — its screens fall back to opening the Ang.
    func vaarTexts() -> [Int: VaarText] {
        if let vaarTextCache { return vaarTextCache }
        let built = db.vaarTexts()
        vaarTextCache = built
        return built
    }
    func vaarText(id: Int) -> VaarText? { vaarTexts()[id] }

    // Raag-Timing layer (v2.12.0) — attributed claims with citations, never facts.
    func timingClock() -> TimingClock { db.timingClock() }
    func timingRaag(name: String) -> RaagTiming { db.timingRaag(name: name) }
    func timingDivergence() -> TimingDivergence { db.timingDivergence() }
    func forms(compId: Int) -> ShabadForms { db.forms(compId: compId) }
    /// The Index: one raag's page facts (nil = no such raag) and the named poetic forms.
    func raagFacts(name: String) -> RaagFacts? { db.raagFacts(name: name) }
    func poeticForms() -> [PoeticFormEntry] { db.poeticForms() }

    // Nitnem / Gutka registry (v1.2.0, ADR-0006) — pointers into the verbatim corpus plus a
    // separate labelled non-SGGS layer. Gated by `capabilities.hasBanis`.
    func banis() -> BaniList { db.fetchBanis() }
    func bani(key: String, variant: String = "") -> Bani? { db.fetchBani(key: key, variant: variant) }

    private var cachedThemeIndex: [ThemeIndexRow]?
    /// The 54 themes with words, headword, counts and Ang bins — computed once, then cached (the
    /// DB is immutable for the life of the process).
    func themeIndex() throws -> [ThemeIndexRow] {
        if let cachedThemeIndex { return cachedThemeIndex }
        let rows = try db.themeIndex()
        cachedThemeIndex = rows
        return rows
    }
    func themeOfTheDay(day: Int) throws -> ThemeOfTheDay? { try db.themeOfTheDay(day: day) }
    func themeTally(lineIds: [Int]) throws -> [ThemeTally] { try db.themeTally(lineIds: lineIds) }
    /// The themes today's Hukam carries (its verses only, never its headings).
    func hukamThemes(day: Int) throws -> [ThemeTally] {
        let unit = try db.hukamUnit(seed: db.hukamOfTheDaySeed(day: day))
        return try db.themeTally(lineIds: unit.lines.filter { !$0.isHeader }.map(\.id))
    }

    /// One keyset page of a theme's verses in reading order, with the true total under the same
    /// filter (the card's count and the list's end always agree).
    func themePage(_ concept: String, filter: ThemeFilter = .none, afterId: Int = 0, limit: Int = 50) throws -> ThemePage {
        let p = try db.themePage(concept: concept, filter: filter, afterId: afterId, limit: limit)
        return ThemePage(concept: p.concept, total: p.total, lines: db.attachTranslations(p.lines), nextAfterId: p.nextAfterId,
                         matched: p.matched)
    }
    func themeCount(_ concept: String, filter: ThemeFilter = .none) throws -> Int { try db.themeCount(concept: concept, filter: filter) }
    func themeWords(_ concept: String) throws -> [ThemeWord] { try db.themeWords(concept: concept) }
    func themeAngBins(_ concept: String, filter: ThemeFilter = .none) throws -> [Int] { try db.themeAngBins(concept: concept, filter: filter) }
    func themeSteeped(_ concept: String, filter: ThemeFilter = .none) throws -> [SteepedShabad] {
        try db.themeSteeped(concept: concept, filter: filter)
    }
}
