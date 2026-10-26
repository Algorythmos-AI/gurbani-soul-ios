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

    /// CI run 40083157947: on a slow simulator a "Next pauri" landing ran about 3 s, past the 1 s
    /// landing window, and its tail hid the bar. Movement the reader did not make never hides it.
    func testMovementTheReaderDidNotMakeNeverHidesTheChrome() {
        var c = tallPage()
        c.userScrolling = false                   // the landing scroll, or row heights settling
        XCTAssertNil(c.scrolled(to: 100))
        XCTAssertNil(c.scrolled(to: 900))
        c.userScrolling = true                    // the reader's own drag starts a fresh run
        XCTAssertNil(c.scrolled(to: 910))
        XCTAssertEqual(c.scrolled(to: 960), true)
    }

    func testAHiddenChromeReturnsAtTheTopWhateverMovedThePage() {
        var c = tallPage()
        c.userScrolling = true
        XCTAssertEqual(c.scrolled(to: 300), true)
        c.userScrolling = false                   // e.g. a tap on the status bar scrolls to the top
        XCTAssertNil(c.scrolled(to: 120))
        XCTAssertEqual(c.scrolled(to: 0), false)
    }

    /// The bar the reader scrolled away comes back on a small upward read (it never did in the
    /// bani reader: `hidden` stayed false, so the restore branch was unreachable).
    func testAnUpwardReadRestoresTheChrome() {
        var c = tallPage()
        XCTAssertEqual(c.scrolled(to: 300), true)
        XCTAssertTrue(c.hidden)
        XCTAssertNil(c.scrolled(to: 400), "already hidden: no change to report")
        XCTAssertEqual(c.scrolled(to: 390), false)
        XCTAssertFalse(c.hidden)
    }
}
