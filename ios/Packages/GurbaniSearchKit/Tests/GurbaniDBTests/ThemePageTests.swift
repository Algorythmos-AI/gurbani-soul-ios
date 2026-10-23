import XCTest
import CSQLite
@testable import GurbaniDB
@testable import GurbaniSearchKit

/// The Themes list on the shipped iOS DB: for every theme, paging walks each tagged verse exactly
/// once, in reading order, and the total it reports is the true count — the card's number and
/// the list's end always agree. Filters (word form, lens) count the same rows they list.
final class ThemePageTests: XCTestCase {

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

    /// Ground truth straight from SQLite, independent of the reader under test.
    private func ints(_ path: String, _ sql: String, _ text: [String] = []) throws -> [Int] {
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { throw XCTSkip("cannot open DB") }
        defer { sqlite3_close(db) }
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else {
            XCTFail(String(cString: sqlite3_errmsg(db))); return []
        }
        defer { sqlite3_finalize(st) }
        for (i, t) in text.enumerated() { sqlite3_bind_text(st, Int32(i + 1), t, -1, SQLiteCandidateSource.transientDtor) }
        var out: [Int] = []
        while sqlite3_step(st) == SQLITE_ROW { out.append(Int(sqlite3_column_int64(st, 0))) }
        return out
    }

    private func walk(_ db: SQLiteCandidateSource, _ concept: String, _ filter: ThemeFilter = .none, size: Int) throws -> (Int, [Int]) {
        var ids: [Int] = [], after = 0, total = -1, pages = 0
        let full = min(size, SQLiteCandidateSource.themePageMax)
        while true {
            let p = try db.themePage(concept: concept, filter: filter, afterId: after, limit: size)
            if total == -1 { total = p.total } else { XCTAssertEqual(p.total, total, "\(concept): total changed mid-walk") }
            XCTAssertLessThanOrEqual(p.lines.count, full)
            ids += p.lines.map(\.id)
            pages += 1
            guard let next = p.nextAfterId else { break }
            XCTAssertEqual(next, p.lines.last?.id)
            XCTAssertEqual(p.lines.count, full, "\(concept): a non-final page must be full")
            after = next
            if pages > 10_000 { XCTFail("\(concept): paging never ended"); break }
        }
        return (total, ids)
    }

    func testEveryThemePagesThroughEveryVerseOnceInReadingOrder() throws {
        let path = try dbPath()
        let db = try SQLiteCandidateSource(path: path)
        let concepts = try db.fetchMeta().concepts
        XCTAssertEqual(concepts.count, 54)
        var sum = 0
        for c in concepts {
            let (total, ids) = try walk(db, c.concept, size: 200)
            let truth = try ints(path, "SELECT DISTINCT line_id FROM concept_lines WHERE concept=? ORDER BY line_id", [c.concept])
            XCTAssertEqual(total, truth.count, "\(c.concept): total")
            XCTAssertEqual(ids, truth, "\(c.concept): paged ids differ from the tagged ids")
            XCTAssertEqual(total, c.nLines, "\(c.concept): the card's count and the list's total disagree")
            sum += total
        }
        XCTAssertEqual(sum, 62_221, "all tags")
    }

    func testPageSizeDoesNotChangeWhatIsListed() throws {
        let db = try SQLiteCandidateSource(path: try dbPath())
        for c in ["akal", "sahaj", "kaam", "garab"] {
            let (_, a) = try walk(db, c, size: 7)
            let (_, b) = try walk(db, c, size: 37)
            let (_, d) = try walk(db, c, size: 10_000)            // clamped to themePageMax
            XCTAssertEqual(a, b, c); XCTAssertEqual(b, d, c)
        }
    }

    func testVersesAreVerbatimAndNeverHeaders() throws {
        let path = try dbPath()
        let db = try SQLiteCandidateSource(path: path)
        let p = try db.themePage(concept: "naam", limit: 500)
        for line in p.lines {
            XCTAssertFalse(line.isHeader, "line \(line.id) is a header")
            XCTAssertFalse(line.gurmukhi.isEmpty)
        }
        let headers = try ints(path, "SELECT COUNT(*) FROM concept_lines cl JOIN lines l ON l.id=cl.line_id WHERE l.is_header=1")
        XCTAssertEqual(headers, [0], "a theme tags a header line; counts would include headings")
        // first page == the search engine's theme order (same rows, same order)
        let legacy = try db.themeSearch("naam", limit: 50, offset: 0).lines.map(\.id)
        XCTAssertEqual(Array(p.lines.prefix(50)).map(\.id), legacy)
    }

