import Foundation
import CSQLite
import GurbaniSearchKit

/// The Themes surface over the read-only DB. Every value is bound (`?`), never interpolated;
/// the lens fragment is the Constellation's own (`lensWhere`), so a filtered count here equals
/// the Constellation's count for the same lens.
extension SQLiteCandidateSource {

    /// Largest page a caller may ask for; anything above is clamped.
    public static let themePageMax = 500

    /// The WHERE clause (over `concept_lines cl JOIN lines l`) for a theme under a filter.
    private func themeWhere(_ concept: String, _ filter: ThemeFilter) -> (String, [Bind]) {
        let (lw, lb) = lensWhere(Self.normalised(filter.lens))
        var sql = "cl.concept=?"
        var binds: [Bind] = [.text(concept)]
        if let term = filter.term?.trimmingCharacters(in: .whitespaces), !term.isEmpty {
            sql += " AND cl.term=?"; binds.append(.text(term))
        }
        return (sql + lw, binds + lb)
    }

    /// How many distinct verses carry the theme under the filter.
    public func themeCount(concept: String, filter: ThemeFilter = .none) throws -> Int {
        let (w, b) = themeWhere(concept, filter)
        var n = 0
        try query("SELECT COUNT(DISTINCT cl.line_id) FROM concept_lines cl JOIN lines l ON l.id=cl.line_id WHERE \(w)", b) {
            n = cInt($0, 0)
        }
        return n
    }

    /// One keyset page of the theme's verses in reading order: lines with id > `afterId`
    /// (0 = from the start), at most `limit` (clamped to 1…themePageMax), plus the true total.
    public func themePage(concept: String, filter: ThemeFilter = .none, afterId: Int = 0, limit: Int = 50) throws -> ThemePage {
        let size = max(1, min(Self.themePageMax, limit))
        let total = try themeCount(concept: concept, filter: filter)
        if total == 0 { return ThemePage(concept: concept, total: 0, lines: [], nextAfterId: nil) }
        let (w, b) = themeWhere(concept, filter)
        // DISTINCT over the id-ordered join: a verse appears once even if a future dataset tags
        // it twice; one extra row tells us whether another page exists.
        let cols = Self.lineCols.split(separator: ",").map { "l." + $0.trimmingCharacters(in: .whitespaces) }.joined(separator: ", ")
        var lines: [SearchLine] = []
        try query("SELECT DISTINCT \(cols) FROM concept_lines cl JOIN lines l ON l.id=cl.line_id "
                  + "WHERE \(w) AND l.id>? ORDER BY l.id LIMIT ?", b + [.int(max(0, afterId)), .int(size + 1)]) { s in
            lines.append(mapLine(s))
        }
        let more = lines.count > size
        if more { lines.removeLast() }
        return ThemePage(concept: concept, total: total, lines: lines, nextAfterId: more ? lines.last?.id : nil,
                         matched: try matchedWords(concept: concept, lineIds: lines.map(\.id)))
    }

    /// The theme's words in its printed order (`concepts.gurmukhi_terms`), verbatim.
    private func printedTerms(_ concept: String) throws -> [String] {
        var json = "[]"
        try query("SELECT COALESCE(gurmukhi_terms,'[]') FROM concepts WHERE concept=?", [.text(concept)]) { json = cText($0, 0) ?? "[]" }
        return (try? JSONDecoder().decode([String].self, from: Data(json.utf8))) ?? []
    }

