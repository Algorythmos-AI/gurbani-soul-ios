import XCTest
import GurbaniSearchKit
@testable import SGGS

/// The pure layout and filter logic behind the Vaars home and weave.
final class VaarsHomeTests: XCTestCase {

    private func unit(_ i: Int, _ kind: VaarTextUnit.Kind, lines n: Int, author: String?, pauri: Int? = nil) -> VaarTextUnit {
        let lines = (0..<n).map { VaarLine(id: i * 100 + $0, ang: 10, isHeader: false, gurmukhi: "ਤੁਕ") }
        return VaarTextUnit(index: i, kind: kind, pauriNo: pauri, label: nil, author: author, lines: lines)
    }

    private func text(_ units: [VaarTextUnit], dhuni: Bool = false) -> VaarText {
        let head = VaarLine(id: 1, ang: 10, isHeader: true, gurmukhi: "ਟੇਸਟ ਕੀ ਵਾਰ")
        return VaarText(vaarId: 1, heading: [head], dhuni: dhuni ? head : nil, units: units)
    }

    func testVoiceStripFillsTheWidthInOrder() {
        let t = text([unit(0, .salok, lines: 4, author: "Guru Nanak Dev Ji (M1)"),
                      unit(1, .salok, lines: 2, author: "Guru Angad Dev Ji (M2)"),
                      unit(2, .pauri, lines: 6, author: "Guru Nanak Dev Ji (M1)", pauri: 1)])
        for width in [3.0, 40.0, 320.0] {
            let segs = VoiceStrip.layout(t, width: CGFloat(width))
            XCTAssertEqual(segs.map(\.index), [0, 1, 2])
            XCTAssertEqual(segs.last!.x + segs.last!.width, CGFloat(width), accuracy: 0.001, "width \(width)")
            for (a, b) in zip(segs, segs.dropFirst()) { XCTAssertLessThanOrEqual(a.x + a.width, b.x + 0.001) }
        }
        XCTAssertTrue(VoiceStrip.layout(t, width: 0).isEmpty)
        XCTAssertEqual(VoiceStrip.summary(t), "1 pauris by Guru Nanak Dev Ji (M1); 2 saloks by 2 voices")
    }

    func testRibbonSpansAndHitTesting() {
        let m = [GranthRibbon.Mark(id: 1, firstAng: 83, lastAng: 91, author: nil, label: "a"),
                 GranthRibbon.Mark(id: 19, firstAng: 1193, lastAng: 1193, author: nil, label: "b"),
                 GranthRibbon.Mark(id: 22, firstAng: 1312, lastAng: 1318, author: nil, label: "c")]
        let w: CGFloat = 343
        XCTAssertGreaterThanOrEqual(GranthRibbon.span(m[1], width: w).width, 3, "a one-Ang Vaar stays visible")
        XCTAssertLessThanOrEqual(GranthRibbon.span(m[2], width: w).maxX, w + 0.001)
        XCTAssertEqual(GranthRibbon.nearest(to: 0, width: w, in: m), 1)
        XCTAssertEqual(GranthRibbon.nearest(to: GranthRibbon.span(m[1], width: w).midX, width: w, in: m), 19)
        XCTAssertEqual(GranthRibbon.nearest(to: w, width: w, in: m), 22)
        XCTAssertNil(GranthRibbon.nearest(to: 10, width: w, in: []))
    }

    func testAngSpanReadsSingleAngs() {
        XCTAssertEqual(angSpan(1193, 1193), "Ang 1193")
        XCTAssertEqual(angSpan(137, 150), "Angs 137–150")
    }

    func testFiltersRoundTripAndHideEmpty() {
        for f in [VaarFilter.all, .voice("Guru Ram Das Ji (M4)"), .dhuni, .short] {
            XCTAssertEqual(VaarFilter(key: f.key), f)
        }
        XCTAssertEqual(VaarFilter(key: "garbage"), .all)
        let s = [VaarSummary(vaarId: 1, raag: nil, roman: nil, firstAng: 83, lastAng: 91, nPauris: 21, nSaloks: 43,
                             pauriAuthor: "Guru Ram Das Ji (M4)", salokAuthors: [], crossAuthor: true, title: nil)]
        let long = text((0..<21).map { unit($0, .pauri, lines: 2, author: nil, pauri: $0 + 1) })
        let avail = VaarFilter.available(in: s, texts: [1: long])
        XCTAssertEqual(avail, [.all, .voice("Guru Ram Das Ji (M4)")], "no ਧੁਨੀ and nothing short → those chips hide")
        let short = VaarFilter.available(in: s, texts: [1: text([unit(0, .pauri, lines: 2, author: nil, pauri: 1)], dhuni: true)])
        XCTAssertEqual(short, [.all, .voice("Guru Ram Das Ji (M4)"), .dhuni, .short])
        XCTAssertEqual(VaarFilter.voice("Guru Ram Das Ji (M4)").title, "M4")
    }

    func testWeaveGroupsSaloksBeforeTheirPauri() {
        let t = text([unit(0, .salok, lines: 2, author: nil), unit(1, .salok, lines: 2, author: nil),
                      unit(2, .pauri, lines: 5, author: nil, pauri: 1), unit(3, .pauri, lines: 5, author: nil, pauri: 2),
                      unit(4, .salok, lines: 2, author: nil)])
        let g = VaarWeaveScreen.groups(t)
        XCTAssertEqual(g.map { $0.saloks.map(\.index) }, [[0, 1], [], [4]])
        XCTAssertEqual(g.map { $0.pauri?.pauriNo }, [1, 2, nil])
        XCTAssertEqual(Set(g.map(\.id)).count, g.count, "group ids are unique")
    }
}
