import XCTest
import CSQLite
@testable import GurbaniDB
@testable import GurbaniSearchKit

/// The printed structure of the 22 Vaars on the shipped iOS DB. Every count below was read from
/// the print — label lines and the ॥N॥ each pauri closes with — and is pinned so a DB rebuild that
/// moves a boundary fails here, not on a reader's screen.
final class VaarTextTests: XCTestCase {

    private func dbPath() throws -> String {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<12 {
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent("contract/_meta.json").path) { break }
            dir = dir.deletingLastPathComponent()
        }
        let path = dir.appendingPathComponent("ios/Resources/sggs-ios.sqlite").path
        guard FileManager.default.fileExists(atPath: path) else {
            throw XCTSkip("ios/Resources/sggs-ios.sqlite missing — run pipeline/build_ios_db.py")
        }
        return path
    }

    private func source() throws -> SQLiteCandidateSource { try SQLiteCandidateSource(path: try dbPath()) }

    /// vaar_id → (pauris, saloks), as printed.
    private let printed: [Int: (Int, Int)] = [
        1: (21, 43), 2: (27, 63), 3: (33, 68), 4: (21, 42), 5: (24, 59), 6: (22, 44), 7: (21, 42),
        8: (21, 42), 9: (21, 43), 10: (29, 58), 11: (20, 20), 12: (20, 47), 13: (13, 27), 14: (21, 52),
        15: (22, 44), 16: (8, 0), 17: (22, 47), 18: (23, 69), 19: (3, 0), 20: (36, 74), 21: (28, 58),
        22: (15, 30),
    ]

    /// vaar_id → the line id of its ਧੁਨੀ / ਧੁਨਿ rubric.
    private let dhuni: [Int: Int] = [2: 5618, 4: 14499, 5: 20885, 6: 22758, 9: 25685, 14: 40605,
                                     20: 53198, 21: 54912, 22: 56249]

    func testEveryVaarBuildsWithItsPrintedCounts() throws {
        let db = try source()
        let texts = db.vaarTexts()
        XCTAssertEqual(texts.count, 22, "a Vaar failed to build: missing \(Set(1...22).subtracting(texts.keys).sorted())")
        var pauris = 0, saloks = 0
        for (id, want) in printed {
            let t = try XCTUnwrap(texts[id], "vaar \(id)")
            XCTAssertEqual(t.nPauris, want.0, "vaar \(id) pauris")
            XCTAssertEqual(t.nSaloks, want.1, "vaar \(id) saloks")
            XCTAssertEqual(t.pauris.map { $0.pauriNo }, Array(1...want.0).map { Optional($0) }, "vaar \(id) pauri numbering")
            pauris += t.nPauris; saloks += t.nSaloks
        }
        XCTAssertEqual(pauris, 471)
        XCTAssertEqual(saloks, 972)
    }

    func testHeadingIsTheVaarTitleNeverTheInvocation() throws {
        let db = try source()
        for (id, t) in db.vaarTexts() {
            XCTAssertFalse(t.titleLines.isEmpty, "vaar \(id): no title")
            XCTAssertTrue(t.titleLines.allSatisfy { !VaarStructure.isInvocation($0.gurmukhi) }, "vaar \(id)")
            XCTAssertTrue(t.titleLines.contains { $0.gurmukhi.contains("ਵਾਰ") }, "vaar \(id): title has no ਵਾਰ")
        }
        // the four the vaars table mis-titles with the invocation
        let texts = db.vaarTexts()
        XCTAssertEqual(texts[1]?.titleLines.map(\.id), [3300])
        XCTAssertEqual(texts[5]?.titleLines.map(\.id), [20884, 20885])
        XCTAssertEqual(texts[12]?.titleLines.map(\.id), [33503])
        XCTAssertEqual(texts[14]?.titleLines.map(\.id), [40604, 40605])
    }

    func testExactlyNineDhunis() throws {
        let got = try source().vaarTexts().compactMapValues { $0.dhuni?.id }
        XCTAssertEqual(got, dhuni)
    }

    /// Complete or not at all: the heading and units tile the run with no gap, no overlap, and
    /// every string is the corpus line byte for byte.
    func testUnitsTileTheRunVerbatim() throws {
        let path = try dbPath()
        let db = try SQLiteCandidateSource(path: path)
        var raw: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(path, &raw, SQLITE_OPEN_READONLY, nil), SQLITE_OK)
        defer { sqlite3_close(raw) }
        for (id, t) in db.vaarTexts() {
            let all = t.heading + t.units.flatMap(\.lines)
            let ids = all.map(\.id)
            XCTAssertEqual(ids, Array(ids.first!...ids.last!), "vaar \(id): gap or overlap")
            for line in all {
                var s: OpaquePointer?
                sqlite3_prepare_v2(raw, "SELECT gurmukhi, ang FROM lines WHERE id=?", -1, &s, nil)
                sqlite3_bind_int64(s, 1, Int64(line.id))
                XCTAssertEqual(sqlite3_step(s), SQLITE_ROW)
                let g = String(cString: sqlite3_column_text(s, 0))
                XCTAssertTrue(g.utf8.elementsEqual(line.gurmukhi.utf8), "vaar \(id) line \(line.id) differs")
                XCTAssertEqual(Int(sqlite3_column_int64(s, 1)), line.ang)
                sqlite3_finalize(s)
            }
            XCTAssertTrue(t.units.allSatisfy { !$0.verse.isEmpty }, "vaar \(id): empty unit")
        }
    }

    func testEverySalokHasAVoice() throws {
        for (id, t) in try source().vaarTexts() {
            for u in t.units { XCTAssertNotNil(u.author, "vaar \(id) unit \(u.index) has no author") }
        }
    }

    func testRunsStayInsideTheirVaar() throws {
        let db = try source()
        let texts = db.vaarTexts()
        // Maru M3's last pauri closes with ॥੨੨॥੧॥ and ਸੁਧੁ ॥ — and nothing of Maru M5 after it.
        XCTAssertEqual(texts[17]?.units.last?.lines.last?.id, 46990)
        XCTAssertEqual(texts[18]?.heading.first?.id, 46991)
        // Kanara ends at ਸੁਧੁ ॥ on Ang 1318, before Namdev ji's shabad.
        XCTAssertEqual(texts[22]?.units.last?.lines.last?.id, 56482)
        // Ramkali M3: the ਧੁਨੀ belongs to the heading, the first salok starts at its label.
        XCTAssertEqual(texts[14]?.units.first?.label?.id, 40606)
        for v in db.vaars() {
            let t = try XCTUnwrap(texts[v.vaarId])
            XCTAssertEqual(t.firstAng, v.firstAng, "vaar \(v.vaarId) first Ang")
            XCTAssertTrue((v.lastAng...v.lastAng + 1).contains(t.lastAng), "vaar \(v.vaarId) last Ang \(t.lastAng)")
        }
    }

    func testUnknownVaarIsNil() throws {
        let db = try source()
        XCTAssertNil(db.vaarText(id: 0))
        XCTAssertNil(db.vaarText(id: 23))
        XCTAssertNil(db.vaarText(id: -1))
    }
}
