import XCTest
import GurbaniSearchKit
@testable import SGGS

/// The theme verse list's paging state: pages append only from the open cursor, so a duplicate or
/// stale reply can never repeat or reorder a verse, and the footer always tells the truth.
final class ThemeFeedTests: XCTestCase {

    private func line(_ id: Int) -> SearchLine {
        SearchLine(id: id, ang: 1, gurmukhi: "ਨਾਮੁ", translit: "naam", raag: nil, section: nil, author: nil,
                   compId: 1, isRahao: false, isHeader: false)
    }
    private func page(_ ids: [Int], total: Int, next: Int?) -> ThemePage {
        ThemePage(concept: "naam", total: total, lines: ids.map(line), nextAfterId: next)
    }

    func testPagesAppendInOrderUntilTheEnd() {
        var feed = ThemeFeed(first: page([1, 2], total: 5, next: 2))
        XCTAssertEqual(feed.footer, "Showing 2 of 5 verses")
        XCTAssertEqual(feed.cursorToLoad, 2)
        feed.append(page([3, 4], total: 5, next: 4), from: 2)
        feed.append(page([5], total: 5, next: nil), from: 4)
        XCTAssertEqual(feed.lines.map(\.id), [1, 2, 3, 4, 5])
        XCTAssertFalse(feed.hasMore)
        XCTAssertNil(feed.cursorToLoad)
        XCTAssertEqual(feed.footer, "All 5 verses shown")
    }

    func testAStaleOrRepeatedPageIsIgnored() {
        var feed = ThemeFeed(first: page([1, 2], total: 6, next: 2))
        feed.append(page([3, 4], total: 6, next: 4), from: 2)
        feed.append(page([3, 4], total: 6, next: 4), from: 2)     // the same reply twice
        XCTAssertEqual(feed.lines.map(\.id), [1, 2, 3, 4])
        XCTAssertEqual(feed.nextAfterId, 4)
    }

    func testNoRequestWhileLoadingOrAfterAFailure() {
        var feed = ThemeFeed(first: page([1], total: 3, next: 1))
        feed.loadingMore = true
        XCTAssertNil(feed.cursorToLoad, "a second trigger while loading must not fire")
        feed.loadingMore = false
        feed.moreFailed = "offline"
        XCTAssertNil(feed.cursorToLoad, "a failure waits for Try again")
        feed.moreFailed = nil
        XCTAssertEqual(feed.cursorToLoad, 1)
    }

    func testSingleVerseFooter() {
        XCTAssertEqual(ThemeFeed(first: page([9], total: 1, next: nil)).footer, "1 verse")
        XCTAssertEqual(ThemeFeed().footer, "")
    }
}
