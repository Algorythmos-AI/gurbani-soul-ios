import XCTest

/// The automatable rows of the physical-device checklist (docs/ios/testflight-test-plan.md §8).
/// Skipped unless TEST_RUNNER_SGGS_DEVICE_CHECKLIST=1, so CI time is unchanged. Every row attaches
/// screenshots (kept in the result bundle) as its evidence. The app's UITestVault keeps the
/// device's real data out of reach: the next ordinary launch restores it.
final class DeviceChecklistTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        guard ProcessInfo.processInfo.environment["SGGS_DEVICE_CHECKLIST"] == "1" else {
            throw XCTSkip("device checklist: set TEST_RUNNER_SGGS_DEVICE_CHECKLIST=1")
        }
    }

    override func tearDown() {
        // Housekeeping only: the row's verdict is already recorded. Over a Wi-Fi tunnel on iOS 27
        // terminate() timed out after D2 and D6 had passed every step (2026-10-25); that must
        // not fail the row. The next launch() terminates any leftover instance anyway.
        XCTExpectFailure("terminate() can time out over a Wi-Fi tunnel", strict: false) {
            XCUIApplication().terminate()
        }
    }

    /// End of the class: one ordinary launch hands the device's real data back (UITestVault).
    override class func tearDown() {
        if ProcessInfo.processInfo.environment["SGGS_DEVICE_CHECKLIST"] == "1" {
            MainActor.assumeIsolated {
                let app = XCUIApplication()
                app.launch()
                _ = app.wait(for: .runningForeground, timeout: 30)
                app.terminate()
            }
        }
        super.tearDown()
    }

    // MARK: helpers

    private func launch(relaunch: Bool = false, arguments: [String] = [],
                        environment: [String: String] = [:]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment[relaunch ? "SGGS_UITEST_RELAUNCH" : "SGGS_UITEST"] = "1"
        for (k, v) in environment { app.launchEnvironment[k] = v }
        app.launchArguments += arguments
        app.launch()
        return app
    }

    private func evidence(_ app: XCUIApplication, _ name: String) {
        let shot = app.screenshot()
        XCTAssertFalse(shot.pngRepresentation.isEmpty, "evidence for \(name) is missing")
        let a = XCTAttachment(screenshot: shot)
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    private func note(_ name: String, _ text: String) {
        let a = XCTAttachment(string: text)
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    private func tab(_ app: XCUIApplication, _ name: String, nav: String) {
        for _ in 0..<3 {
            let bar = app.tabBars.buttons[name]
            (bar.waitForExistence(timeout: 2) ? bar : app.buttons[name].firstMatch).tap()
            if app.navigationBars[nav].waitForExistence(timeout: 4) { return }
        }
        XCTFail("tab \(name) did not open \(nav)")
    }

    private func openAng(_ app: XCUIApplication, _ n: Int) {
        XCUIDevice.shared.system.open(URL(string: "sggs://ang/\(n)")!)
        tab(app, "Reader", nav: "Ang \(n)")
        XCTAssertTrue(app.scrollViews["angContent-\(n)"].waitForExistence(timeout: 15), "Ang \(n) did not render")
    }

    private func scalars(_ s: String) -> String {
        s.unicodeScalars.map { String(format: "U+%04X", $0.value) }.joined(separator: " ")
    }

    /// The verse row on the current page whose spoken label contains `text`, scrolled on screen.
    private func row(_ app: XCUIApplication, containing text: String) -> XCUIElement {
        // rows below the fold are not in the hierarchy until scrolled near (lazy stack)
        let r = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
        _ = r.waitForExistence(timeout: 4)
        for _ in 0..<20 where !(r.exists && r.isHittable) { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(r.exists && r.isHittable, "no verse containing \(text)")
        return r
    }

    /// Long-press the row, choose Copy verse, then paste into the app's own search field (an
    /// in-app paste raises no permission prompt) and return exactly what arrived.
    private func copyAndPaste(_ app: XCUIApplication, row r: XCUIElement) -> String {
        var copy = app.buttons["Copy verse"].firstMatch
        for _ in 0..<3 {
            r.press(forDuration: 1.1)
            copy = app.buttons["Copy verse"].firstMatch
            if copy.waitForExistence(timeout: 5) { break }
            app.tap()
        }
        XCTAssertTrue(copy.exists, "Copy verse missing")
        copy.tap()
        tab(app, "Search", nav: "Search")
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        if let clear = field.buttons["Clear text"].firstMatch as XCUIElement?, clear.exists { clear.tap() }
        field.press(forDuration: 1.2)
        let paste = app.menuItems["Paste"].firstMatch.exists ? app.menuItems["Paste"].firstMatch
                                                            : app.buttons["Paste"].firstMatch
        XCTAssertTrue(paste.waitForExistence(timeout: 6), "Paste menu missing")
        paste.tap()
        let value = (field.value as? String) ?? ""
        let cancel = app.buttons["Cancel"].firstMatch
        if cancel.exists { cancel.tap() } else { field.typeText("\n") }   // the keyboard hides the tab bar
        return value
    }

    // MARK: D2 — Copy fidelity (saroop on, then off)

    func testD2CopyIsVerbatimWithSaroopOnAndOff() {
        let doubledYa = "\u{0A1C}\u{0A32}\u{0A4D}\u{0A2F}\u{0A4D}\u{0A2F}\u{0A28}"   // ਜਲ੍ਯ੍ਯਨ
        let app = launch()
        var results: [String] = []
        for saroopOn in [true, false] {
            if !saroopOn {
                tab(app, "More", nav: "More")
                let toggle = app.switches["saroopToggle"].firstMatch
                for _ in 0..<4 where !(toggle.exists && toggle.isHittable) { app.swipeUp() }
                XCTAssertTrue(toggle.waitForExistence(timeout: 8), "saroop toggle missing")
                XCTAssertEqual(toggle.value as? String, "1", "saroop is on by default")
                toggle.switches.firstMatch.exists ? toggle.switches.firstMatch.tap() : toggle.tap()
                XCTAssertEqual(toggle.value as? String, "0", "saroop did not switch off")
            }
            openAng(app, 1400)
            let r = row(app, containing: doubledYa)
            evidence(app, "D2 Ang 1400, saroop \(saroopOn ? "on" : "off")")
            let pasted = copyAndPaste(app, row: r)
            evidence(app, "D2 pasted, saroop \(saroopOn ? "on" : "off")")
            results.append("saroop \(saroopOn ? "on" : "off"): \(pasted)\n\(scalars(pasted))")
            XCTAssertTrue(pasted.contains(doubledYa), "the paste must carry the stored doubled form ਜਲ੍ਯ੍ਯਨ")
            XCTAssertFalse(pasted.unicodeScalars.contains("\u{0A75}"), "the display-only yakash must never reach the clipboard")
        }
        note("D2 pasted text and scalars", results.joined(separator: "\n\n"))
    }

    // MARK: D3 — Gurmukhi rendering (light and dark, AX3)

    func testD3RenderingLightAndDarkAtAX3() {
        // The app's own Appearance setting wins over the device's, so pin it per launch through
        // the argument domain (never written to the stored settings).
        for dark in [false, true] {
            let look = ["-sggs_appearance", dark ? "dark" : "light"]
            let app = launch(arguments: look + ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"])
            for ang in [1, 1354, 1359, 1400] {
                openAng(app, ang)
                evidence(app, "D3 Ang \(ang) \(dark ? "dark" : "light") AX3")
            }
            app.terminate()
            // ਸਤੵਿੰ sits ten verses down Ang 1354; at AX3 that is many screens, so show it at the
            // standard size too
            let std = launch(arguments: look)
            openAng(std, 1354)
            // match whole clusters: a predicate cannot stop inside one (ਸਤ੍ਯ alone never matches ਸਤ੍ਯ੍ਯਿੰ)
            _ = row(std, containing: "ਸਾਧਸੰਗ ਸ੍ਨੇਹ")
            evidence(std, "D3 Ang 1354 ਸਤੵਿੰ \(dark ? "dark" : "light") standard size")
            std.terminate()
        }
    }

    // MARK: D6 — Clear reading history: cancel changes nothing; confirm clears history only

    func testD6ClearHistoryCancelThenConfirmKeepsEverythingElse() {
        let app = launch(arguments: ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"])
        // something to keep: a saved verse and a Rehras choice
        openAng(app, 1)
        let r = row(app, containing: "ਆਦਿ ਸਚੁ ਜੁਗਾਦਿ ਸਚੁ")       // a verse (the Mool Mantar is a heading)
        r.press(forDuration: 1.1)
        let save = app.buttons["Save"].firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 6)); save.tap()
        tab(app, "More", nav: "More")
        let picker = app.buttons["rehrasVariantPicker"].firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 10)); picker.tap()
        let taksal = app.buttons["Damdami Taksal"].firstMatch
        XCTAssertTrue(taksal.waitForExistence(timeout: 6)); taksal.tap()
        // history: read Lavan to the end
        tab(app, "Explore", nav: "Explore")
        tab(app, "Nitnem", nav: "Nitnem")
        let japji = app.buttons["bani_japji"].firstMatch
        XCTAssertTrue(japji.waitForExistence(timeout: 12)); japji.tap()
        XCTAssertTrue(app.navigationBars["Japji Sahib"].waitForExistence(timeout: 12))
        let forward = app.buttons["baniForward"].firstMatch
        let mark = app.buttons["baniMarkComplete"].firstMatch
        var steps = 0
        while !(mark.exists && mark.isHittable) && steps < 80 {
            if !forward.exists { app.swipeDown(velocity: .slow) }
            else if forward.isEnabled { forward.tap() } else { app.swipeUp() }
            steps += 1
        }
        XCTAssertTrue(mark.waitForExistence(timeout: 10)); mark.tap()
        tab(app, "Nitnem", nav: "Nitnem")
        if app.navigationBars["Japji Sahib"].exists { app.navigationBars.buttons.firstMatch.tap() }
        let card = app.buttons["nitnemJourney"].firstMatch
        for _ in 0..<4 where !(card.exists && card.isHittable) { app.swipeUp() }
        XCTAssertTrue(card.waitForExistence(timeout: 12)); card.tap()
        XCTAssertTrue(app.navigationBars["Reading journey"].waitForExistence(timeout: 10))
        let clear = app.buttons["clearReadingHistory"].firstMatch
        for _ in 0..<4 where !(clear.exists && clear.isHittable) { app.swipeUp() }
        XCTAssertTrue(clear.waitForExistence(timeout: 8))
        evidence(app, "D6 journey with history")

        clear.tap()
        let confirmFirst = app.buttons["Clear history"].firstMatch
        XCTAssertTrue(confirmFirst.waitForExistence(timeout: 6), "clearing asks first")
        evidence(app, "D6 confirmation")
        // iOS 26 shows it as a popover with no Cancel button; tapping outside cancels
        if app.buttons["Cancel"].exists { app.buttons["Cancel"].tap() }
        else { app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)).tap() }
        XCTAssertTrue(confirmFirst.waitForNonExistence(timeout: 6), "the confirmation dismissed")
        XCTAssertTrue(clear.waitForExistence(timeout: 6), "Cancel changed nothing: history is still there")

        clear.tap()
        let confirm = app.buttons["Clear history"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 6)); confirm.tap()
        XCTAssertTrue(clear.waitForNonExistence(timeout: 6), "confirm clears the history")
        evidence(app, "D6 journey after clearing")

        // everything else stays: the saved verse and the Rehras choice
        tab(app, "Nitnem", nav: "Nitnem")
        let rehras = app.buttons["bani_rehras"].firstMatch
        for _ in 0..<4 where !(rehras.exists && rehras.isHittable) { app.swipeUp() }
        XCTAssertTrue(rehras.waitForExistence(timeout: 10))
        XCTAssertTrue(rehras.label.contains("Taksal"), "the Rehras choice must survive clearing history")
        tab(app, "More", nav: "More")
        let saved = app.buttons["Saved verses"].firstMatch
        for _ in 0..<4 where !(saved.exists && saved.isHittable) { app.swipeUp() }
        XCTAssertTrue(saved.waitForExistence(timeout: 10)); saved.tap()
        XCTAssertTrue(app.navigationBars["Saved"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.cells.firstMatch.waitForExistence(timeout: 8), "the saved verse must survive clearing history")
        evidence(app, "D6 saved verses after clearing")
    }

    // D7 (Spotlight) is run by hand: the Home Screen is not reliably readable from a device test.

    // MARK: D10 + D11 — launch time, resume, an interrupted verify

    /// D10: a cold launch (the integrity cache cleared, so the whole database is re-hashed, as
    /// after an install or an update) reaches the app in under 5 s, and a warm relaunch is faster.
    /// Measured on this device only; the oldest supported device is a separate, manual run.
    ///
    /// The time is the app's own (`LaunchClock`, Debug only): from the moment the kernel created
    /// the process to the Nitnem home appearing with its banis loaded. XCTest's clock is recorded
    /// beside it but not judged: over the Wi-Fi tunnel its spawn and polling added about 3 s (±2 s)
    /// to every reading (docs/ios/device-checklist-1.4.9.md).
    func testD10ColdAndWarmLaunchTimes() throws {
        // Start each launch with the app not running: otherwise launch() first terminates a
        // leftover instance, and over a Wi-Fi tunnel that alone took 7.4 s (2026-10-25).
        let leftover = XCUIApplication()
        leftover.terminate()
        XCTAssertTrue(leftover.wait(for: .notRunning, timeout: 30), "a leftover instance would not quit")
        let metrics = ["SGGS_UITEST_LAUNCH_METRICS": "1"]
        var xctestStart = Date()
        var app = launch(environment: metrics.merging(["SGGS_UITEST_COLD_VERIFY": "1"]) { $1 })
        XCTAssertTrue(app.navigationBars["Nitnem"].waitForExistence(timeout: 30), "cold launch never reached the app")
        let coldXCTest = Date().timeIntervalSince(xctestStart)
        let cold = try launchTimeline(app, "cold")
        evidence(app, "D10 after a cold launch")
        app.terminate()
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 30), "the app would not quit before the warm launch")
        xctestStart = Date()
        app = launch(relaunch: true, environment: metrics)
        XCTAssertTrue(app.navigationBars["Nitnem"].waitForExistence(timeout: 30), "warm launch never reached the app")
        let warmXCTest = Date().timeIntervalSince(xctestStart)
        let warm = try launchTimeline(app, "warm")
        // Attached before any assertion can stop the test, so a slow launch still leaves its timeline.
        attachTimeline(cold: cold, warm: warm, xctest: (coldXCTest, warmXCTest))
        XCTAssertEqual(cold.cachedHash, false, "the cold launch must re-hash the whole database")
        XCTAssertEqual(warm.cachedHash, true, "the warm launch must use the verified fingerprint")
        note("D10 timings", """
            process start to Nitnem, measured in the app:
              cold (full verify): \(String(format: "%.2f", cold.nitnem)) s
              warm:               \(String(format: "%.2f", warm.nitnem)) s
            XCTest's clock (not judged; includes spawning and polling over the connection):
              cold \(String(format: "%.2f", coldXCTest)) s, warm \(String(format: "%.2f", warmXCTest)) s
            timelines (s since process start):
              cold \(cold.raw)
              warm \(warm.raw)
            """)
        XCTAssertLessThan(cold.nitnem, 5, "a cold launch must finish verifying in under 5 s")
        XCTAssertLessThan(warm.nitnem, 5, "a warm launch must be under 5 s too")
        // "faster" is recorded, not asserted: on a current iPhone the full hash takes tens of
        // milliseconds, well inside launch-to-launch noise, so a comparison would only flake.
    }

    private struct LaunchTimeline { let nitnem: Double; let cachedHash: Bool?; let raw: String }

    /// D10's evidence as data: "D10 launch timeline" (JSON) holds each launch's marks as the app
    /// reported them, split into `pre_main` (process start → the first app code: dyld and, under
    /// XCTest, its injected bootstrap over the connection) and `app_work` (the first app code →
    /// Nitnem drawn), and XCTest's clock beside them (recorded, never judged). device_run.py reads
    /// it into the run's summary and its launch trend (docs/ios/device-evidence.md).
    private func attachTimeline(cold: LaunchTimeline, warm: LaunchTimeline, xctest: (cold: Double, warm: Double)) {
        func seconds(_ s: Double) -> Double { (s * 1000).rounded() / 1000 }
        func marks(_ t: LaunchTimeline) -> Any {
            guard var object = (try? JSONSerialization.jsonObject(with: Data(t.raw.utf8))) as? [String: Any] else { return [:] }
            if let since = object["since_process_start"] as? [String: Double], let appInit = since["appInit"] {
                object["pre_main"] = seconds(appInit)
                object["app_work"] = seconds(t.nitnem - appInit)
            }
            return object
        }
        let doc: [String: Any] = ["cold": marks(cold), "warm": marks(warm), "budget_s": 5,
                                  "xctest_clock": ["cold": seconds(xctest.cold), "warm": seconds(xctest.warm)]]
        guard let data = try? JSONSerialization.data(withJSONObject: doc, options: [.sortedKeys]) else { return }
        let a = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        a.name = "D10 launch timeline"
        a.lifetime = .keepAlways
        add(a)
    }

    /// The app's own launch timeline (`launchMetrics` on the Nitnem screen; Debug builds only).
    private func launchTimeline(_ app: XCUIApplication, _ name: String) throws -> LaunchTimeline {
        let probe = app.staticTexts["launchMetrics"].firstMatch
        XCTAssertTrue(probe.waitForExistence(timeout: 10), "\(name): the app published no launch timeline")
        var raw = ""
        let deadline = Date().addingTimeInterval(5)
        while raw.isEmpty && Date() < deadline {
            raw = probe.value as? String ?? ""
            if raw.isEmpty { RunLoop.current.run(until: Date().addingTimeInterval(0.25)) }
        }
        let object = try JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any]
        let since = object?["since_process_start"] as? [String: Double] ?? [:]
        let nitnem = try XCTUnwrap(since["nitnemDrawn"], "\(name): no Nitnem mark in \(raw)")
        return LaunchTimeline(nitnem: nitnem, cachedHash: object?["cached_hash"] as? Bool, raw: raw)
    }

    /// D11: resume after a force quit, and a force quit DURING the integrity verify.
    func testD11ResumeAndAnInterruptedVerify() {
        var app = launch()
        openAng(app, 700)
        evidence(app, "D11 reading Ang 700")
        app.terminate()
        app = launch(relaunch: true)
        tab(app, "Reader", nav: "Ang 700")
        evidence(app, "D11 resumed on Ang 700")
        app.terminate()

        // a cold verify, held open (Debug fault injection) so the force quit lands during it; the
        // verify screen must be up when killed, or this run proves nothing about an interruption
        app = launch(environment: ["SGGS_UITEST_COLD_VERIFY": "1", "SGGS_UITEST_HOLD_VERIFY": "8"])
        let verifying = app.staticTexts["Verifying scripture integrity…"]
        let caught = verifying.waitForExistence(timeout: 4)
        evidence(app, "D11 at the force quit")
        app.terminate()
        XCTAssertTrue(caught, "the force quit did not land during the verify; the row is not proven")
        app = launch(relaunch: true)                 // the cache was never written: a full verify again
        XCTAssertTrue(app.navigationBars["Nitnem"].waitForExistence(timeout: 30), "an interrupted verify must re-run and pass")
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "integrity check failed")).firstMatch.exists)
        evidence(app, "D11 after the interrupted verify")
    }

    // MARK: D12 — hostile links

    func testD12HostileLinksNeverCrash() {
        let app = launch()
        openAng(app, 500)
        for link in ["sggs://shabad/3000000000", "sggs://shabad/-1", "sggs://ang/99999", "sggs://shabad/abc"] {
            XCUIDevice.shared.system.open(URL(string: link)!)
            Thread.sleep(forTimeInterval: 2)
            XCTAssertEqual(app.state, .runningForeground, "\(link) must not crash the app")
            evidence(app, "D12 after \(link)")
        }
        XCTAssertTrue(app.navigationBars["Ang 500"].waitForExistence(timeout: 6), "the app stays on its screen")
    }
}
