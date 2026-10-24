import Foundation
import CSQLite
import GurbaniSearchKit

/// Insight-Engine deep reads over the read-only DB — the exact serve.py SQL/logic for
/// /api/analytics/{author,resonance,progression,vaars,vaar}. Pinned by
/// contract/golden_analytics.ndjson. All degrade to empty when analytics tables are absent.
extension SQLiteCandidateSource {

    private func aText(_ s: OpaquePointer?, _ c: Int32) -> String? {
        sqlite3_column_type(s, c) == SQLITE_NULL ? nil : sqlite3_column_text(s, c).map { String(cString: $0) }
    }
    private func aInt(_ s: OpaquePointer?, _ c: Int32) -> Int? {
        sqlite3_column_type(s, c) == SQLITE_NULL ? nil : Int(sqlite3_column_int64(s, c))
    }

    /// serve.py:/api/analytics/author?author=X(&full=1) — stylometry + fingerprint + terms.
    public func authorProfile(_ author: String, full: Bool) -> AuthorProfile {
        var failed = false   // a step error discards the partial result (see SQLiteStep)
        var stylometry: AuthorStylometry?
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(handle,
            "SELECT author, n_lines, n_shabads, n_raags, n_tokens, mattr_100, hapax_pct, "
            + "avg_words_line, avg_lines_shabad, top_themes, is_reliable "
            + "FROM author_analytics WHERE author=?", -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, author, -1, Self.transientDtor)
            if stepRow(stmt, failed: &failed) {
                let themesJSON = aText(stmt, 9) ?? "[]"
                let themes = (try? JSONDecoder().decode([TopTheme].self, from: Data(themesJSON.utf8))) ?? []
                stylometry = AuthorStylometry(
                    author: aText(stmt, 0) ?? author,
                    nLines: aInt(stmt, 1) ?? 0, nShabads: aInt(stmt, 2) ?? 0, nRaags: aInt(stmt, 3) ?? 0,
                    nTokens: aInt(stmt, 4) ?? 0, mattr100: sqlite3_column_double(stmt, 5),
                    hapaxPct: sqlite3_column_double(stmt, 6), avgWordsLine: sqlite3_column_double(stmt, 7),
                    avgLinesShabad: sqlite3_column_double(stmt, 8),
                    topThemes: themes, isReliable: (aInt(stmt, 10) ?? 0) != 0)
            }
        }
        sqlite3_finalize(stmt)

        var fp: [FingerprintAxis] = []
        var fs: OpaquePointer?
        let fpLim: Int32 = full ? 60 : 12    // serve.py:901 — full=1 → every concept (radar axes)
        if sqlite3_prepare_v2(handle,
            "SELECT concept, n_tagged, entity_rate, corpus_rate, lift FROM theme_fingerprint "
            + "WHERE entity_type='author' AND entity_id=? ORDER BY lift DESC LIMIT ?", -1, &fs, nil) == SQLITE_OK {
            sqlite3_bind_text(fs, 1, author, -1, Self.transientDtor)
            sqlite3_bind_int(fs, 2, fpLim)
            while stepRow(fs, failed: &failed) {
                fp.append(FingerprintAxis(concept: aText(fs, 0) ?? "", nTagged: aInt(fs, 1) ?? 0,
                                          entityRate: sqlite3_column_double(fs, 2),
                                          corpusRate: sqlite3_column_double(fs, 3),
                                          lift: sqlite3_column_double(fs, 4)))
            }
        }
        sqlite3_finalize(fs)

