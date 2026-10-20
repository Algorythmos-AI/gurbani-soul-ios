import XCTest
import GurbaniDB
import GurbaniSearchKit
@testable import SGGS

/// The bani reader's gutka layout, Dasam headings and glyph repair are DISPLAY-ONLY. These tests
/// pin that rows only ever regroup the original lines (in order, none dropped or altered), that
/// the data's 59 Dasam / Ardaas headings are drawn as headings while the Sri Guru Granth Sahib Ji
/// filter is unchanged, and that the ਜਤੱ੍ਰ repair touches exactly two lines of the whole app.
final class BaniGutkaTests: XCTestCase {

    // MARK: fixtures

    private func db() throws -> SQLiteCandidateSource {
        guard let path = Bundle.main.url(forResource: "sggs-ios", withExtension: "sqlite")?.path
            ?? Bundle(for: Self.self).url(forResource: "sggs-ios", withExtension: "sqlite")?.path
        else { throw XCTSkip("bundled DB not found in host app") }
        return try SQLiteCandidateSource(path: path)
    }

    /// Every registry entry, every variant.
    private func allBanis(_ db: SQLiteCandidateSource) -> [Bani] {
        db.fetchBanis().banis.compactMap { db.fetchBani(key: $0.key, variant: $0.variant) }
    }

    private func heading(_ l: BaniLine) -> Bool {
        VerseTypography.rendersAsHeading(l.gurmukhi, flaggedHeader: l.isHeader, trustFlag: !l.citation.isSGGS)
    }

    /// The reader's packing input for a bani, as BaniReaderScreen builds it (English hidden).
    private func input(_ bani: Bani) -> [GutkaRows.Line] {
        let starts = Set(BaniOutline.sections(for: bani)
            .filter { $0.kind == .pauri || $0.kind == .ashtapadi || $0.kind == .salok }.map(\.startSeq))
        return bani.lines.map {
            GutkaRows.Line(seq: $0.seq, gurmukhi: $0.gurmukhi, lineGroup: $0.lineGroup, heading: heading($0),
                           pairable: !$0.isRahao, opensSection: starts.contains($0.seq))
        }
    }

    private func line(_ seq: Int, _ g: String, group: Int = 1, heading: Bool = false,
                      pairable: Bool = true, opens: Bool = false) -> GutkaRows.Line {
        GutkaRows.Line(seq: seq, gurmukhi: g, lineGroup: group, heading: heading, pairable: pairable, opensSection: opens)
    }

    // MARK: switch

    func testGutkaIsOnByDefaultOnlyForTheShortLineBanis() {
        for key in ["jaap", "chaupai", "savaiye", "savaiye_deenan", "shabad_hazare_p10", "aarti"] {
            XCTAssertTrue(GutkaPrefs.isOn(key, stored: ""), key)
        }
        for key in ["japji", "rehras", "anand", "sukhmani", "sohila", "ardaas", "shabad_hazare"] {
            XCTAssertFalse(GutkaPrefs.isOn(key, stored: ""), key)
        }
    }

    func testTheSwitchStoresOnlyRealOverrides() {
        var s = GutkaPrefs.setting("anand", on: true, in: "")
        XCTAssertEqual(s, "anand=1")
        s = GutkaPrefs.setting("jaap", on: false, in: s)
        XCTAssertEqual(s, "anand=1,jaap=0")
        XCTAssertTrue(GutkaPrefs.isOn("anand", stored: s))
        XCTAssertFalse(GutkaPrefs.isOn("jaap", stored: s))
        s = GutkaPrefs.setting("jaap", on: true, in: s)              // back to its default: dropped
        XCTAssertEqual(s, "anand=1")
        XCTAssertTrue(GutkaPrefs.isOn("chaupai", stored: "garbage,=1,chaupai=x"))
    }

    // MARK: packing

    func testAVerseNumberClosesTheVerse() {
        XCTAssertTrue(VerseTypography.closesVerse("ਨਮਸਤੰ ਅਨੂਪੇ ॥੨॥"))
        XCTAssertTrue(VerseTypography.closesVerse("ਸ੍ਰੀ ਭਗਵਾਨ ਕੀ ਭਾਇ ਕ੍ਰਿਪਾ ਹੂ ਤੇ ਏਕ ਰਤੀ ਬਿਨੁ ਏਕ ਰਤੀ ਕੇ ॥੧॥੨੧॥"))
        XCTAssertTrue(VerseTypography.closesVerse("ਮਨ ਹੀ ਮਾਹਿ ਉਦਾਸਾ ॥੧॥ ਰਹਾਉ ॥"))
        XCTAssertFalse(VerseTypography.closesVerse("ਨਮਸਤ੍ਵੰ ਅਕਾਲੇ ॥"))
        XCTAssertFalse(VerseTypography.closesVerse("ਤਾਰਿਕਾ ਮੰਡਲ ਜਨਕ ਮੋਤੀ ॥"))
    }

