import XCTest
@testable import GurbaniSearchKit

/// Parity with serve.py attach_translations: one English record covering several printed lines
/// shows once, under the last member present; every member present carries the span.
final class EnglishSpansTests: XCTestCase {
    // Ang 734, Soohee M4: lines 31529-31530 share one ShabadOS record.
    let span = EnglishSpans.Span(first: 31529, last: 31530, en: "SEED")

    func testWholeSpanPresent() {
        let p = EnglishSpans.place(ids: [31528, 31529, 31530, 31531],
                                   en: [31528: "JEWELS", 31530: "SEED", 31531: "FEARLESS"], spans: [span])
        XCTAssertEqual(p.en, [31528: "JEWELS", 31530: "SEED", 31531: "FEARLESS"])
        XCTAssertEqual(p.span[31529], 31529...31530)
        XCTAssertEqual(p.span[31530], 31529...31530)
        XCTAssertNil(p.span[31528])
    }

    func testAngBoundaryCutsTheSpan() {
        // Only the first member is on this page: the English still shows, under it.
        let p = EnglishSpans.place(ids: [31527, 31528, 31529], en: [31528: "JEWELS"], spans: [span])
        XCTAssertEqual(p.en[31529], "SEED")
        XCTAssertEqual(p.span[31529], 31529...31530)
    }

    func testNoSpansIsIdentity() {
        let en = [1: "A", 2: "B"]
        let p = EnglishSpans.place(ids: [1, 2], en: en, spans: [])
        XCTAssertEqual(p.en, en)
        XCTAssertTrue(p.span.isEmpty)
    }

    func testSpanOutsideTheListIsIgnored() {
        let p = EnglishSpans.place(ids: [10, 11], en: [10: "A"], spans: [span])
        XCTAssertEqual(p.en, [10: "A"])
        XCTAssertTrue(p.span.isEmpty)
    }

    func testIdempotent() {
        let once = EnglishSpans.place(ids: [31529, 31530], en: [31530: "SEED"], spans: [span])
        let twice = EnglishSpans.place(ids: [31529, 31530], en: once.en, spans: [span])
        XCTAssertEqual(once.en, twice.en)
    }
}