        var terms: [DistinctiveTerm] = []
        var ts: OpaquePointer?
        if sqlite3_prepare_v2(handle,
            "SELECT term, z_score, rank FROM author_distinctive_terms "
            + "WHERE author=? ORDER BY rank LIMIT 12", -1, &ts, nil) == SQLITE_OK {
            sqlite3_bind_text(ts, 1, author, -1, Self.transientDtor)
            while stepRow(ts, failed: &failed) {
                terms.append(DistinctiveTerm(term: aText(ts, 0) ?? "",
                                             zScore: sqlite3_column_double(ts, 1),
                                             rank: aInt(ts, 2) ?? 0))
            }
        }
        sqlite3_finalize(ts)
        if failed { return AuthorProfile(author: author, stylometry: nil, fingerprint: [], distinctiveTerms: []) }
        return AuthorProfile(author: author, stylometry: stylometry, fingerprint: fp, distinctiveTerms: terms)
    }

    /// serve.py:/api/analytics/resonance — nodes ≥ minLines, edges filtered to those nodes.
    /// The strongest echoes from voice `a` to voice `b`: a's verse lines whose semantic nearest
    /// neighbours (line_neighbors) are b's verse lines, best first, at most one pair per verse of
    /// `a`. Empty when the voices never meet, on any step error, or for a == b.
    public func versePairs(from a: String, to b: String, limit: Int = 3) -> [VersePair] {
        guard a != b else { return [] }
        let sql = "SELECT la.id, la.ang, la.gurmukhi, lb.id, lb.ang, lb.gurmukhi, max(n.score) AS s "
            + "FROM lines la JOIN line_neighbors n ON n.line_id = la.id JOIN lines lb ON lb.id = n.neighbor_id "
            + "WHERE la.author = ?1 AND lb.author = ?2 AND la.is_header = 0 AND lb.is_header = 0 "
            + "GROUP BY la.id ORDER BY s DESC, la.id LIMIT ?3"
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &st, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(st) }
        sqlite3_bind_text(st, 1, a, -1, Self.transientDtor)
        sqlite3_bind_text(st, 2, b, -1, Self.transientDtor)
        sqlite3_bind_int(st, 3, Int32(clamping: max(1, min(limit, 20))))
        var failed = false
        var out: [VersePair] = []
        while stepRow(st, failed: &failed) {
            out.append(VersePair(
                a: .init(id: aInt(st, 0) ?? 0, ang: aInt(st, 1) ?? 0, gurmukhi: aText(st, 2) ?? ""),
                b: .init(id: aInt(st, 3) ?? 0, ang: aInt(st, 4) ?? 0, gurmukhi: aText(st, 5) ?? ""),
                score: sqlite3_column_double(st, 6)))
        }
        return failed ? [] : out
    }

    public func resonance(minLines: Int = 250, minLift: Double = 1.0, minEdges: Int = 8) -> ResonanceGraph {
        var failed = false   // a step error discards the partial result (see SQLiteStep)
        var nodes: [ResonanceGraph.Node] = []
        var ns: OpaquePointer?
        guard sqlite3_prepare_v2(handle,
            "SELECT name, n_lines, first_ang FROM authors WHERE n_lines >= ? ORDER BY n_lines DESC",
            -1, &ns, nil) == SQLITE_OK else { return ResonanceGraph(nodes: [], edges: []) }
        sqlite3_bind_int(ns, 1, Int32(clamping: max(1, minLines)))
        while stepRow(ns, failed: &failed) {
            nodes.append(.init(author: aText(ns, 0) ?? "", nLines: aInt(ns, 1) ?? 0, firstAng: aInt(ns, 2) ?? 0))
        }
        sqlite3_finalize(ns)
        if failed { return ResonanceGraph(nodes: [], edges: []) }
        if nodes.isEmpty { return ResonanceGraph(nodes: [], edges: []) }

        let names = nodes.map { $0.author }
        let ph = Array(repeating: "?", count: names.count).joined(separator: ",")
        let sql = "SELECT src_author, dst_author, edges, mean_score, lift FROM author_resonance "
            + "WHERE src_author <> dst_author AND lift >= ? AND edges >= ? "
            + "AND src_author IN (\(ph)) AND dst_author IN (\(ph)) ORDER BY lift DESC"
        var es: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &es, nil) == SQLITE_OK else {
            return ResonanceGraph(nodes: nodes, edges: [])
        }
        defer { sqlite3_finalize(es) }
        sqlite3_bind_double(es, 1, minLift)
        sqlite3_bind_int(es, 2, Int32(clamping: max(1, minEdges)))
        for (i, n) in names.enumerated() {
            sqlite3_bind_text(es, Int32(3 + i), n, -1, Self.transientDtor)
            sqlite3_bind_text(es, Int32(3 + names.count + i), n, -1, Self.transientDtor)
        }
        var edges: [ResonanceGraph.Edge] = []
        while stepRow(es, failed: &failed) {
            edges.append(.init(source: aText(es, 0) ?? "", target: aText(es, 1) ?? "",
                               edges: aInt(es, 2) ?? 0, meanScore: sqlite3_column_double(es, 3),
                               lift: sqlite3_column_double(es, 4)))
        }
        if failed { return ResonanceGraph(nodes: [], edges: []) }
        return ResonanceGraph(nodes: nodes, edges: edges)
    }

    /// serve.py:/api/analytics/progression — ported OPERATION-FOR-OPERATION. The binning uses
    /// Python floor division (`pos*bins//M`; Swift Int `/` matches for non-negatives) and the
    /// ang_axis uses `int((b + 0.5) * M / bins)` — the same IEEE-754 double ops in the same
    /// order, truncated toward zero. Do NOT algebraically simplify; the {8,36,80}-bin golden
    /// vectors are the referee.
    public func progression(raag: String, bins binsReq: Int = 36, top topReq: Int = 7) -> Progression? {
        var failed = false   // a step error discards the partial result (see SQLiteStep)
        var bins = max(8, min(binsReq, 80))
        let top = max(2, min(topReq, 10))

        var ordered: [(id: Int, ang: Int)] = []
        var os: OpaquePointer?
        guard sqlite3_prepare_v2(handle,
            "SELECT id, ang FROM lines WHERE raag=? ORDER BY ang, id", -1, &os, nil) == SQLITE_OK else { return nil }
        sqlite3_bind_text(os, 1, raag, -1, Self.transientDtor)
        while stepRow(os, failed: &failed) {
            ordered.append((Int(sqlite3_column_int64(os, 0)), Int(sqlite3_column_int64(os, 1))))
        }
        sqlite3_finalize(os)
        let M = ordered.count
        if M == 0 {
            return Progression(raag: raag, roman: "", nLines: 0, bins: 0, concepts: [],
                               series: [:], linesPerBin: [], angAxis: [])
        }
        bins = min(bins, M)
        var pos: [Int: Int] = [:]
        for (i, r) in ordered.enumerated() { pos[r.id] = i }
        let angs = ordered.map { $0.ang }

        var concepts: [String] = []
        var cs: OpaquePointer?
        if sqlite3_prepare_v2(handle,
            "SELECT cl.concept, COUNT(*) c FROM concept_lines cl JOIN lines l ON l.id=cl.line_id "
            + "WHERE l.raag=? GROUP BY cl.concept ORDER BY c DESC LIMIT ?", -1, &cs, nil) == SQLITE_OK {
            sqlite3_bind_text(cs, 1, raag, -1, Self.transientDtor)
            sqlite3_bind_int(cs, 2, Int32(clamping: top))
            while stepRow(cs, failed: &failed) { concepts.append(aText(cs, 0) ?? "") }
        }
        sqlite3_finalize(cs)

        var series: [String: [Int]] = [:]
        for c in concepts { series[c] = Array(repeating: 0, count: bins) }
        let cset = Set(concepts)
        var ls: OpaquePointer?
        if sqlite3_prepare_v2(handle,
            "SELECT cl.line_id, cl.concept FROM concept_lines cl JOIN lines l ON l.id=cl.line_id "
            + "WHERE l.raag=?", -1, &ls, nil) == SQLITE_OK {
            sqlite3_bind_text(ls, 1, raag, -1, Self.transientDtor)
            while stepRow(ls, failed: &failed) {
                let lid = Int(sqlite3_column_int64(ls, 0))
                let concept = aText(ls, 1) ?? ""
                if cset.contains(concept), let p = pos[lid] {
                    series[concept]![min(bins - 1, p * bins / M)] += 1
                }
            }
        }
        sqlite3_finalize(ls)

        var linesPerBin = Array(repeating: 0, count: bins)
        for i in 0..<M { linesPerBin[min(bins - 1, i * bins / M)] += 1 }
        let angAxis = (0..<bins).map { b in
            angs[min(M - 1, Int((Double(b) + 0.5) * Double(M) / Double(bins)))]
        }

        var roman = ""
        var rs: OpaquePointer?
        if sqlite3_prepare_v2(handle, "SELECT roman FROM raags WHERE name=?", -1, &rs, nil) == SQLITE_OK {
            sqlite3_bind_text(rs, 1, raag, -1, Self.transientDtor)
            if stepRow(rs, failed: &failed) { roman = aText(rs, 0) ?? "" }
        }
        sqlite3_finalize(rs)

        if failed { return nil }
        return Progression(raag: raag, roman: roman, nLines: M, bins: bins, concepts: concepts,
                           series: series, linesPerBin: linesPerBin, angAxis: angAxis)
    }

    /// serve.py:/api/analytics/vaars — the 22 Vaar summaries in first_ang order.
    public func vaars() -> [VaarSummary] {
        var failed = false   // a step error discards the partial result (see SQLiteStep)
        var out: [VaarSummary] = []
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle,
            "SELECT vaar_id, raag, roman, first_ang, last_ang, n_pauris, n_saloks, "
            + "pauri_author, salok_authors, cross_author, title FROM vaars ORDER BY first_ang",
            -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        while stepRow(stmt, failed: &failed) {
            let salokJSON = aText(stmt, 8) ?? "[]"
            let saloks = (try? JSONDecoder().decode([String].self, from: Data(salokJSON.utf8))) ?? []
            out.append(VaarSummary(
                vaarId: aInt(stmt, 0) ?? 0, raag: aText(stmt, 1), roman: aText(stmt, 2),
                firstAng: aInt(stmt, 3) ?? 0, lastAng: aInt(stmt, 4) ?? 0,
                nPauris: aInt(stmt, 5) ?? 0, nSaloks: aInt(stmt, 6) ?? 0,
                pauriAuthor: aText(stmt, 7), salokAuthors: saloks,
                crossAuthor: (aInt(stmt, 9) ?? 0) != 0, title: aText(stmt, 10)))
        }
        if failed { return [] }
        return out
    }

    /// serve.py:/api/analytics/vaar?id=N — salok + pauri anatomy in reading order.
    public func vaar(id: Int) -> VaarAnatomy {
        var failed = false   // a step error discards the partial result (see SQLiteStep)
        guard let head = vaars().first(where: { $0.vaarId == id }) else {
            return VaarAnatomy(vaar: nil, units: [])
        }
        var units: [VaarUnit] = []
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(handle,
            "SELECT seq, kind, author, n_lines, pauri_no, first_line_id, ang, theme "
            + "FROM vaar_units WHERE vaar_id=? ORDER BY seq", -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_int(stmt, 1, Int32(clamping: id))
            while stepRow(stmt, failed: &failed) {
                units.append(VaarUnit(
                    seq: aInt(stmt, 0) ?? 0, kind: aText(stmt, 1) ?? "", author: aText(stmt, 2),
                    nLines: aInt(stmt, 3) ?? 0, pauriNo: aInt(stmt, 4),
                    firstLineId: aInt(stmt, 5) ?? 0, ang: aInt(stmt, 6) ?? 0, theme: aText(stmt, 7)))
            }
        }
        sqlite3_finalize(stmt)
        if failed { return VaarAnatomy(vaar: nil, units: []) }
        return VaarAnatomy(vaar: head, units: units)
    }
}