    func testHalfLinesPairUpToTheVerseNumberAndNeverAcrossIt() {
        let lines = [line(1, "ਭੁਜੰਗ ਪ੍ਰਯਾਤ ਛੰਦ ॥", heading: true),
                     line(2, "ਨਮਸਤ੍ਵੰ ਅਕਾਲੇ ॥"), line(3, "ਨਮਸਤ੍ਵੰ ਕ੍ਰਿਪਾਲੇ ॥"),
                     line(4, "ਨਮਸਤੰ ਅਰੂਪੇ ॥"), line(5, "ਨਮਸਤੰ ਅਨੂਪੇ ॥੨॥"),
                     line(6, "ਨਮਸਤੰ ਅਭੇਖੇ ॥"), line(7, "ਨਮਸਤੰ ਅਲੇਖੇ ॥"), line(8, "ਨਮਸਤੰ ਅਕਾਏ ॥੩॥"),
                     line(9, "ਨਮਸਤੰ ਅਗੰਜੇ ॥")]
        let rows = GutkaRows.pack(lines, enabled: true)
        XCTAssertEqual(rows.map(\.seqs), [[1], [2, 3], [4, 5], [6, 7], [8], [9]])
        XCTAssertEqual(rows.map(\.opensVerse), [true, true, false, true, false, true])
        XCTAssertTrue(rows[0].heading)
    }

    func testPairsNeverCrossAHeadingASectionAGroupOrARahao() {
        let rows = GutkaRows.pack([
            line(1, "ਕ ॥"), line(2, "ਖ ॥", heading: true),            // heading
            line(3, "ਗ ॥"), line(4, "ਘ ॥", opens: true),               // a pauri starts at 4
            line(5, "ਙ ॥"), line(6, "ਚ ॥", group: 2),                  // line-group change
            line(7, "ਛ ॥", group: 2), line(8, "ਜ ॥", group: 2, pairable: false),   // ਰਹਾਉ / English
        ], enabled: true)
        XCTAssertEqual(rows.map(\.seqs), [[1], [2], [3], [4, 5], [6, 7], [8]])
    }

    func testOffMeansOneLinePerRow() {
        let lines = (1...6).map { line($0, "ਨਮਸਤੰ ਅਰੂਪੇ ॥") }
        XCTAssertEqual(GutkaRows.pack(lines, enabled: false).map(\.seqs), (1...6).map { [$0] })
    }

    /// Every bani, on and off: the rows read back as exactly the original lines in order — none
    /// reordered, dropped or duplicated — and a pair never ends a verse in its first half.
    func testPackingIsOrderPreservingAndLosslessForEveryBani() throws {
        let db = try db()
        let banis = allBanis(db)
        XCTAssertGreaterThanOrEqual(banis.count, 23)
        var pairs = 0
        for bani in banis {
            let lines = input(bani)
            for enabled in [true, false] {
                let rows = GutkaRows.pack(lines, enabled: enabled)
                XCTAssertEqual(rows.flatMap(\.seqs), bani.lines.map(\.seq), "\(bani.summary.id): rows lost or reordered a line")
                for row in rows where row.isPair {
                    let a = bani.lines.first { $0.seq == row.seqs[0] }!, b = bani.lines.first { $0.seq == row.seqs[1] }!
                    XCTAssertFalse(VerseTypography.closesVerse(a.gurmukhi), "\(bani.summary.id) seq \(a.seq) pairs across ॥N॥")
                    XCTAssertFalse(heading(a) || heading(b))
                    XCTAssertEqual(a.lineGroup, b.lineGroup)
                    if enabled { pairs += 1 }
                }
                if !enabled { XCTAssertTrue(rows.allSatisfy { !$0.isPair }) }
            }
        }
        XCTAssertGreaterThan(pairs, 0)
    }

    func testJaapOpensWithItsBhujangPrayaatPairs() throws {
        let db = try db()
        let jaap = try XCTUnwrap(db.fetchBani(key: "jaap"))
        let rows = GutkaRows.pack(input(jaap), enabled: true)
        // The opening chhapai's long lines are pair candidates too; whether a pair shares a line
        // is decided at render time by the column width (they never fit on a phone).
        let a = try XCTUnwrap(jaap.lines.first { $0.gurmukhi == "ਨਮਸਤ੍ਵੰ ਅਕਾਲੇ ॥" })
        let b = try XCTUnwrap(jaap.lines.first { $0.gurmukhi == "ਨਮਸਤ੍ਵੰ ਕ੍ਰਿਪਾਲੇ ॥" })
        let pair = try XCTUnwrap(rows.first { $0.seqs.contains(a.seq) })
        XCTAssertEqual(pair.seqs, [a.seq, b.seq])
        XCTAssertTrue(pair.opensVerse, "the first pair after the chhand title opens a verse")
        XCTAssertEqual(GutkaRows.rowStart(of: b.seq, in: rows), a.seq, "the second half resumes on its row")
    }

