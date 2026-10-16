import XCTest
@testable import SGGS

/// The reader's ambient chrome must never hide because of the app's own landing scroll.
@MainActor
final class AmbientChromeTests: XCTestCase {
    private func tallPage() -> AmbientChrome {
        var c = AmbientChrome()
        c.contentHeight = 5_000
        c.viewportHeight = 700
        return c
    }

    func testReadingDownHidesTheChrome() {
        var c = tallPage()
        XCTAssertNil(c.scrolled(to: 50))          // not yet past 80 pt
        XCTAssertEqual(c.scrolled(to: 200), true)
    }

    func testALandingScrollNeverHidesTheChrome() {
        var c = tallPage()
        let landing = c.beginLanding()
        XCTAssertNil(c.scrolled(to: 100))
        XCTAssertNil(c.scrolled(to: 900))
        c.endLanding(landing)
        XCTAssertFalse(c.landingInProgress)
    }

    /// CI run 38955222155: two "Next pauri" taps under a second apart. The first tap's timer
    /// switched the guard off while the second jump was still scrolling, so the bar hid under the
    /// reader's finger. Only the latest landing may end the guard.
    func testAnEarlierLandingsTimerNeverEndsALaterLanding() {
        var c = tallPage()
        let first = c.beginLanding()
        let second = c.beginLanding()
        c.endLanding(first)                       // the first tap's 1 s timer fires
        XCTAssertTrue(c.landingInProgress, "the second jump is still landing")
        XCTAssertNil(c.scrolled(to: 100))
        XCTAssertNil(c.scrolled(to: 900), "the landing scroll must not hide the bar")
        c.endLanding(second)
        XCTAssertFalse(c.landingInProgress)
    }
}
