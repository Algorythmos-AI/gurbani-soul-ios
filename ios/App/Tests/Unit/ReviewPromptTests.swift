import XCTest
@testable import SGGS

/// The app asks for a rating only after real use, and at most once per version.
final class ReviewPromptTests: XCTestCase {
    func testNotBeforeThreeReadingDays() {
        XCTAssertFalse(ReviewPrompt.shouldAsk(readingDays: 0, lastPromptedVersion: nil, currentVersion: "1.4.3"))
        XCTAssertFalse(ReviewPrompt.shouldAsk(readingDays: 2, lastPromptedVersion: nil, currentVersion: "1.4.3"))
        XCTAssertTrue(ReviewPrompt.shouldAsk(readingDays: 3, lastPromptedVersion: nil, currentVersion: "1.4.3"))
    }

    func testAtMostOncePerVersion() {
        XCTAssertFalse(ReviewPrompt.shouldAsk(readingDays: 10, lastPromptedVersion: "1.4.3", currentVersion: "1.4.3"))
        XCTAssertTrue(ReviewPrompt.shouldAsk(readingDays: 10, lastPromptedVersion: "1.4.2", currentVersion: "1.4.3"))
        XCTAssertFalse(ReviewPrompt.shouldAsk(readingDays: 10, lastPromptedVersion: nil, currentVersion: ""))
    }

    @MainActor
    func testReadingDaysCountDistinctDaysAcrossBanis() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("review-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = NitnemProgressStore(url: url)
        let day = 86_400.0
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        store.markComplete("japji", on: t0)
        store.markComplete("jaap", on: t0)                      // same day, another bani
        XCTAssertEqual(store.distinctReadingDays, 1)
        store.markComplete("japji", on: t0.addingTimeInterval(day))
        store.markComplete("rehras", on: t0.addingTimeInterval(2 * day))
        XCTAssertEqual(store.distinctReadingDays, 3)
    }

    func testTheRateLinkOpensTheWriteReviewSheet() {
        XCTAssertEqual(AppLinks.writeReview.absoluteString, "https://apps.apple.com/app/id6812982384?action=write-review")
    }
}
