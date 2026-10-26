import Foundation
import CSQLite
import GurbaniSearchKit

/// Constellation v2 over the read-only DB — the exact serve.py SQL/logic of
/// webapp/sggs/insights.py (`_lens`, `_route_analytics_constellation` v2 fields,
/// `_route_analytics_sky`, `_route_analytics_pair`, `_route_analytics_theme`).
/// Pinned by contract/golden_constellation.ndjson (ConstellationParityTests).
extension SQLiteCandidateSource {

    enum Bind { case text(String), int(Int) }

    func bindAll(_ s: OpaquePointer?, _ binds: [Bind]) {
        for (i, b) in binds.enumerated() {
            switch b {
            case .text(let t): sqlite3_bind_text(s, Int32(i + 1), t, -1, Self.transientDtor)
            case .int(let n): sqlite3_bind_int64(s, Int32(i + 1), Int64(n))
            }
        }
    }

    func query(_ sql: String, _ binds: [Bind], _ row: (OpaquePointer?) -> Void) throws {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DBError.prepare(String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(stmt) }
        bindAll(stmt, binds)
        while try stepRow(stmt) { row(stmt) }
    }

    func cText(_ s: OpaquePointer?, _ c: Int32) -> String? {
        sqlite3_column_type(s, c) == SQLITE_NULL ? nil : (sqlite3_column_text(s, c).map { String(cString: $0) })
    }
    func cInt(_ s: OpaquePointer?, _ c: Int32) -> Int { Int(sqlite3_column_int64(s, c)) }

