import XCTest

/// The gurbanisoul.com screenshot set, captured by `ios/AppStore/capture_site_shots.sh` (workflow
/// `ios-site-shots.yml`). Skipped unless TEST_RUNNER_SGGS_SHOT_DIR is set, so CI time is unchanged.
///
/// Built to capture an older tag as well as main: the workflow always drops this file (from its
/// own commit) into the checked-out ref, and nothing here is shared with SGGSUITests, so the app
/// under test is the ref's while the navigation is this file's.
///
/// - Each surface group is its own test with its own launch: a step that goes wrong in one group
///   (the run at v1.4.9 left Index's Find open, and Themes and Constellation were shot on the
///   Index) cannot carry into the next.
/// - Every shot names the element that proves its screen is up (`showing:`). When that element is
///   missing the test fails and nothing is written, so a wrong screen never lands under a name.
/// - TEST_RUNNER_SGGS_SHOT_HOST_FRAMES=1 (iPad landscape): an XCUITest screenshot taken after a
///   rotation comes back rotated and clipped, so the host takes the frame instead. The test leaves
///   `<dir>/.request-<name>` and waits; the script writes `<name>.png` from the simulator's own
///   framebuffer and removes the request.
final class SiteShotTests: XCTestCase {

    override func setUp() { continueAfterFailure = true }
    override func tearDown() { XCUIApplication().terminate() }

    private var env: [String: String] { ProcessInfo.processInfo.environment }

    private func shotDir() throws -> String {
        guard let dir = env["SGGS_SHOT_DIR"] else {
            throw XCTSkip("capture-only: set TEST_RUNNER_SGGS_SHOT_DIR")
        }
        return dir
    }

