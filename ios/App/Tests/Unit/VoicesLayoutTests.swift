import XCTest
import GurbaniSearchKit
@testable import SGGS

/// Voices of the Granth: the dot field and the Granth ribbon are pure layouts over the data,
/// so their honesty is testable — every voice visible, no dot hidden under another, the same
/// dot in every grouping, and ribbon columns that add up.
final class VoicesLayoutTests: XCTestCase {

    private let voices: [(author: String, lines: Int)] = [
        ("Guru Nanak Dev Ji (M1)", 10_997), ("Bhagat Kabir Ji", 3_068), ("Bhatt Bhal (ਭਟ)", 4),
        ("Bhagat Dhanna Ji", 31), ("Satta & Balwand", 88),
    ]

    func testEveryVoiceKeepsAtLeastOneDot() {
        XCTAssertEqual(DotFieldLayout.dotCount(lines: 4), 1, "4 lines must stay visible, not round to 0")
        XCTAssertEqual(DotFieldLayout.dotCount(lines: 0), 1)
        XCTAssertEqual(DotFieldLayout.dotCount(lines: 10_997), 220)
        let l = DotFieldLayout.make(voices: voices, roster: [:], grouping: .voice, width: 320)
        XCTAssertEqual(Set(l.dots.map(\.voice)), Set(voices.map(\.author)))
    }

    func testNoDotOverlapsAnotherInAnyGrouping() {
        for g in DotFieldLayout.Grouping.allCases {
            let l = DotFieldLayout.make(voices: voices, roster: [:], grouping: g, width: 320)
            let keys = l.positions.map { "\(Int($0.x * 10)),\(Int($0.y * 10))" }
            XCTAssertEqual(Set(keys).count, keys.count, "\(g): two dots share a position")
            XCTAssertTrue(l.positions.allSatisfy { $0.x >= 0 && $0.x <= 320 }, "\(g): a dot left the field")
            XCTAssertGreaterThan(l.size.height, 0)
        }
    }

    func testDotIdentityIsStableAcrossGroupingsSoTheMorphIsHonest() {
        let a = DotFieldLayout.make(voices: voices, roster: [:], grouping: .voice, width: 320)
        let b = DotFieldLayout.make(voices: voices, roster: [:], grouping: .tradition, width: 320)
        let c = DotFieldLayout.make(voices: voices, roster: [:], grouping: .century, width: 320)
        XCTAssertEqual(a.dots, b.dots)
        XCTAssertEqual(a.dots, c.dots)
    }

    func testRegroupingMidFlightStartsFromTheDisplayedPositions() {
        let a = DotFieldLayout.make(voices: voices, roster: [:], grouping: .voice, width: 320).positions
        let b = DotFieldLayout.make(voices: voices, roster: [:], grouping: .tradition, width: 320).positions
        let t0 = Date(timeIntervalSince1970: 1_000)
        // morph a → b, interrupted halfway
        let mid = t0.addingTimeInterval(DotMorph.duration / 2)
        let p = DotMorph.progress(start: t0, now: mid)
        XCTAssertGreaterThan(p, 0); XCTAssertLessThan(p, 1)
        let displayed = DotMorph.interpolate(a, b, p)
        // the next morph begins from `displayed`: at its first instant nothing moves
        let next = DotMorph.interpolate(displayed, a, DotMorph.progress(start: mid, now: mid))
        XCTAssertEqual(next, displayed, "regrouping must not jump the dots back to a layout's target")
        // and it lands exactly on the new layout
        XCTAssertEqual(DotMorph.interpolate(displayed, a, DotMorph.progress(start: mid, now: mid.addingTimeInterval(1))), a)
        XCTAssertEqual(DotMorph.progress(start: nil, now: mid), 1, "no morph running: final positions")
    }

    func testTraditionFallsBackToTheNameForVoicesTheRosterDoesNotListYet() {
        XCTAssertEqual(VoiceKind.of("Guru Tegh Bahadur Ji (M9)", roster: [:]), .guru)
        XCTAssertEqual(VoiceKind.of("Bhagat Surdas Ji", roster: [:]), .bhagat)
        XCTAssertEqual(VoiceKind.of("Sheikh Farid Ji", roster: [:]), .bhagat)
        XCTAssertEqual(VoiceKind.of("Bhatt Nal (ਭਟ)", roster: [:]), .bhatt)
        XCTAssertEqual(VoiceKind.of("The Bhatts (ਭਟ)", roster: [:]), .bhatt)
        XCTAssertEqual(VoiceKind.of("Baba Sundar Ji", roster: [:]), .gursikh)
    }

    func testCenturyTitles() {
        XCTAssertEqual(VoiceKind.centuryTitle(12), "12th century")
        XCTAssertEqual(VoiceKind.centuryTitle(15), "15th century")
        XCTAssertEqual(VoiceKind.centuryTitle(21), "21st century")
        XCTAssertEqual(VoiceKind.centuryTitle(nil), "Dates uncertain")
    }

    func testRibbonColumnsAddUpAndNameWhoSingsThere() {
        var kabir = Array(repeating: 0, count: VoicesAtlas.bucketCount)
        var nanak = Array(repeating: 0, count: VoicesAtlas.bucketCount)
        kabir[0] = 5; kabir[136] = 40       // Angs 1–10 and Kabir's saloks at 1361–1370
        nanak[0] = 30
        let atlas = VoicesAtlas(histogram: ["Bhagat Kabir Ji": kabir, "Guru Nanak Dev Ji (M1)": nanak],
                                places: [:], entries: [:])
        let m = RibbonModel(atlas: atlas, roster: [:])
        XCTAssertEqual(m.columns.count, VoicesAtlas.bucketCount)
        XCTAssertEqual(m.columns[0].total, 35)
        XCTAssertEqual(m.columns[0].voices.map(\.0), ["Guru Nanak Dev Ji (M1)", "Bhagat Kabir Ji"], "most lines first")
        XCTAssertEqual(m.peak, 40)
        XCTAssertEqual(m.columns[1].total, 0)
        XCTAssertTrue(RibbonModel.describe(136, column: m.columns[136], selected: "Bhagat Kabir Ji")
            .contains("Angs 1361 to 1370: Bhagat Kabir Ji, 40 lines"))
        XCTAssertTrue(RibbonModel.describe(1, column: m.columns[1], selected: "Bhagat Kabir Ji")
            .contains("does not sing here"))
    }
}