    /// serve.py `_lens`: the lens clamped exactly as the server clamps it, and its WHERE fragment.
    static func normalised(_ lens: ConstellationLens) -> ConstellationLens {
        let au = lens.author.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0.trimmingCharacters(in: .whitespaces) }
        let rg = lens.raag.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0.trimmingCharacters(in: .whitespaces) }
        let rgs = Array(lens.raags.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.prefix(40))
        return ConstellationLens(author: au, raag: rg, raags: rgs, rahaoOnly: lens.rahaoOnly,
                                 minThemes: max(0, min(8, lens.minThemes)),
                                 angMin: max(1, min(GranthAngs.count, lens.angMin)), angMax: max(1, min(GranthAngs.count, lens.angMax)))
    }

    func lensWhere(_ lens: ConstellationLens) -> (String, [Bind]) {
        var parts: [String] = [], binds: [Bind] = []
        if let au = lens.author { parts.append("l.author=?"); binds.append(.text(au)) }
        if let rg = lens.raag { parts.append("l.raag=?"); binds.append(.text(rg)) }
        if !lens.raags.isEmpty {
            parts.append("l.raag IN (" + Array(repeating: "?", count: lens.raags.count).joined(separator: ",") + ")")
            binds += lens.raags.map { .text($0) }
        }
        if lens.rahaoOnly { parts.append("l.is_rahao=1") }
        if lens.minThemes > 1 {
            parts.append("(SELECT COUNT(*) FROM concept_lines x WHERE x.line_id=l.id)>=?"); binds.append(.int(lens.minThemes))
        }
        if lens.angMin > 1 || lens.angMax < GranthAngs.count {
            parts.append("l.ang BETWEEN ? AND ?"); binds += [.int(lens.angMin), .int(lens.angMax)]
        }
        return (parts.isEmpty ? "" : " AND " + parts.joined(separator: " AND "), binds)
    }

    /// The Focus model: total = solo + shared, every companion with its bond, the Ang strip.
    public func constellationFocus(concept: String, lens rawLens: ConstellationLens = .none) throws -> ConstellationFocus {
        let lens = Self.normalised(rawLens)
        let (lw, lb) = lensWhere(lens)
        let whereClause = "cl.concept=?" + lw
        let binds: [Bind] = [.text(concept)] + lb
        var total = 0
        try query("SELECT COUNT(DISTINCT cl.line_id) FROM concept_lines cl JOIN lines l ON l.id=cl.line_id WHERE \(whereClause)",
                  binds) { total = cInt($0, 0) }
        let empty = Array(repeating: 0, count: ConstellationFocus.binCount)
        if total == 0 {
            return ConstellationFocus(concept: concept, lens: lens, total: 0, solo: 0, shared: 0, companions: [], angBins: empty)
        }
        var counts: [String: Int] = [:]
        var sharedIds = Set<Int>()
        try query("SELECT co.concept, l.id FROM concept_lines cl JOIN concept_lines co ON co.line_id=cl.line_id AND co.concept<>cl.concept "
                  + "JOIN lines l ON l.id=cl.line_id WHERE \(whereClause) ORDER BY co.concept, l.id", binds) { s in
            counts[cText(s, 0) ?? "", default: 0] += 1
            sharedIds.insert(cInt(s, 1))
        }
        var bonds: [String: ThemeBond] = [:]
        try query("SELECT target, ppmi, jaccard, shabad_count FROM theme_network WHERE source=?", [.text(concept)]) { s in
            bonds[cText(s, 0) ?? ""] = ThemeBond(ppmi: sqlite3_column_double(s, 1), jaccard: sqlite3_column_double(s, 2),
                                                shabadCount: cInt(s, 3))
        }
        let companions = counts.map { entry -> ConstellationCompanion in
            let b = bonds[entry.key]
            return ConstellationCompanion(co: entry.key, n: entry.value, ppmi: b?.ppmi ?? 0, jaccard: b?.jaccard ?? 0,
                                          shabadCount: b?.shabadCount ?? 0)
        }.sorted { a, b in a.n != b.n ? a.n > b.n : a.co < b.co }
        var bins = empty
        try query("SELECT l.ang FROM concept_lines cl JOIN lines l ON l.id=cl.line_id WHERE \(whereClause)", binds) { s in
            bins[min(ConstellationFocus.binCount - 1, (cInt(s, 0) - 1) / ConstellationFocus.binWidth)] += 1
        }
        return ConstellationFocus(concept: concept, lens: lens, total: total, solo: total - sharedIds.count,
                                  shared: sharedIds.count, companions: companions, angBins: bins)
    }

    /// Every theme with its verse count, and the pairs with PPMI ≥ minPPMI (clamped to 0…4).
    public func constellationSky(minPPMI: Double = 0.7) throws -> SkyGraph {
        let mp = max(0.0, min(4.0, minPPMI.isFinite ? minPPMI : 0.7))
        var nodes: [SkyNode] = []
        try query("SELECT concept, COUNT(DISTINCT line_id) n FROM concept_lines GROUP BY concept ORDER BY concept", []) { s in
            nodes.append(SkyNode(concept: cText(s, 0) ?? "", n: cInt(s, 1)))
        }
        var edges: [ThemeEdge] = []
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "SELECT source, target, shabad_count, ppmi, jaccard FROM theme_network "
                                 + "WHERE source < target AND ppmi>=? ORDER BY source, target", -1, &stmt, nil) == SQLITE_OK else {
            throw DBError.prepare(String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_double(stmt, 1, mp)
        while try stepRow(stmt) {
            edges.append(ThemeEdge(source: cText(stmt, 0) ?? "", target: cText(stmt, 1) ?? "", shabadCount: cInt(stmt, 2),
                                   ppmi: sqlite3_column_double(stmt, 3), jaccard: sqlite3_column_double(stmt, 4)))
        }
        return SkyGraph(nodes: nodes, edges: edges)
    }

    /// The verses carrying both `concept` and `with` (or, with `with == nil`, `concept` and no
    /// other theme), in reading order, grouped by shabad; `limit` clamped to 1…200.
    public func constellationPair(concept: String, with other: String?, lens rawLens: ConstellationLens = .none,
                                  offset: Int = 0, limit: Int = 50) throws -> PairPage {
        let lens = Self.normalised(rawLens)
        let (lw, lb) = lensWhere(lens)
        let off = max(0, min(100_000, offset)), lim = max(1, min(200, limit))
        let base: String, binds: [Bind], cols: String
        if let other {
            base = "FROM concept_lines ca JOIN concept_lines cb ON cb.line_id=ca.line_id AND cb.concept=? "
                + "JOIN lines l ON l.id=ca.line_id WHERE ca.concept=?\(lw)"
            binds = [.text(other), .text(concept)] + lb
            cols = "ca.term term_a, cb.term term_b"
        } else {
            base = "FROM concept_lines ca JOIN lines l ON l.id=ca.line_id WHERE ca.concept=? AND NOT EXISTS "
                + "(SELECT 1 FROM concept_lines o WHERE o.line_id=ca.line_id AND o.concept<>ca.concept)\(lw)"
            binds = [.text(concept)] + lb
            cols = "ca.term term_a, NULL term_b"
        }
        var total = 0
        try query("SELECT COUNT(*) \(base)", binds) { total = cInt($0, 0) }
        var shabads: [PairShabad] = []
        var cur: (compId: Int, ang: Int, raag: String?, author: String?, verses: [PairVerse])?
        try query("SELECT l.id, l.ang, l.comp_id, l.raag, l.author, l.is_rahao, l.gurmukhi, l.translit, \(cols) "
                  + "\(base) ORDER BY l.id LIMIT ? OFFSET ?", binds + [.int(lim), .int(off)]) { s in
            let compId = cInt(s, 2)
            let terms = other == nil ? [cText(s, 8) ?? ""] : [cText(s, 8) ?? "", cText(s, 9) ?? ""]
            let v = PairVerse(id: cInt(s, 0), ang: cInt(s, 1), isRahao: cInt(s, 5) != 0,
                              gurmukhi: cText(s, 6) ?? "", translit: cText(s, 7) ?? "", terms: terms)
            if cur?.compId == compId {
                cur?.verses.append(v)
            } else {
                if let c = cur { shabads.append(PairShabad(compId: c.compId, ang: c.ang, raag: c.raag, author: c.author, verses: c.verses)) }
                cur = (compId, v.ang, cText(s, 3), cText(s, 4), [v])
            }
        }
        if let c = cur { shabads.append(PairShabad(compId: c.compId, ang: c.ang, raag: c.raag, author: c.author, verses: c.verses)) }
        var bond: ThemeBond?
        if let other {
            try query("SELECT ppmi, jaccard, shabad_count FROM theme_network WHERE source=? AND target=?",
                      [.text(concept), .text(other)]) { s in
                bond = ThemeBond(ppmi: sqlite3_column_double(s, 0), jaccard: sqlite3_column_double(s, 1), shabadCount: cInt(s, 2))
            }
        }
        return PairPage(concept: concept, with: other, lens: lens, total: total, offset: off, bond: bond, shabads: shabads)
    }

    /// The theme card; nil for a key the corpus does not have.
    public func themeCard(concept: String) throws -> ThemeCard? {
        var found: (terms: String, description: String)?
        try query("SELECT gurmukhi_terms, description FROM concepts WHERE concept=?", [.text(concept)]) { s in
            found = (cText(s, 0) ?? "[]", cText(s, 1) ?? "")
        }
        guard let head = found else { return nil }
        let terms = (try? JSONDecoder().decode([String].self, from: Data(head.terms.utf8))) ?? []
        var counts = (0, 0, 0)
        try query("SELECT COUNT(DISTINCT cl.line_id), COUNT(DISTINCT l.comp_id), "
                  + "COUNT(DISTINCT CASE WHEN l.is_rahao=1 THEN l.id END) "
                  + "FROM concept_lines cl JOIN lines l ON l.id=cl.line_id WHERE cl.concept=?", [.text(concept)]) { s in
            counts = (cInt(s, 0), cInt(s, 1), cInt(s, 2))
        }
        func fp(_ kind: String) throws -> [ThemeConcentration] {
            var out: [ThemeConcentration] = []
            try query("SELECT entity_id, n_tagged, entity_rate, corpus_rate, lift FROM theme_fingerprint "
                      + "WHERE entity_type=? AND concept=? AND is_reliable=1 AND lift>1 "
                      + "ORDER BY lift DESC, entity_id LIMIT 5", [.text(kind), .text(concept)]) { s in
                out.append(ThemeConcentration(entityId: cText(s, 0) ?? "", nTagged: cInt(s, 1),
                                              entityRate: sqlite3_column_double(s, 2), corpusRate: sqlite3_column_double(s, 3),
                                              lift: sqlite3_column_double(s, 4)))
            }
            return out
        }
        let raags = try fp("raag"), authors = try fp("author")
        return ThemeCard(concept: concept, description: head.description, terms: terms, nVerses: counts.0,
                         nShabads: counts.1, nRahao: counts.2, raags: raags, authors: authors)
    }
}