// MARK: - Voices of the Granth (Lineage)
//
// Counts, raags, Angs and rahao verses are computed from `lines` (headers excluded), so they are
// right on every DB build. The pipeline tables (`author_facts`, `author_mentions`,
// `author_dialogues`) are optional: each reader checks sqlite_master (and the columns it needs)
// first and returns its empty value when they are absent, so the screen section hides instead
// of failing on an older DB.
extension SQLiteCandidateSource {

    /// True when `name` is a table or view in this DB.
    func hasTable(_ name: String) -> Bool {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(handle, "SELECT 1 FROM sqlite_master WHERE type IN ('table','view') AND name=?",
                                 -1, &stmt, nil) == SQLITE_OK else { return false }
        sqlite3_bind_text(stmt, 1, name, -1, Self.transientDtor)
        var failed = false
        return stepRow(stmt, failed: &failed) && !failed
    }

    /// The column names of `table` (empty when it does not exist). `table` must be a literal
    /// identifier from this file — it is spliced into a PRAGMA, never taken from input.
    func columns(of table: String) -> Set<String> {
        guard hasTable(table), table.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else { return [] }
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(handle, "PRAGMA table_info(\(table))", -1, &stmt, nil) == SQLITE_OK else { return [] }
        var out: Set<String> = []
        var failed = false
        while stepRow(stmt, failed: &failed) { if let n = aText(stmt, 1) { out.insert(n) } }
        return failed ? [] : out
    }

