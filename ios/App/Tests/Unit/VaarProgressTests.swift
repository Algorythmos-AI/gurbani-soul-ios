import XCTest
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
    }
}