    func testWordFormsPartitionTheTheme() throws {
        let path = try dbPath()
        let db = try SQLiteCandidateSource(path: path)
        for c in ["sahaj", "haumai", "naam", "karam_nadar"] {
            let terms = try ints(path, "SELECT COUNT(*) FROM concept_lines WHERE concept=? GROUP BY term", [c])
            let total = try db.themeCount(concept: c)
            XCTAssertEqual(terms.reduce(0, +), total, "\(c): word-form counts must add up to the theme")
        }
        let sahajji = try walk(db, "sahaj", ThemeFilter(term: "ਸਹਜਿ"), size: 100)
        XCTAssertEqual(sahajji.0, 375)
        XCTAssertEqual(sahajji.1.count, 375)
        XCTAssertEqual(try db.themeCount(concept: "sahaj", filter: ThemeFilter(term: "  ")), try db.themeCount(concept: "sahaj"),
                       "a blank term is no filter")
    }

    func testLensCountsMatchTheConstellation() throws {
        let db = try SQLiteCandidateSource(path: try dbPath())
        let lenses: [ConstellationLens] = [
            .none, ConstellationLens(rahaoOnly: true), ConstellationLens(angMin: 1, angMax: 100),
            ConstellationLens(author: "Bhagat Kabir Ji"), ConstellationLens(minThemes: 5),
        ]
        for c in ["naam", "haumai", "akal"] {
            for lens in lenses {
                let f = ThemeFilter(lens: lens)
                let (total, ids) = try walk(db, c, f, size: 250)
                XCTAssertEqual(total, ids.count, "\(c) \(lens)")
                XCTAssertEqual(total, try db.constellationFocus(concept: c, lens: lens).total, "\(c) \(lens): differs from Constellation")
            }
        }
        XCTAssertEqual(try db.themeCount(concept: "akal", filter: ThemeFilter(lens: ConstellationLens(rahaoOnly: true))), 0,
                       "Akal has no refrain lines (the theme page hides that section)")
    }

    func testUnknownThemeIsEmptyNotAnError() throws {
        let db = try SQLiteCandidateSource(path: try dbPath())
        let p = try db.themePage(concept: "no_such_theme")
        XCTAssertEqual(p.total, 0); XCTAssertTrue(p.lines.isEmpty); XCTAssertNil(p.nextAfterId)
        let injection = try db.themePage(concept: "naam' OR '1'='1")
        XCTAssertEqual(injection.total, 0)
    }

    // MARK: the Themes index

    func testIndexCountsAgreeWithEverySurface() throws {
        let path = try dbPath()
        let db = try SQLiteCandidateSource(path: path)
        let index = try db.themeIndex()
        let meta = try db.fetchMeta().concepts
        XCTAssertEqual(index.map(\.concept), meta.map(\.concept), "same 54 themes, same order")
        for (row, m) in zip(index, meta) {
            XCTAssertEqual(row.nVerses, m.nLines, "\(row.concept): verse count")
            XCTAssertEqual(row.angBins.count, ConstellationFocus.binCount)
            XCTAssertEqual(row.angBins.reduce(0, +), row.nVerses, "\(row.concept): bins must add up")
            XCTAssertEqual(row.angBins, try db.constellationFocus(concept: row.concept).angBins, "\(row.concept): Ang strip")
            XCTAssertEqual(row.nRahao, try db.themeCount(concept: row.concept, filter: ThemeFilter(lens: ConstellationLens(rahaoOnly: true))))
            let shabads = try ints(path, "SELECT COUNT(DISTINCT l.comp_id) FROM concept_lines cl JOIN lines l ON l.id=cl.line_id WHERE cl.concept=?", [row.concept])
            XCTAssertEqual([row.nShabads], shabads, row.concept)
            XCTAssertFalse(row.terms.isEmpty, "\(row.concept): no Gurmukhi words")
            let head = try XCTUnwrap(row.headword, "\(row.concept): no headword")
            XCTAssertTrue(row.terms.contains(head), "\(row.concept): headword \(head) is not one of its words")
            XCTAssertGreaterThan(try db.themeCount(concept: row.concept, filter: ThemeFilter(term: head)), 0)
            let earlier = row.terms.prefix { $0 != head }
            for t in earlier { XCTAssertEqual(try db.themeCount(concept: row.concept, filter: ThemeFilter(term: t)), 0,
                                              "\(row.concept): \(t) comes first and tags verses, so it is the lead word") }
        }
        let byKey = Dictionary(uniqueKeysWithValues: index.map { ($0.concept, $0) })
        XCTAssertEqual(byKey["sahaj"]?.headword, "ਸਹਜ")
        XCTAssertEqual(byKey["haumai"]?.headword, "ਹਉਮੈ")
        XCTAssertEqual(byKey["garab"]?.headword, "ਗਰਬੁ", "Garab's own word, not its most frequent (ਹਉਮੈ)")
        XCTAssertEqual(byKey["shabad"]?.headword, "ਸਬਦੁ")
        let heads = index.compactMap(\.headword)
        XCTAssertEqual(heads.count, 54)
        XCTAssertEqual(Set(heads).count, heads.count, "no two themes share a headword")
        XCTAssertEqual(byKey["naam"]?.nShabads, 2472)
        XCTAssertEqual(byKey["akal"]?.nRahao, 0)
    }

