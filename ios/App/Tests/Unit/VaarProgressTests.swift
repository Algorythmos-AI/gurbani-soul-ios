import XCTest
import GurbaniSearchKit
@testable import SGGS

@MainActor
final class VaarProgressTests: XCTestCase {

    private var dir: URL!

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("vaar-progress-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws { try? FileManager.default.removeItem(at: dir) }

    private var url: URL { dir.appendingPathComponent(VaarProgressStore.filename) }

    func testPositionsPersistAndTheNewestUnfinishedIsCurrent() {
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        let a = VaarProgressStore(url: url)
        XCTAssertNil(a.current())
        a.setPosition(2, lineId: 5700, pauriNo: 3, nPauris: 27, at: t0)
        a.setPosition(5, lineId: 20900, pauriNo: 12, nPauris: 24, at: t0.addingTimeInterval(60))
        let b = VaarProgressStore(url: url)          // reload from disk
        XCTAssertEqual(b.current()?.vaarId, 5)
        XCTAssertEqual(b.fraction(for: 5), 0.5, accuracy: 0.0001)
        b.markComplete(5, at: t0.addingTimeInterval(120))
        XCTAssertEqual(b.fraction(for: 5), 1)
        XCTAssertEqual(b.current()?.vaarId, 2, "a finished Vaar is not offered to continue")
        // reading a finished Vaar again makes it current again
        b.setPosition(5, lineId: 20950, pauriNo: 13, nPauris: 24, at: t0.addingTimeInterval(180))
        XCTAssertEqual(b.current()?.vaarId, 5)
        XCTAssertLessThan(b.fraction(for: 5), 1)
        b.reset(5)
        XCTAssertNil(b.position(for: 5))
    }

    func testTheFirstPositionIsSaved() {
        let s = VaarProgressStore(url: url)
        s.setPosition(19, lineId: 51554, pauriNo: 1, nPauris: 3)
        XCTAssertEqual(VaarProgressStore(url: url).position(for: 19)?.lineId, 51554, "a first position must reach disk")
        s.setPosition(19, lineId: 51554, pauriNo: 1, nPauris: 3)       // unchanged: no write, no error
        s.markComplete(19)
        XCTAssertEqual(VaarProgressStore(url: url).fraction(for: 19), 1)
    }

    func testCorruptFileIsMovedAsideNotLost() throws {
        try Data("not json".utf8).write(to: url)
        let s = VaarProgressStore(url: url)
        XCTAssertFalse(s.isReadOnly)
        XCTAssertNil(s.current())
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertTrue(names.contains { $0.hasPrefix("\(VaarProgressStore.filename).unreadable-") }, "\(names)")
    }

    func testNewerSchemaIsReadOnly() throws {
        try Data(#"{"schemaVersion": 9, "vaars": {}, "future": true}"#.utf8).write(to: url)
        let s = VaarProgressStore(url: url)
        XCTAssertTrue(s.isReadOnly)
        s.setPosition(1, lineId: 3302, pauriNo: 1, nPauris: 21)
        XCTAssertTrue(String(decoding: try Data(contentsOf: url), as: UTF8.self).contains("future"), "a newer file is never overwritten")
    }

    func testVaultCoversVaarProgress() {
        XCTAssertTrue(UITestVault.defaultItems().contains { $0.name == "vaar-progress" },
                      "UI tests wipe vaar progress, so the vault must seal it first")
    }
}

final class VaarReaderRowIdTests: XCTestCase {
    func testRowIdsNeverCollideOrOverflow() {
        XCTAssertNil(VaarReaderScreen.unitIndex(fromRowId: VaarReaderScreen.headingRowId))
        XCTAssertNil(VaarReaderScreen.unitIndex(fromRowId: VaarReaderScreen.endRowId))
        XCTAssertNil(VaarReaderScreen.unitIndex(fromRowId: 3302), "a line id is not a unit row")
        for i in [0, 1, 109] {
            XCTAssertEqual(VaarReaderScreen.unitIndex(fromRowId: VaarReaderScreen.unitRowId(i)), i)
            XCTAssertLessThan(VaarReaderScreen.unitRowId(i), 0)
        }
        XCTAssertNotEqual(VaarReaderScreen.headingRowId, VaarReaderScreen.endRowId)
        let mark = VaarReaderScreen.angMarkRowId(1430)
        XCTAssertNil(VaarReaderScreen.unitIndex(fromRowId: mark), "an Ang marker is not a unit row")
        XCTAssertEqual(VaarReaderScreen.ang(fromRowId: mark), 1430)
        XCTAssertNil(VaarReaderScreen.ang(fromRowId: VaarReaderScreen.unitRowId(109)))
        XCTAssertNil(VaarReaderScreen.ang(fromRowId: 3302))
    }
}

/// Where the Vaar reader opens (`VaarReaderScreen.landing`).
final class VaarReaderLandingTests: XCTestCase {
    /// heading 100–101 · salok 102 (label) 103–104 · salok 105 (label) 106 · pauri 107 (label) 108–109
    private let t: VaarText = {
        func l(_ id: Int, _ header: Bool = false) -> VaarLine { VaarLine(id: id, ang: 10, isHeader: header, gurmukhi: "ਤੁਕ") }
        return VaarText(vaarId: 1, heading: [l(100, true), l(101, true)], dhuni: nil, units: [
            VaarTextUnit(index: 0, kind: .salok, pauriNo: nil, label: l(102, true), author: nil, lines: [l(102, true), l(103), l(104)]),
            VaarTextUnit(index: 1, kind: .salok, pauriNo: nil, label: l(105, true), author: nil, lines: [l(105, true), l(106)]),
            VaarTextUnit(index: 2, kind: .pauri, pauriNo: 1, label: l(107, true), author: nil, lines: [l(107, true), l(108), l(109)]),
        ])
    }()
    private func saved(_ line: Int, done: Bool = false) -> VaarPosition {
        let t0 = Date(timeIntervalSince1970: 1_000)
        return VaarPosition(lineId: line, pauriNo: 1, nPauris: 1, lastReadAt: t0, completedAt: done ? t0.addingTimeInterval(1) : nil)
    }

    func testPrecedenceExplicitThenSavedThenHeading() {
        XCTAssertNil(VaarReaderScreen.landing(in: t, startLineId: nil, saved: nil, paurisOnly: false), "nothing → heading")
        XCTAssertEqual(VaarReaderScreen.landing(in: t, startLineId: nil, saved: saved(106), paurisOnly: false), 106)
        XCTAssertEqual(VaarReaderScreen.landing(in: t, startLineId: 108, saved: saved(106), paurisOnly: false), 108, "explicit wins")
        XCTAssertEqual(VaarReaderScreen.landing(in: t, startLineId: 9_999, saved: saved(106), paurisOnly: false), 106,
                       "a line outside the Vaar falls back to the saved position")
        XCTAssertNil(VaarReaderScreen.landing(in: t, startLineId: nil, saved: saved(106, done: true), paurisOnly: false),
                     "a finished Vaar opens at its heading")
    }

    func testADeepLinkedPauriComesAfterAnExplicitLine() {
        XCTAssertEqual(VaarReaderScreen.landing(in: t, startLineId: nil, startPauri: 1, saved: saved(103), paurisOnly: false), 108)
        XCTAssertEqual(VaarReaderScreen.landing(in: t, startLineId: 104, startPauri: 1, saved: nil, paurisOnly: false), 104)
        XCTAssertEqual(VaarReaderScreen.landing(in: t, startLineId: nil, startPauri: 9, saved: saved(103), paurisOnly: false), 103,
                       "a pauri the Vaar doesn't have falls back to the saved position")
    }

    func testLabelLinesLandOnTheirUnitRow() {
        XCTAssertEqual(VaarReaderScreen.landing(in: t, startLineId: 105, saved: nil, paurisOnly: false),
                       VaarReaderScreen.unitRowId(1))
    }

    func testPaurisOnlyLandsOnThePauriASalokLeadsInto() {
        XCTAssertEqual(VaarReaderScreen.landing(in: t, startLineId: 103, saved: nil, paurisOnly: true),
                       VaarReaderScreen.unitRowId(2))
        XCTAssertEqual(VaarReaderScreen.landing(in: t, startLineId: 109, saved: nil, paurisOnly: true), 109,
                       "a pauri line stays put")
    }
}
