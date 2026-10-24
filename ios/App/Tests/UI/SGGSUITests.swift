import XCTest

final class SGGSUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }
    /// End of the class: one ordinary launch hands the device's real data back (UITestVault), so
    /// a finished run never leaves it in the vault.
    override class func tearDown() {
        MainActor.assumeIsolated {
            let app = XCUIApplication()
            app.launch()
            _ = app.wait(for: .runningForeground, timeout: 30)
            app.terminate()
        }
        super.tearDown()
    }

    /// Every test ends with the app terminated so no keyboard/sheet/tab state leaks into the next.
    override func tearDown() {
        // TEST_RUNNER_SGGS_KEEP_APP=1 leaves the app running after a test (manual screenshots)
        if ProcessInfo.processInfo.environment["SGGS_KEEP_APP"] != "1" { XCUIApplication().terminate() }
    }

    /// Launch with the UI-test environment: the app (Debug only) clears per-launch residue
    /// (resume-last-Ang, transliteration toggle) — never the accent, whose persistence is under test.
    /// The app opens on the Nitnem tab; `selectSearch` (the default) then moves to Search so
    /// the search-driven tests start where they always did.
    private func launchApp(selectSearch: Bool = true, arguments: [String] = [],
                           forwardCaptureEnv: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["SGGS_UITEST"] = "1"
        app.launchArguments += arguments
        if forwardCaptureEnv {
            // Capture runs only: the runner's TEST_RUNNER_SGGS_CLOCK_* pins the Raag Clock (Debug
            // hooks; never present in Release) so the dial agrees with the 9:41 status bar.
            let env = ProcessInfo.processInfo.environment
            for key in ["SGGS_CLOCK_NOW", "SGGS_CLOCK_MODE", "SGGS_CLOCK_NO_COORDS"] {
                if let v = env[key] { app.launchEnvironment[key] = v }
            }
            // the app's own Appearance wins over the device's: pin it for the capture (argument
            // domain only, never stored)
            if let look = env["SGGS_SHOT_APPEARANCE"] { app.launchArguments += ["-sggs_appearance", look] }
        }
        app.launch()
        if selectSearch { openTab(app, "Search", expectingNavBar: "Search") }
        return app
    }

    /// Poll a static text's label (a value the UI sets a beat after an action, e.g. a scroll landing).
    private func waitLabel(_ element: XCUIElement, hasPrefix prefix: String, timeout: TimeInterval = 8) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.exists, element.label.hasPrefix(prefix) { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        return element.exists && element.label.hasPrefix(prefix)
    }

    /// A screenshot into SGGS_SHOT_DIR when a capture run sets it (TEST_RUNNER_SGGS_SHOT_DIR); a
    /// no-op in CI, so a test can document the surface it proves without writing anywhere.
    private func captureIfRequested(_ app: XCUIApplication, _ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["SGGS_SHOT_DIR"] else { return }
        try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
    }

    /// The Raag Clock lives under Explore: open the hub, then its card.
    private func openClock(_ app: XCUIApplication) {
        openTab(app, "Explore", expectingNavBar: "Explore")
        let card = app.buttons["Raag Clock"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 12), "Raag Clock card missing")
        card.tap()
        XCTAssertTrue(app.navigationBars["Raag Clock"].waitForExistence(timeout: 12), "Raag Clock did not open")
    }

    /// Tab button that also resolves on iPadOS 26 (top tab bar may not expose `tabBars`).
    private func tab(_ app: XCUIApplication, _ name: String) -> XCUIElement {
        let bar = app.tabBars.buttons[name]
        return bar.waitForExistence(timeout: 2) ? bar : app.buttons[name].firstMatch
    }

    /// Switch tabs and WAIT for the destination to be on screen. The iOS 26 glass tab bar can
    /// swallow a tap while it is minimised/animating (first tap restores it), so verify the
    /// destination's navigation bar and tap once more if it did not arrive.
    private func openTab(_ app: XCUIApplication, _ name: String, expectingNavBar nav: String) {
        for _ in 0..<3 {
            tab(app, name).tap()
            if app.navigationBars[nav].waitForExistence(timeout: 4) { return }
        }
        XCTFail("tab \(name) did not open \(nav)")
    }

    /// Focus the search field and make sure the keyboard is actually up (a tap that lands
    /// during the search-bar layout animation can leave the field unfocused).
    private func focusSearch(_ app: XCUIApplication) -> XCUIElement {
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 20), "search field missing")
        for _ in 0..<3 {
            field.tap()
            if app.keyboards.firstMatch.waitForExistence(timeout: 3) { return field }
            // iPad with a hardware keyboard shows no software keyboard — focus is enough
            if (field.value(forKey: "hasKeyboardFocus") as? Bool) == true { return field }
        }
        XCTFail("search field never took keyboard focus")
        return field
    }

    /// Long-press a verse row until its context menu shows `action` (a long press that
    /// starts mid-scroll can be dropped; retry rather than fail on a synthetic-input hiccup).
    private func contextAction(_ app: XCUIApplication, on element: XCUIElement, _ action: String) -> XCUIElement {
        for _ in 0..<3 {
            element.press(forDuration: 1.1)
            let b = app.buttons[action].firstMatch
            if b.waitForExistence(timeout: 5) { return b }
            app.tap()                                   // dismiss a half-open menu, then retry
        }
        XCTFail("context action \(action) never appeared")
        return app.buttons[action].firstMatch
    }

    // MARK: Jump-sheet helpers

    /// Enter a new Ang into the (seeded, editable) number field: focus, clear the existing digits,
    /// then type the value. Robust whether or not select-all-on-focus has fired.
    private func enterAng(_ app: XCUIApplication, _ value: String, file: StaticString = #file, line: UInt = #line) {
        let field = app.textFields["angField"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 8), "angField missing", file: file, line: line)
        field.tap()
        field.typeText(String(repeating: "\u{8}", count: 5))   // delete up to 5 seeded digits
        field.typeText(value)
    }

    // MARK: Reader pager helpers

    /// The Reader mounts three pages at once (current ±1), so the same in-page control id exists on
    /// off-screen neighbours too. The *visible* page is identified by the pager's own container id
    /// `angPager-<n>` (from the pager, not the router), suffixed `-h0` under UI test so a self-heal —
    /// which would mean the desync bug re-appeared — makes this assertion fail instead of passing quietly.
    private func assertOnAng(_ app: XCUIApplication, _ n: Int, _ note: String = "",
                             timeout: TimeInterval = 12, file: StaticString = #file, line: UInt = #line) {
        XCTAssertTrue(app.navigationBars["Ang \(n)"].waitForExistence(timeout: timeout),
                      "title should read Ang \(n) \(note)", file: file, line: line)
        XCTAssertTrue(app.otherElements["angPager-\(n)-h0"].waitForExistence(timeout: timeout),
                      "the visible page should be Ang \(n) with no self-heal \(note)", file: file, line: line)
        // The regression that shipped: title + pager agreed while the page stayed a skeleton. Require
        // the loaded content view (only present when verses rendered, never on the skeleton).
        XCTAssertTrue(app.scrollViews["angContent-\(n)"].waitForExistence(timeout: timeout),
                      "Ang \(n) must render verses, not a skeleton \(note)", file: file, line: line)
    }

    /// Open the Reader on a specific Ang via the deep link (avoids typing into the Jump sheet and
    /// starts every pager test from a known page).
    private func goReader(_ app: XCUIApplication, at n: Int) {
        XCUIDevice.shared.system.open(URL(string: "sggs://ang/\(n)")!)
        openTab(app, "Reader", expectingNavBar: "Ang \(n)")
    }

    /// The first HITTABLE element with this id — the on-screen page's copy, never a neighbour's.
    private func hittable(_ app: XCUIApplication, button id: String, timeout: TimeInterval = 8) -> XCUIElement? {
        _ = app.buttons[id].firstMatch.waitForExistence(timeout: timeout)
        return app.buttons.matching(identifier: id).allElementsBoundByIndex.first { $0.isHittable }
    }

    /// The on-screen page's scroll view (neighbours are mounted but off-screen / not hittable).
    private func readerScroll(_ app: XCUIApplication) -> XCUIElement {
        app.scrollViews.allElementsBoundByIndex.first { $0.isHittable } ?? app.scrollViews.firstMatch
    }

    /// Scroll the reading area down one screen. `scrollViews.firstMatch` is the current page's
    /// vertical scroll view (the mechanism `testReaderChromeReturnsOnScrollUp` relies on); a
    /// coordinate drag is the fallback if it is not hittable.
    private func dragReaderUp(_ app: XCUIApplication) {
        let sv = app.scrollViews.firstMatch
        if sv.isHittable { sv.swipeUp() ; return }
        let top = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
        let bottom = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
        top.press(forDuration: 0.05, thenDragTo: bottom)
    }

    /// The current page's forward control at the bottom: the "Continues on Ang N+1" hint pill when
    /// the shabad carries over, else the always-present end-of-page "Next · Ang N+1" card.
    private func forwardFooter(_ app: XCUIApplication) -> XCUIElement? {
        // The in-page "Continues on" pill when the shabad carries over; otherwise the page bar's
        // Next (the end-of-page buttons were removed in 1.4.7 — one set of page controls).
        hittable(app, button: "continuesOnPill", timeout: 1) ?? hittable(app, button: "nextAng", timeout: 1)
    }

    /// One page swipe. The simulator occasionally drops a synthesized swipe outright (CI run
    /// 38955222155: the page never moved, title and pager both stayed on the old Ang, no heal).
    /// Only that case — still settled on the old page — is retried once, and the retry is logged;
    /// a page that moved anywhere else, or a skeleton, still fails in `assertOnAng`.
    private func swipePage(_ app: XCUIApplication, from: Int, to: Int, left: Bool) {
        swipeOnce(app, left: left)
        if app.navigationBars["Ang \(to)"].waitForExistence(timeout: 4) { return }
        guard app.navigationBars["Ang \(from)"].exists, app.otherElements["angPager-\(from)-h0"].exists else { return }
        XCTContext.runActivity(named: "swipe from Ang \(from) was not delivered; retrying once") { _ in }
        swipeOnce(app, left: left)
    }

    private func swipeOnce(_ app: XCUIApplication, left: Bool) {
        if left { readerScroll(app).swipeLeft() } else { readerScroll(app).swipeRight() }
    }

    /// THE new regression guard for the reported bug: after a jump, swiping several pages must render
    /// verses on EVERY page — not a permanent skeleton (TestFlight 1.3.0 (4), Angs 352 / 918 / 1106).
    /// `assertOnAng` now requires the content view, so a blank page fails here.
    func testSwipeRunAfterJumpRendersContent() {
        let app = launchApp()
        for start in [1100, 348, 915] {
            goReader(app, at: start)
            assertOnAng(app, start)
            for i in 1...8 {                       // swipe forward past the old 3-4 page eviction cliff
                swipePage(app, from: start + i - 1, to: start + i, left: true)
                assertOnAng(app, start + i, "forward swipe #\(i) from \(start)")
            }
            for i in stride(from: 7, through: 0, by: -1) {
                swipePage(app, from: start + i + 1, to: start + i, left: false)
                assertOnAng(app, start + i, "back swipe to \(start + i)")
            }
        }
    }

    /// The bottom page row never wraps a destination Ang across two lines (2026-10-17 device run:
    /// "135 / 3" at AX3). At the default size the numbers show; at AX3 the row steps down to fit,
    /// and the three controls stay one line high, apart, and tappable.
    func testPageBarStaysOnOneLineAtLargeText() {
        for (size, numbers) in [("UICTContentSizeCategoryL", true), ("UICTContentSizeCategoryAccessibilityXL", false),
                                ("UICTContentSizeCategoryAccessibilityXXXL", false)] {
            let app = launchApp(selectSearch: false, arguments: ["-UIPreferredContentSizeCategoryName", size])
            goReader(app, at: 1354)
            let prev = app.buttons["prevAng"].firstMatch, next = app.buttons["nextAng"].firstMatch
            let hukam = app.buttons["Hukam"].firstMatch
            XCTAssertTrue(prev.waitForExistence(timeout: 12) && prev.isHittable, "\(size): previous not tappable")
            XCTAssertTrue(next.isHittable && hukam.isHittable, "\(size): next/Hukam not tappable")
            for (name, b) in [("previous", prev), ("next", next)] {
                XCTAssertLessThanOrEqual(b.frame.height, hukam.frame.height * 1.3,
                                         "\(size): the \(name) control wrapped onto a second line")
                XCTAssertGreaterThanOrEqual(b.frame.width, 44, "\(size): \(name) tap target too small")
            }
            XCTAssertFalse(prev.frame.intersects(hukam.frame) || hukam.frame.intersects(next.frame), "\(size): controls overlap")
            XCTAssertEqual(prev.value as? String, "Ang 1353"); XCTAssertEqual(next.value as? String, "Ang 1355")
            if numbers {
                XCTAssertTrue(prev.staticTexts["1353"].exists && next.staticTexts["1355"].exists,
                              "\(size): the destination Angs show at the default size")
            }
            captureIfRequested(app, "page_bar_\(size)")
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "page bar \(size)"; shot.lifetime = .keepAlways; add(shot)
            app.terminate()
        }
    }

    /// The "Ang N" title is a control: tapping it opens Jump with the keypad up, and typing a number
    /// then Go lands on a rendered page.
    func testTitleOpensJumpAndTypedAngRenders() {
        let app = launchApp()
        goReader(app, at: 500)
        assertOnAng(app, 500)
        let title = app.buttons["angTitle"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 12), "the Ang title should be a button")
        title.tap()
        XCTAssertTrue(app.textFields["angField"].firstMatch.waitForExistence(timeout: 8), "title tap should open Jump")
        enterAng(app, "1106")
        app.buttons["goToAng"].tap()
        assertOnAng(app, 1106, "after typing an Ang from the title")
    }

    func testLaunchShowsNitnem() {
        let app = launchApp(selectSearch: false)
        XCTAssertTrue(app.navigationBars["Nitnem"].waitForExistence(timeout: 20), "the app opens on the daily reading")
        XCTAssertTrue(app.buttons["bani_japji"].waitForExistence(timeout: 12), "Japji Sahib row missing")
        XCTAssertTrue(app.buttons["Hukam"].exists, "Hukam card missing")
    }

    func testSearchTabReachable() {
        let app = launchApp()
        XCTAssertTrue(app.navigationBars["Search"].waitForExistence(timeout: 20))
    }

    /// Nitnem → Japji Sahib: the bani reader opens on the verbatim Mool Mantar, the position
    /// bar reads, marking it read completes the ring, and Next leads on to Jaap Sahib.
    func testNitnemOpensJapjiAndCompletes() {
        let app = XCUIApplication()
        app.launchEnvironment["SGGS_CLOCK_NOW"] = "300"      // 05:00 → Amrit Vela
        app.launchEnvironment["SGGS_UITEST"] = "1"
        app.launch()
        XCTAssertTrue(app.navigationBars["Nitnem"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["Amrit Vela"].waitForExistence(timeout: 8), "band title missing")
        let row = app.buttons["bani_japji"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 12))
        for _ in 0..<4 where !row.isHittable { app.swipeUp() }   // the Hukam cards sit above the banis
        row.tap()
        XCTAssertTrue(app.navigationBars["Japji Sahib"].waitForExistence(timeout: 12), "bani reader did not open")
        let mool = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "ੴ ਸਤਿ ਨਾਮੁ ਕਰਤਾ ਪੁਰਖੁ")).firstMatch
        XCTAssertTrue(mool.waitForExistence(timeout: 12), "Mool Mantar (verbatim) missing at the top of Japji")
        XCTAssertTrue(app.staticTexts["baniPosition"].firstMatch.waitForExistence(timeout: 8), "position bar missing")
        // go to the end and mark it read. Japji steps pauri by pauri, so the bar's forward control
        // reads "Next pauri", not "End" — use its stable identifier and step until the end appears.
        let forward = app.buttons["baniForward"].firstMatch
        XCTAssertTrue(forward.waitForExistence(timeout: 8), "position bar forward control missing")
        let mark = app.buttons["baniMarkComplete"].firstMatch
        var steps = 0
        var scrolledDown = false
        while !(mark.exists && mark.isHittable) && steps < 80 {
            if !forward.exists {
                // The bar hides only when the reader scrolls down. After a Next tap it must stay put
                // (CI run 38955222155: an earlier tap's landing timer let the jump hide it).
                XCTAssertTrue(scrolledDown, "the position bar hid after a Next tap (step \(steps))")
                if !scrolledDown { break }
                app.swipeDown(velocity: .slow)     // a small upward read brings it back, by design
                scrolledDown = false
            } else if forward.isEnabled {
                forward.tap(); scrolledDown = false
            } else {
                app.swipeUp(); scrolledDown = true
            }
            steps += 1
        }
        XCTAssertTrue(mark.waitForExistence(timeout: 12), "Mark as read missing at the end (\(steps) steps)")
        mark.tap()
        let next = app.buttons["nitnemNext"].firstMatch
        XCTAssertTrue(next.waitForExistence(timeout: 8), "Next bani action missing after completion")
        XCTAssertTrue(next.label.contains("Jaap Sahib"), "next bani should be Jaap Sahib, got \(next.label)")
        next.tap()
        XCTAssertTrue(app.navigationBars["Jaap Sahib"].waitForExistence(timeout: 12), "Next did not open Jaap Sahib")
        // the extra layer is labelled, never cited as an Ang
        // the header is one combined element and each LineRow is one element: query any kind
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", "Sri Dasam Granth")).firstMatch
            .waitForExistence(timeout: 8), "Dasam source label missing")
    }

    /// The Live Activity opt-in is present in More and defaults off (never on without consent).
    func testLiveActivityToggleDefaultsOff() {
        let app = launchApp(selectSearch: false)
        openTab(app, "More", expectingNavBar: "More")
        let toggle = app.switches["liveActivityToggle"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 12), "Live Activity toggle missing in More")
        XCTAssertEqual(toggle.value as? String, "0", "Live Activity must default OFF")
    }

    /// My Nitnem: the editor opens from More and shows the set picker, the morning banis and the
    /// "Add a bani" affordance. (Reorder/hide/add persistence is covered by NitnemSetsTests and
    /// validated on-device.)
    func testMyNitnemEditorOpens() {
        let app = launchApp(selectSearch: false)
        openTab(app, "More", expectingNavBar: "More")
        let link = app.buttons["nitnemSetsLink"].firstMatch
        XCTAssertTrue(link.waitForExistence(timeout: 12), "My Nitnem link missing in More")
        link.tap()
        XCTAssertTrue(app.navigationBars["My Nitnem"].waitForExistence(timeout: 8), "My Nitnem did not open")
        XCTAssertTrue(app.buttons["nitnemSetsAdd"].firstMatch.waitForExistence(timeout: 6), "Add a bani missing")
        XCTAssertTrue(app.staticTexts["Japji Sahib"].firstMatch.exists, "morning set not shown")
        // switch to the Sohila set and confirm the header changes
        app.buttons["Sohila"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Kirtan Sohila"].firstMatch.waitForExistence(timeout: 6), "Sohila set not shown")
    }

    /// Reminders: the screen opens from More and shows a toggle for each of the three daily sets
    /// plus the calm, offline footer. (Toggling → scheduling is covered by NitnemRemindersTests
    /// and validated on-device; a SwiftUI Toggle is not reliably tappable from XCUITest here.)
    func testNitnemRemindersScreenOpens() {
        let app = launchApp(selectSearch: false)
        openTab(app, "More", expectingNavBar: "More")
        let link = app.buttons["nitnemRemindersLink"].firstMatch
        XCTAssertTrue(link.waitForExistence(timeout: 12), "Reminders link missing in More")
        link.tap()
        XCTAssertTrue(app.navigationBars["Reminders"].waitForExistence(timeout: 8), "Reminders screen did not open")
        XCTAssertTrue(app.switches["reminder_amritVela"].firstMatch.waitForExistence(timeout: 6), "Amrit Vela toggle missing")
        XCTAssertTrue(app.switches["reminder_evening"].firstMatch.exists, "Rehras toggle missing")
        XCTAssertTrue(app.switches["reminder_night"].firstMatch.exists, "Sohila toggle missing")
        XCTAssertTrue(app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "no account, no network")).firstMatch.exists,
            "offline reassurance footer missing")
    }

    /// Privacy Policy is reachable inside the app (Guideline 5.1.1(i)): a row in More opens a
    /// static, offline policy screen that states the "Data Not Collected" stance.
    func testPrivacyPolicyReachableFromMore() {
        let app = launchApp(selectSearch: false)
        openTab(app, "More", expectingNavBar: "More")
        // More is a lazy List longer than the screen: rows below the fold do not exist until scrolled to
        let link = app.buttons["privacyPolicyLink"].firstMatch
        var swipes = 0
        while !link.waitForExistence(timeout: 2) && swipes < 8 { app.swipeUp(); swipes += 1 }
        XCTAssertTrue(link.waitForExistence(timeout: 12), "Privacy Policy link missing in More")
        XCTAssertTrue(app.buttons["supportLink"].firstMatch.exists, "Support link missing in More")
        link.tap()
        XCTAssertTrue(app.navigationBars["Privacy Policy"].waitForExistence(timeout: 8), "Privacy Policy screen did not open")
        // the policy is a lazy List too: its "Data Not Collected" paragraph is below the fold
        let stance = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "Data Not Collected")).firstMatch
        var down = 0
        while !stance.waitForExistence(timeout: 2) && down < 8 { app.swipeUp(); down += 1 }
        XCTAssertTrue(stance.exists, "Privacy Policy screen does not state the Data Not Collected stance")
        // a SwiftUI Link's element type varies by iOS version: match the identifier on any type
        let web = app.descendants(matching: .any).matching(identifier: "privacyWebLink").firstMatch
        var more = 0
        while !web.waitForExistence(timeout: 2) && more < 4 { app.swipeUp(); more += 1 }
        XCTAssertTrue(web.exists, "online policy link missing")
    }

    /// More offers "Rate Gurbani Soul" (the App Store's write-a-review sheet) and "Share Gurbani Soul".
    func testRateAndShareAreOfferedInMore() {
        let app = launchApp(selectSearch: false)
        openTab(app, "More", expectingNavBar: "More")
        let rate = app.descendants(matching: .any).matching(identifier: "rateAppLink").firstMatch
        for _ in 0..<6 where !(rate.exists && rate.isHittable) { app.swipeUp() }
        XCTAssertTrue(rate.waitForExistence(timeout: 8), "Rate Gurbani Soul missing in More")
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "shareAppLink").firstMatch.exists,
                      "Share Gurbani Soul missing in More")
    }

    /// Rehras variant is a setting: switching to Taksal persists and retitles the row.
    func testRehrasVariantPersists() {
        let app = launchApp(selectSearch: false)
        openTab(app, "More", expectingNavBar: "More")
        let picker = app.buttons["rehrasVariantPicker"].firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 12), "Rehras variant picker missing")
        picker.tap()
        let taksal = app.buttons["Damdami Taksal"].firstMatch
        XCTAssertTrue(taksal.waitForExistence(timeout: 8))
        taksal.tap()
        openTab(app, "Nitnem", expectingNavBar: "Nitnem")
        XCTAssertTrue(app.buttons["bani_rehras"].firstMatch.waitForExistence(timeout: 12))
        XCTAssertTrue(app.buttons["bani_rehras"].firstMatch.label.contains("Taksal"), "row should show the Taksal variant")
        app.terminate()
        let again = XCUIApplication()
        again.launchEnvironment["SGGS_UITEST_RELAUNCH"] = "1"   // keep this test's state
        again.launch()
        XCTAssertTrue(again.navigationBars["Nitnem"].waitForExistence(timeout: 20))
        XCTAssertTrue(again.buttons["bani_rehras"].firstMatch.waitForExistence(timeout: 12))
        XCTAssertTrue(again.buttons["bani_rehras"].firstMatch.label.contains("Taksal"), "variant must persist across relaunch")
    }

    /// Hands-free auto-scroll advances the reading position and pauses on touch.
    func testAutoScrollAdvancesAndPausesOnTouch() {
        let app = XCUIApplication()
        app.launchEnvironment["SGGS_UITEST"] = "1"
        app.launchEnvironment["SGGS_AUTOSCROLL_PPS"] = "320"
        app.launch()
        openTab(app, "Nitnem", expectingNavBar: "Nitnem")
        let row = app.buttons["bani_sohila"].firstMatch
        for _ in 0..<6 where !(row.exists && row.isHittable) { app.swipeUp() }
        XCTAssertTrue(row.waitForExistence(timeout: 12), "Sohila row missing")
        row.tap()
        XCTAssertTrue(app.navigationBars["Kirtan Sohila"].waitForExistence(timeout: 12))
        let play = app.buttons["baniAutoScroll"].firstMatch
        XCTAssertTrue(play.waitForExistence(timeout: 8), "auto-scroll control missing")
        XCTAssertEqual(play.label, "Auto-scroll", "starts in the play state")
        play.tap()
        // it is running now — the control shows the pause label
        XCTAssertTrue(waitLabel(app.buttons["baniAutoScroll"].firstMatch, hasPrefix: "Pause", timeout: 6),
                      "tapping play should start auto-scroll")
        // touching the page pauses it — the control returns to the play label
        app.swipeUp()
        XCTAssertTrue(waitLabel(app.buttons["baniAutoScroll"].firstMatch, hasPrefix: "Auto-scroll", timeout: 6),
                      "a touch should pause auto-scroll")
    }

    /// The reading journey opens from the home and shows the month.
    func testJourneyOpens() {
        let app = launchApp(selectSearch: false)
        let card = app.buttons["nitnemJourney"].firstMatch
        for _ in 0..<4 where !(card.exists && card.isHittable) { app.swipeUp() }
        XCTAssertTrue(card.waitForExistence(timeout: 12), "journey card missing")
        card.tap()
        XCTAssertTrue(app.navigationBars["Reading journey"].waitForExistence(timeout: 10), "journey did not open")
        XCTAssertTrue(app.staticTexts["Begin today"].waitForExistence(timeout: 6)
                      || app.staticTexts.matching(NSPredicate(format: "label ENDSWITH %@", "together")).firstMatch.exists,
                      "journey header missing")
    }

    /// Reading history is the reader's to clear: mark a composition read, then clear it from the
    /// journey after confirming; the control goes once there is nothing left to clear.
    func testJourneyClearsReadingHistory() {
        let app = launchApp(selectSearch: false)   // SGGS_UITEST starts with no progress
        openIndex(app)
        let row = app.buttons["composition_lavan"].firstMatch
        for _ in 0..<6 where !(row.exists && row.isHittable) { app.swipeUp() }
        XCTAssertTrue(row.waitForExistence(timeout: 10), "Lavan missing from More compositions")
        row.tap()
        XCTAssertTrue(app.navigationBars["Lavan"].waitForExistence(timeout: 15))
        app.buttons["End"].firstMatch.tap()
        let markRead = app.buttons["baniMarkComplete"].firstMatch
        for _ in 0..<8 where !(markRead.exists && markRead.isHittable) { app.swipeUp() }
        XCTAssertTrue(markRead.waitForExistence(timeout: 10), "end-of-bani action missing")
        markRead.tap()

        openTab(app, "Nitnem", expectingNavBar: "Nitnem")
        let card = app.buttons["nitnemJourney"].firstMatch
        for _ in 0..<4 where !(card.exists && card.isHittable) { app.swipeUp() }
        XCTAssertTrue(card.waitForExistence(timeout: 12), "journey card missing")
        card.tap()
        XCTAssertTrue(app.navigationBars["Reading journey"].waitForExistence(timeout: 10))

        let clear = app.buttons["clearReadingHistory"].firstMatch
        for _ in 0..<4 where !(clear.exists && clear.isHittable) { app.swipeUp() }
        XCTAssertTrue(clear.waitForExistence(timeout: 8), "a reader with history can clear it")
        captureIfRequested(app, "journey_clear_history")
        clear.tap()
        let confirm = app.buttons["Clear history"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 6), "clearing asks first")
        captureIfRequested(app, "journey_clear_confirm")
        confirm.tap()
        XCTAssertTrue(clear.waitForNonExistence(timeout: 6), "nothing left to clear")
    }

    /// Contents jumps to a pauri, and the position bar's stanza caption follows.
    func testBaniContentsJumpsToPauri() {
        let app = launchApp(selectSearch: false)
        let row = app.buttons["bani_japji"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 12))
        for _ in 0..<4 where !row.isHittable { app.swipeUp() }   // the Hukam cards sit above the banis
        row.tap()
        XCTAssertTrue(app.navigationBars["Japji Sahib"].waitForExistence(timeout: 12))
        app.buttons["baniOptions"].tap()
        let contents = app.buttons["Contents"].firstMatch
        XCTAssertTrue(contents.waitForExistence(timeout: 8), "Contents item missing")
        contents.tap()
        XCTAssertTrue(app.navigationBars["Contents"].waitForExistence(timeout: 8), "Contents sheet did not open")
        // Pauri 5 may sit below the fold — scroll the sheet's own list (swiping the window can
        // just resize the sheet), then tap it.
        let list = app.collectionViews.firstMatch
        let pauri = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Pauri 5")).firstMatch
        for _ in 0..<8 where !(pauri.exists && pauri.isHittable) {
            if list.exists { list.swipeUp() } else { app.swipeUp() }
        }
        XCTAssertTrue(pauri.waitForExistence(timeout: 8), "Pauri 5 row missing")
        pauri.tap()
        let stanza = app.staticTexts["baniStanza"].firstMatch
        XCTAssertTrue(waitLabel(stanza, hasPrefix: "Pauri 5", timeout: 10), "stanza caption did not follow the jump")
    }

    // MARK: Bani reader — gutka layout, chhand headings, the ਜਤ੍ਰ glyph (1.4.7)

    /// Nitnem → Jaap Sahib (the row can sit below the fold on a small phone).
    private func openJaap(_ app: XCUIApplication) {
        XCTAssertTrue(app.navigationBars["Nitnem"].waitForExistence(timeout: 20))
        let row = app.buttons["bani_jaap"].firstMatch
        _ = row.waitForExistence(timeout: 12)
        for _ in 0..<6 where !(row.exists && row.isHittable) { app.swipeUp() }
        XCTAssertTrue(row.exists, "Jaap row missing from Nitnem")
        row.tap()
        XCTAssertTrue(app.navigationBars["Jaap Sahib"].waitForExistence(timeout: 12), "Jaap reader did not open")
    }

    private func attachShot(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = "shot \(name)"; a.lifetime = .keepAlways; add(a)
    }

    private func gutkaRows(_ app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: "gutkaRow")
    }

    /// A Sri Dasam Granth chhand title (`extra_lines.is_header`) draws as a heading, not a verse.
    func testJaapChhandTitleIsAHeading() {
        let app = launchApp(selectSearch: false)
        openJaap(app)
        let chhand = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier == %@ AND label BEGINSWITH %@", "verseHeading", "ਭੁਜੰਗ ਪ੍ਰਯਾਤ ਛੰਦ")).firstMatch
        for _ in 0..<4 where !chhand.exists { app.swipeUp() }
        XCTAssertTrue(chhand.waitForExistence(timeout: 10), "ਭੁਜੰਗ ਪ੍ਰਯਾਤ ਛੰਦ is not drawn as a heading")
        let opening = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier == %@ AND label BEGINSWITH %@", "verseHeading", "ਛਪੈ ਛੰਦ")).firstMatch
        XCTAssertTrue(opening.exists || chhand.exists)
        attachShot(app, "bani_jaap_heading")
    }

    /// Jaap's short lines sit two to a row: one row holds two separate half-lines, each its own
    /// element (verbatim Copy / Share / VoiceOver per original line).
    func testJaapGutkaRowHoldsTwoHalfLines() {
        let app = launchApp(selectSearch: false)
        openJaap(app)
        let row = gutkaRows(app).firstMatch
        // rows below the fold are not built yet (lazy) or not on screen: bring one into view
        for _ in 0..<6 where !(row.exists && row.isHittable) { app.swipeUp() }
        XCTAssertTrue(row.waitForExistence(timeout: 10), "no gutka row in Jaap Sahib")
        let halves = row.descendants(matching: .any).matching(identifier: "gutkaHalf")
        XCTAssertEqual(halves.count, 2, "a gutka row must hold exactly two half-lines")
        XCTAssertTrue(halves.element(boundBy: 0).label.hasPrefix("ਨਮਸਤ੍ਵੰ ਅਕਾਲੇ"), halves.element(boundBy: 0).label)
        XCTAssertTrue(halves.element(boundBy: 1).label.hasPrefix("ਨਮਸਤ੍ਵੰ ਕ੍ਰਿਪਾਲੇ"), halves.element(boundBy: 1).label)
        attachShot(app, "bani_jaap_gutka")
    }

    /// The "Gutka layout" switch in the bani's reading options turns the pairs off and on again.
    func testGutkaSwitchTogglesTheLayout() {
        let app = launchApp(selectSearch: false)
        openJaap(app)
        let row = gutkaRows(app).firstMatch
        // rows below the fold are not built yet (lazy) or not on screen: bring one into view
        for _ in 0..<6 where !(row.exists && row.isHittable) { app.swipeUp() }
        XCTAssertTrue(row.waitForExistence(timeout: 10), "gutka layout should be on by default for Jaap")
        func toggleGutka() {
            let item = app.buttons["Gutka layout"].firstMatch
            let alt = app.switches["Gutka layout"].firstMatch
            // the menu can miss a tap while the reader is still settling: open it again
            for _ in 0..<3 where !(item.exists || alt.exists) {
                app.buttons["baniOptions"].firstMatch.tap()
                _ = item.waitForExistence(timeout: 4) || alt.waitForExistence(timeout: 1)
            }
            let control = item.exists ? item : alt
            XCTAssertTrue(control.exists, "Gutka layout switch missing from reading options")
            control.tap()
        }
        toggleGutka()
        XCTAssertTrue(gutkaRows(app).firstMatch.waitForNonExistence(timeout: 8), "gutka rows did not turn off")
        attachShot(app, "bani_jaap_gutka_off")
        let single = app.descendants(matching: .any).matching(NSPredicate(
            format: "label BEGINSWITH %@", "ਨਮਸਤ੍ਵੰ ਕ੍ਰਿਪਾਲੇ")).firstMatch
        XCTAssertTrue(single.waitForExistence(timeout: 8), "the lines must still be there, one per row")
        toggleGutka()
        XCTAssertTrue(gutkaRows(app).firstMatch.waitForExistence(timeout: 8), "gutka rows did not come back")
    }

    /// Jaap pauris 79/80 hold the ਜਤ੍ਰ ਤਤ੍ਰ words the font used to draw on a dotted circle.
    /// The repair is display-only; this attaches the screen for review (glyphs are pinned by
    /// BaniGutkaTests).
    func testCaptureJaapPauri79() {
        let app = launchApp(selectSearch: false)
        openJaap(app)
        app.buttons["baniOptions"].firstMatch.tap()
        let contents = app.buttons["Contents"].firstMatch
        XCTAssertTrue(contents.waitForExistence(timeout: 8), "Jaap has no Contents")
        contents.tap()
        XCTAssertTrue(app.navigationBars["Contents"].waitForExistence(timeout: 8))
        let list = app.collectionViews.firstMatch
        let pauri = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Verse 79")).firstMatch
        for _ in 0..<40 where !(pauri.exists && pauri.isHittable) {
            if list.exists { list.swipeUp(velocity: .slow) } else { app.swipeUp(velocity: .slow) }
        }
        XCTAssertTrue(pauri.waitForExistence(timeout: 8), "Verse 79 row missing")
        pauri.tap()
        let line = app.descendants(matching: .any).matching(NSPredicate(
            format: "label BEGINSWITH %@", "ਜਤ\u{0A71}\u{0A4D}ਰ ਤਤ\u{0A71}\u{0A4D}ਰ ਬਿਰਾਜਹੀ")).firstMatch
        XCTAssertTrue(line.waitForExistence(timeout: 10), "pauri 79 line missing (VoiceOver must read the stored text)")
        attachShot(app, "bani_jaap_p79")
    }

    // MARK: Explore → Index → a composition's own reader

    /// Open the Index and push a major composition onto the EXPLORE stack: the reader appears on
    /// top of the Index (tab bar unchanged, back returns to the Index), and the saved position is
    /// the same one the Nitnem surface uses.
    func testIndexOpensCompositionReaderOnTheExploreStack() {
        let app = launchApp(selectSearch: false)
        openIndex(app)

        let card = app.buttons["composition_sukhmani"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 12), "Sukhmani card missing from the Index")
        card.tap()
        XCTAssertTrue(app.navigationBars["Sukhmani Sahib"].waitForExistence(timeout: 15),
                      "the composition did not open its own reader")
        XCTAssertFalse(app.navigationBars["Ang 262"].exists, "must NOT drop into the Ang reader")
        XCTAssertTrue(tab(app, "Explore").isSelected, "a composition reads inside Explore")

        // Move the position, then go back: Back must land on the Index, not the Explore hub.
        let pos = app.staticTexts["baniPosition"].firstMatch
        XCTAssertTrue(pos.waitForExistence(timeout: 10), "the reading-position bar is missing")
        app.buttons["Next ashtapadi"].firstMatch.tap()
        app.navigationBars["Sukhmani Sahib"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Index"].waitForExistence(timeout: 10),
                      "Back from a composition must return to the Index")

        // Reopening resumes where it was left.
        app.buttons["composition_sukhmani"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Sukhmani Sahib"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["baniPosition"].firstMatch.waitForExistence(timeout: 8))
    }

    /// The closing chrome of a composition belongs to Explore: "Back to Index", never the Nitnem
    /// band's "Back to Nitnem". Uses Lavan (25 lines) so the end is one tap away.
    func testCompositionEndOffersBackToIndexNotNitnem() {
        let app = launchApp(selectSearch: false)
        openIndex(app)

        let row = app.buttons["composition_lavan"].firstMatch
        for _ in 0..<6 where !(row.exists && row.isHittable) { app.swipeUp() }
        XCTAssertTrue(row.waitForExistence(timeout: 10), "Lavan missing from More compositions")
        row.tap()
        XCTAssertTrue(app.navigationBars["Lavan"].waitForExistence(timeout: 15))

        app.buttons["End"].firstMatch.tap()
        let markRead = app.buttons["baniMarkComplete"].firstMatch
        for _ in 0..<8 where !(markRead.exists && markRead.isHittable) { app.swipeUp() }
        XCTAssertTrue(markRead.waitForExistence(timeout: 10), "end-of-bani action missing")
        markRead.tap()

        let back = app.buttons["baniBackToIndex"].firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 10), "a composition must close back to the Index")
        XCTAssertFalse(app.buttons["baniBackToNitnem"].exists, "Nitnem chrome must not leak into Explore")
        XCTAssertFalse(app.buttons["nitnemNext"].exists, "the time band must not drive a composition read")
        back.tap()
        XCTAssertTrue(app.navigationBars["Index"].waitForExistence(timeout: 10))
    }

    /// The Index reads in the Granth's own order: the banis before the raags, the 31 raags as
    /// cards that each name their place in the saroop, then the banis after the raags. Japji
    /// Sahib leads the composition rail.
    func testIndexFollowsTheSaroop() {
        let app = launchApp(selectSearch: false)
        openIndex(app)
        let japji = app.buttons["composition_japji"].firstMatch
        XCTAssertTrue(japji.waitForExistence(timeout: 12), "Japji Sahib must lead the composition rail")
        // The Ribbon: one adjustable element that speaks the work it is on.
        let ribbon = app.descendants(matching: .any)["index_ribbon"].firstMatch
        XCTAssertTrue(ribbon.waitForExistence(timeout: 8), "the Granth Ribbon is missing")
        XCTAssertTrue((ribbon.value as? String)?.contains("Raag") ?? false,
                      "the Ribbon should start on a raag: \(String(describing: ribbon.value))")
        attachShot(app, "index_compositions")

        app.buttons["index_raags"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["BEFORE THE RAAGS"].waitForExistence(timeout: 10), "opening movement missing")
        attachShot(app, "index_raags_top")
        let gauri = app.buttons["raag_gauri"].firstMatch
        for _ in 0..<6 where !(gauri.exists && gauri.isHittable) { app.swipeUp() }
        XCTAssertTrue(gauri.waitForExistence(timeout: 8), "Raag Gauri card missing")
        XCTAssertTrue(gauri.label.contains("Angs 151–346"), "the card must name its Angs: \(gauri.label)")
        attachShot(app, "index_raags_grid")
        let after = app.staticTexts["AFTER THE RAAGS"].firstMatch
        for _ in 0..<12 where !(after.exists && after.isHittable) { app.swipeUp() }
        XCTAssertTrue(after.waitForExistence(timeout: 8), "closing movement missing")
        attachShot(app, "index_raags_after")
    }

    /// Explore hub → Index, waiting for each step (the glass tab bar can swallow a first tap).
    private func openIndex(_ app: XCUIApplication) {
        openTab(app, "Explore", expectingNavBar: "Explore")
        let index = app.buttons["Index"].firstMatch
        XCTAssertTrue(index.waitForExistence(timeout: 10), "Index card missing from Explore")
        index.tap()
        XCTAssertTrue(app.navigationBars["Index"].waitForExistence(timeout: 10))
    }

    /// A bani reopens where the reader left it (progress file), and Start again returns to the top.
    func testBaniProgressResumes() {
        let app = launchApp(selectSearch: false)
        let row = app.buttons["bani_sukhmani"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 12))
        row.tap()
        XCTAssertTrue(app.navigationBars["Sukhmani Sahib"].waitForExistence(timeout: 12))
        // Sukhmani steps by its printed rhythm (24 ashtapadis), not by the three registry groups.
        app.buttons["Next ashtapadi"].firstMatch.tap()
        let stanza = app.staticTexts["baniStanza"].firstMatch
        XCTAssertTrue(stanza.waitForExistence(timeout: 8))
        XCTAssertTrue(waitLabel(stanza, hasPrefix: "Ashtapadi 2"), "expected Ashtapadi 2, got \(stanza.label)")
        app.navigationBars.buttons.element(boundBy: 0).tap()          // back (flushes the save)
        XCTAssertTrue(app.buttons["bani_sukhmani"].firstMatch.waitForExistence(timeout: 12))
        app.buttons["bani_sukhmani"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Sukhmani Sahib"].waitForExistence(timeout: 12))
        XCTAssertTrue(app.staticTexts["baniStanza"].firstMatch.waitForExistence(timeout: 8))
        XCTAssertTrue(waitLabel(app.staticTexts["baniStanza"].firstMatch, hasPrefix: "Ashtapadi 2"),
                      "position did not resume")
        app.buttons["baniOptions"].tap()
        app.buttons["Start again"].firstMatch.tap()
        XCTAssertTrue(waitLabel(app.staticTexts["baniStanza"].firstMatch, hasPrefix: "Ashtapadi 1"),
                      "Start again should return to the top")
    }

    func testSearchOpensShabad() {
        let app = launchApp()
        let field = focusSearch(app)
        field.typeText("naam")
        let firstCell = app.cells.firstMatch
        XCTAssertTrue(firstCell.waitForExistence(timeout: 20), "no search results appeared")
        firstCell.tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 12), "shabad sheet did not open")
        app.buttons["Done"].tap()
    }

    func testVerifyShowsVerdict() {
        let app = launchApp()
        // Type first (the field is guaranteed at launch), THEN switch mode: the search task is
        // keyed on (query, mode) so it re-runs as Verify. Drag the pill row from an always-
        // visible pill (Roman) — the Verify pill is last and off-screen on narrow widths.
        let field = focusSearch(app)
        field.typeText("pavan guroo paanee pitaa maataa dharat mahat")
        let from = app.buttons["mode_roman"].firstMatch
        XCTAssertTrue(from.waitForExistence(timeout: 5))
        from.press(forDuration: 0.05, thenDragTo: app.buttons["mode_auto"].firstMatch)
        let verifyPill = app.buttons["mode_verify"].firstMatch
        XCTAssertTrue(verifyPill.waitForExistence(timeout: 10))
        verifyPill.tap()
        let verified = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "verified")).firstMatch
        XCTAssertTrue(verified.waitForExistence(timeout: 20), "verdict not shown")
    }

    func testReaderTab() {
        let app = launchApp()
        tab(app, "Reader").tap(); XCTAssertTrue(app.buttons["Hukam"].waitForExistence(timeout: 12), "Reader did not open")
        XCTAssertTrue(app.navigationBars.element.waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["Hukam"].waitForExistence(timeout: 10))
    }

    func testTrailFromSearch() {
        let app = launchApp()
        let field = focusSearch(app)
        field.typeText("naam")
        let firstCell = app.cells.firstMatch
        XCTAssertTrue(firstCell.waitForExistence(timeout: 20))
        let explore = contextAction(app, on: firstCell, "Explore related")
        explore.tap()
        XCTAssertTrue(app.navigationBars["Related verses"].waitForExistence(timeout: 12),
                      "Trail did not open")
    }

    func testInsights() {
        let app = launchApp()
        openTab(app, "Explore", expectingNavBar: "Explore")
        let insights = app.buttons["Insights"].firstMatch
        XCTAssertTrue(insights.waitForExistence(timeout: 12))
        insights.tap()
        XCTAssertTrue(app.buttons["Contributors"].waitForExistence(timeout: 12), "Insights did not open")
        _ = app.staticTexts.element(boundBy: 0).waitForExistence(timeout: 6)
    }

    func testConstellation() {
        let app = launchApp()
        openTab(app, "Explore", expectingNavBar: "Explore")
        let cons = app.buttons["Constellation"].firstMatch
        XCTAssertTrue(cons.waitForExistence(timeout: 12))
        cons.tap()
        XCTAssertTrue(app.navigationBars["Constellation"].waitForExistence(timeout: 12), "Constellation did not open")
        // the caption adds up: "N verses carry Naam" then "S also carry another theme · A carry Naam alone"
        let caption = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "verses carry Naam")).firstMatch
        XCTAssertTrue(caption.waitForExistence(timeout: 12), "the Focus caption did not appear")
        // the list twin carries the same model, and a companion opens the verses both themes share
        app.navigationBars["Constellation"].buttons["View as list"].tap()
        let alone = app.buttons.containing(NSPredicate(format: "label BEGINSWITH %@", "Naam alone")).firstMatch
        XCTAssertTrue(alone.waitForExistence(timeout: 8), "the list twin has no alone row")
        alone.tap()
        XCTAssertTrue(app.navigationBars["Naam alone"].waitForExistence(timeout: 12), "the alone sheet did not open")
        let count = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "1,952 verses")).firstMatch
        XCTAssertTrue(count.waitForExistence(timeout: 8), "the alone sheet's count is wrong")
        app.navigationBars["Naam alone"].buttons["Done"].tap()
        // the whole sky: every theme, and a star (here via the list twin) returns to Focus on it
        app.navigationBars["Constellation"].buttons["See the whole sky"].tap()
        XCTAssertTrue(app.navigationBars["The whole sky"].waitForExistence(timeout: 12), "the Sky did not open")
        app.navigationBars["The whole sky"].buttons["View as list"].tap()
        // Kaam sits in the third family (the Five Vices), below the first screen of the lazy list
        let kaam = app.buttons.containing(NSPredicate(format: "label BEGINSWITH %@", "Kaam,")).firstMatch
        XCTAssertTrue(app.buttons.containing(NSPredicate(format: "label ENDSWITH %@", " verses")).firstMatch
            .waitForExistence(timeout: 12), "the Sky's list twin did not load")
        for _ in 0..<8 where !(kaam.exists && kaam.isHittable) { app.swipeUp() }
        XCTAssertTrue(kaam.waitForExistence(timeout: 4), "the Sky's list twin has no Kaam row")
        kaam.tap()
        let kaamCaption = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "verses carry Kaam")).firstMatch
        XCTAssertTrue(kaamCaption.waitForExistence(timeout: 12), "a Sky star did not focus its theme")
        // the theme card: the centre star opens the description, the words and where it concentrates
        app.navigationBars["Constellation"].buttons["View as map"].tap()
        let centre = app.buttons["Kaam: about this theme"]
        XCTAssertTrue(centre.waitForExistence(timeout: 12), "the centre star is not a button")
        centre.tap()
        XCTAssertTrue(app.navigationBars["Kaam"].waitForExistence(timeout: 12), "the theme card did not open")
        let terms = app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", "gurmukhi words that tag it")).firstMatch
        XCTAssertTrue(terms.waitForExistence(timeout: 8), "the theme card has no terms section")
        app.navigationBars["Kaam"].buttons["Done"].tap()
    }

    /// sggs://constellation?theme=&with= lands on Focus for the theme and opens the pair sheet.
    func testConstellationDeepLink() {
        let app = launchApp()
        XCUIDevice.shared.system.open(URL(string: "sggs://constellation?theme=kaam&with=krodh")!)
        XCTAssertTrue(app.navigationBars["Kaam ✦ Krodh"].waitForExistence(timeout: 15), "the pair sheet did not open from the link")
        app.navigationBars["Kaam ✦ Krodh"].buttons["Done"].tap()
        let caption = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "verses carry Kaam")).firstMatch
        XCTAssertTrue(caption.waitForExistence(timeout: 12), "the link did not land on Focus for Kaam")
    }

    /// English layer (personal profile): the English mode pill exists and returns results,
    /// and the More-tab toggle is present. (The public profile hides both — degradation gate.)
    func testEnglishSearchMode() {
        let app = launchApp()
        // toggle first (before typing raises a keyboard over the tab bar)
        openTab(app, "More", expectingNavBar: "More")
        let toggleLabel = app.staticTexts["Show English translation"]
        XCTAssertTrue(toggleLabel.waitForExistence(timeout: 20), "English toggle missing in More")
        openTab(app, "Search", expectingNavBar: "Search")
        let pill = app.buttons["mode_english"].firstMatch
        XCTAssertTrue(pill.waitForExistence(timeout: 20), "English mode pill missing (personal profile)")
        // the 4th pill can be clipped on narrow widths — bring the row into view first
        app.buttons["mode_roman"].firstMatch.press(forDuration: 0.05, thenDragTo: app.buttons["mode_auto"].firstMatch)
        pill.tap()
        let field = focusSearch(app)
        field.typeText("mercy")
        XCTAssertTrue(app.cells.firstMatch.waitForExistence(timeout: 20), "english-mode search returned nothing")
    }

    /// Lineage: timeline renders, a profile opens, compare mode produces the ⇄ sheet.
    /// Vaars: the 22 ballads list to an anatomy with pauri/salok units.
    func testLineageAndVaars() {
        let app = launchApp()
        openTab(app, "Explore", expectingNavBar: "Explore")
        let lineage = app.buttons["Lineage"].firstMatch
        XCTAssertTrue(lineage.waitForExistence(timeout: 15)); lineage.tap()
        XCTAssertTrue(app.staticTexts["30 voices · 12th–17th century"].waitForExistence(timeout: 15),
                      "lineage header missing")
        // open a profile
        let farid = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Baba Sheikh Farid")).firstMatch
        XCTAssertTrue(farid.waitForExistence(timeout: 8)); farid.tap()
        // "lines preserved" stat tile always renders once the profile loads (some voices,
        // like Farid, legitimately have no signature-themes section)
        XCTAssertTrue(app.staticTexts["lines preserved"].waitForExistence(timeout: 12), "profile did not load")
        app.buttons["Done"].tap()
        // compare two voices
        app.buttons["compareVoices"].tap()
        farid.tap()
        // Jaidev sits in the same top century group as Farid (List rows are lazy — a
        // far-scrolled voice wouldn't exist in the hierarchy yet)
        let jaidev = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Jaidev,")).firstMatch
        XCTAssertTrue(jaidev.waitForExistence(timeout: 8)); jaidev.tap()
        XCTAssertTrue(app.staticTexts["Theme emphasis (lift)"].waitForExistence(timeout: 12),
                      "compare sheet missing")
        app.buttons["Done"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()   // back to Explore
        // vaars
        let vaars = app.buttons["Vaars"].firstMatch
        XCTAssertTrue(vaars.waitForExistence(timeout: 8)); vaars.tap()
        XCTAssertTrue(app.navigationBars["Vaars"].waitForExistence(timeout: 12))
        app.cells.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Anatomy in reading order"].waitForExistence(timeout: 12),
                      "vaar anatomy missing")
    }

    /// Insights completions: network + resonance + flow views render their content.
    func testInsightsVisualizations() {
        let app = launchApp()
        openTab(app, "Explore", expectingNavBar: "Explore")
        let insights = app.buttons["Insights"].firstMatch
        XCTAssertTrue(insights.waitForExistence(timeout: 15)); insights.tap()
        app.buttons["insights_Network"].tap()
        XCTAssertTrue(app.staticTexts["Strongest pairs"].waitForExistence(timeout: 15), "network list missing")
        app.buttons["insights_Resonance"].tap()
        XCTAssertTrue(app.staticTexts["Strongest resonances"].waitForExistence(timeout: 15), "resonance missing")
        // Flow is the last pill in a horizontal row — on narrow widths it sits off-screen
        // (an off-screen XCUIElement has no hit point). Drag the row left first.
        // (`isHittable` itself throws for an off-screen element, so always drag — harmless
        // when the row already fits.)
        app.buttons["insights_Resonance"].firstMatch
            .press(forDuration: 0.05, thenDragTo: app.buttons["insights_Contributors"].firstMatch)
        let flow = app.buttons["insights_Flow"].firstMatch
        XCTAssertTrue(flow.waitForExistence(timeout: 5))
        flow.tap()
        XCTAssertTrue(app.otherElements["progressionRaagPicker"].firstMatch.waitForExistence(timeout: 15)
                      || app.buttons["progressionRaagPicker"].firstMatch.exists
                      || app.staticTexts["Raag"].firstMatch.waitForExistence(timeout: 5),
                      "progression picker missing")
    }

    /// Reader parity: jump-to-Ang (boundary 1430, next disabled), swipe page-turn back.
    func testReaderJumpAndSwipe() {
        let app = launchApp()
        tab(app, "Reader").tap(); XCTAssertTrue(app.buttons["Hukam"].waitForExistence(timeout: 12), "Reader did not open")
        let jump = app.buttons["jumpToAng"].firstMatch
        XCTAssertTrue(jump.waitForExistence(timeout: 15))
        jump.tap()
        enterAng(app, "1430")
        app.buttons["goToAng"].tap()
        XCTAssertTrue(app.navigationBars["Ang 1430"].waitForExistence(timeout: 12), "jump to 1430 failed")
        XCTAssertFalse(app.buttons["Next Ang"].isEnabled, "next must be disabled at Ang 1430")
        // swipe left-to-right = previous Ang
        readerScroll(app).swipeRight()
        XCTAssertTrue(app.navigationBars["Ang 1429"].waitForExistence(timeout: 12), "swipe page-turn failed")
    }

    /// THE regression for the shipped bug: the bottom bar chevrons must turn the page every time —
    /// not just once — and the visible page must always agree with the title. On TestFlight 1.3.0 (2)
    /// the second `nextAng` tap was swallowed (the pager latched) while the title kept counting up.
    func testChevronsTurnPagesRepeatedly() {
        let app = launchApp()
        goReader(app, at: 1180)
        assertOnAng(app, 1180)
        app.buttons["Next Ang"].tap(); assertOnAng(app, 1181, "after Next ×1")
        app.buttons["Next Ang"].tap(); assertOnAng(app, 1182, "after Next ×2")   // died here on 1.3.0
        app.buttons["Next Ang"].tap(); assertOnAng(app, 1183, "after Next ×3")
        app.buttons["Previous Ang"].tap(); assertOnAng(app, 1182, "after Prev ×1")
        app.buttons["Previous Ang"].tap(); assertOnAng(app, 1181, "after Prev ×2")
    }

    /// The end-of-page forward pill (the other control that died) turns the page and names the right
    /// Ang: on 1181 it reads "Continues on Ang 1182" and lands there; the next page's forward footer
    /// then advances to 1183.
    func testContinuationPillGoesToNextAng() {
        let app = launchApp()
        goReader(app, at: 1181)
        assertOnAng(app, 1181)
        // Ang 1181's shabad continues onto 1182 (verified in the DB), so the forward footer is the
        // "Continues on Ang 1182" pill; reach it by scrolling to the bottom of the page.
        var pill = hittable(app, button: "continuesOnPill", timeout: 1)
        for _ in 0..<12 where pill == nil { dragReaderUp(app); pill = hittable(app, button: "continuesOnPill", timeout: 1) }
        XCTAssertNotNil(pill, "Continues-on pill should be reachable on Ang 1181")
        XCTAssertTrue(pill!.label.contains("1182"), "the pill must name the NEXT Ang, not the current one")
        pill!.tap()
        assertOnAng(app, 1182, "after tapping Continues-on")
        // the forward footer on 1182 (continues or plain "Next ·") advances to 1183
        var fwd = forwardFooter(app)
        for _ in 0..<12 where fwd == nil { dragReaderUp(app); fwd = forwardFooter(app) }
        XCTAssertNotNil(fwd, "every Ang before 1430 must offer a forward control")
        fwd!.tap()
        assertOnAng(app, 1183, "after tapping the forward footer")
    }

    /// Several fast chevron taps must not desync the pager (the title and the visible page still agree,
    /// and no self-heal was needed — `assertOnAng` requires `-h0`).
    func testRapidChevronTapsStayInSync() {
        let app = launchApp()
        goReader(app, at: 700)
        for _ in 0..<5 { app.buttons["Next Ang"].tap() }
        assertOnAng(app, 705, "after 5 rapid Next taps")
    }

    /// Bounds: at Ang 1 Previous is disabled and a swipe-right rubber-bands; at Ang 1430 Next is
    /// disabled and Previous still works.
    func testReaderBoundsAndRubberBand() {
        let app = launchApp()
        goReader(app, at: 1)
        assertOnAng(app, 1)
        XCTAssertFalse(app.buttons["Previous Ang"].isEnabled, "Previous must be disabled at Ang 1")
        readerScroll(app).swipeRight()
        assertOnAng(app, 1, "rubber-band: still on Ang 1 after swiping past the start")
        goReader(app, at: 1430)
        assertOnAng(app, 1430)
        XCTAssertFalse(app.buttons["Next Ang"].isEnabled, "Next must be disabled at Ang 1430")
        app.buttons["Previous Ang"].tap()
        assertOnAng(app, 1429, "Previous still works at the end")
    }

    /// Navigation stays correct around a sheet and after backgrounding: a deep link dismisses a
    /// covering Hukam sheet and lands on the Reader, and a chevron tap survives background→foreground.
    func testReaderNavAroundSheetAndBackground() {
        let app = launchApp()
        goReader(app, at: 300)
        // open Hukam, then deep-link elsewhere — the sheet must not hide the destination
        app.buttons["Hukam"].tap()
        XCTAssertTrue(app.buttons["Done"].firstMatch.waitForExistence(timeout: 12), "Hukam sheet did not open")
        XCUIDevice.shared.system.open(URL(string: "sggs://ang/900")!)
        assertOnAng(app, 900, "deep link must land on the Reader, not behind the Hukam sheet")
        // background and return, then keep navigating
        XCUIDevice.shared.press(.home)
        app.activate()
        assertOnAng(app, 900, "state preserved across background")
        app.buttons["Next Ang"].tap()
        assertOnAng(app, 901, "chevrons work after foregrounding")
    }

    /// Open Reader → jump to an Ang that continues a shabad (164) → the "Shabad starts on Ang N"
    /// pill is a real control that navigates back to the shabad's start (163). Regression guard for
    /// the dead-label bug where this chip did nothing on any Ang.
    func testContinuesFromPillGoesToShabadStart() {
        let app = launchApp()
        tab(app, "Reader").tap(); XCTAssertTrue(app.buttons["Hukam"].waitForExistence(timeout: 12), "Reader did not open")
        let jump = app.buttons["jumpToAng"].firstMatch
        XCTAssertTrue(jump.waitForExistence(timeout: 15)); jump.tap()
        let field = app.textFields["angField"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 8))
        field.tap(); field.typeText("164")
        app.buttons["goToAng"].tap()
        XCTAssertTrue(app.navigationBars["Ang 164"].waitForExistence(timeout: 12), "jump to 164 failed")
        // Query the HITTABLE pill: the neighbour page 165 also mounts a continuesFromPill, so
        // `firstMatch` could hit the wrong one.
        let pill = hittable(app, button: "continuesFromPill")
        XCTAssertNotNil(pill, "Continues-from pill missing on Ang 164")
        pill!.tap()
        XCTAssertTrue(app.navigationBars["Ang 163"].waitForExistence(timeout: 12),
                      "Continues-from pill did not navigate to the shabad's start Ang")
    }

    /// The Jump sheet's fine-tune steppers reach an exact Ang without typing, and the primary
    /// action restates the destination ("Go to Ang 12") and lands there.
    func testJumpSteppersAndGoLabel() {
        let app = launchApp()
        tab(app, "Reader").tap(); XCTAssertTrue(app.buttons["Hukam"].waitForExistence(timeout: 12), "Reader did not open")
        let jump = app.buttons["jumpToAng"].firstMatch
        XCTAssertTrue(jump.waitForExistence(timeout: 15)); jump.tap()
        let go = app.buttons["goToAng"].firstMatch
        XCTAssertTrue(go.waitForExistence(timeout: 8))
        // from Ang 1: +10, +1 → 12
        app.buttons["Forward 10"].firstMatch.tap()
        app.buttons["Forward 1"].firstMatch.tap()
        XCTAssertTrue(waitLabel(go, hasPrefix: "Go to Ang 12", timeout: 6),
                      "Go label should restate the destination, got \(go.label)")
        go.tap()
        XCTAssertTrue(app.navigationBars["Ang 12"].waitForExistence(timeout: 12), "steppers did not land on Ang 12")
    }

    /// At the largest accessibility text size the Jump sheet stays usable: the primary Go action
    /// is present and hittable (nothing truncates it off-screen).
    func testJumpSheetAtAX5() {
        let app = XCUIApplication()
        app.launchEnvironment["SGGS_UITEST"] = "1"
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        tab(app, "Reader").tap(); XCTAssertTrue(app.buttons["Hukam"].waitForExistence(timeout: 15), "Reader did not open")
        let jump = app.buttons["jumpToAng"].firstMatch
        XCTAssertTrue(jump.waitForExistence(timeout: 15)); jump.tap()
        let go = app.buttons["goToAng"].firstMatch
        XCTAssertTrue(go.waitForExistence(timeout: 10), "Go action missing at AX5")
        XCTAssertTrue(go.isHittable, "Go action must stay hittable at the largest text size")
    }

    /// The bottom bar's "Ang N of 1430" progress control is a third, thumb-reachable way into Jump.
    func testReaderProgressOpensJump() {
        let app = launchApp()
        tab(app, "Reader").tap(); XCTAssertTrue(app.buttons["Hukam"].waitForExistence(timeout: 12), "Reader did not open")
        // the "Ang N of 1430" progress control (a button whose label is the count text)
        let progress = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "of 1430")).firstMatch
        XCTAssertTrue(progress.waitForExistence(timeout: 12), "progress control missing")
        progress.tap()
        XCTAssertTrue(app.textFields["angField"].waitForExistence(timeout: 8), "progress control did not open Jump")
    }

    /// One set of page controls: the end-of-page buttons are gone, and the page bar turns the page.
    /// Sehaj focus hides the page bar and the tab bar, shows a single "Exit Sehaj", and exits cleanly.
    func testSehajFocusHidesChromeAndExits() {
        let app = launchApp()
        tab(app, "Reader").tap(); XCTAssertTrue(app.buttons["Hukam"].waitForExistence(timeout: 12), "Reader did not open")
        XCTAssertFalse(app.buttons["endNextAng"].exists, "end-of-page Next must be gone (single page control)")
        app.buttons["readerOptions"].firstMatch.tap()
        let sehaj = app.switches["sehajToggle"].firstMatch
        XCTAssertTrue(sehaj.waitForExistence(timeout: 8), "Sehaj focus toggle missing")
        flipSwitch(sehaj)
        dismissPopover(app)
        let exit = app.buttons["exitSehaj"].firstMatch
        XCTAssertTrue(exit.waitForExistence(timeout: 8), "Exit Sehaj missing in focus mode")
        XCTAssertFalse(app.buttons["Hukam"].isHittable, "page bar should be hidden in Sehaj focus")
        exit.tap()
        XCTAssertTrue(app.buttons["Hukam"].waitForExistence(timeout: 8), "page bar did not return after Exit Sehaj")
        XCTAssertFalse(app.buttons["exitSehaj"].exists, "Exit Sehaj should disappear after exiting")
    }

    /// A SwiftUI Toggle with a custom label only flips when the switch itself is tapped.
    private func flipSwitch(_ element: XCUIElement) {
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()
    }

    private func dismissPopover(_ app: XCUIApplication) {
        // Tap outside the popover (top-left of the page content) to dismiss it.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5)).tap()
    }

    /// Reading options open a popover with the in-Reader text-size control (A− / A+).
    func testReadingOptionsTextSize() {
        let app = launchApp()
        tab(app, "Reader").tap(); XCTAssertTrue(app.buttons["Hukam"].waitForExistence(timeout: 12), "Reader did not open")
        app.buttons["readerOptions"].firstMatch.tap()
        let larger = app.buttons["textLarger"].firstMatch
        XCTAssertTrue(larger.waitForExistence(timeout: 8), "text-size control missing in reading options")
        XCTAssertTrue(larger.isHittable)
        larger.tap()                                   // bumps sggs_gurmukhi_size
        XCTAssertTrue(app.buttons["textSmaller"].firstMatch.isHittable, "A− control missing")
    }

    /// Raag Clock: pinned wall clock (16:40 → 4th pahar of day), now card + pahar list +
    /// detail sheet + divergence sheet all reachable.
    func testRaagClock() {
        let app = XCUIApplication()
        app.launchEnvironment["SGGS_CLOCK_NOW"] = "1000"     // 16:40 → pahar 4 (3–6 PM)
        app.launchEnvironment["SGGS_CLOCK_MODE"] = "fixed"   // a stored Solar choice must not change the strings
        app.launchEnvironment["SGGS_UITEST"] = "1"
        // the clock renders in the READER'S locale (12/24-h, am/pm casing); pin en_US so the
        // strings below are the same on every developer's simulator, not only CI's
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        openClock(app)
        XCTAssertTrue(app.staticTexts["What raag is it now?"].waitForExistence(timeout: 20), "now card missing")
        XCTAssertTrue(app.staticTexts["4th pahar of day  ·  3–6 PM"].waitForExistence(timeout: 8),
                      "pinned pahar/window line missing")
        // the live local clock in the dial's hollow: the pinned minute (16:40) on the reader's
        // own clock, the watch and the countdown, as one accessibility element
        let readout = app.otherElements["clockNowReadout"].firstMatch
        XCTAssertTrue(readout.waitForExistence(timeout: 8), "dial readout missing")
        XCTAssertTrue(readout.label.contains("4:40 PM"), "readout should show the pinned local time, got: \(readout.label)")
        XCTAssertTrue(readout.label.contains("4th pahar of day"), "readout should name the current watch")
        XCTAssertTrue(readout.label.contains("Next watch, 1st pahar of night"), "readout should name the next watch")
        // the current watch's raags are a readable list under the clock (never clipped chips)
        let raagRow = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Raag ")).firstMatch
        XCTAssertTrue(raagRow.waitForExistence(timeout: 8), "\"Sung in this watch\" list missing")
        XCTAssertTrue(raagRow.label.contains("read from Ang"), "raag rows lead into the Granth")
        // the accessible pahar list is the content path — open P7 (deliberately silent)
        let p7 = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "3rd pahar of night")).firstMatch
        XCTAssertTrue(p7.waitForExistence(timeout: 8), "pahar list missing")
        p7.tap()
        XCTAssertTrue(app.staticTexts
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "Deliberately silent")).firstMatch
            .waitForExistence(timeout: 8), "P7 empty-state missing")
        app.buttons["Done"].tap()
        // divergence sheet
        let div = app.buttons["divergenceLink"].firstMatch
        XCTAssertTrue(div.waitForExistence(timeout: 8))
        div.tap()
        XCTAssertTrue(app.navigationBars["Where traditions disagree"].waitForExistence(timeout: 10),
                      "divergence sheet did not open")
    }

    /// Solar is the default. With no stored location the clock shows the fixed watches and the
    /// one-tap location card — location is never requested on its own.
    func testRaagClockDefaultsToSolarPrompt() {
        let app = XCUIApplication()
        app.launchEnvironment["SGGS_CLOCK_NOW"] = "1000"
        app.launchEnvironment["SGGS_CLOCK_MODE"] = "solar"
        app.launchEnvironment["SGGS_CLOCK_NO_COORDS"] = "1"   // DEBUG: ignore any stored location
        app.launchEnvironment["SGGS_UITEST"] = "1"
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        openClock(app)
        XCTAssertTrue(app.buttons["useMyLocation"].waitForExistence(timeout: 20), "one-tap location card missing")
        XCTAssertTrue(app.buttons["enterLocationManually"].exists)
        XCTAssertTrue(app.staticTexts["4th pahar of day  ·  3–6 PM"].waitForExistence(timeout: 8),
                      "with no location the fixed windows are shown")
    }

    /// A stored location is the reader's to remove: enter one by hand, forget it, and the clock is
    /// back to its no-location state (the one-tap card and the fixed windows).
    func testForgetLocationReturnsToTheLocationCard() {
        let app = XCUIApplication()
        app.launchEnvironment["SGGS_CLOCK_NOW"] = "1000"
        app.launchEnvironment["SGGS_CLOCK_MODE"] = "solar"
        app.launchEnvironment["SGGS_UITEST"] = "1"
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        openClock(app)
        let forget = app.buttons["forgetLocation"].firstMatch
        if forget.waitForExistence(timeout: 6) { forget.tap() }   // a location this simulator already stored
        let manual = app.buttons["enterLocationManually"].firstMatch
        XCTAssertTrue(manual.waitForExistence(timeout: 20), "no-location card missing")
        manual.tap()
        let fields = app.textFields
        XCTAssertTrue(fields.element(boundBy: 0).waitForExistence(timeout: 8), "manual location sheet missing")
        fields.element(boundBy: 0).tap(); fields.element(boundBy: 0).typeText("31.63")
        fields.element(boundBy: 1).tap(); fields.element(boundBy: 1).typeText("74.87")
        app.buttons["Use these coordinates"].firstMatch.tap()

        XCTAssertTrue(forget.waitForExistence(timeout: 10), "a stored location offers Forget location")
        captureIfRequested(app, "clock_forget_location")
        forget.tap()
        XCTAssertTrue(app.buttons["useMyLocation"].waitForExistence(timeout: 10), "forgetting returns the one-tap card")
        XCTAssertFalse(forget.exists, "nothing left to forget")
        XCTAssertTrue(app.staticTexts["4th pahar of day  ·  3–6 PM"].waitForExistence(timeout: 8),
                      "with no location the fixed windows are shown")
    }

    /// The Explore hub reaches every browse surface (nav-restructure gate).
    func testExploreHubReachesEverySurface() {
        let app = launchApp()
        openTab(app, "Explore", expectingNavBar: "Explore")
        for (card, marker) in [("Index", "Index"), ("Themes", "Themes"), ("Raag Clock", "Raag Clock")] {
            let btn = app.buttons[card].firstMatch
            XCTAssertTrue(btn.waitForExistence(timeout: 12), "\(card) card missing")
            btn.tap()
            XCTAssertTrue(app.navigationBars[marker].waitForExistence(timeout: 12), "\(card) did not open")
            app.navigationBars.buttons.element(boundBy: 0).tap()   // back
        }
    }

    /// A theme lists every verse it counts: the list states the card's own total and pages to the
    /// end (it used to stop silently at 200 while the card promised thousands).
    func testThemeListStatesItsTrueTotal() {
        let app = launchApp(selectSearch: false)
        openThemes(app)
        let naam = app.buttons["theme_naam"].firstMatch
        XCTAssertTrue(naam.waitForExistence(timeout: 12), "Naam card missing")
        naam.tap()
        XCTAssertTrue(app.navigationBars["Naam"].waitForExistence(timeout: 12))
        let header = app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", "5,672 verses carry Naam")).firstMatch
        XCTAssertTrue(header.waitForExistence(timeout: 15), "the list does not state the theme's true total")
        attachShot(app, "theme-verses")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let akal = app.buttons["theme_akal"].firstMatch
        XCTAssertTrue(akal.waitForExistence(timeout: 12), "Akal card missing")
        akal.tap()
        let footer = app.staticTexts["themes.verses.footer"]
        for _ in 0..<6 where !(footer.exists && footer.isHittable) { app.swipeUp() }
        XCTAssertTrue(footer.waitForExistence(timeout: 10))
        XCTAssertEqual(footer.label, "All 15 verses shown")
    }

    /// The Themes index: today's theme, the family bar, cards with honest counts, and search that
    /// finds a theme by its English name, its meaning, or one of its Gurmukhi words.
    func testThemesIndexSearchFindsByMeaningAndGurmukhi() {
        let app = launchApp(selectSearch: false)
        openThemes(app)
        XCTAssertTrue(app.buttons["themes.today"].waitForExistence(timeout: 12), "no theme of the day")
        let naam = app.buttons["theme_naam"].firstMatch
        XCTAssertTrue(naam.waitForExistence(timeout: 12))
        XCTAssertTrue(naam.label.contains("5,672 verses in 2,472 shabads"), "card label: \(naam.label)")
        attachShot(app, "themes-index")
        let family = app.buttons["The Five Vices"].firstMatch
        if family.waitForExistence(timeout: 5) {
            family.tap()
            XCTAssertTrue(app.buttons["theme_kaam"].waitForExistence(timeout: 8), "the family chip did not reach the Five Vices")
            attachShot(app, "themes-family-jump")
        }
        let field = app.searchFields.firstMatch
        for _ in 0..<6 where !field.exists { app.swipeDown() }    // back to the top reveals the drawer
        XCTAssertTrue(field.waitForExistence(timeout: 8), "no search field")
        field.tap()
        field.typeText("ਹਉਮੈ")
        XCTAssertTrue(app.buttons["theme_haumai"].waitForExistence(timeout: 8), "Gurmukhi word did not find Haumai")
        attachShot(app, "themes-search-gurmukhi")
        field.buttons.firstMatch.tap()                 // clear
        field.typeText("ego")
        XCTAssertTrue(app.buttons["theme_haumai"].waitForExistence(timeout: 8), "meaning did not find Haumai")
        XCTAssertTrue(app.buttons["theme_ahankar"].exists, "meaning did not find Ahankar")
        field.buttons.firstMatch.tap()
        field.typeText("zzzz")
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", "No theme matches")).firstMatch
                        .waitForExistence(timeout: 8), "no empty state")
    }

    private func openThemes(_ app: XCUIApplication) {
        openTab(app, "Explore", expectingNavBar: "Explore")
        let hub = app.buttons["Themes"].firstMatch
        XCTAssertTrue(hub.waitForExistence(timeout: 12), "Themes card missing")
        hub.tap()
        XCTAssertTrue(app.navigationBars["Themes"].waitForExistence(timeout: 12))
    }

    /// Regression for the consolidated single root sheet: opening a shabad from INSIDE the Trail must
    /// swap the one sheet (not drop it, as two competing `.sheet(item:)` modifiers did).
    func testTrailOpenSwapsToShabad() {
        let app = launchApp()
        let field = focusSearch(app)
        field.typeText("naam")
        let firstCell = app.cells.firstMatch
        XCTAssertTrue(firstCell.waitForExistence(timeout: 20))
        let explore = contextAction(app, on: firstCell, "Explore related")
        explore.tap()
        XCTAssertTrue(app.navigationBars["Related verses"].waitForExistence(timeout: 12))
        let openBtn = app.buttons["Open"].firstMatch
        XCTAssertTrue(openBtn.waitForExistence(timeout: 5), "pinned Open button missing")
        openBtn.tap()                                              // pinned-verse Open → swap to shabad
        // the single sheet must swap to a shabad (nav title "Ang N"), not be dropped
        let shabadBar = app.navigationBars.matching(NSPredicate(format: "identifier BEGINSWITH %@", "Ang ")).firstMatch
        XCTAssertTrue(shabadBar.waitForExistence(timeout: 12), "Trail→Open did not surface the shabad (dropped sheet)")
    }

    func testSettingsControls() {
        let app = launchApp()
        openTab(app, "More", expectingNavBar: "More")
        XCTAssertTrue(app.switches["translitToggle"].waitForExistence(timeout: 12), "translit toggle missing")
        XCTAssertTrue(app.sliders["gurmukhiSizeSlider"].exists, "size slider missing")
        app.switches["translitToggle"].tap()                       // hide transliteration
        openTab(app, "Search", expectingNavBar: "Search")
        let field = focusSearch(app)
        field.typeText("naam")
        XCTAssertTrue(app.cells.firstMatch.waitForExistence(timeout: 20), "results must still render with translit hidden")
    }

    /// Accent picker (premium pass): switching accents re-tints live via \.palette environment
    /// injection and persists across launches; navigation state must survive the switch.
    func testAccentPickerSwitchesAndPersists() {
        let app = launchApp()
        openTab(app, "More", expectingNavBar: "More")
        let indigo = app.buttons["Indigo accent"]
        if !indigo.waitForExistence(timeout: 8) { app.swipeUp() }
        XCTAssertTrue(indigo.waitForExistence(timeout: 8))
        indigo.tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label == %@ AND selected == 1", "Indigo accent"))
                        .firstMatch.waitForExistence(timeout: 4), "swatch must show selected")
        // still on More (no navigation reset), and the app survives a relaunch with the choice
        XCTAssertTrue(app.navigationBars["More"].waitForExistence(timeout: 4))
        app.terminate(); app.launch()
        openTab(app, "More", expectingNavBar: "More")
        if !app.buttons["Indigo accent"].waitForExistence(timeout: 8) { app.swipeUp() }
        XCTAssertTrue(app.buttons["Indigo accent"].isSelected, "accent choice must persist")
        // restore the default for subsequent tests/captures
        app.buttons["Saffron accent"].tap()
    }

    // MARK: pre-TestFlight hardening (2026-09)

    /// The Search tab must never be a blank pane: idle shows guidance, and the mode pills
    /// change that guidance.
    func testSearchIdleStateShowsExamples() {
        let app = launchApp()
        XCTAssertTrue(app.otherElements["searchIdle"].firstMatch.waitForExistence(timeout: 20)
                      || app.staticTexts["Search the Granth"].waitForExistence(timeout: 5), "idle guidance missing")
        // Roman is the third pill — always on screen (Theme/Verify scroll off on narrow widths)
        app.buttons["mode_roman"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Roman"].firstMatch.waitForExistence(timeout: 5), "mode-specific guidance missing")
    }

    /// Save a verse (context menu) → More → Saved verses lists it → opens its composition →
    /// Done returns to Saved → swipe-delete removes it (SwiftData store round trip).
    func testSavedVerseRoundTrip() {
        let app = launchApp()
        let field = focusSearch(app)
        field.typeText("naam")
        let firstCell = app.cells.firstMatch
        XCTAssertTrue(firstCell.waitForExistence(timeout: 20))
        let save = contextAction(app, on: firstCell, "Save")
        save.tap()
        field.typeText("\n")                                     // keyboard covers the tab bar
        openTab(app, "More", expectingNavBar: "More")
        let saved = app.buttons["Saved verses"].firstMatch
        for _ in 0..<3 where !saved.exists { app.swipeUp() }     // below the Nitnem + Display sections
        XCTAssertTrue(saved.waitForExistence(timeout: 10))
        // the row can sit under the floating tab bar — bring it clear, then verify the push
        for _ in 0..<3 where !app.navigationBars["Saved"].exists {
            app.swipeUp(); saved.tap()
            _ = app.navigationBars["Saved"].waitForExistence(timeout: 4)
        }
        XCTAssertTrue(app.navigationBars["Saved"].waitForExistence(timeout: 6), "Saved did not open")
        let row = app.cells.firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "saved verse not listed")
        row.tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 12), "composition did not open from Saved")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Saved"].waitForExistence(timeout: 8), "Done must return to Saved")
        row.swipeLeft()
        let del = app.buttons["Delete"].firstMatch
        XCTAssertTrue(del.waitForExistence(timeout: 5)); del.tap()
        XCTAssertTrue(app.staticTexts["No saved verses"].waitForExistence(timeout: 8), "delete did not empty the list")
    }

    /// Every composition sheet's Done returns to exactly where the reader was.
    func testShabadDoneReturnsToOrigin() {
        let app = launchApp()
        tab(app, "Reader").tap(); XCTAssertTrue(app.buttons["Hukam"].waitForExistence(timeout: 12), "Reader did not open")
        let hukam = app.buttons["Hukam"]
        XCTAssertTrue(hukam.waitForExistence(timeout: 15)); hukam.tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 12))
        app.buttons["Done"].tap()
        XCTAssertTrue(hukam.waitForExistence(timeout: 8), "Done must return to the Reader")
        // Reader-only chrome proves we are back where we started (not on another tab/sheet)
        XCTAssertTrue(app.buttons["jumpToAng"].firstMatch.waitForExistence(timeout: 8), "Reader toolbar must be back")
        XCTAssertFalse(app.buttons["Done"].waitForExistence(timeout: 2), "the sheet must be gone")
    }

    /// The About screen shows "<CFBundleShortVersionString>+<CFBundleVersion>". The test bundle's
    /// own Info.plist carries the same MARKETING_VERSION / CURRENT_PROJECT_VERSION as the app
    /// (see SGGSUITests `info:` in project.yml), so we assert against what was *built* — including
    /// the per-archive build number — instead of a literal that has to be hand-edited every bump.
    /// Mirrors LaunchIntegrity.bundleVersionString's "short+build" format on purpose: a change to
    /// that format should fail here (the UI-test target can't import the app to share the helper).
    private func expectedVersionLabel() -> String {
        let info = Bundle(for: type(of: self)).infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short)+\(build)"
    }

    /// Testers must be able to report which build they are on.
    func testAboutShowsVersion() {
        let expected = expectedVersionLabel()
        XCTAssertTrue(
            expected.range(of: "^[0-9]+\\.[0-9]+\\.[0-9]+\\+[0-9]+$", options: .regularExpression) != nil,
            "UI-test bundle Info.plist is not carrying MARKETING_VERSION/CURRENT_PROJECT_VERSION "
            + "(got \(expected)) — check the SGGSUITests `info:` block in project.yml"
        )
        let app = launchApp()
        openTab(app, "More", expectingNavBar: "More")
        let about = app.buttons["About & credits"].firstMatch
        for _ in 0..<3 where !about.exists { app.swipeUp() }     // last row: below Nitnem + Display
        XCTAssertTrue(about.waitForExistence(timeout: 12))
        app.swipeUp()                                   // last row can sit under the floating tab bar
        XCTAssertTrue(about.waitForExistence(timeout: 4)); about.tap()
        let v = app.staticTexts["aboutVersion"].firstMatch
        XCTAssertTrue(v.waitForExistence(timeout: 8), "version line missing")
        XCTAssertTrue(v.label.contains(expected), "expected \(expected), got version label: \(v.label)")
    }

    /// A deep link arriving while the app runs must open the Hukam sheet (no production hook:
    /// the system opens the URL exactly as a widget/Siri/Spotlight would).
    func testDeepLinkOpensHukam() {
        let app = launchApp()
        XCTAssertTrue(app.navigationBars["Search"].waitForExistence(timeout: 20))
        XCUIDevice.shared.system.open(URL(string: "sggs://hukam")!)
        XCTAssertTrue(app.navigationBars.matching(NSPredicate(format: "identifier BEGINSWITH %@", "Hukam")).firstMatch
                        .waitForExistence(timeout: 15), "sggs://hukam did not open the Hukam sheet")
        app.buttons["Done"].tap()
    }

    /// sggs://hukam/today (Siri's "Today's Hukam") opens the Hukam of the day: the widget's unit,
    /// the same every time today and with no redraw. The Nitnem home card opens the same one.
    func testHukamOfTheDayIsTheSameEachTime() {
        let app = launchApp()
        XCTAssertTrue(app.navigationBars["Search"].waitForExistence(timeout: 20))
        let bar = app.navigationBars.matching(NSPredicate(format: "identifier BEGINSWITH %@", "Hukam of the day")).firstMatch
        XCUIDevice.shared.system.open(URL(string: "sggs://hukam/today")!)
        XCTAssertTrue(bar.waitForExistence(timeout: 15), "sggs://hukam/today did not open the Hukam of the day")
        let first = bar.identifier
        XCTAssertTrue(first.contains("Ang"), "the title cites its Ang: \(first)")
        XCTAssertFalse(app.buttons["Another"].exists, "the day's Hukam must not offer a redraw")
        app.buttons["Done"].tap()
        openTab(app, "Nitnem", expectingNavBar: "Nitnem")
        let card = app.buttons["hukamOfTheDay"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 12), "Hukam of the day card missing")
        card.tap()
        XCTAssertTrue(bar.waitForExistence(timeout: 15), "the card did not open the Hukam of the day")
        XCTAssertEqual(bar.identifier, first, "the card and the link must open the same day's Hukam")
        app.buttons["Done"].tap()
    }

    // MARK: Reader & Shabad UX pass

    /// Tapping a verse opens its composition scrolled to THAT verse; "Open Ang N in Reader" lands
    /// the Reader on the same verse.
    func testSearchResultOpensShabadAtLine() {
        let app = launchApp()
        let field = focusSearch(app); field.typeText("naam")
        let verses = app.cells.matching(NSPredicate(format: "NOT (label BEGINSWITH %@)", "Related themes"))
        XCTAssertTrue(verses.element(boundBy: 2).waitForExistence(timeout: 20), "need at least 3 results")
        field.typeText("\n")                       // keyboard down: the 3rd row must not sit under it
        let target = verses.element(boundBy: 2)
        // List cells carry no label of their own; the LineRow inside is the labelled element
        // (its label starts with the verbatim Gurmukhi)
        // pick the element whose label is the verbatim Gurmukhi (starts in the Gurmukhi block)
        let gurmukhiLabelled = NSPredicate(format: "label MATCHES %@", "^[\\u0A00-\\u0A7F].*")
        let key = String(target.descendants(matching: .any).matching(gurmukhiLabelled).firstMatch.label.prefix(20))
        XCTAssertFalse(key.isEmpty, "could not read the verse label")
        target.tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 12), "sheet did not open")
        let inSheet = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", key)).firstMatch
        XCTAssertTrue(inSheet.waitForExistence(timeout: 8), "tapped verse missing from the sheet")
        XCTAssertTrue(inSheet.isHittable, "tapped verse must be scrolled on screen")
        let openBtn = app.buttons["openInReader"].firstMatch      // fixed footer — no scrolling needed
        XCTAssertTrue(openBtn.waitForExistence(timeout: 5), "Open Ang button missing")
        let angLabel = openBtn.label.replacingOccurrences(of: " in Reader", with: "").replacingOccurrences(of: "Open ", with: "")
        openBtn.tap()
        XCTAssertTrue(app.navigationBars[angLabel].waitForExistence(timeout: 12), "Reader did not open \(angLabel)")
        let inReader = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", key)).firstMatch
        XCTAssertTrue(inReader.waitForExistence(timeout: 8), "Reader did not land on the verse")
        XCTAssertTrue(inReader.isHittable, "landed verse must be on screen")
    }

    /// Ambient chrome: reading downwards hides the navigation bar; scrolling back reveals it.
    /// The bottom reading chrome (Prev · Hukam · Next) fades while reading downward and returns on
    /// scroll-up. With the finger-tracked pager the top navigation bar deliberately PERSISTS (the
    /// Ang number + Go/AA stay for orientation; the nav bar is never toggled from scroll — that
    /// caused the 120 Hz watchdog freeze), so the immersive-reading affordance is the bottom bar.
    func testReaderChromeReturnsOnScrollUp() {
        let app = launchApp()
        tab(app, "Reader").tap()
        let hukam = app.buttons["Hukam"].firstMatch      // lives in the bottom page bar
        XCTAssertTrue(hukam.waitForExistence(timeout: 15))
        XCTAssertTrue(hukam.isHittable, "chrome should start visible")
        let scroll = app.scrollViews.firstMatch
        scroll.swipeUp(); scroll.swipeUp()
        // faded chrome keeps `exists` true (opacity 0) but is not hittable — assert on that.
        let hidden = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == false"), object: hukam)
        XCTAssertEqual(XCTWaiter().wait(for: [hidden], timeout: 5), .completed, "bottom chrome should hide while reading down")
        scroll.swipeDown()
        let shown = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: hukam)
        XCTAssertEqual(XCTWaiter().wait(for: [shown], timeout: 5), .completed, "chrome must return on scroll up")
    }

    /// A deep link must beat resume-last-Ang even on a launch WITHOUT the test env (which
    /// would itself clear the resume state): control relaunch resumes 1430, linked launch → 7.
    func testDeepLinkAngBeatsResume() {
        let app = launchApp()
        tab(app, "Reader").tap()
        let jump = app.buttons["jumpToAng"].firstMatch
        XCTAssertTrue(jump.waitForExistence(timeout: 15)); jump.tap()
        let field = app.textFields["angField"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 8)); field.tap(); field.typeText("1430")
        app.buttons["goToAng"].tap()
        XCTAssertTrue(app.navigationBars["Ang 1430"].waitForExistence(timeout: 12))
        app.terminate()
        let plain = XCUIApplication()                            // no SGGS_UITEST: resume is live
        plain.launchEnvironment["SGGS_UITEST_RELAUNCH"] = "1"    // (and the real-data vault stays sealed)
        plain.launch()
        tab(plain, "Reader").tap()
        XCTAssertTrue(plain.navigationBars["Ang 1430"].waitForExistence(timeout: 15), "control: resume must work")
        plain.terminate()
        plain.launch()
        XCUIDevice.shared.system.open(URL(string: "sggs://ang/7")!)
        tab(plain, "Reader").tap()
        XCTAssertTrue(plain.navigationBars["Ang 7"].waitForExistence(timeout: 15), "deep link must beat resume")
        plain.terminate()
    }

    /// Two near-simultaneous verse taps must leave exactly one dismissable sheet and a
    /// re-armed presenter (never a stranded modal state).
    func testRapidTapsNeverStrandSheets() {
        let app = launchApp()
        let field = focusSearch(app); field.typeText("naam")
        let verses = app.cells.matching(NSPredicate(format: "NOT (label BEGINSWITH %@)", "Related themes"))
        XCTAssertTrue(verses.element(boundBy: 1).waitForExistence(timeout: 20))
        field.typeText("\n")                       // keyboard down before coordinate taps
        let a = verses.element(boundBy: 0).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let b = verses.element(boundBy: 1).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        a.tap(); b.tap()
        XCTAssertTrue(app.buttons["Done"].firstMatch.waitForExistence(timeout: 12), "a sheet must be up")
        XCTAssertEqual(app.buttons.matching(identifier: "Done").count, 1, "exactly one sheet")
        app.buttons["Done"].firstMatch.tap()
        XCTAssertFalse(app.buttons["Done"].waitForExistence(timeout: 3), "sheet must dismiss")
        verses.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 12), "presenting must stay armed")
        app.buttons["Done"].tap()
    }

    /// Captures reference screenshots (not an assertion gate). Written to the simulator's tmp
    /// dir — pull with `xcrun simctl get_app_container` or read the test attachments.
    /// Set SGGS_SHOT_TAG in the runner env to prefix filenames (disambiguates light/dark runs
    /// when harvesting with `find` — identical names across runs/containers mix otherwise).
    /// Pre-pass for the hardware accessibility check (runbook H5): Apple's automated audit on each
    /// main tab, recorded — never failing — to <SGGS_SHOT_DIR>/a11y-audit.txt. Report-only and skipped
    /// unless TEST_RUNNER_SGGS_SHOT_DIR is set; the human VoiceOver pass (A11Y_CHECKLIST.md) still decides.
    func testAccessibilityAuditReport() throws {
        let env = ProcessInfo.processInfo.environment
        guard let dir = env["SGGS_SHOT_DIR"] else { throw XCTSkip("report-only: set TEST_RUNNER_SGGS_SHOT_DIR") }
        let app = launchApp(selectSearch: false)
        final class Collector: @unchecked Sendable {   // the audit handler is @Sendable; guard the log
            private let lock = NSLock(); private var items: [String] = []
            func add(_ s: String) { lock.lock(); items.append(s); lock.unlock() }
            var all: [String] { lock.lock(); defer { lock.unlock() }; return items }
        }
        let log = Collector()
        for (tabName, nav) in [("Nitnem", "Nitnem"), ("Reader", ""), ("Search", "Search"), ("Explore", "Explore"), ("More", "More")] {
            if nav.isEmpty {
                tab(app, tabName).tap()
                _ = app.buttons["Hukam"].firstMatch.waitForExistence(timeout: 12)
            } else {
                openTab(app, tabName, expectingNavBar: nav)
            }
            let screen = tabName
            try app.performAccessibilityAudit { @Sendable issue in
                let el = issue.element.map { "\($0.elementType.rawValue) '\($0.label.prefix(40))'" } ?? "-"
                log.add("\(screen)\t\(issue.auditType.rawValue)\t\(issue.compactDescription)\t\(el)")
                return true   // record, never fail
            }
        }
        // Constellation v2: Focus and the Sky (report-only, like the tabs above)
        openTab(app, "Explore", expectingNavBar: "Explore")
        let cons = app.buttons["Constellation"].firstMatch
        if cons.waitForExistence(timeout: 8) {
            cons.tap()
            _ = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "verses carry Naam")).firstMatch.waitForExistence(timeout: 12)
            try app.performAccessibilityAudit { @Sendable issue in
                let el = issue.element.map { "\($0.elementType.rawValue) '\($0.label.prefix(40))'" } ?? "-"
                log.add("Constellation\t\(issue.auditType.rawValue)\t\(issue.compactDescription)\t\(el)")
                return true
            }
            let sky = app.navigationBars["Constellation"].buttons["See the whole sky"]
            if sky.waitForExistence(timeout: 8) {
                sky.tap()
                _ = app.navigationBars["The whole sky"].waitForExistence(timeout: 12)
                try app.performAccessibilityAudit { @Sendable issue in
                    let el = issue.element.map { "\($0.elementType.rawValue) '\($0.label.prefix(40))'" } ?? "-"
                    log.add("Sky\t\(issue.auditType.rawValue)\t\(issue.compactDescription)\t\(el)")
                    return true
                }
            }
        }
        let text = (["tab\tauditType\tissue\telement"] + log.all).joined(separator: "\n") + "\n"
        try text.write(toFile: "\(dir)/a11y-audit.txt", atomically: true, encoding: .utf8)
    }

    /// Ang 1400 with the traditional saroop on (the default) and off (`-sggs_saroop NO`, the verbatim
    /// characters), for the scholar's sensitivity review (brand gate G3 / submission gate H2). Runs only
    /// when TEST_RUNNER_SGGS_SHOT_DIR is set, so CI time is unchanged. The scripture shown is the app's
    /// own rendering of the verbatim corpus; nothing is typed or edited.
    func testCaptureSaroopReview() throws {
        let env = ProcessInfo.processInfo.environment
        guard let dir = env["SGGS_SHOT_DIR"] else { throw XCTSkip("capture-only: set TEST_RUNNER_SGGS_SHOT_DIR") }
        for (name, args) in [("ang1400_saroop_on", [String]()), ("ang1400_saroop_off", ["-sggs_saroop", "NO"])] {
            let app = launchApp(selectSearch: false, arguments: args)
            let readerTab = tab(app, "Reader")
            XCTAssertTrue(readerTab.waitForExistence(timeout: 20), "Reader tab missing")
            readerTab.tap()
            let jump = app.buttons["jumpToAng"].firstMatch
            XCTAssertTrue(jump.waitForExistence(timeout: 15), "jump control missing")
            jump.tap()
            enterAng(app, "1400")
            app.buttons["goToAng"].tap()
            assertOnAng(app, 1400, "(saroop review)")
            try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
            app.terminate()
        }
    }

    func testCaptureScreens() {
        // Simulator processes share the host filesystem: TEST_RUNNER_SGGS_SHOT_DIR points the
        // captures at a host directory (default: the runner's tmp).
        let dir = ProcessInfo.processInfo.environment["SGGS_SHOT_DIR"] ?? NSTemporaryDirectory()
        let tag = ProcessInfo.processInfo.environment["SGGS_SHOT_TAG"].map { "\($0)_" } ?? ""
        let app = launchApp(forwardCaptureEnv: true)
        // SGGS_SHOT_LANDSCAPE=1 rotates the running app before capturing (iPad regular-width
        // landscape gate); the orientation is applied to the foreground app, so after launch.
        if ProcessInfo.processInfo.environment["SGGS_SHOT_LANDSCAPE"] == "1" {
            XCUIDevice.shared.orientation = .landscapeLeft
            _ = app.navigationBars["Search"].waitForExistence(timeout: 8)
        }
        func shot(_ name: String) {
            let png = app.screenshot()
            try? png.pngRepresentation.write(to: URL(fileURLWithPath: "\(dir)/\(tag)\(name).png"))
            // on a device the runner's files stay on the phone: the result bundle carries them too
            let a = XCTAttachment(screenshot: png)
            a.name = "shot \(tag)\(name)"; a.lifetime = .keepAlways; add(a)
        }
        let field = focusSearch(app)
        field.typeText("naam")
        _ = app.cells.firstMatch.waitForExistence(timeout: 20)
        shot("search_results")
        // Dismiss the keyboard via the return key — it covers the tab bar (a swipe would
        // dismiss it too, but iOS 26 minimises the floating tab bar during scroll and the
        // Reader tap lands on nothing; both failure modes are silent).
        field.typeText("\n")
        // iPadOS 26 keeps the tab bar hidden while search is active — leave search explicitly
        let cancel = app.buttons["Cancel"].firstMatch
        if cancel.waitForExistence(timeout: 2) { cancel.tap() }
        shot("after_search")
        print("[SGGS shots] \(dir)")
        let readerTab = tab(app, "Reader")
        if !readerTab.waitForExistence(timeout: 8) {
            print("[SGGS hierarchy]\n" + String(app.debugDescription.prefix(6000)))
            XCTFail("Reader tab missing after search")
        }
        readerTab.tap()
        if !app.buttons["Hukam"].waitForExistence(timeout: 12) {
            shot("reader_missing_hukam")
            print("[SGGS hierarchy]\n" + String(app.debugDescription.prefix(6000)))
            XCTFail("Reader must actually open before its screenshot")
        }
        _ = app.staticTexts.element(boundBy: 0).waitForExistence(timeout: 8)
        shot("reader")
        // Reading options (text size, what the page shows, Sehaj focus) and Sehaj focus itself.
        app.buttons["readerOptions"].firstMatch.tap()
        if app.switches["sehajToggle"].firstMatch.waitForExistence(timeout: 8) {
            shot("reader_options")
            flipSwitch(app.switches["sehajToggle"].firstMatch)
            dismissPopover(app)
            if app.buttons["exitSehaj"].firstMatch.waitForExistence(timeout: 8) {
                shot("reader_sehaj")
                app.buttons["exitSehaj"].firstMatch.tap()
                _ = app.buttons["Hukam"].firstMatch.waitForExistence(timeout: 8)
            }
        }
        // The Hukam sheet over the Reader (App Store set): the app's own draw of a complete unit.
        app.buttons["Hukam"].firstMatch.tap()
        if app.buttons["Done"].firstMatch.waitForExistence(timeout: 12) {
            _ = app.staticTexts.element(boundBy: 2).waitForExistence(timeout: 8)
            shot("hukam")
            app.buttons["Done"].firstMatch.tap()
            _ = app.buttons["Hukam"].firstMatch.waitForExistence(timeout: 8)
        }
        openClock(app)
        _ = app.staticTexts["What raag is it now?"].waitForExistence(timeout: 12)
        shot("clock")
        app.navigationBars.buttons.firstMatch.tap()   // back to the hub
        openTab(app, "Nitnem", expectingNavBar: "Nitnem")
        _ = app.buttons["bani_japji"].waitForExistence(timeout: 12)
        shot("nitnem_home")
        app.buttons["bani_japji"].firstMatch.tap()
        _ = app.navigationBars["Japji Sahib"].waitForExistence(timeout: 12)
        _ = app.staticTexts.element(boundBy: 2).waitForExistence(timeout: 8)
        shot("bani_reader")
        app.navigationBars.buttons.firstMatch.tap()   // back to Nitnem
        // Jaap Sahib: chhand headings and the gutka layout (two half-lines to a row).
        let jaap = app.buttons["bani_jaap"].firstMatch
        if jaap.waitForExistence(timeout: 8) {
            for _ in 0..<6 where !jaap.isHittable { app.swipeUp() }
            jaap.tap()
            _ = app.navigationBars["Jaap Sahib"].waitForExistence(timeout: 12)
            _ = app.descendants(matching: .any).matching(identifier: "verseHeading").firstMatch
                .waitForExistence(timeout: 8)
            shot("bani_jaap")
            app.navigationBars.buttons.firstMatch.tap()   // back to Nitnem
        }
        openTab(app, "Explore", expectingNavBar: "Explore")
        _ = app.staticTexts["Explore the Granth"].waitForExistence(timeout: 8)
        shot("explore_hub")
        let index = app.buttons["Index"].firstMatch
        if index.waitForExistence(timeout: 8) { index.tap() }
        _ = app.navigationBars["Index"].waitForExistence(timeout: 8)
        _ = app.staticTexts["MAJOR COMPOSITIONS"].waitForExistence(timeout: 8)
        shot("index")
        // A major composition opens its own reader on the Explore stack (Index → composition).
        let composition = app.buttons["composition_sukhmani"].firstMatch
        if composition.waitForExistence(timeout: 8) {
            composition.tap()
            _ = app.navigationBars["Sukhmani Sahib"].waitForExistence(timeout: 15)
            _ = app.staticTexts["baniPosition"].firstMatch.waitForExistence(timeout: 8)
            shot("composition_reader")
            app.navigationBars.buttons.firstMatch.tap()   // back to the Index
            _ = app.navigationBars["Index"].waitForExistence(timeout: 8)
        }
        app.navigationBars.buttons.firstMatch.tap()   // back to the hub
        let themes = app.buttons["Themes"].firstMatch
        if themes.waitForExistence(timeout: 8) { themes.tap() }
        _ = app.navigationBars["Themes"].waitForExistence(timeout: 8)
        shot("themes")
        app.navigationBars.buttons.firstMatch.tap()   // back to the hub
        let constellation = app.buttons["Constellation"].firstMatch
        if constellation.waitForExistence(timeout: 8) { constellation.tap() }
        _ = app.navigationBars["Constellation"].waitForExistence(timeout: 8)
        _ = app.staticTexts["Naam"].waitForExistence(timeout: 8)   // centre bubble rendered
        shot("constellation")
        shot("constellation-focus")
        let consCentre = app.buttons["Naam: about this theme"]
        if consCentre.waitForExistence(timeout: 8) {
            consCentre.tap()
            _ = app.navigationBars["Naam"].waitForExistence(timeout: 12)
            shot("constellation-card")
            app.navigationBars["Naam"].buttons["Done"].tap()
        }
        let consList = app.navigationBars["Constellation"].buttons["View as list"]
        if consList.waitForExistence(timeout: 8) {
            consList.tap()
            let first = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "verses shared")).firstMatch
            if first.waitForExistence(timeout: 8) {
                first.tap()
                _ = app.buttons.containing(NSPredicate(format: "label BEGINSWITH %@", "Show ")).firstMatch.waitForExistence(timeout: 12)
                shot("constellation-pair")
                app.buttons["Done"].firstMatch.tap()
            }
            app.navigationBars["Constellation"].buttons["View as map"].tap()
        }
        let sky = app.navigationBars["Constellation"].buttons["See the whole sky"]
        if sky.waitForExistence(timeout: 8) {
            sky.tap()
            _ = app.navigationBars["The whole sky"].waitForExistence(timeout: 12)
            _ = app.buttons.containing(NSPredicate(format: "label BEGINSWITH %@", "Naam:")).firstMatch.waitForExistence(timeout: 12)
            shot("constellation-sky")
            app.navigationBars.buttons.firstMatch.tap()   // back to Focus
            _ = app.navigationBars["Constellation"].waitForExistence(timeout: 8)
        }
        app.navigationBars.buttons.firstMatch.tap()   // back to the hub
        let insights = app.buttons["Insights"].firstMatch
        if insights.waitForExistence(timeout: 8) {
            insights.tap()
            _ = app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", "Guru Nanak Dev Ji"))
                .firstMatch.waitForExistence(timeout: 12)
            shot("insights_contributors")
            app.navigationBars.buttons.firstMatch.tap()   // back to the hub
            _ = app.navigationBars["Explore"].waitForExistence(timeout: 8)
        }
        let lineage = app.buttons["Lineage"].firstMatch
        if lineage.waitForExistence(timeout: 8) { lineage.tap() }
        _ = app.staticTexts["30 voices · 12th–17th century"].waitForExistence(timeout: 8)
        shot("lineage")
        openTab(app, "More", expectingNavBar: "More")
        _ = app.staticTexts["Accent"].waitForExistence(timeout: 8)
        shot("more_display")
    }
}
