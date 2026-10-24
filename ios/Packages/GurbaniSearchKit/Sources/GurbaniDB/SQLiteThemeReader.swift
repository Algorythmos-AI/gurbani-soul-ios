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
        return ThemePage(concept: concept, total: total, lines: lines, nextAfterId: more ? lines.last?.id : nil)
    }
}
