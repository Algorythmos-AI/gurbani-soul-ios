import XCTest
import GurbaniDB
import GurbaniSearchKit
@testable import SGGS

/// The traditional saroop is DISPLAY-ONLY: it draws the source font's doubled subjoined yayya as
/// the yakash sign U+0A75, the way the printed Bir does, and must map back to the stored text
/// exactly. These tests pin the mapping and the two corpus facts that make it exact.
final class SaroopTests: XCTestCase {
    private let yakash = "\u{0A75}"

    func testDoubledSubjoinedYayyaIsDrawnAsOneYakash() {
        XCTAssertEqual(Saroop.toTraditional("ਜਲ੍ਯ੍ਯਨ"), "ਜਲ\(yakash)ਨ")     // Ang 1400, as the Bir prints it
        XCTAssertEqual(Saroop.toTraditional("ਧਰ੍ਯ੍ਯਉ"), "ਧਰ\(yakash)ਉ")
        XCTAssertEqual(Saroop.toTraditional("ਗ੍ਯ੍ਯਾਨੀਅਹੁ"), "ਗ\(yakash)ਾਨੀਅਹੁ")
    }

    func testASihariAfterTheYayyaIsDrawnToo() {
        // Skipped by the previous transform, which left the raw doubled form on screen.
        XCTAssertEqual(Saroop.toTraditional("ਸਤ੍ਯ੍ਯਿੰ"), "ਸਤ\(yakash)ਿੰ")      // Ang 1354
    }

    func testTextWithoutASubjoinedYayyaIsUntouched() {
        for s in ["ਹੈ ਭੀ ਸਚੁ ਨਾਨਕ ਹੋਸੀ ਭੀ ਸਚੁ ॥੧॥", "ਪ੍ਰਗਟਿਆ ਸਭ ਮਹਿ", "ਕਰਿ ਕਿਰਪਾ ਯਾ", "ੴ ਸਤਿ ਨਾਮੁ"] {
            XCTAssertEqual(Saroop.toTraditional(s), s)
        }
    }

    func testTheDisplayFormMapsBackToTheStoredText() {
        let stored = "ਗੋਬਿੰਦ ਵਾਲੁ ਗੋਬਿੰਦ ਪੁਰੀ ਸਮ ਜਲ੍ਯ੍ਯਨ ਤੀਰਿ ਬਿਪਾਸ ਬਨਾਯਉ ॥"
        XCTAssertEqual(Saroop.toVerbatim(Saroop.toTraditional(stored)), stored)
        XCTAssertEqual(Saroop.toVerbatim("ਧਰ\u{FE00}ਯਉ"), "ਧਰਯਉ")                // an older build's selector is dropped
    }

    /// Every line of the shipped corpus: no yakash of its own, every subjoined yayya one doubled
    /// pair, and display → verbatim byte-identical. If a dataset change breaks this, the saroop
    /// could no longer be mapped back exactly — fail before a reader ever sees it.
    func testEveryCorpusLineRoundTripsExactly() throws {
        guard let path = Bundle.main.url(forResource: "sggs-ios", withExtension: "sqlite")?.path
            ?? Bundle(for: Self.self).url(forResource: "sggs-ios", withExtension: "sqlite")?.path
        else { throw XCTSkip("bundled DB not found in host app") }
        let db = try SQLiteCandidateSource(path: path)
        var pairs = 0, lines = 0
        for n in 1...1430 {
            for line in try db.fetchAng(n).lines {
                let g = line.gurmukhi
                lines += 1
                XCTAssertFalse(g.unicodeScalars.contains(Saroop.yakash), "Ang \(n) stores a yakash")
                pairs += g.components(separatedBy: Saroop.verbatimPair).count - 1
                let shown = Saroop.toTraditional(g)
                XCTAssertFalse(shown.contains("\u{0A4D}\u{0A2F}"), "Ang \(n): a subjoined yayya that is not one doubled pair")
                XCTAssertEqual(Saroop.toVerbatim(shown), g, "Ang \(n): display form does not map back")
            }
        }
        XCTAssertGreaterThan(lines, 60_000)
        XCTAssertGreaterThan(pairs, 0)
    }
}
