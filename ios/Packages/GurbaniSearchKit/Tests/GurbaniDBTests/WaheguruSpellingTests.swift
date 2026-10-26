import XCTest
@testable import GurbaniDB
@testable import GurbaniSearchKit

/// The app shows the name as "Waheguru"; a seeker may type it any of the ways it is written in
/// Roman letters. Roman search gives every spelling the same results from the fold alone
/// (`roman_norm` folds all of them to `vhgr`; the fold is unchanged). Auto mode resolves every
/// spelling through the seeker lexicon (`vahiguru` too: serve.py `LEXICON_OVER_SLUG`), and theme
/// mode finds the theme by fold — mirroring sggs-platform #316.
final class WaheguruSpellingTests: XCTestCase {

    static let spellings = ["waheguru", "Waheguru", "vaheguru", "Vaheguru", "vahiguru", "wahiguru"]

    private func dbPath() throws -> String {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<12 {
            let p = dir.appendingPathComponent("ios/Resources/sggs-ios.sqlite").path
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent("contract/_meta.json").path) {
                guard FileManager.default.fileExists(atPath: p) else { break }
                return p
            }
            dir = dir.deletingLastPathComponent()
        }
        throw XCTSkip("ios/Resources/sggs-ios.sqlite missing — run `make ios-db-repair`")
    }

    func testEverySpellingFoldsToOneKey() {
        for s in Self.spellings { XCTAssertEqual(RomanNorm.fold(s), "vhgr", s) }
    }

    func testRomanSearchGivesEverySpellingTheSameResults() throws {
        let engine = SearchEngine(source: try SQLiteCandidateSource(path: try dbPath()))
        let base = try engine.search("waheguru", mode: "roman", limit: 20)
        XCTAssertFalse(base.results.isEmpty, "waheguru finds the Granth's ਵਾਹਿਗੁਰੂ verses")
        for s in Self.spellings.dropFirst() {
            let out = try engine.search(s, mode: "roman", limit: 20)
            XCTAssertEqual(out.results.map(\.id), base.results.map(\.id), s)
            XCTAssertEqual(out.mode, base.mode, s)
        }
    }

    func testAutoSearchResolvesEverySpellingThroughTheLexicon() throws {
        let engine = SearchEngine(source: try SQLiteCandidateSource(path: try dbPath()))
        let base = try engine.search("waheguru", mode: "auto", limit: 5)
        XCTAssertEqual(base.mode, "seeker-lexicon (vaahiguroo)")
        for s in Self.spellings + ["satnam vaheguru", "vaheguruji"] {
            let out = try engine.search(s, mode: "auto", limit: 5)
            XCTAssertEqual(out.mode, base.mode, s)
            XCTAssertEqual(out.results.map(\.id), base.results.map(\.id), s)
            XCTAssertNil(out.concept, "\(s) finds the Name's lines, not the theme shortcut")
        }
        XCTAssertEqual(try engine.search("naam", mode: "auto", limit: 5).mode, "theme", "other slugs keep the shortcut")
    }

    func testThemeSearchFindsTheThemeByFold() throws {
        let engine = SearchEngine(source: try SQLiteCandidateSource(path: try dbPath()))
        for s in Self.spellings {
            XCTAssertEqual(try engine.search(s, mode: "theme", limit: 5).concept?.name, "vahiguru", s)
        }
    }
}