    func testThemeOfTheDayIsDeterministicAndNeverEmpty() throws {
        let db = try SQLiteCandidateSource(path: try dbPath())
        let today = HukamOfTheDay.dayNumber(year: 2026, month: 10, day: 23)
        var seen = Set<String>()
        for day in today..<(today + 54) {
            let t = try XCTUnwrap(try db.themeOfTheDay(day: day))
            XCTAssertEqual(t, try db.themeOfTheDay(day: day), "day \(day) must always give the same theme and verse")
            XCTAssertFalse(t.line.gurmukhi.isEmpty)
            XCTAssertFalse(t.line.isHeader)
            let tagged = try db.themePage(concept: t.concept, limit: 500).lines.map(\.id)
            XCTAssertTrue(try db.themeCount(concept: t.concept) > 0)
            if t.concept != "akal" { XCTAssertTrue(t.isRefrain, "\(t.concept): has refrains, so the verse must be one") }
            if t.concept == "akal" { XCTAssertEqual(t.line.id, tagged.first, "Akal falls back to its first verse") }
            seen.insert(t.concept)
        }
        XCTAssertEqual(seen.count, 54, "54 consecutive days visit every theme once")
        XCTAssertEqual(ThemeOfTheDay.index(day: -1, count: 54), 53)
    }

    func testTallyCountsOnlyTheGivenVerses() throws {
        let path = try dbPath()
        let db = try SQLiteCandidateSource(path: path)
        XCTAssertEqual(try db.themeTally(lineIds: []), [])
        XCTAssertEqual(try db.themeTally(lineIds: [-5, 99_999_999]), [])
        let naam = try ints(path, "SELECT line_id FROM concept_lines WHERE concept='naam' ORDER BY line_id LIMIT 1200")
        let tally = try db.themeTally(lineIds: naam + naam)                // duplicates count once; > one chunk
        XCTAssertEqual(tally.first, ThemeTally(concept: "naam", n: 1200))
        for t in tally {
            let truth = try ints(path, "SELECT COUNT(DISTINCT line_id) FROM concept_lines WHERE concept=? AND line_id IN (SELECT line_id FROM concept_lines WHERE concept='naam' ORDER BY line_id LIMIT 1200)", [t.concept])
            XCTAssertEqual([t.n], truth, t.concept)
        }
        XCTAssertEqual(tally.map(\.n), tally.map(\.n).sorted(by: >))
    }

    // MARK: the theme page

