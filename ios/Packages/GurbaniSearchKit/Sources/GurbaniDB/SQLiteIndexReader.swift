import Foundation
import CSQLite
import GurbaniSearchKit

/// The Index's raag and poetic-form reads (see IndexFacts.swift). Non-throwing like the other
/// optional-layer readers: a missing shabd_* layer degrades to `hasFormLayer: false` with empty
/// lists, and a step error returns nil / empty rather than a partial result.
extension SQLiteCandidateSource {

    private func iText(_ s: OpaquePointer?, _ c: Int32) -> String? {
        sqlite3_column_type(s, c) == SQLITE_NULL ? nil : sqlite3_column_text(s, c).map { String(cString: $0) }
    }
    private func iInt(_ s: OpaquePointer?, _ c: Int32) -> Int? {
        sqlite3_column_type(s, c) == SQLITE_NULL ? nil : Int(sqlite3_column_int64(s, c))
    }

    /// Runs `sql` with text binds, calling `row` per result. Returns false when the statement
    /// cannot be prepared (the table is absent); `failed` is set on a step error.
    private func eachRow(_ sql: String, _ binds: [String], failed: inout Bool,
                         _ row: (OpaquePointer?) -> Void) -> Bool {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else {
            sqlite3_finalize(stmt)
            return false
        }
        defer { sqlite3_finalize(stmt) }
        for (i, b) in binds.enumerated() { sqlite3_bind_text(stmt, Int32(i + 1), b, -1, Self.transientDtor) }
        while stepRow(stmt, failed: &failed) { row(stmt) }
        return true
    }

    /// One raag's Index facts, by Gurmukhi name or roman (case-insensitive). nil when no such
    /// raag exists or the read failed part-way.
    public func raagFacts(name: String) -> RaagFacts? {
        var failed = false
        var raag: RaagRow?
        _ = eachRow("SELECT name, roman, first_ang, last_ang, n_lines, n_shabads, seq FROM raags "
                    + "WHERE name = ? OR lower(roman) = ? LIMIT 1", [name, name.lowercased()], failed: &failed) { s in
            raag = RaagRow(name: iText(s, 0) ?? "", roman: iText(s, 1), firstAng: iInt(s, 2) ?? 0,
                           lastAng: iInt(s, 3) ?? 0, nLines: iInt(s, 4) ?? 0, nShabads: iInt(s, 5) ?? 0,
                           seq: iInt(s, 6) ?? 0)
        }
        guard let raag, !failed else { return nil }

        var voices: [RaagVoice] = []
        _ = eachRow("SELECT author, COUNT(*) AS n FROM lines WHERE raag = ? AND is_header = 0 "
                    + "AND author IS NOT NULL GROUP BY author ORDER BY n DESC, author",
                    [raag.name], failed: &failed) { s in
            if let a = iText(s, 0) { voices.append(RaagVoice(author: a, nLines: iInt(s, 1) ?? 0)) }
        }

        var firstOfForm: [String: RaagForm] = [:]
        let hasFormLayer = eachRow(
            "SELECT sf.form, m.comp_id, m.first_ang FROM shabd_structural_form sf "
            + "JOIN shabd_raag_map m ON m.comp_id = sf.comp_id "
            + "WHERE m.raag_name = ? AND sf.form IS NOT NULL ORDER BY m.first_ang, m.comp_id",
            [raag.name], failed: &failed) { s in
            guard let f = iText(s, 0), firstOfForm[f] == nil else { return }
            firstOfForm[f] = RaagForm(form: f, firstCompId: iInt(s, 1) ?? 0, firstAng: iInt(s, 2) ?? raag.firstAng)
        }
        let order = RaagFacts.formOrder
        let forms = firstOfForm.values.sorted {
            (order.firstIndex(of: $0.form) ?? order.count, $0.firstAng) < (order.firstIndex(of: $1.form) ?? order.count, $1.firstAng)
        }

        var genres: [PoeticFormEntry] = []
        _ = eachRow(
            "SELECT pg.genre, m.comp_id, m.first_ang, pg.source_label FROM shabd_poetic_genre pg "
            + "JOIN shabd_raag_map m ON m.comp_id = pg.comp_id WHERE m.raag_name = ? "
            + "ORDER BY m.first_ang, m.comp_id", [raag.name], failed: &failed) { s in
            guard let g = iText(s, 0) else { return }
            genres.append(PoeticFormEntry(genre: g, compId: iInt(s, 1) ?? 0, firstAng: iInt(s, 2) ?? 0,
                                          raag: raag.name, raagRoman: raag.roman, sourceLabel: iText(s, 3)))
        }

        var ghars: [Int] = []
        var partaal: [Int] = []
        _ = eachRow(
            "SELECT mm.ghar, mm.partaal, m.comp_id FROM shabd_musical_markers mm "
            + "JOIN shabd_raag_map m ON m.comp_id = mm.comp_id WHERE m.raag_name = ? "
            + "ORDER BY m.first_ang, m.comp_id", [raag.name], failed: &failed) { s in
            if let g = iInt(s, 0), !ghars.contains(g) { ghars.append(g) }
            if (iInt(s, 1) ?? 0) != 0, let c = iInt(s, 2) { partaal.append(c) }
        }

        if failed { return nil }
        return RaagFacts(raag: raag, voices: voices, forms: forms, genres: genres,
                         ghars: ghars.sorted(), partaalCompIds: partaal, hasFormLayer: hasFormLayer)
    }

    /// Every composition whose printed heading names a poetic genre, in Ang order. Empty when the
    /// form layer is absent or the read failed.
    public func poeticForms() -> [PoeticFormEntry] {
        var failed = false
        var out: [PoeticFormEntry] = []
        _ = eachRow(
            "SELECT pg.genre, pg.comp_id, COALESCE(m.first_ang, (SELECT MIN(ang) FROM lines l WHERE l.comp_id = pg.comp_id)), "
            + "m.raag_name, r.roman, pg.source_label FROM shabd_poetic_genre pg "
            + "LEFT JOIN shabd_raag_map m ON m.comp_id = pg.comp_id "
            + "LEFT JOIN raags r ON r.name = m.raag_name ORDER BY 3, pg.comp_id", [], failed: &failed) { s in
            guard let g = iText(s, 0), let c = iInt(s, 1) else { return }
            out.append(PoeticFormEntry(genre: g, compId: c, firstAng: iInt(s, 2) ?? 0,
                                       raag: iText(s, 3), raagRoman: iText(s, 4), sourceLabel: iText(s, 5)))
        }
        return failed ? [] : out
    }
}
