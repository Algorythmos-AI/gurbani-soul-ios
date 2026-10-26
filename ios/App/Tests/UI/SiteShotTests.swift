import XCTest

/// Capture-only screens for gurbanisoul.com that `testCaptureScreens` does not reach: Search in
/// Verify mode, and About. Skipped unless TEST_RUNNER_SGGS_SHOT_DIR is set, so CI time is unchanged.
/// Self-contained (its own helpers, nothing shared with SGGSUITests) so the site-shots workflow can
/// also drop it into an older tag's checkout as a driver: the app under test is still the tag's.
final class SiteShotTests: XCTestCase {

    override func setUp() { continueAfterFailure = true }
    override func tearDown() { XCUIApplication().terminate() }

    private func shotDir() throws -> String {
        guard let dir = ProcessInfo.processInfo.environment["SGGS_SHOT_DIR"] else {
            throw XCTSkip("capture-only: set TEST_RUNNER_SGGS_SHOT_DIR")
        }
        return dir
    }

    /// The capture launch of SGGSUITests: UI-test residue cleared, the Raag Clock pinned and the
    /// app's own Appearance pinned (argument domain only, never stored).
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["SGGS_UITEST"] = "1"
        let env = ProcessInfo.processInfo.environment
        for key in ["SGGS_CLOCK_NOW", "SGGS_CLOCK_MODE", "SGGS_CLOCK_NO_COORDS"] {
            if let v = env[key] { app.launchEnvironment[key] = v }
        }
        if let look = env["SGGS_SHOT_APPEARANCE"] { app.launchArguments += ["-sggs_appearance", look] }
        app.launch()
        return app
    }

    private func shot(_ app: XCUIApplication, _ dir: String, _ name: String) {
        let png = app.screenshot()
        try? png.pngRepresentation.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
        let a = XCTAttachment(screenshot: png)
        a.name = "shot \(name)"; a.lifetime = .keepAlways; add(a)
    }

    private func openTab(_ app: XCUIApplication, _ name: String, expectingNavBar nav: String) {
        for _ in 0..<3 {
            let bar = app.tabBars.buttons[name]
            (bar.waitForExistence(timeout: 2) ? bar : app.buttons[name].firstMatch).tap()
            if app.navigationBars[nav].waitForExistence(timeout: 4) { return }
        }
        XCTFail("tab \(name) did not open \(nav)")
    }

    /// Search → Verify: a Japji line typed in Roman, checked against the Granth.
    func testCaptureVerify() throws {
        let dir = try shotDir()
        let app = launch()
        openTab(app, "Search", expectingNavBar: "Search")
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 20), "search field missing")
        for _ in 0..<3 {
            field.tap()
            if app.keyboards.firstMatch.waitForExistence(timeout: 3) { break }
        }
        field.typeText("pavan guroo paanee pitaa maataa dharat mahat")
        // The Verify pill is last and off-screen on narrow widths: drag the row from Roman.
        let from = app.buttons["mode_roman"].firstMatch
        XCTAssertTrue(from.waitForExistence(timeout: 5))
        from.press(forDuration: 0.05, thenDragTo: app.buttons["mode_auto"].firstMatch)
        let verify = app.buttons["mode_verify"].firstMatch
        XCTAssertTrue(verify.waitForExistence(timeout: 10))
        var nudges = 0
        while !verify.isHittable && nudges < 4 { from.swipeLeft(); nudges += 1 }
        verify.tap()
        let selected = NSPredicate(format: "isSelected == true")
        if XCTWaiter().wait(for: [expectation(for: selected, evaluatedWith: verify)], timeout: 3) != .completed {
            verify.tap()
        }
        let verdict = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "verified")).firstMatch
        XCTAssertTrue(verdict.waitForExistence(timeout: 20), "verdict not shown")
        shot(app, dir, "verify_typing")
        field.typeText("\n")                       // the keyboard off the verdict
        sleep(1)
        shot(app, dir, "verify")
    }

    /// More → About & credits.
    func testCaptureAbout() throws {
        let dir = try shotDir()
        let app = launch()
        openTab(app, "More", expectingNavBar: "More")
        let about = app.buttons["About & credits"].firstMatch
        for _ in 0..<3 where !about.exists { app.swipeUp() }
        XCTAssertTrue(about.waitForExistence(timeout: 12))
        app.swipeUp()                              // the last row can sit under the floating tab bar
        XCTAssertTrue(about.waitForExistence(timeout: 4)); about.tap()
        XCTAssertTrue(app.staticTexts["aboutVersion"].firstMatch.waitForExistence(timeout: 8), "About did not open")
        shot(app, dir, "about")
    }
}
