import Foundation
import CSQLite
import GurbaniSearchKit

/// The English records that cover several printed lines and overlap ids lo...hi, with the
/// English of each (stored on its last line). [] on a DB without `translation_spans`
/// (public profile, or a dataset before 1.4.0) — serve.py catches OperationalError the same way.
func readEnglishSpans(_ handle: OpaquePointer?, lo: Int, hi: Int) -> [EnglishSpans.Span] {
    let sql = "SELECT s.first_line_id, s.last_line_id, t.text FROM translation_spans s "
        + "JOIN translations t ON t.line_id = s.last_line_id AND t.lang = s.lang "
        + "WHERE s.lang='en' AND s.first_line_id <= ? AND s.last_line_id >= ? ORDER BY s.first_line_id"
    var stmt: OpaquePointer?
    guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
    defer { sqlite3_finalize(stmt) }
    sqlite3_bind_int64(stmt, 1, Int64(hi)); sqlite3_bind_int64(stmt, 2, Int64(lo))
    var out: [EnglishSpans.Span] = []
    var failed = false
    while stepRow(stmt, failed: &failed) {
        out.append(EnglishSpans.Span(first: Int(sqlite3_column_int64(stmt, 0)), last: Int(sqlite3_column_int64(stmt, 1)),
                                     en: sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? ""))
    }
    return failed ? [] : out
}
