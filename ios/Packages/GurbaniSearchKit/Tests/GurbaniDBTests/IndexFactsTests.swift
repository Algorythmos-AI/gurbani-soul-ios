import XCTest
import CSQLite
@testable import GurbaniDB
@testable import GurbaniSearchKit

/// The Index facts (raag page + poetic forms) on the shipped iOS DBs: every number the Index shows
/// must equal a direct SQL count, every raag must resolve, and both profiles must agree (the form
/// layer is Gurmukhi-structural, so the public build carries it too).
final class IndexFactsTests: XCTestCase {

    private func dbPath(_ file: String) throws -> String {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<12 {
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent("contract/_meta.json").path) { break }
            dir = dir.deletingLastPathComponent()
        }
        let path = dir.appendingPathComponent("ios/Resources/\(file)").path
        guard FileManager.default.fileExists(atPath: path) else { throw XCTSkip("ios/Resources/\(file) missing") }
        return path
    }

    private func source(_ file: String = "sggs-ios.sqlite") throws -> SQLiteCandidateSource {
        try SQLiteCandidateSource(path: dbPath(file))
    }

    /// A one-integer SQL probe, so the expectations are counted independently of the reader.
    private func scalar(_ db: SQLiteCandidateSource, _ sql: String, _ bind: String? = nil) throws -> Int {
        var stmt: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(db.handle, sql, -1, &stmt, nil), SQLITE_OK, sql)
        defer { sqlite3_finalize(stmt) }
        if let bind { sqlite3_bind_text(stmt, 1, bind, -1, SQLiteCandidateSource.transientDtor) }
        XCTAssertTrue(try stepRow(stmt))
        return Int(sqlite3_column_int64(stmt, 0))
    }

    func testEveryRaagResolvesByNameAndRoman() throws {
        let db = try source()
        let meta = try db.fetchMeta()
        XCTAssertEqual(meta.raags.count, 31)
        for r in meta.raags {
            let byName = try XCTUnwrap(db.raagFacts(name: r.name), "\(r.name) did not resolve")
            XCTAssertEqual(byName.raag, r)
            let roman = try XCTUnwrap(r.roman)
            XCTAssertEqual(db.raagFacts(name: roman.uppercased())?.raag, r, "roman lookup is case-insensitive")
            XCTAssertTrue(byName.hasFormLayer)
            XCTAssertEqual(byName.ghars, byName.ghars.sorted())
            XCTAssertEqual(Set(byName.ghars).count, byName.ghars.count)
            let attributed = try scalar(db, "SELECT COUNT(*) FROM lines WHERE raag=? AND is_header=0 AND author IS NOT NULL", r.name)
            XCTAssertEqual(byName.voices.reduce(0) { $0 + $1.nLines }, attributed, "\(r.name) voice total")
            XCTAssertEqual(byName.nVerses, try scalar(db, "SELECT COUNT(*) FROM lines WHERE raag=? AND is_header=0", r.name))
            XCTAssertLessThanOrEqual(attributed, byName.nVerses)
            XCTAssertEqual(byName.voices.map(\.nLines), byName.voices.map(\.nLines).sorted(by: >))
            for g in byName.genres { XCTAssertTrue((r.firstAng...r.lastAng).contains(g.firstAng), "\(g.genre) outside \(r.name)") }
            for f in byName.forms { XCTAssertTrue((r.firstAng...r.lastAng).contains(f.firstAng), "\(f.form) outside \(r.name)") }
        }
    }

    func testRamkaliFactsMatchThePrint() throws {
        let db = try source()
        let f = try XCTUnwrap(db.raagFacts(name: "ਰਾਮਕਲੀ"))
        XCTAssertEqual(f.raag.firstAng, 876)
        XCTAssertEqual(f.raag.lastAng, 974)
        // Ramkali Sadd (Ang 923) and Ramkali Ruti (Ang 927) carry named genres in their headings.
        XCTAssertEqual(f.genres.map(\.genre), ["sadd", "ruti"])
        XCTAssertEqual(f.genres.map(\.firstAng), [923, 927])
        XCTAssertTrue(f.forms.contains { $0.form == "vaar" })
        XCTAssertEqual(f.forms.map(\.form), f.forms.map(\.form).sorted {
            RaagFacts.formOrder.firstIndex(of: $0)! < RaagFacts.formOrder.firstIndex(of: $1)!
        })
    }

    func testUnknownRaagIsNil() throws {
        let db = try source()
        XCTAssertNil(db.raagFacts(name: "not-a-raag"))
        XCTAssertNil(db.raagFacts(name: ""))
        XCTAssertNil(db.raagFacts(name: "'; DROP TABLE raags; --"))
    }

    func testPoeticFormsAreCompleteAndInAngOrder() throws {
        let db = try source()
        let all = db.poeticForms()
        XCTAssertEqual(all.count, try scalar(db, "SELECT COUNT(*) FROM shabd_poetic_genre"))
        XCTAssertEqual(Set(all.map(\.genre)).count, try scalar(db, "SELECT COUNT(DISTINCT genre) FROM shabd_poetic_genre"))
        XCTAssertEqual(all.map(\.firstAng), all.map(\.firstAng).sorted())
        XCTAssertTrue(all.allSatisfy { (1...1430).contains($0.firstAng) })
        // Both Barah Mahas: Majh (Guru Arjan Dev Ji, Ang 133) and Tukhari (Guru Nanak Dev Ji, Ang 1107).
        XCTAssertEqual(all.filter { $0.genre == "barah_maha" }.map(\.firstAng), [133, 1107])
        // After the raags a genre has no raag (Gatha, Funhe, Savaiye, Mundavani).
        XCTAssertTrue(all.filter { $0.firstAng > 1353 }.allSatisfy { $0.raag == nil })
    }

    func testPublicProfileCarriesTheSameFacts() throws {
        let personal = try source()
        let pub = try source("sggs-ios-public.sqlite")
        XCTAssertEqual(pub.poeticForms(), personal.poeticForms())
        XCTAssertEqual(pub.raagFacts(name: "ਗਉੜੀ"), personal.raagFacts(name: "ਗਉੜੀ"))
    }

    func testRaagFactsStayFast() throws {
        let db = try source()
        let start = Date()
        _ = db.raagFacts(name: "ਗਉੜੀ")   // the largest raag (196 Angs)
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.25, "Gauri facts took too long")
    }
}
