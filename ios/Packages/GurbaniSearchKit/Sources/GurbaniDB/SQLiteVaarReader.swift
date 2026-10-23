import Foundation
import CSQLite
import GurbaniSearchKit

/// The full printed text of a Vaar (see `VaarText`). iOS-only read — the web serves the anatomy
/// through `vaar(id:)`, which stays pinned to the golden contract unchanged.
///
/// The run is bounded by compositions, never by `vaar_units.n_lines`: it starts at the first line
/// of the composition that holds the first unit and ends at the last line of the composition that
/// holds the last unit, so it can neither reach back into the shabad before the heading nor run on
/// into the bani after the closing pauri. Degrades to nil when the vaar tables are absent.
extension SQLiteCandidateSource {

    /// A Vaar never spans more than ~700 lines; anything far larger means the bounds are wrong.
    private static let vaarLineCap = 2_000

    public func vaarText(id: Int) -> VaarText? {
        var failed = false   // a step error discards the partial result (see SQLiteStep)

        var pauriAuthor: String?
        var head: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "SELECT pauri_author FROM vaars WHERE vaar_id=?", -1, &head, nil) == SQLITE_OK
        else { return nil }
        sqlite3_bind_int(head, 1, Int32(clamping: id))
        let found = stepRow(head, failed: &failed)
        if found, sqlite3_column_type(head, 0) != SQLITE_NULL {
            pauriAuthor = sqlite3_column_text(head, 0).map { String(cString: $0) }
        }
        sqlite3_finalize(head)
        guard found, !failed else { return nil }

        var hints: [VaarUnitHint] = []
        var us: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "SELECT kind, first_line_id, author FROM vaar_units WHERE vaar_id=? ORDER BY seq",
                                 -1, &us, nil) == SQLITE_OK else { return nil }
        sqlite3_bind_int(us, 1, Int32(clamping: id))
        while stepRow(us, failed: &failed) {
            let kind = sqlite3_column_text(us, 0).map { String(cString: $0) } ?? ""
            let author = sqlite3_column_type(us, 2) == SQLITE_NULL ? nil
                : sqlite3_column_text(us, 2).map { String(cString: $0) }
            hints.append(VaarUnitHint(kind: kind, firstLineId: Int(sqlite3_column_int64(us, 1)), author: author))
        }
        sqlite3_finalize(us)
        guard !failed, let first = hints.first, let last = hints.last else { return nil }

        var bounds: OpaquePointer?
        let boundSQL = """
        SELECT (SELECT MIN(id) FROM lines WHERE comp_id = (SELECT comp_id FROM lines WHERE id=?)),
               (SELECT MAX(id) FROM lines WHERE comp_id = (SELECT comp_id FROM lines WHERE id=?))
        """
        guard sqlite3_prepare_v2(handle, boundSQL, -1, &bounds, nil) == SQLITE_OK else { return nil }
        sqlite3_bind_int64(bounds, 1, Int64(first.firstLineId))
        sqlite3_bind_int64(bounds, 2, Int64(last.firstLineId))
        var lo = 0, hi = -1
        if stepRow(bounds, failed: &failed), sqlite3_column_type(bounds, 0) != SQLITE_NULL,
           sqlite3_column_type(bounds, 1) != SQLITE_NULL {
            lo = Int(sqlite3_column_int64(bounds, 0)); hi = Int(sqlite3_column_int64(bounds, 1))
        }
        sqlite3_finalize(bounds)
        guard !failed, lo <= first.firstLineId, last.firstLineId <= hi, hi - lo < Self.vaarLineCap else { return nil }

        var lines: [VaarLine] = []
        var ls: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "SELECT id, ang, is_header, gurmukhi FROM lines WHERE id BETWEEN ? AND ? ORDER BY id",
                                 -1, &ls, nil) == SQLITE_OK else { return nil }
        sqlite3_bind_int64(ls, 1, Int64(lo))
        sqlite3_bind_int64(ls, 2, Int64(hi))
        while stepRow(ls, failed: &failed) {
            lines.append(VaarLine(id: Int(sqlite3_column_int64(ls, 0)), ang: Int(sqlite3_column_int64(ls, 1)),
                                  isHeader: sqlite3_column_int64(ls, 2) != 0,
                                  gurmukhi: sqlite3_column_text(ls, 3).map { String(cString: $0) } ?? ""))
        }
        sqlite3_finalize(ls)
        guard !failed else { return nil }
        return VaarStructure.build(vaarId: id, pauriAuthor: pauriAuthor, lines: lines, hints: hints)
    }

    /// Every Vaar's printed text, keyed by vaar id. A Vaar whose structure cannot be proven is
    /// absent from the map (its card then opens the Ang instead of the reader).
    public func vaarTexts() -> [Int: VaarText] {
        var out: [Int: VaarText] = [:]
        for v in vaars() { if let t = vaarText(id: v.vaarId) { out[v.vaarId] = t } }
        return out
    }
}
