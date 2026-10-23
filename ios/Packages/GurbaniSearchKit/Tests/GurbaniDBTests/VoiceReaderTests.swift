import XCTest
import CSQLite
@testable import GurbaniDB
@testable import GurbaniSearchKit

/// Lineage ("Voices of the Granth") readers. Against the shipped iOS DB: one canonical count
/// (headers excluded) that agrees with author_analytics, Ang sets that match the corpus, signature
/// raags. Against tiny throwaway DBs: a DB without the optional pipeline tables yields empty
/// results (the section hides), and a DB with them yields verbatim verses.
final class VoiceReaderTests: XCTestCase {

    private func repoRoot() -> URL {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<12 {
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent("contract/_meta.json").path) { return dir }
            dir = dir.deletingLastPathComponent()
        }
        return URL(fileURLWithPath: #filePath)
    }

    private func shippedDB() throws -> SQLiteCandidateSource {
        let path = repoRoot().appendingPathComponent("ios/Resources/sggs-ios.sqlite").path
        guard FileManager.default.fileExists(atPath: path) else {
            throw XCTSkip("ios/Resources/sggs-ios.sqlite missing — run make ios-db-repair")
        }
        return try SQLiteCandidateSource(path: path)
    }

    /// One raw scalar query against the same DB (the referee for the reader's own SQL).
    private func scalar(_ db: SQLiteCandidateSource, _ sql: String, _ bind: String? = nil) -> Int {
        var s: OpaquePointer?
        defer { sqlite3_finalize(s) }
        guard sqlite3_prepare_v2(db.handle, sql, -1, &s, nil) == SQLITE_OK else { return -1 }
        if let bind { sqlite3_bind_text(s, 1, bind, -1, SQLiteCandidateSource.transientDtor) }
        return (try? stepRow(s)) == true ? Int(sqlite3_column_int64(s, 0)) : -1
    }

    // MARK: shipped DB

    func testOneCanonicalCountMatchesAuthorAnalytics() throws {
        let db = try shippedDB()
        let voices = db.voiceSummaries()
        XCTAssertGreaterThanOrEqual(voices.count, 29)   // 29 today (Baba Sundar Ji's Sadu awaits the sggs-data fix)
        for v in voices {
            let analytics = scalar(db, "SELECT n_lines FROM author_analytics WHERE author=?", v.author)
            XCTAssertGreaterThanOrEqual(analytics, 0, "\(v.author): no author_analytics row")
            XCTAssertEqual(v.nVerses, analytics, "\(v.author): card and page must show the same count")
            XCTAssertEqual(v.angs.count,
                           scalar(db, "SELECT COUNT(DISTINCT ang) FROM lines WHERE is_header=0 AND author=?", v.author),
                           "\(v.author): barcode bits = distinct Angs")
            XCTAssertTrue(v.angs.contains(v.firstAng) && v.angs.contains(v.lastAng))
        }
    }

    func testGuruTeghBahadurJi() throws {
        let db = try shippedDB()
        let m9 = try XCTUnwrap(db.voiceSummaries().first { $0.author == "Guru Tegh Bahadur Ji (M9)" })
        XCTAssertEqual(m9.nVerses, scalar(db, "SELECT COUNT(*) FROM lines WHERE is_header=0 AND author=?", m9.author))
        XCTAssertLessThan(m9.nVerses,
                          scalar(db, "SELECT COUNT(*) FROM lines WHERE author=?", m9.author),
                          "headers are not verses")
        let raags = db.authorRaags(m9.author)
        XCTAssertEqual(raags.count, m9.nRaags)
        XCTAssertEqual(raags.filter(\.isSignature).map(\.raag), ["ਜੈਜਾਵੰਤੀ"],
                       "ਜੈਜਾਵੰਤੀ appears only in Guru Tegh Bahadur Ji's Bani")
        let deck = db.authorRahao(m9.author)
        XCTAssertGreaterThan(deck.totalLines, 0)
        XCTAssertEqual(Set(deck.verses.map(\.compId)).count, deck.verses.count, "one rahao verse per shabad")
        XCTAssertTrue(deck.verses.allSatisfy { !$0.gurmukhi.isEmpty && (1...1430).contains($0.ang) })
        let comps = db.authorCompositions(m9.author)
        XCTAssertEqual(comps.count, m9.nCompositions)
        XCTAssertEqual(comps.reduce(0) { $0 + $1.nVerses }, m9.nVerses)
        let jai = db.authorCompositions(m9.author, raag: "ਜੈਜਾਵੰਤੀ")
        XCTAssertEqual(jai.count, raags.first { $0.raag == "ਜੈਜਾਵੰਤੀ" }?.nCompositions)
        XCTAssertFalse(db.authorVerses(m9.author, containing: "ਨਾਨਕ").isEmpty)
        XCTAssertEqual(db.conceptHeadTerms()["naam"], "ਨਾਮੁ")
    }

