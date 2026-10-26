import XCTest
@testable import GurbaniDB
@testable import GurbaniSearchKit

/// The app shows the name as "Waheguru"; a seeker may type it any of the ways it is written in
/// Roman letters. Roman search must give every spelling the same results, from the fold alone
/// (`roman_norm` folds all of them to `vhgr`) — no lexicon entry, no change to the fold.
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
}