    /// Every voice with at least one verse: the canonical verse count, compositions, raags and
    /// the Angs they appear on. One count for the card, the page and the hero.
    public func voiceSummaries() -> [VoiceSummary] {
        var failed = false
        struct Row { var n = 0, comps = 0, raags = 0, first = 0, last = 0 }
        var rows: [String: Row] = [:]
        var order: [String] = []
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(handle,
            "SELECT author, COUNT(*), COUNT(DISTINCT comp_id), COUNT(DISTINCT NULLIF(raag,'')), MIN(ang), MAX(ang) "
            + "FROM lines WHERE is_header=0 AND author IS NOT NULL AND author<>'' "
            + "GROUP BY author ORDER BY MIN(ang), author", -1, &stmt, nil) == SQLITE_OK {
            while stepRow(stmt, failed: &failed) {
                let a = aText(stmt, 0) ?? ""
                order.append(a)
                rows[a] = Row(n: aInt(stmt, 1) ?? 0, comps: aInt(stmt, 2) ?? 0, raags: aInt(stmt, 3) ?? 0,
                              first: aInt(stmt, 4) ?? 0, last: aInt(stmt, 5) ?? 0)
            }
        }
        sqlite3_finalize(stmt)

        var angs: [String: [Int]] = [:]
        var ast: OpaquePointer?
        if sqlite3_prepare_v2(handle,
            "SELECT DISTINCT author, ang FROM lines WHERE is_header=0 AND author IS NOT NULL AND author<>''",
            -1, &ast, nil) == SQLITE_OK {
            while stepRow(ast, failed: &failed) {
                angs[aText(ast, 0) ?? "", default: []].append(aInt(ast, 1) ?? 0)
            }
        }
        sqlite3_finalize(ast)
        if failed { return [] }
        return order.compactMap { a in
            guard let r = rows[a] else { return nil }
            return VoiceSummary(author: a, nVerses: r.n, nCompositions: r.comps, nRaags: r.raags,
                                firstAng: r.first, lastAng: r.last, angs: AngSet(angs[a] ?? []))
        }
    }

