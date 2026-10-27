import XCTest
import GurbaniSearchKit

/// The Raag Clock's one 12-hour scale: the ring and the analog face put every moment at the
/// same angle, and the ring shows the half of the day the hour hand is in.
final class PaharFaceTests: XCTestCase {

    /// The hour hand of an ordinary clock, degrees clockwise from 12 (what `ClockHands` draws).
    private func hourHand(_ h: Int, _ m: Int) -> Double { (Double(h % 12) + Double(m) / 60) / 12 * 360 }

    func testCardinalHoursSitWhereTheDialNumbersAre() {
        XCTAssertEqual(Pahar.faceDegrees(0), 0)          // 12 AM → 12
        XCTAssertEqual(Pahar.faceDegrees(180), 90)       // 3 AM → 3
        XCTAssertEqual(Pahar.faceDegrees(360), 180)      // 6 AM → 6, never beside the 9
        XCTAssertEqual(Pahar.faceDegrees(540), 270)      // 9 AM → 9
        XCTAssertEqual(Pahar.faceDegrees(720), 0)        // 12 PM → 12
        XCTAssertEqual(Pahar.faceDegrees(1080), 180)     // 6 PM → 6
        XCTAssertEqual(Pahar.faceDegrees(1440), 0)       // midnight again
        XCTAssertEqual(Pahar.faceDegrees(-60), 330)      // wraps like the rest of Pahar
    }

    func testEveryMinuteMatchesTheHourHand() {
        for m in 0..<1440 {
            XCTAssertEqual(Pahar.faceDegrees(m), hourHand(m / 60, m % 60), accuracy: 1e-9, "minute \(m)")
        }
    }

    /// The owner's screenshot: a solar boundary at 08:18 must sit under the hour hand at 08:18.
    func testSolarBoundaryLandsUnderTheHourHand() {
        let w = Pahar.Window(start: 498, end: 659)       // 8:18–10:59
        XCTAssertEqual(Pahar.faceDegrees(w.start), hourHand(8, 18), accuracy: 1e-9)
        XCTAssertEqual(Pahar.faceDegrees(w.end), hourHand(10, 59), accuracy: 1e-9)
        XCTAssertEqual(Pahar.clip(w, to: .am), [Pahar.Span(start: 498, end: 659)])
        XCTAssertEqual(Pahar.clip(w, to: .pm), [])
    }

    func testHalfSwitchesAtNoonAndMidnight() {
        XCTAssertEqual(Pahar.HalfDay(minute: 0), .am)
        XCTAssertEqual(Pahar.HalfDay(minute: 719), .am)
        XCTAssertEqual(Pahar.HalfDay(minute: 720), .pm)
        XCTAssertEqual(Pahar.HalfDay(minute: 1439), .pm)
        XCTAssertEqual(Pahar.HalfDay(minute: 1440), .am)
        XCTAssertEqual(Pahar.HalfDay(minute: -1), .pm)
        XCTAssertEqual(Pahar.HalfDay.am.start, 0); XCTAssertEqual(Pahar.HalfDay.am.end, 720)
        XCTAssertEqual(Pahar.HalfDay.pm.start, 720); XCTAssertEqual(Pahar.HalfDay.pm.end, 1440)
    }

    /// Fixed watches start on 6 AM / 9 AM / … so each half holds exactly four whole watches.
    func testFixedWatchesSplitCleanlyIntoHalves() {
        let am = (1...8).filter { !Pahar.clip(Pahar.window($0), to: .am).isEmpty }
        let pm = (1...8).filter { !Pahar.clip(Pahar.window($0), to: .pm).isEmpty }
        XCTAssertEqual(am, [1, 2, 7, 8])
        XCTAssertEqual(pm, [3, 4, 5, 6])
        for p in 1...8 {
            let pieces = Pahar.clip(Pahar.window(p), to: .am) + Pahar.clip(Pahar.window(p), to: .pm)
            XCTAssertEqual(pieces.count, 1, "pahar \(p) is never cut")
            XCTAssertEqual(pieces[0].minutes, 180)
        }
        // pahar 6 ends at midnight: its span ends at 1440 (the 12 at the top), not 0
        XCTAssertEqual(Pahar.clip(Pahar.window(6), to: .pm), [Pahar.Span(start: 1260, end: 1440)])
    }

    /// Solar watches cross noon and midnight; each is cut there and the halves tile the day.
    func testSolarWatchesClippedAcrossTheHalfBoundary() {
        let sr = 351, ss = 1067                          // 5:51 AM / 5:47 PM
        let ws = (1...8).map { Pahar.solarWindow($0, sunrise: sr, sunset: ss) }
        // pahar 2 (≈8:50 AM–11:49 AM) stays AM; pahar 3 (11:49 AM–2:48 PM) crosses noon
        let p3 = ws[2]
        XCTAssertLessThan(p3.start, 720); XCTAssertGreaterThan(p3.end, 720)
        XCTAssertEqual(Pahar.clip(p3, to: .am), [Pahar.Span(start: p3.start, end: 720)])
        XCTAssertEqual(Pahar.clip(p3, to: .pm), [Pahar.Span(start: 720, end: p3.end)])
        // pahar 6 or 7 crosses midnight: its tail lands at the start of the AM half
        let crossing = ws.firstIndex { $0.end < $0.start }!
        let w = ws[crossing]
        XCTAssertEqual(Pahar.clip(w, to: .pm), [Pahar.Span(start: w.start, end: 1440)])
        XCTAssertEqual(Pahar.clip(w, to: .am), [Pahar.Span(start: 0, end: w.end)])
        // each half is tiled exactly: 720 minutes, no gaps, no overlaps
        for half in [Pahar.HalfDay.am, .pm] {
            let spans = ws.flatMap { Pahar.clip($0, to: half) }.sorted { $0.start < $1.start }
            XCTAssertEqual(spans.reduce(0) { $0 + $1.minutes }, 720)
            XCTAssertEqual(spans.first?.start, half.start)
            XCTAssertEqual(spans.last?.end, half.end)
            for (a, b) in zip(spans, spans.dropFirst()) { XCTAssertEqual(a.end, b.start) }
        }
    }

    func testClipEdgeCases() {
        XCTAssertEqual(Pahar.clip(Pahar.Window(start: 300, end: 300), to: .am), [], "zero-length is empty")
        // a (hypothetical) window over 12 h wrapping midnight leaves pieces at both ends of AM
        let long = Pahar.Window(start: 700, end: 560)
        XCTAssertEqual(Pahar.clip(long, to: .am), [Pahar.Span(start: 0, end: 560), Pahar.Span(start: 700, end: 720)])
        XCTAssertEqual(Pahar.clip(long, to: .pm), [Pahar.Span(start: 720, end: 1440)])
        XCTAssertTrue(Pahar.isIn(351, half: .am)); XCTAssertTrue(Pahar.isIn(1067, half: .pm))
    }
}
