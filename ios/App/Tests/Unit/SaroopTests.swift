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
        // Compare Unicode SCALARS, never String: a Swift String compares and searches by grapheme
        // cluster, and the virama-ya pair lives inside its letter's cluster, so `contains` and
        // `components(separatedBy:)` would never see it (this test once passed vacuously that way).
        let pair = Array(Saroop.verbatimPair.unicodeScalars)
        func count(_ needle: [Unicode.Scalar], in hay: [Unicode.Scalar]) -> Int {
            guard hay.count >= needle.count else { return 0 }
            return (0...(hay.count - needle.count)).filter { Array(hay[$0..<($0 + needle.count)]) == needle }.count
        }
        var pairs = 0, lines = 0, drawn = 0
        for n in 1...1430 {
            for line in try db.fetchAng(n).lines {
                let g = Array(line.gurmukhi.unicodeScalars)
                lines += 1
                XCTAssertFalse(g.contains(Saroop.yakash), "Ang \(n) stores a yakash")
                let p = count(pair, in: g)
                pairs += p
                let shown = Array(Saroop.toTraditional(line.gurmukhi).unicodeScalars)
                XCTAssertEqual(count([Unicode.Scalar(0x0A4D)!, Unicode.Scalar(0x0A2F)!], in: shown), 0,
                               "Ang \(n): a subjoined yayya that is not one doubled pair")
                XCTAssertEqual(shown.filter { $0 == Saroop.yakash }.count, p, "Ang \(n): one yakash per stored pair")
                if p > 0 { drawn += 1 }
                XCTAssertEqual(Array(Saroop.toVerbatim(String(String.UnicodeScalarView(shown))).unicodeScalars), g,
                               "Ang \(n): display form does not map back byte for byte")
            }
        }
        XCTAssertEqual(pairs, 268, "the corpus's doubled subjoined yayya (268 words, 78 Angs)")
        XCTAssertEqual(drawn, 234, "lines the saroop draws differently")
        XCTAssertEqual(lines, 60_658)
    }
}