    /// A voice's verses per raag, in the Granth's raag order. A raag is a signature raag when no
    /// other voice has a verse in it.
    public func authorRaags(_ author: String) -> [RaagShare] {
        var failed = false
        var out: [RaagShare] = []
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        let hasRaags = hasTable("raags")
        let sql = hasRaags
            ? "SELECT l.raag, COUNT(*), COUNT(DISTINCT l.comp_id), COALESCE(r.roman,''), "
              + "(SELECT COUNT(DISTINCT l2.author) FROM lines l2 WHERE l2.raag=l.raag AND l2.is_header=0) "
              + "FROM lines l LEFT JOIN raags r ON r.name=l.raag "
              + "WHERE l.author=? AND l.is_header=0 AND l.raag<>'' GROUP BY l.raag ORDER BY MIN(l.ang)"
            : "SELECT l.raag, COUNT(*), COUNT(DISTINCT l.comp_id), '', "
              + "(SELECT COUNT(DISTINCT l2.author) FROM lines l2 WHERE l2.raag=l.raag AND l2.is_header=0) "
              + "FROM lines l WHERE l.author=? AND l.is_header=0 AND l.raag<>'' GROUP BY l.raag ORDER BY MIN(l.ang)"
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        sqlite3_bind_text(stmt, 1, author, -1, Self.transientDtor)
        while stepRow(stmt, failed: &failed) {
            out.append(RaagShare(raag: aText(stmt, 0) ?? "", roman: aText(stmt, 3) ?? "",
                                 nVerses: aInt(stmt, 1) ?? 0, nCompositions: aInt(stmt, 2) ?? 0,
                                 isSignature: (aInt(stmt, 4) ?? 0) == 1))
        }
        return failed ? [] : out
    }