    /// Which of the theme's words each verse contains, in printed order (unlisted words last).
    private func matchedWords(concept: String, lineIds: [Int]) throws -> [Int: [String]] {
        guard !lineIds.isEmpty else { return [:] }
        let order = try printedTerms(concept)
        func rank(_ t: String) -> Int { order.firstIndex(of: t) ?? Int.max }
        var out: [Int: [String]] = [:]
        var start = 0
        while start < lineIds.count {
            let chunk = Array(lineIds[start..<min(start + 500, lineIds.count)])
            start += chunk.count
            let marks = Array(repeating: "?", count: chunk.count).joined(separator: ",")
            try query("SELECT line_id, term FROM concept_lines WHERE concept=? AND line_id IN (\(marks))",
                      [.text(concept)] + chunk.map { .int($0) }) { s in
                out[cInt(s, 0), default: []].append(cText(s, 1) ?? "")
            }
        }
        return out.mapValues { Array(Set($0)).sorted { rank($0) != rank($1) ? rank($0) < rank($1) : $0 < $1 } }
    }

    /// The theme's words with the verses each tags, in printed order; words that tag nothing are
    /// left out, and a tagged word missing from the printed list (never expected) comes last.
    public func themeWords(concept: String) throws -> [ThemeWord] {
        var counts: [String: Int] = [:]
        try query("SELECT term, COUNT(DISTINCT line_id) FROM concept_lines WHERE concept=? GROUP BY term", [.text(concept)]) { s in
            counts[cText(s, 0) ?? ""] = cInt(s, 1)
        }
        let printed = try printedTerms(concept)
        let ordered = printed + counts.keys.filter { !printed.contains($0) }.sorted()
        return ordered.compactMap { t in counts[t].map { ThemeWord(term: t, n: $0) } }
    }

    /// Shabads steeped in the theme (under the filter's word, if any): `SteepedShabad.minLines`+
    /// verses, half or more of which carry it — in reading order, never ranked.
    public func themeSteeped(concept: String, filter: ThemeFilter = .none) throws -> [SteepedShabad] {
        let (w, b) = themeWhere(concept, filter)
        let sql = """
        WITH t AS (SELECT l.comp_id AS k, COUNT(DISTINCT cl.line_id) AS n FROM concept_lines cl JOIN lines l ON l.id=cl.line_id
                   WHERE \(w) GROUP BY l.comp_id),
             s AS (SELECT comp_id AS k, COUNT(*) AS tot, MIN(id) AS first FROM lines
                   WHERE is_header=0 AND comp_id IN (SELECT k FROM t) GROUP BY comp_id)
        SELECT t.k, t.n, s.tot, s.first, f.ang, f.gurmukhi,
               (SELECT raag FROM lines WHERE comp_id=t.k AND raag IS NOT NULL ORDER BY id LIMIT 1),
               (SELECT author FROM lines WHERE comp_id=t.k AND author IS NOT NULL ORDER BY id LIMIT 1)
        FROM t JOIN s ON s.k=t.k JOIN lines f ON f.id=s.first
        WHERE s.tot>=? AND 2*t.n>=s.tot ORDER BY s.first
        """
        var out: [SteepedShabad] = []
        try query(sql, b + [.int(SteepedShabad.minLines)]) { r in
            out.append(SteepedShabad(compId: cInt(r, 0), ang: cInt(r, 4), raag: cText(r, 6), author: cText(r, 7),
                                     n: cInt(r, 1), total: cInt(r, 2), firstLineId: cInt(r, 3), firstVerse: cText(r, 5) ?? ""))
        }
        return out
    }

