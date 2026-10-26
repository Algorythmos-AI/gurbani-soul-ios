import XCTest
import GurbaniDB
import GurbaniSearchKit
@testable import SGGS

/// The Granth Ribbon's geometry on the SHIPPED DB: the strip covers Ang 1…1430 exactly, works sit
/// end to end with nothing at zero width, and every Ang maps back to the work that holds it.
final class RibbonLayoutTests: XCTestCase {

    private func layout() throws -> (RibbonLayout, GranthMap) {
        guard let path = Bundle.main.url(forResource: "sggs-ios", withExtension: "sqlite")?.path
            ?? Bundle(for: Self.self).url(forResource: "sggs-ios", withExtension: "sqlite")?.path
        else { throw XCTSkip("bundled DB not found in host app") }
        let map = GranthMap(meta: try SQLiteCandidateSource(path: path).fetchMeta())
        return (RibbonLayout(map: map), map)
    }

    func testStripIsContiguousAndCoversTheWholeGranth() throws {
        let (l, map) = try layout()
        XCTAssertEqual(l.length, Double(GranthAngs.count), accuracy: 1e-9, "one unit per Ang, 1…\(GranthAngs.count)")
        XCTAssertEqual(l.segments.count, map.opening.count + map.raags.count + map.closing.count)
        XCTAssertEqual(l.segments.first?.x0, 0)
        for (a, b) in zip(l.segments, l.segments.dropFirst()) {
            XCTAssertEqual(a.x1, b.x0, accuracy: 1e-9, "\(a.name) → \(b.name)")
        }
        for s in l.segments { XCTAssertGreaterThan(s.width, 0.25, "\(s.name) drawn too thin") }
        XCTAssertEqual(l.segments.first?.movement, .opening)
        XCTAssertEqual(l.segments.last?.movement, .closing)
        XCTAssertEqual(l.segments.filter { $0.movement == .raags }.count, 31)
    }

    func testEveryAngMapsBackToAWorkThatHoldsIt() throws {
        let (l, _) = try layout()
        for a in GranthAngs.all {
            let x = try XCTUnwrap(l.x(forAng: a), "Ang \(a) is off the strip")
            let s = try XCTUnwrap(l.segment(at: x))
            XCTAssertTrue((s.firstAng...s.lastAng).contains(a), "Ang \(a) landed on \(s.name)")
            XCTAssertTrue((s.firstAng...s.lastAng).contains(s.ang(at: x)))
        }
        let gauri = try XCTUnwrap(l.segment(at: try XCTUnwrap(l.x(forAng: 262))))
        XCTAssertEqual(gauri.name, "ਗਉੜੀ")
        XCTAssertEqual(gauri.ang(at: gauri.x(forAng: 262)), 262, "an Ang survives the round trip")
    }

    func testEdgesClampInsteadOfFailing() throws {
        let (l, _) = try layout()
        XCTAssertEqual(l.segment(at: -50)?.id, l.segments.first?.id)
        XCTAssertEqual(l.segment(at: 1e9)?.id, l.segments.last?.id)
        XCTAssertEqual(l.segments.last?.ang(at: 1e9), 1430)
        XCTAssertEqual(l.segments.first?.ang(at: -1), 1)
        XCTAssertNil(l.x(forAng: 0))
        XCTAssertNil(l.x(forAng: 1431))
    }

    func testSharedAngsAreSplitNotDoubleCounted() {
        let map = GranthMap(raags: [], sections: [
            SectionRow(name: "a", firstAng: 1, lastAng: 2, nLines: 1),
            SectionRow(name: "b", firstAng: 2, lastAng: 2, nLines: 1),   // one Ang, shared with a and c
            SectionRow(name: "c", firstAng: 2, lastAng: 3, nLines: 1),
        ])
        let l = RibbonLayout(map: map)
        XCTAssertEqual(l.length, 3, accuracy: 1e-9)
        let third: Double = 1.0 / 3
        let widths: [Double] = l.segments.map(\.width)
        XCTAssertEqual(widths.count, 3)
        XCTAssertEqual(widths[0], 1.0 + third, accuracy: 1e-9, "Ang 2 split three ways")
        XCTAssertEqual(widths[1], third, accuracy: 1e-9)
        XCTAssertEqual(widths[2], third + 1.0, accuracy: 1e-9)
        XCTAssertTrue(RibbonLayout(map: GranthMap(raags: [], sections: [])).segments.isEmpty)
        XCTAssertNil(RibbonLayout(map: GranthMap(raags: [], sections: [])).segment(at: 3))
    }

    func testScrubIgnoresScrollsAndLiftsOffTheStrip() {
        XCTAssertTrue(SaroopRibbon.isScrub(.zero), "a tap is a scrub")
        XCTAssertTrue(SaroopRibbon.isScrub(CGSize(width: 120, height: 30)))
        XCTAssertTrue(SaroopRibbon.isScrub(CGSize(width: 4, height: 20)), "a little wobble is still a scrub")
        XCTAssertFalse(SaroopRibbon.isScrub(CGSize(width: 10, height: 80)), "a vertical swipe scrolls the page")
        XCTAssertTrue(SaroopRibbon.liftsOnStrip(y: 20, height: 38))
        XCTAssertTrue(SaroopRibbon.liftsOnStrip(y: -20, height: 38))
        XCTAssertFalse(SaroopRibbon.liftsOnStrip(y: 140, height: 38), "lifting well below cancels")
        XCTAssertFalse(SaroopRibbon.liftsOnStrip(y: -90, height: 38), "lifting well above cancels")
    }

    func testSpokenLabelsNameTheWorkAndItsPlace() throws {
        let (l, map) = try layout()
        let gauri = try XCTUnwrap(l.segments.first { $0.name == "ਗਉੜੀ" })
        XCTAssertEqual(RibbonLayout.spokenLabel(gauri, raagCount: map.raags.count),
                       "Raag Gauri, raag 3 of 31, Angs 151–346, 740 shabads")
        let japji = try XCTUnwrap(l.segments.first)
        XCTAssertEqual(RibbonLayout.spokenLabel(japji, raagCount: 31), "Japji Sahib, before the raags, Angs 1–8")
    }
}
