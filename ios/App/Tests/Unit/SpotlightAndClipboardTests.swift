import XCTest
import UIKit
import GurbaniDB
@testable import SGGS

/// Spotlight's launch decision (the platform index itself is not observable in unit tests, so the
/// decision is a pure seam) and the clipboard round trip of verbatim scripture.
@MainActor
final class SpotlightAndClipboardTests: XCTestCase {
    private struct ReadFailed: Error {}
    private func line(_ id: Int) -> SavedLine { SavedLine(lineId: id, gurmukhi: "ਸਚੁ", translit: "sach", ang: 1, compId: 2) }

    func testOnlyASuccessfullyReadPersistentStoreMayReplaceTheIndex() {
        if case .reconcile(let rows) = SpotlightIndex.launchAction(degraded: false, saved: .success([line(1), line(2)])) {
            XCTAssertEqual(rows.map(\.lineId), [1, 2])
        } else { XCTFail("a readable store reconciles") }
        if case .reconcile(let rows) = SpotlightIndex.launchAction(degraded: false, saved: .success([])) {
            XCTAssertTrue(rows.isEmpty, "a readable, empty store correctly clears the index")
        } else { XCTFail("an empty readable store reconciles") }
    }

    func testADegradedOrUnreadableStoreNeverTouchesTheIndex() {
        guard case .leaveAlone = SpotlightIndex.launchAction(degraded: false, saved: .failure(ReadFailed())) else {
            return XCTFail("a failed read must not clear entries it cannot rebuild")
        }
        guard case .leaveAlone = SpotlightIndex.launchAction(degraded: true, saved: .success([line(1)])) else {
            return XCTFail("an in-memory store must not replace the index")
        }
    }

    /// Copy puts the verbatim string on the pasteboard; reading it back must give the same Unicode
    /// scalars — no normalisation, no reordering — for the Charter S lines and every line with a
    /// subjoined ya (the display-only yakash must never be what is copied).
    func testVerbatimScriptureSurvivesThePasteboardScalarForScalar() throws {
        guard let path = Bundle.main.url(forResource: "sggs-ios", withExtension: "sqlite")?.path
        else { throw XCTSkip("bundled DB not found in host app") }
        let db = try SQLiteCandidateSource(path: path)
        var samples: [String] = []
        for n in [1, 712, 1256, 1400, 1430] { samples += try db.fetchAng(n).lines.map(\.gurmukhi) }
        let pair = Array(Saroop.verbatimPair.unicodeScalars)
        for n in 1...1430 {
            for l in try db.fetchAng(n).lines {
                let s = Array(l.gurmukhi.unicodeScalars)
                if s.count >= pair.count, (0...(s.count - pair.count)).contains(where: { Array(s[$0..<($0 + pair.count)]) == pair }) {
                    samples.append(l.gurmukhi)
                }
            }
        }
        XCTAssertGreaterThanOrEqual(samples.count, 234 + 100)
        let board = try XCTUnwrap(UIPasteboard(name: UIPasteboard.Name("org.sggs.tests.\(UUID().uuidString)"), create: true))
        defer { UIPasteboard.remove(withName: board.name) }
        for g in samples {
            board.string = g
            let back = try XCTUnwrap(board.string)
            XCTAssertEqual(Array(back.unicodeScalars), Array(g.unicodeScalars), g)
            XCTAssertFalse(back.unicodeScalars.contains(Saroop.yakash))
        }
    }
}