    /// Every theme (including any with no tagged verse) with its words, headword, counts and
    /// Ang bins, in slug order. One scan of the tags (~62k rows), aggregated here: about 5× faster
    /// than grouped SQL, and it runs once per launch.
    public func themeIndex() throws -> [ThemeIndexRow] {
        var meta: [(String, String, [String])] = []
        try query("SELECT concept, COALESCE(gurmukhi_terms,'[]'), COALESCE(description,'') FROM concepts ORDER BY concept", []) { s in
            let terms = (try? JSONDecoder().decode([String].self, from: Data((cText(s, 1) ?? "[]").utf8))) ?? []
            meta.append((cText(s, 0) ?? "", cText(s, 2) ?? "", terms))
        }
        struct Acc {
            var lines = Set<Int>(), comps = Set<Int>(), rahao = Set<Int>()
            var terms: [String: Set<Int>] = [:]
            var bins = Array(repeating: 0, count: ConstellationFocus.binCount)
        }
        var acc: [String: Acc] = [:]
        try query("SELECT cl.concept, cl.term, cl.line_id, l.ang, l.comp_id, l.is_rahao "
                  + "FROM concept_lines cl JOIN lines l ON l.id=cl.line_id", []) { s in
            let c = cText(s, 0) ?? "", id = cInt(s, 2)
            var a = acc[c] ?? Acc()
            a.terms[cText(s, 1) ?? "", default: []].insert(id)
            if a.lines.insert(id).inserted {
                let bin = max(0, min(ConstellationFocus.binCount - 1, (cInt(s, 3) - 1) / ConstellationFocus.binWidth))
                a.bins[bin] += 1
                a.comps.insert(cInt(s, 4))
                if cInt(s, 5) != 0 { a.rahao.insert(id) }
            }
            acc[c] = a
        }
        return meta.map { concept, description, terms in
            let a = acc[concept] ?? Acc()
            // the theme's own lead word: the first word of its printed list that tags a verse
            // (the most frequent word is NOT used — ਹਉਮੈ is Garab's most frequent word as well as
            // Haumai's, so two cards would carry one headword); a tagged word missing from the
            // list (never expected) is the fallback
            let headword = terms.first { (a.terms[$0]?.count ?? 0) > 0 }
                ?? a.terms.max { $0.value.count != $1.value.count ? $0.value.count < $1.value.count : $0.key > $1.key }?.key
            return ThemeIndexRow(concept: concept, description: description, terms: terms, headword: headword,
                                 nVerses: a.lines.count, nShabads: a.comps.count, nRahao: a.rahao.count, angBins: a.bins)
        }
    }

    /// The theme of the day: themes in slug order, the day number modulo their count; its verse is
    /// the theme's first Rahao line in reading order, or its first verse when it has no refrain.
    public func themeOfTheDay(day: Int) throws -> ThemeOfTheDay? {
        var slugs: [String] = []
        try query("SELECT DISTINCT concept FROM concept_lines ORDER BY concept", []) { slugs.append(cText($0, 0) ?? "") }
        guard !slugs.isEmpty else { return nil }
        let concept = slugs[ThemeOfTheDay.index(day: day, count: slugs.count)]
        let cols = Self.lineCols.split(separator: ",").map { "l." + $0.trimmingCharacters(in: .whitespaces) }.joined(separator: ", ")
        var line: SearchLine?
        try query("SELECT \(cols) FROM concept_lines cl JOIN lines l ON l.id=cl.line_id WHERE cl.concept=? "
                  + "ORDER BY l.is_rahao DESC, l.id LIMIT 1", [.text(concept)]) { line = mapLine($0) }
        return line.map { ThemeOfTheDay(concept: concept, line: $0) }
    }

    /// How many of the given verses carry each theme, most first (ties by slug). Ids are bound in
    /// chunks (SQLite caps host parameters); unknown ids simply match nothing.
    public func themeTally(lineIds: [Int]) throws -> [ThemeTally] {
        let ids = Array(Set(lineIds)).sorted()
        var tally: [String: Int] = [:]
        var start = 0
        while start < ids.count {
            let chunk = Array(ids[start..<min(start + 500, ids.count)])
            start += chunk.count
            let marks = Array(repeating: "?", count: chunk.count).joined(separator: ",")
            try query("SELECT concept, COUNT(DISTINCT line_id) FROM concept_lines WHERE line_id IN (\(marks)) GROUP BY concept",
                      chunk.map { .int($0) }) { s in tally[cText(s, 0) ?? "", default: 0] += cInt(s, 1) }
        }
        return tally.map { ThemeTally(concept: $0.key, n: $0.value) }
            .sorted { $0.n != $1.n ? $0.n > $1.n : $0.concept < $1.concept }
    }
}