    /// The capture launch: UI-test residue cleared, the Raag Clock pinned, the app's own Appearance
    /// pinned (argument domain only, never stored), and rotated when the set is landscape.
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["SGGS_UITEST"] = "1"
        for key in ["SGGS_CLOCK_NOW", "SGGS_CLOCK_MODE", "SGGS_CLOCK_NO_COORDS", "SGGS_EXPLORE_FEATURE"] {
            if let v = env[key] { app.launchEnvironment[key] = v }
        }
        if let look = env["SGGS_SHOT_APPEARANCE"] { app.launchArguments += ["-sggs_appearance", look] }
        app.launch()
        // the orientation applies to the foreground app, so after launch
        if env["SGGS_SHOT_LANDSCAPE"] == "1" {
            XCUIDevice.shared.orientation = .landscapeLeft
            settle(2)
        }
        return app
    }

    private func settle(_ seconds: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    /// Writes `<dir>/<name>.png` only while `anchor` is on screen.
    private func shot(_ app: XCUIApplication, _ name: String, showing anchor: XCUIElement,
                      file: StaticString = #filePath, line: UInt = #line) {
        guard let dir = env["SGGS_SHOT_DIR"] else { return }
        guard anchor.waitForExistence(timeout: 10) else {
            let a = XCTAttachment(screenshot: app.screenshot())
            a.name = "missed \(name)"; a.lifetime = .keepAlways; add(a)
            XCTFail("\(name): the screen is not up (\(anchor)), nothing written", file: file, line: line)
            return
        }
        if env["SGGS_SHOT_HOST_FRAMES"] == "1" {
            // The host removes the request whether or not it wrote a frame, so the frame itself is
            // the proof: none before the request, one after it.
            let fm = FileManager.default
            let request = "\(dir)/.request-\(name)", frame = "\(dir)/\(name).png"
            try? fm.removeItem(atPath: frame)
            fm.createFile(atPath: request, contents: Data())
            let deadline = Date().addingTimeInterval(60)
            while fm.fileExists(atPath: request) && Date() < deadline { settle(0.25) }
            if fm.fileExists(atPath: request) {
                try? fm.removeItem(atPath: request)
                XCTFail("\(name): the host never answered the frame request", file: file, line: line)
            } else if !fm.fileExists(atPath: frame) {
                XCTFail("\(name): the host could not take the frame", file: file, line: line)
            }
            return
        }
        let png = app.screenshot()
        try? png.pngRepresentation.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
        let a = XCTAttachment(screenshot: png)
        a.name = "shot \(name)"; a.lifetime = .keepAlways; add(a)
    }

    // MARK: Navigation

    /// Tab button that also resolves on iPadOS 26 (the top tab bar may not expose `tabBars`).
    private func tab(_ app: XCUIApplication, _ name: String) -> XCUIElement {
        let bar = app.tabBars.buttons[name]
        return bar.waitForExistence(timeout: 2) ? bar : app.buttons[name].firstMatch
    }

    /// The iOS 26 glass tab bar can swallow a tap while it animates: check the destination arrived.
    private func openTab(_ app: XCUIApplication, _ name: String, expectingNavBar nav: String) {
        for _ in 0..<3 {
            tab(app, name).tap()
            if app.navigationBars[nav].waitForExistence(timeout: 4) { return }
        }
        XCTFail("tab \(name) did not open \(nav)")
    }

    /// Explore → one of its cards (the card's button carries the destination's title).
    @discardableResult
    private func openExplore(_ app: XCUIApplication, _ card: String, nav: String? = nil) -> Bool {
        openTab(app, "Explore", expectingNavBar: "Explore")
        let button = app.buttons[card].firstMatch
        guard button.waitForExistence(timeout: 12) else { XCTFail("\(card) card missing"); return false }
        for _ in 0..<2 {
            button.tap()
            if app.navigationBars[nav ?? card].waitForExistence(timeout: 12) { return true }
        }
        XCTFail("\(card) did not open")
        return false
    }

    /// Back one level, checked: the navigation bar must be `nav` afterwards. An active search holds
    /// the bar (its "Clear text" sits where Back was), so it is left first.
    private func back(_ app: XCUIApplication, to nav: String) {
        if app.buttons["Clear text"].exists || app.keyboards.firstMatch.exists { leaveSearch(app, timeout: 0.5) }
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars[nav].waitForExistence(timeout: 10), "Back did not return to \(nav)")
    }

    /// Focus a search field and make sure it really took focus (a tap during the search bar's
    /// layout animation can leave it unfocused).
    private func focus(_ app: XCUIApplication, _ field: XCUIElement) -> Bool {
        guard field.waitForExistence(timeout: 12) else { XCTFail("search field missing"); return false }
        for _ in 0..<3 {
            field.tap()
            if app.keyboards.firstMatch.waitForExistence(timeout: 3) { return true }
            // iPad with a hardware keyboard shows no software keyboard: focus is enough
            if (field.value(forKey: "hasKeyboardFocus") as? Bool) == true { return true }
        }
        XCTFail("search field never took focus")
        return false
    }

    /// Leaves an active search field. iOS 26 labels the button "Close" (earlier systems "Cancel").
    /// Left open, the navigation bar holds the search field instead of the back button, so the next
    /// back tap lands on "Clear text" — the fault in the v1.4.9 capture.
    private func leaveSearch(_ app: XCUIApplication, timeout: TimeInterval = 2) {
        for label in ["Cancel", "Close"] {
            let inBar = app.navigationBars.buttons[label].firstMatch
            let anywhere = app.buttons[label].firstMatch
            if inBar.waitForExistence(timeout: label == "Cancel" ? timeout : 0.5) { inBar.tap(); return }
            if anywhere.exists { anywhere.tap(); return }
        }
    }

    /// A segment (or chip) tap that is checked: tap again until the button reports selected. A
    /// missing control fails the test (its shots would otherwise be skipped without a word).
    private func select(_ button: XCUIElement, file: StaticString = #filePath, line: UInt = #line) -> Bool {
        guard button.waitForExistence(timeout: 6) else {
            XCTFail("\(button) is missing", file: file, line: line); return false
        }
        for _ in 0..<3 {
            button.tap()
            let selected = NSPredicate(format: "isSelected == true")
            if XCTWaiter().wait(for: [expectation(for: selected, evaluatedWith: button)], timeout: 3) == .completed {
                settle(0.6)                        // the content cross-fades in after the selection
                return true
            }
        }
        XCTFail("\(button) never became selected", file: file, line: line)
        return false
    }

    /// A SwiftUI Toggle with a custom label only flips when the switch itself is tapped.
    private func flipSwitch(_ element: XCUIElement) {
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()
    }

    /// Lineage is a lazy list: waits until the cards carry their counts, then drags up a third of
    /// the window at a time until `card` exists, and drags it into the middle band (clear of the
    /// floating tab bar) so a tap lands on it.
    private func scrollToCard(_ app: XCUIApplication, _ card: XCUIElement) -> Bool {
        _ = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", " verses · ")).firstMatch
            .waitForExistence(timeout: 20)
        let window = app.windows.firstMatch
        for _ in 0..<12 where !card.exists {
            let from = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
            from.press(forDuration: 0.05, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)))
        }
        guard card.waitForExistence(timeout: 2) else { return false }
        let frame = window.frame
        var lastMid = CGFloat.nan
        for _ in 0..<8 {
            let mid = card.frame.midY
            if mid > frame.height * 0.3 && mid < frame.height * 0.6 { break }
            if abs(mid - lastMid) < 2 { break }
            lastMid = mid
            let from = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55))
            let dy = (frame.height * 0.45 - mid) / frame.height
            from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: max(-0.35, min(0.35, dy)) * frame.height)))
        }
        return true
    }

    // MARK: Search, Reader, Hukam

    func testCaptureSearchAndReader() throws {
        _ = try shotDir()
        let app = launch()
        openTab(app, "Search", expectingNavBar: "Search")
        let field = app.searchFields.firstMatch
        guard focus(app, field) else { return }
        field.typeText("naam")
        shot(app, "search_results", showing: app.cells.firstMatch)
        // The return key takes the keyboard off the tab bar (a swipe would minimise the floating
        // tab bar instead); iPadOS 26 hides the tab bar while search is active, so leave it too.
        field.typeText("\n")
        leaveSearch(app)
        shot(app, "after_search", showing: app.navigationBars["Search"])

        tab(app, "Reader").tap()
        let hukam = app.buttons["Hukam"].firstMatch
        XCTAssertTrue(hukam.waitForExistence(timeout: 12), "Reader did not open")
        _ = app.staticTexts.element(boundBy: 0).waitForExistence(timeout: 8)
        shot(app, "reader", showing: hukam)
        // Reading options (text size, what the page shows, Sehaj focus) and Sehaj focus itself.
        app.buttons["readerOptions"].firstMatch.tap()
        let sehaj = app.switches["sehajToggle"].firstMatch
        shot(app, "reader_options", showing: sehaj)
        if sehaj.exists {
            flipSwitch(sehaj)
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5)).tap()   // off the popover
            let exit = app.buttons["exitSehaj"].firstMatch
            shot(app, "reader_sehaj", showing: exit)
            if exit.exists { exit.tap() }
        }
        // The Hukam sheet over the Reader: the app's own draw of a complete unit.
        XCTAssertTrue(hukam.waitForExistence(timeout: 8), "the page bar did not return")
        hukam.tap()
        let done = app.buttons["Done"].firstMatch
        if done.waitForExistence(timeout: 12) { _ = app.staticTexts.element(boundBy: 2).waitForExistence(timeout: 8) }
        shot(app, "hukam", showing: done)
    }

    // MARK: Raag Clock

    func testCaptureClock() throws {
        _ = try shotDir()
        let app = launch()
        guard openExplore(app, "Raag Clock") else { return }
        _ = app.staticTexts["What raag is it now?"].waitForExistence(timeout: 12)
        shot(app, "clock", showing: app.navigationBars["Raag Clock"])
    }

    // MARK: Nitnem

    func testCaptureNitnem() throws {
        _ = try shotDir()
        let app = launch()
        openTab(app, "Nitnem", expectingNavBar: "Nitnem")
        let japji = app.buttons["bani_japji"].firstMatch
        shot(app, "nitnem_home", showing: japji)
        guard japji.exists else { return }
        japji.tap()
        _ = app.staticTexts.element(boundBy: 2).waitForExistence(timeout: 8)
        shot(app, "bani_reader", showing: app.navigationBars["Japji Sahib"])
        back(app, to: "Nitnem")
        // Jaap Sahib: chhand headings and the gutka layout (two half-lines to a row).
        let jaap = app.buttons["bani_jaap"].firstMatch
        XCTAssertTrue(jaap.waitForExistence(timeout: 8), "Jaap row missing")
        for _ in 0..<6 where jaap.exists && !jaap.isHittable { app.swipeUp() }
        jaap.tap()
        _ = app.descendants(matching: .any).matching(identifier: "verseHeading").firstMatch.waitForExistence(timeout: 8)
        shot(app, "bani_jaap", showing: app.navigationBars["Jaap Sahib"])
    }

    // MARK: Explore hub and Index 2.0

    func testCaptureIndex() throws {
        _ = try shotDir()
        let app = launch()
        openTab(app, "Explore", expectingNavBar: "Explore")
        _ = app.buttons["Index"].firstMatch.waitForExistence(timeout: 12)
        settle(2.5)                                 // the live previews arrive a beat after the first frame
        shot(app, "explore_hub", showing: app.navigationBars["Explore"])
        let card = app.buttons["Index"].firstMatch
        card.tap()
        let index = app.navigationBars["Index"]
        XCTAssertTrue(index.waitForExistence(timeout: 12), "Index did not open")
        _ = app.staticTexts["MAJOR COMPOSITIONS"].waitForExistence(timeout: 8)
        shot(app, "index", showing: index)

        // A major composition opens its own reader; two steps in, it is "in progress", so the
        // Index leads with its Continue card.
        let composition = app.buttons["composition_sukhmani"].firstMatch
        if composition.waitForExistence(timeout: 8) {
            composition.tap()
            let reader = app.navigationBars["Sukhmani Sahib"]
            XCTAssertTrue(reader.waitForExistence(timeout: 15), "Sukhmani did not open")
            _ = app.staticTexts["baniPosition"].firstMatch.waitForExistence(timeout: 8)
            shot(app, "composition_reader", showing: reader)
            let next = app.buttons["Next ashtapadi"].firstMatch
            for _ in 0..<2 where next.waitForExistence(timeout: 6) { next.tap(); settle(0.8) }
            back(app, to: "Index")
            shot(app, "index_compositions_continue", showing: app.buttons["index_continue"].firstMatch)
        } else {
            XCTFail("Sukhmani card missing")
        }

        // Raags: "In this hour", the grid, a Raag page.
        if select(app.buttons["index_raags"].firstMatch) {
            _ = app.staticTexts["BEFORE THE RAAGS"].waitForExistence(timeout: 8)
            shot(app, "index_raags", showing: index)
            let gauri = app.buttons["raag_gauri"].firstMatch
            for _ in 0..<6 where !(gauri.exists && gauri.isHittable) { app.swipeUp() }
            shot(app, "index_raags_hour_and_grid", showing: gauri)
            if gauri.exists && gauri.isHittable {
                gauri.tap()
                let bar = app.navigationBars["Raag Gauri"]
                _ = app.buttons["raagBegin"].firstMatch.waitForExistence(timeout: 12)
                shot(app, "raag_gauri", showing: bar)
                app.swipeUp(); app.swipeUp()
                shot(app, "raag_gauri_forms_time", showing: bar)
                back(app, to: "Index")
            }
        }
        if select(app.buttons["index_forms"].firstMatch) {
            shot(app, "index_forms", showing: app.buttons["form_pahare_74"].firstMatch)
        }
        // Find in Index (last: the field is left open, and the test ends here).
        let find = app.searchFields.firstMatch
        if !find.waitForExistence(timeout: 3) { app.swipeDown() }
        if focus(app, find) {
            find.typeText("gauri")
            shot(app, "index_find", showing: app.buttons
                .containing(NSPredicate(format: "label BEGINSWITH %@", "Raag Gauri")).firstMatch)
        }
    }

    // MARK: Themes

    func testCaptureThemes() throws {
        _ = try shotDir()
        let app = launch()
        guard openExplore(app, "Themes") else { return }
        let bar = app.navigationBars["Themes"]
        let naam = app.buttons["theme_naam"].firstMatch
        _ = naam.waitForExistence(timeout: 12)
        shot(app, "themes", showing: bar)
        shot(app, "themes-index", showing: naam)
        let yours = app.descendants(matching: .any)["themes.yours"].firstMatch
        if yours.waitForExistence(timeout: 5) {
            for _ in 0..<3 where !yours.isHittable { app.swipeUp() }
            shot(app, "your-themes", showing: yours)
            for _ in 0..<3 { app.swipeDown() }
        }
        if naam.waitForExistence(timeout: 8) {
            for _ in 0..<3 where !naam.isHittable { app.swipeDown() }
            naam.tap()
            let headword = app.descendants(matching: .any)["themes.page.headword"].firstMatch
            shot(app, "theme-page", showing: headword)
            let all = app.buttons["themes.page.all"].firstMatch
            for _ in 0..<8 where all.exists && !all.isHittable { app.swipeUp() }
            if all.waitForExistence(timeout: 6) {
                all.tap()
                shot(app, "theme-verses", showing: app.staticTexts["themes.verses.total"])
                app.navigationBars.buttons.firstMatch.tap()             // the theme page
                _ = headword.waitForExistence(timeout: 8)
            }
            back(app, to: "Themes")
        }
        // Find a theme by one of its Gurmukhi words (the field sits in a drawer at the top).
        let field = app.searchFields.firstMatch
        for _ in 0..<6 where !field.exists { app.swipeDown() }
        if focus(app, field) {
            field.typeText("ਹਉਮੈ")
            shot(app, "themes-search-gurmukhi", showing: app.buttons["theme_haumai"].firstMatch)
        }
    }

    // MARK: Constellation

    func testCaptureConstellation() throws {
        _ = try shotDir()
        let app = launch()
        guard openExplore(app, "Constellation") else { return }
        let bar = app.navigationBars["Constellation"]
        _ = app.staticTexts["Naam"].waitForExistence(timeout: 8)   // the centre bubble is drawn
        settle(1)
        shot(app, "constellation", showing: bar)
        shot(app, "constellation-focus", showing: bar)
        let centre = app.buttons["Naam: about this theme"]
        if centre.waitForExistence(timeout: 8) {
            centre.tap()
            shot(app, "constellation-card", showing: app.navigationBars["Naam"])
            let done = app.navigationBars["Naam"].buttons["Done"]
            if done.exists { done.tap() }
        }
        let list = bar.buttons["View as list"]
        if list.waitForExistence(timeout: 8) {
            list.tap()
            let first = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "verses shared")).firstMatch
            if first.waitForExistence(timeout: 8) {
                first.tap()
                shot(app, "constellation-pair", showing: app.buttons
                    .containing(NSPredicate(format: "label BEGINSWITH %@", "Show ")).firstMatch)
                let done = app.buttons["Done"].firstMatch
                if done.exists { done.tap() }
            }
            let map = bar.buttons["View as map"]
            if map.waitForExistence(timeout: 6) { map.tap() }
        }
        let sky = bar.buttons["See the whole sky"]
        if sky.waitForExistence(timeout: 8) {
            sky.tap()
            _ = app.buttons.containing(NSPredicate(format: "label BEGINSWITH %@", "Naam:")).firstMatch
                .waitForExistence(timeout: 12)
            shot(app, "constellation-sky", showing: app.navigationBars["The whole sky"])
        }
    }

    // MARK: Insights (Voices)

    func testCaptureInsights() throws {
        _ = try shotDir()
        let app = launch()
        guard openExplore(app, "Insights") else { return }
        let bar = app.navigationBars["Insights"]
        _ = app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", "Guru Nanak Dev Ji"))
            .firstMatch.waitForExistence(timeout: 12)
        shot(app, "insights_contributors", showing: bar)
        let grouping = app.segmentedControls["voicesGrouping"]
        for (segment, name) in [("Traditions", "voices_dots_traditions"), ("Centuries", "voices_dots_centuries"),
                                ("Voices", "voices_dots_voices")] {
            let button = grouping.exists ? grouping.buttons[segment] : app.buttons[segment].firstMatch
            if select(button) { shot(app, name, showing: bar) }
        }
        let ribbon = app.descendants(matching: .any)["granthRibbon"].firstMatch
        for _ in 0..<6 where !(ribbon.exists && ribbon.isHittable) { app.swipeUp() }
        shot(app, "voices_ribbon", showing: ribbon)
        let resonance = app.buttons["insights_Resonance"].firstMatch
        for _ in 0..<6 where !(resonance.exists && resonance.isHittable) { app.swipeDown() }
        if resonance.waitForExistence(timeout: 6) {
            resonance.tap()
            let echo = app.buttons["echoRow"].firstMatch
            shot(app, "voices_resonance_chord_and_list", showing: echo)
            if echo.exists {
                echo.tap()
                shot(app, "voices_echoes", showing: app.buttons["echoVerse"].firstMatch)
            }
        }
    }

    // MARK: Lineage, a Voice page, Compare

    func testCaptureLineage() throws {
        _ = try shotDir()
        let app = launch()
        guard openExplore(app, "Lineage") else { return }
        let header = app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", "[0-9]+ voices · 12th–17th century"))
            .firstMatch
        shot(app, "lineage", showing: header)
        let roll = app.segmentedControls.buttons["Roll"]
        if roll.exists { roll.tap() }
        shot(app, "lineage-roll", showing: header)
        let votd = app.buttons["voiceOfTheDay"]
        if votd.waitForExistence(timeout: 8) {
            if !votd.isHittable { app.swipeUp() }
            shot(app, "voice-of-the-day", showing: votd)
        }
        let river = app.segmentedControls.buttons["River"]
        if river.waitForExistence(timeout: 5) {
            river.tap()
            app.swipeUp()
            shot(app, "lineage-river", showing: app.navigationBars["Lineage"])
            app.swipeDown()
            roll.tap()
        }
        // Guru Tegh Bahadur Ji's page: Gurus only, then scroll to the card (the list is lazy).
        let gurus = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Gurus")).firstMatch
        if gurus.waitForExistence(timeout: 5) { gurus.tap() }
        let m9 = app.buttons["voiceCard_guru-tegh-bahadur-ji"].firstMatch
        if scrollToCard(app, m9) {
            let page = app.descendants(matching: .any)["voicePage"].firstMatch
            for _ in 0..<2 where !page.exists { m9.tap(); _ = page.waitForExistence(timeout: 12) }
            _ = app.buttons["voiceBeginFirst"].waitForExistence(timeout: 12)
            shot(app, "voice-m9", showing: page)
            back(app, to: "Lineage")
        } else {
            XCTFail("Guru Tegh Bahadur Ji's card missing")
        }
        // Compare v2: Guru Tegh Bahadur Ji ⇄ Guru Nanak Dev Ji
        let compare = app.buttons["compareVoices"]
        if compare.waitForExistence(timeout: 5), m9.waitForExistence(timeout: 5) {
            compare.tap()
            m9.tap()
            let m1 = app.buttons["voiceCard_guru-nanak-dev-ji"].firstMatch
            for _ in 0..<6 where !(m1.exists && m1.isHittable) { app.swipeDown() }
            if m1.waitForExistence(timeout: 5) {
                m1.tap()
                _ = app.staticTexts["THEME EMPHASIS"].waitForExistence(timeout: 12)
                shot(app, "compare-v2", showing: app.buttons["Done"].firstMatch)
            }
        }
    }

    // MARK: More

    func testCaptureMore() throws {
        _ = try shotDir()
        let app = launch()
        openTab(app, "More", expectingNavBar: "More")
        shot(app, "more_display", showing: app.staticTexts["Accent"])
    }

    /// Search → Verify: a Japji line typed in Roman, checked against the Granth.
    func testCaptureVerify() throws {
        _ = try shotDir()
        let app = launch()
        openTab(app, "Search", expectingNavBar: "Search")
        let field = app.searchFields.firstMatch
        guard focus(app, field) else { return }
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
        shot(app, "verify_typing", showing: verdict)
        field.typeText("\n")                       // the keyboard off the verdict
        settle(1)
        shot(app, "verify", showing: verdict)
    }

    /// More → About & credits.
    func testCaptureAbout() throws {
        _ = try shotDir()
        let app = launch()
        openTab(app, "More", expectingNavBar: "More")
        let about = app.buttons["About & credits"].firstMatch
        for _ in 0..<3 where !about.exists { app.swipeUp() }
        XCTAssertTrue(about.waitForExistence(timeout: 12))
        app.swipeUp()                              // the last row can sit under the floating tab bar
        XCTAssertTrue(about.waitForExistence(timeout: 4)); about.tap()
        shot(app, "about", showing: app.staticTexts["aboutVersion"].firstMatch)
    }
}