    func testBhattsSitOutsideTheRaagSections() throws {
        let db = try shippedDB()
        let bhatts = db.voiceSummaries().filter { $0.author.hasPrefix("Bhatt ") }
        XCTAssertFalse(bhatts.isEmpty)
        for b in bhatts {
            XCTAssertEqual(b.nRaags, 0, b.author)
            XCTAssertTrue(db.authorRaags(b.author).isEmpty)
        }
    }

    func testOptionalTablesAbsentOnTodaysDBAreEmptyNotErrors() throws {
        let db = try shippedDB()
        if !db.hasTable("author_mentions") { XCTAssertTrue(db.authorMentions("Bhagat Kabir Ji").isEmpty) }
        if !db.hasTable("author_dialogues") { XCTAssertTrue(db.authorDialogues("Bhagat Kabir Ji").isEmpty) }
        if !db.hasTable("author_facts") { XCTAssertNil(db.authorFacts("Bhagat Kabir Ji")) }
        XCTAssertTrue(db.authorRaags("no such voice").isEmpty)
        XCTAssertEqual(db.authorRahao("no such voice"), .empty)
    }

    // MARK: tiny DBs

    private func makeDB(_ sql: String) throws -> SQLiteCandidateSource {
        let path = NSTemporaryDirectory() + "voices-\(UUID().uuidString).sqlite"
        var h: OpaquePointer?
        guard sqlite3_open_v2(path, &h, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK, let h else {
            throw XCTSkip("cannot create sqlite")
        }
        let base = """
        CREATE TABLE lines(id INTEGER PRIMARY KEY, ang INT, raag TEXT, author TEXT, comp_id INT,
                           is_rahao INT, is_header INT, gurmukhi TEXT);
        INSERT INTO lines VALUES
          (1, 1364, '', 'Bhagat Kabir Ji', 10, 0, 1, 'ਸਲੋਕ ਭਗਤ ਕਬੀਰ ਜੀਉ ਕੇ'),
          (2, 1364, '', 'Bhagat Kabir Ji', 10, 0, 0, 'ਕਬੀਰ ਪਹਿਲੀ ਤੁਕ ॥੧॥'),
          (3, 1364, '', 'Bhagat Kabir Ji', 10, 0, 0, 'ਕਬੀਰ ਦੂਜੀ ਤੁਕ ॥੨॥'),
          (4, 1365, '', 'Guru Arjan Dev Ji (M5)', 10, 0, 1, 'ਮਹਲਾ ੫ ॥'),
          (5, 1365, '', 'Guru Arjan Dev Ji (M5)', 10, 0, 0, 'ਕਬੀਰ ਉਤਰ ਦੀ ਤੁਕ ॥੩॥'),
          (6, 330, 'ਗਉੜੀ', 'Bhagat Kabir Ji', 11, 1, 0, 'ਰਹਾਉ ਦੀ ਤੁਕ ॥੧॥ ਰਹਾਉ ॥');
        """
        let rc = sqlite3_exec(h, base + sql, nil, nil, nil)
        sqlite3_close(h)
        XCTAssertEqual(rc, SQLITE_OK)
        addTeardownBlock { try? FileManager.default.removeItem(atPath: path) }
        return try SQLiteCandidateSource(path: path)
    }

    func testOldDBWithoutPipelineTablesDegradesToEmpty() throws {
        let db = try makeDB("")
        XCTAssertFalse(db.hasTable("author_facts"))
        XCTAssertNil(db.authorFacts("Bhagat Kabir Ji"))
        XCTAssertTrue(db.authorMentions("Bhagat Kabir Ji").isEmpty)
        XCTAssertTrue(db.authorDialogues("Bhagat Kabir Ji").isEmpty)
        XCTAssertTrue(db.authorEchoes("Bhagat Kabir Ji").isEmpty)
        // …while everything computed from `lines` still works.
        let kabir = try XCTUnwrap(db.voiceSummaries().first { $0.author == "Bhagat Kabir Ji" })
        XCTAssertEqual(kabir.nVerses, 3, "the header row is not a verse")
        XCTAssertEqual(kabir.nCompositions, 2)
        XCTAssertEqual(kabir.nRaags, 1)
        XCTAssertEqual(kabir.angs.angs, [330, 1364])
        XCTAssertEqual(db.authorRaags("Bhagat Kabir Ji").map(\.isSignature), [true])
        XCTAssertEqual(db.authorRahao("Bhagat Kabir Ji").verses.map(\.id), [6])
    }

    func testPipelineTablesLightUpTheirSections() throws {
        let db = try makeDB("""
        CREATE TABLE author_facts(author TEXT PRIMARY KEY, n_verses INT, outside_raag_verses INT, chhap_count INT,
                                  mattr_100 REAL);
        INSERT INTO author_facts VALUES ('Bhagat Kabir Ji', 3, 2, 3, 0.81);
        CREATE TABLE author_mentions(line_id INT, ang INT, src_author TEXT, mentioned TEXT, form TEXT);
        INSERT INTO author_mentions VALUES (5, 1365, 'Guru Arjan Dev Ji (M5)', 'Bhagat Kabir Ji', 'ਕਬੀਰ');
        CREATE TABLE author_dialogues(seq INT, bhagat TEXT, guru TEXT, ang INT, bhagat_first_id INT, bhagat_last_id INT,
                                      guru_first_id INT, guru_last_id INT);
        INSERT INTO author_dialogues VALUES (1, 'Bhagat Kabir Ji', 'Guru Arjan Dev Ji (M5)', 1364, 1, 3, 4, 5);
        """)
        let facts = try XCTUnwrap(db.authorFacts("Bhagat Kabir Ji"))
        XCTAssertEqual(facts.nVerses, 3)
        XCTAssertEqual(facts.outsideRaagVerses, 2)
        XCTAssertEqual(facts.chhapCount, 3)
        XCTAssertEqual(facts.mattr100, 0.81)
        XCTAssertNil(facts.wordsPerVerse, "a column the table lacks reads as nil")
        let m = db.authorMentions("Bhagat Kabir Ji")
        XCTAssertEqual(m.namedBy.map(\.verse.gurmukhi), ["ਕਬੀਰ ਉਤਰ ਦੀ ਤੁਕ ॥੩॥"])
        XCTAssertEqual(m.namedBy.first?.form, "ਕਬੀਰ")
        XCTAssertTrue(m.names.isEmpty)
        let d = try XCTUnwrap(db.authorDialogues("Guru Arjan Dev Ji (M5)").first)
        XCTAssertEqual(d.bhagat.map(\.id), [2, 3], "headers excluded, verbatim by id")
        XCTAssertEqual(d.guru.map(\.id), [5])
    }

    func testAngSet() {
        let s = AngSet([1, 64, 65, 1430, 0, 1431, 64])
        XCTAssertEqual(s.count, 4)
        XCTAssertEqual(s.angs, [1, 64, 65, 1430])
        XCTAssertTrue(s.intersects(60...70))
        XCTAssertFalse(s.intersects(2...63))
        XCTAssertEqual(s.nearest(to: 700), 65)
        XCTAssertEqual(s.nearest(to: 1200), 1430)
        XCTAssertNil(AngSet([]).nearest(to: 5))
    }
}