    /// The rahao verse of each of a voice's shabads (the first per composition, in Granth order),
    /// plus the total number of rahao verses.
    public func authorRahao(_ author: String, limit: Int = 80) -> RahaoDeck {
        var failed = false
        var total = 0
        var cs: OpaquePointer?
        if sqlite3_prepare_v2(handle, "SELECT COUNT(*) FROM lines WHERE author=? AND is_rahao=1 AND is_header=0",
                              -1, &cs, nil) == SQLITE_OK {
            sqlite3_bind_text(cs, 1, author, -1, Self.transientDtor)
            if stepRow(cs, failed: &failed) { total = aInt(cs, 0) ?? 0 }
        }
        sqlite3_finalize(cs)
        var verses: [VoiceVerse] = []
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(handle,
            "SELECT id, ang, comp_id, gurmukhi FROM lines WHERE id IN ("
            + "SELECT MIN(id) FROM lines WHERE author=? AND is_rahao=1 AND is_header=0 GROUP BY comp_id"
            + ") ORDER BY id LIMIT ?", -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, author, -1, Self.transientDtor)
            sqlite3_bind_int(stmt, 2, Int32(clamping: max(1, limit)))
            while stepRow(stmt, failed: &failed) { verses.append(verse(stmt)) }
        }
        sqlite3_finalize(stmt)
        return failed ? .empty : RahaoDeck(totalLines: total, verses: verses)
    }

    /// A voice's compositions in Granth order (optionally one raag only), each with its opening
    /// verse verbatim.
    public func authorCompositions(_ author: String, raag: String? = nil) -> [VoiceComposition] {
        var failed = false
        var out: [VoiceComposition] = []
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        let sql = "SELECT c.comp_id, c.ang, c.fid, c.n, l.raag, l.gurmukhi FROM ("
            + "SELECT comp_id, MIN(ang) ang, MIN(id) fid, COUNT(*) n FROM lines "
            + "WHERE author=? AND is_header=0" + (raag == nil ? "" : " AND raag=?")
            + " GROUP BY comp_id) c JOIN lines l ON l.id=c.fid ORDER BY c.fid"
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        sqlite3_bind_text(stmt, 1, author, -1, Self.transientDtor)
        if let raag { sqlite3_bind_text(stmt, 2, raag, -1, Self.transientDtor) }
        while stepRow(stmt, failed: &failed) {
            let r = aText(stmt, 4)
            out.append(VoiceComposition(compId: aInt(stmt, 0) ?? 0, ang: aInt(stmt, 1) ?? 0,
                                        firstLineId: aInt(stmt, 2) ?? 0, nVerses: aInt(stmt, 3) ?? 0,
                                        raag: (r?.isEmpty ?? true) ? nil : r, opening: aText(stmt, 5) ?? ""))
        }
        return failed ? [] : out
    }

    /// Up to `limit` verses by a voice containing `token` verbatim (how a voice signs its Bani).
    public func authorVerses(_ author: String, containing token: String, limit: Int = 3) -> [VoiceVerse] {
        guard !token.isEmpty else { return [] }
        var failed = false
        var out: [VoiceVerse] = []
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(handle,
            "SELECT id, ang, comp_id, gurmukhi FROM lines WHERE author=? AND is_header=0 "
            + "AND instr(gurmukhi, ?) > 0 ORDER BY id LIMIT ?", -1, &stmt, nil) == SQLITE_OK else { return [] }
        sqlite3_bind_text(stmt, 1, author, -1, Self.transientDtor)
        sqlite3_bind_text(stmt, 2, token, -1, Self.transientDtor)
        sqlite3_bind_int(stmt, 3, Int32(clamping: max(1, limit)))
        while stepRow(stmt, failed: &failed) { out.append(verse(stmt)) }
        return failed ? [] : out
    }

    /// `author_facts` (sggs-data, optional). Nil when the table or this voice's row is absent;
    /// a column the table lacks reads as nil.
    public func authorFacts(_ author: String) -> AuthorFacts? {
        let cols = columns(of: "author_facts")
        guard cols.contains("author") else { return nil }
        let wanted = ["n_verses", "outside_raag_verses", "chhap_count", "n_tokens", "mattr_100", "words_per_verse"]
        let select = wanted.map { cols.contains($0) ? $0 : "NULL" }.joined(separator: ", ")
        var failed = false
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(handle, "SELECT \(select) FROM author_facts WHERE author=?",
                                 -1, &stmt, nil) == SQLITE_OK else { return nil }
        sqlite3_bind_text(stmt, 1, author, -1, Self.transientDtor)
        guard stepRow(stmt, failed: &failed), !failed else { return nil }
        func dbl(_ c: Int32) -> Double? { sqlite3_column_type(stmt, c) == SQLITE_NULL ? nil : sqlite3_column_double(stmt, c) }
        return AuthorFacts(nVerses: aInt(stmt, 0), outsideRaagVerses: aInt(stmt, 1), chhapCount: aInt(stmt, 2),
                           nTokens: aInt(stmt, 3), mattr100: dbl(4), wordsPerVerse: dbl(5))
    }

    /// `author_mentions(line_id, ang, src_author, mentioned, form)` (sggs-data, optional): verses
    /// naming this voice, and verses by it naming others — verbatim from `lines`.
    public func authorMentions(_ author: String, limit: Int = 40) -> VoiceMentions {
        let cols = columns(of: "author_mentions")
        guard cols.isSuperset(of: ["src_author", "mentioned", "line_id"]) else { return .empty }
        let form = cols.contains("form") ? "m.form" : "NULL"
        var failed = false
        func read(_ keyColumn: String) -> [VoiceMention] {
            var out: [VoiceMention] = []
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(handle,
                "SELECT m.src_author, m.mentioned, \(form), l.id, l.ang, l.comp_id, l.gurmukhi FROM author_mentions m "
                + "JOIN lines l ON l.id=m.line_id WHERE m.\(keyColumn)=? AND m.src_author<>m.mentioned "
                + "ORDER BY l.id LIMIT ?", -1, &stmt, nil) == SQLITE_OK else { return [] }
            sqlite3_bind_text(stmt, 1, author, -1, Self.transientDtor)
            sqlite3_bind_int(stmt, 2, Int32(clamping: max(1, limit)))
            while stepRow(stmt, failed: &failed) {
                out.append(VoiceMention(speaker: aText(stmt, 0) ?? "", named: aText(stmt, 1) ?? "", form: aText(stmt, 2),
                                        verse: VoiceVerse(id: aInt(stmt, 3) ?? 0, ang: aInt(stmt, 4) ?? 0,
                                                          compId: aInt(stmt, 5) ?? 0, gurmukhi: aText(stmt, 6) ?? "")))
            }
            return out
        }
        let namedBy = read("mentioned"), names = read("src_author")
        return failed ? .empty : VoiceMentions(namedBy: namedBy, names: names)
    }

    /// `author_dialogues(seq, bhagat, guru, ang, bhagat_first_id, bhagat_last_id, guru_first_id,
    /// guru_last_id)` (sggs-data, optional): a Bhagat's salok and the Guru's salok set beside it,
    /// each read verbatim from `lines` by id range (headers excluded, at most 12 verses a side).
    public func authorDialogues(_ author: String, limit: Int = 30) -> [VoiceDialogue] {
        let need: Set<String> = ["seq", "bhagat", "guru", "bhagat_first_id", "bhagat_last_id", "guru_first_id", "guru_last_id"]
        guard columns(of: "author_dialogues").isSuperset(of: need) else { return [] }
        var failed = false
        struct Pair { let seq: Int; let ba: String; let b0, b1: Int; let ga: String; let g0, g1: Int }
        var pairs: [Pair] = []
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(handle,
            "SELECT seq, bhagat, bhagat_first_id, bhagat_last_id, guru, guru_first_id, guru_last_id "
            + "FROM author_dialogues WHERE bhagat=? OR guru=? ORDER BY seq LIMIT ?", -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, author, -1, Self.transientDtor)
            sqlite3_bind_text(stmt, 2, author, -1, Self.transientDtor)
            sqlite3_bind_int(stmt, 3, Int32(clamping: max(1, limit)))
            while stepRow(stmt, failed: &failed) {
                pairs.append(Pair(seq: aInt(stmt, 0) ?? 0, ba: aText(stmt, 1) ?? "",
                                  b0: aInt(stmt, 2) ?? 0, b1: aInt(stmt, 3) ?? 0, ga: aText(stmt, 4) ?? "",
                                  g0: aInt(stmt, 5) ?? 0, g1: aInt(stmt, 6) ?? 0))
            }
        }
        sqlite3_finalize(stmt)
        func verses(_ from: Int, _ to: Int) -> [VoiceVerse] {
            var out: [VoiceVerse] = []
            var vs: OpaquePointer?
            defer { sqlite3_finalize(vs) }
            guard from > 0, to >= from, sqlite3_prepare_v2(handle,
                "SELECT id, ang, comp_id, gurmukhi FROM lines WHERE id BETWEEN ? AND ? AND is_header=0 ORDER BY id LIMIT 12",
                -1, &vs, nil) == SQLITE_OK else { return [] }
            sqlite3_bind_int64(vs, 1, Int64(from))
            sqlite3_bind_int64(vs, 2, Int64(to))
            while stepRow(vs, failed: &failed) { out.append(verse(vs)) }
            return out
        }
        let out = pairs.compactMap { p -> VoiceDialogue? in
            let b = verses(p.b0, p.b1), g = verses(p.g0, p.g1)
            return b.isEmpty || g.isEmpty ? nil
                : VoiceDialogue(seq: p.seq, bhagatAuthor: p.ba, bhagat: b, guruAuthor: p.ga, guru: g)
        }
        return failed ? [] : out
    }

    /// The voices whose verses resonate most with this one's (`author_resonance`, by lift).
    public func authorEchoes(_ author: String, limit: Int = 5, minEdges: Int = 8) -> [VoiceEcho] {
        guard hasTable("author_resonance") else { return [] }
        var failed = false
        var out: [VoiceEcho] = []
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(handle,
            "SELECT dst_author, edges, lift FROM author_resonance WHERE src_author=? AND dst_author<>src_author "
            + "AND edges >= ? ORDER BY lift DESC, dst_author LIMIT ?", -1, &stmt, nil) == SQLITE_OK else { return [] }
        sqlite3_bind_text(stmt, 1, author, -1, Self.transientDtor)
        sqlite3_bind_int(stmt, 2, Int32(clamping: max(1, minEdges)))
        sqlite3_bind_int(stmt, 3, Int32(clamping: max(1, limit)))
        while stepRow(stmt, failed: &failed) {
            out.append(VoiceEcho(author: aText(stmt, 0) ?? "", edges: aInt(stmt, 1) ?? 0,
                                 lift: sqlite3_column_double(stmt, 2)))
        }
        return failed ? [] : out
    }

    /// Columns 0…3 = id, ang, comp_id, gurmukhi.
    private func verse(_ s: OpaquePointer?) -> VoiceVerse {
        VoiceVerse(id: aInt(s, 0) ?? 0, ang: aInt(s, 1) ?? 0, compId: aInt(s, 2) ?? 0, gurmukhi: aText(s, 3) ?? "")
    }
}