    func testTheJoinedTransliterationSplitsBackIntoEachLine() {
        let parts = ["namasatva(n) akaale", "namasatva(n) kirapaale"]
        let joined = GutkaRows.joinedTranslit(parts)
        XCTAssertEqual(joined.components(separatedBy: GutkaRows.translitSeparator), parts)
        XCTAssertEqual(GutkaRows.joinedTranslit(["", ""]), "")
    }

    // MARK: headings

    /// The extra layer's `is_header` is trusted: every one of its 59 labels draws as a heading,
    /// and no unflagged Dasam / Ardaas line does.
    func testEveryDasamAndArdaasHeadingRendersAsAHeading() throws {
        let db = try db()
        var headers = Set<Int>()
        for bani in allBanis(db) {
            for l in bani.lines where !l.citation.isSGGS {
                let id: Int
                switch l.citation {
                case .dasam(_, let e), .ardaas(let e): id = e
                case .sggs: continue
                }
                XCTAssertEqual(heading(l), l.isHeader, "\(bani.summary.id) seq \(l.seq): \(l.gurmukhi)")
                if l.isHeader { headers.insert(id) }
            }
        }
        XCTAssertEqual(headers.count, 59)
        for h in ["ਭੁਜੰਗ ਪ੍ਰਯਾਤ ਛੰਦ ॥", "ਚਾਚਰੀ ਛੰਦ ॥ ਤ੍ਵ ਪ੍ਰਸਾਦਿ ॥", "ਮਧੁਭਾਰ ਛੰਦ ॥ ਤ੍ਵ ਪ੍ਰਸਾਦਿ ॥"] {
            XCTAssertFalse(VerseTypography.rendersAsHeading(h, flaggedHeader: true), "the SGGS filter alone rejects \(h)")
            XCTAssertTrue(VerseTypography.rendersAsHeading(h, flaggedHeader: true, trustFlag: true))
        }
    }

    func testSGGSLinesKeepTheirFilter() {
        // The default (trustFlag false) is the unchanged Sri Guru Granth Sahib Ji filter.
        XCTAssertFalse(VerseTypography.rendersAsHeading("ਸੋਚੈ ਸੋਚਿ ਨ ਹੋਵਈ ਜੇ ਸੋਚੀ ਲਖ ਵਾਰ ॥", flaggedHeader: true))
        XCTAssertTrue(VerseTypography.rendersAsHeading("ਆਸਾ ਮਹਲਾ ੫ ॥", flaggedHeader: true))
        XCTAssertFalse(VerseTypography.rendersAsHeading("ਆਸਾ ਮਹਲਾ ੫ ॥", flaggedHeader: false, trustFlag: true))
    }

    // MARK: glyph repair

    func testTheAddakIsDrawnAfterTheConjunct() {
        XCTAssertEqual(GlyphRepair.forDisplay("ਜਤ\u{0A71}\u{0A4D}ਰ ਤਤ\u{0A71}\u{0A4D}ਰ"),
                       "ਜਤ\u{0A4D}ਰ\u{0A71} ਤਤ\u{0A4D}ਰ\u{0A71}")
        for s in ["ਚੱਕ੍ਰ ਚਿਹਨ ਅਰੁ ਬਰਨ", "ਕਹਿੱਜੈ ॥", "ਨਮਸਤ੍ਵੰ ਅਕਾਲੇ ॥", "ੴ ਸਤਿ ਨਾਮੁ"] {
            XCTAssertEqual(GlyphRepair.forDisplay(s), s)
        }
    }

    /// Across every Sri Guru Granth Sahib Ji line and every bani line (all 1,191 extra lines), the
    /// repair changes exactly Jaap pauris 79 and 80 — and only reorders, never adds or drops, a
    /// character.
    func testTheRepairTouchesOnlyTheTwoJaapLines() throws {
        let db = try db()
        var changed: [String] = []
        var seen = Set<String>()
        func check(_ g: String) {
            guard seen.insert(g).inserted else { return }
            let shown = GlyphRepair.forDisplay(g)
            let a = Array(g.unicodeScalars), b = Array(shown.unicodeScalars)
            if a != b {
                changed.append(g)
                XCTAssertEqual(a.map(\.value).sorted(), b.map(\.value).sorted(), "repair altered characters: \(g)")
            }
        }
        for n in 1...1430 { for l in try db.fetchAng(n).lines { check(l.gurmukhi) } }
        for bani in allBanis(db) { for l in bani.lines { check(l.gurmukhi) } }
        XCTAssertEqual(changed.sorted(), ["ਜਤੱ੍ਰ ਤਤੱ੍ਰ ਦਿਸਾ ਵਿਸਾ ਹੁਇ ਫੈਲਿਓ ਅਨੁਰਾਗ ॥੮੦॥",
                                          "ਜਤੱ੍ਰ ਤਤੱ੍ਰ ਬਿਰਾਜਹੀ ਅਵਧੂਤ ਰੂਪ ਰਸਾਲ ॥੭੯॥"].sorted())
    }
}