    func testEveryListedVerseSaysWhichWordPutItThere() throws {
        let path = try dbPath()
        let db = try SQLiteCandidateSource(path: path)
        for c in ["naam", "sahaj", "karam_nadar", "akal"] {
            let p = try db.themePage(concept: c, limit: 300)
            let words = Set(try db.themeWords(concept: c).map(\.term))
            for line in p.lines {
                let m = try XCTUnwrap(p.matched[line.id], "\(c) line \(line.id): no matched word")
                XCTAssertFalse(m.isEmpty)
                for t in m {
                    XCTAssertTrue(words.contains(t), "\(c): \(t) is not one of the theme's words")
                    XCTAssertTrue(line.gurmukhi.contains(t), "\(c) line \(line.id): \(t) does not occur verbatim")
                }
            }
            XCTAssertEqual(Set(p.matched.keys), Set(p.lines.map(\.id)), "\(c): matches only for listed verses")
        }
        // under a word filter, that word is among each verse's matches
        let f = try db.themePage(concept: "sahaj", filter: ThemeFilter(term: "ਸਹਜੇ"), limit: 100)
        for line in f.lines { XCTAssertTrue(f.matched[line.id]?.contains("ਸਹਜੇ") == true) }
    }

    func testWordFamilyIsPrintedOrderWithTrueCounts() throws {
        let db = try SQLiteCandidateSource(path: try dbPath())
        let sahaj = try db.themeWords(concept: "sahaj")
        XCTAssertEqual(sahaj.map(\.term), ["ਸਹਜ", "ਸਹਜੁ", "ਸਹਜਿ", "ਸਹਜੈ", "ਸਹਜੇ", "ਸਹਜਾ"].filter { t in sahaj.contains { $0.term == t } })
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: sahaj.map { ($0.term, $0.n) })["ਸਹਜਿ"], 375)
        let index = Dictionary(uniqueKeysWithValues: try db.themeIndex().map { ($0.concept, $0) })
        for (c, row) in index {
            let words = try db.themeWords(concept: c)
            XCTAssertTrue(words.allSatisfy { $0.n > 0 }, c)
            XCTAssertEqual(words.map(\.n).reduce(0, +), row.nVerses, "\(c): the family adds up to the theme")
            XCTAssertEqual(words.max { $0.n < $1.n }?.n, words.first { $0.term == row.headword }?.n, "\(c): headword")
        }
        XCTAssertEqual(try db.themeWords(concept: "no_such_theme"), [])
    }

    func testFilteredAngBinsCountTheFilteredVerses() throws {
        let db = try SQLiteCandidateSource(path: try dbPath())
        let index = Dictionary(uniqueKeysWithValues: try db.themeIndex().map { ($0.concept, $0) })
        XCTAssertEqual(try db.themeAngBins(concept: "naam"), index["naam"]?.angBins)
        let f = ThemeFilter(term: "ਸਹਜਿ")
        let bins = try db.themeAngBins(concept: "sahaj", filter: f)
        XCTAssertEqual(bins.reduce(0, +), 375)
        for i in 0..<bins.count {
            let r = ConstellationFocus.angRange(bin: i)
            let lensed = ThemeFilter(term: "ਸਹਜਿ", lens: ConstellationLens(angMin: r.lowerBound, angMax: r.upperBound))
            XCTAssertEqual(bins[i], try db.themeCount(concept: "sahaj", filter: lensed), "bin \(i): the strip and the list it opens must agree")
        }
    }

    func testSteepedShabadsFollowTheRule() throws {
        let path = try dbPath()
        let db = try SQLiteCandidateSource(path: path)
        let naam = try db.themeSteeped(concept: "naam")
        XCTAssertEqual(naam.count, 51)
        XCTAssertEqual(naam.map(\.firstLineId), naam.map(\.firstLineId).sorted(), "reading order")
        for s in naam {
            XCTAssertTrue(SteepedShabad.qualifies(n: s.n, total: s.total), "comp \(s.compId)")
            let truthTotal = try ints(path, "SELECT COUNT(*) FROM lines WHERE comp_id=? AND is_header=0", [String(s.compId)])
            XCTAssertEqual([s.total], truthTotal)
            XCTAssertFalse(s.firstVerse.isEmpty)
            XCTAssertTrue((1...1430).contains(s.ang))
        }
        XCTAssertTrue(naam.contains { $0.n == 28 && $0.total == 34 && $0.ang == 1155 }, "the Ang 1155 shabad, 28 of 34 lines")
        XCTAssertEqual(try db.themeSteeped(concept: "akal"), [])
        XCTAssertEqual(try db.themeSteeped(concept: "satguru").count, 94)
        XCTAssertFalse(SteepedShabad.qualifies(n: 3, total: 5), "too short")
        XCTAssertTrue(SteepedShabad.qualifies(n: 3, total: 6))
        XCTAssertFalse(SteepedShabad.qualifies(n: 2, total: 6))
    }
}
