import XCTest

/// The Hukamnama from Sri Harmandir Sahib, end to end on the simulator, with the app's fake
/// registrar and fake service (SGGS_UITEST): no APNs, no network.
@MainActor
final class HukamnamaUITests: XCTestCase {
    override func setUp() async throws { continueAfterFailure = false }
    override func tearDown() async throws { XCUIApplication().terminate() }

    /// The generated fixture (ios/tools/hukamnama_fixture.py), re-dated to today's Amritsar date
    /// so the link always passes the router's ±400-day window.
    private func fixture() throws -> (json: String, date: String, opening: String, ang: Int) {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "hukamnama-entry", withExtension: "json"))
        var obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone(identifier: "Asia/Kolkata")
        f.dateFormat = "yyyy-MM-dd"
        let today = f.string(from: Date())
        obj["amritsar_date"] = today
        let data = try JSONSerialization.data(withJSONObject: obj)
        return (String(decoding: data, as: UTF8.self), today,
                try XCTUnwrap(obj["opening_gurmukhi"] as? String), try XCTUnwrap(obj["ang"] as? Int))
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = "shot \(name)"; a.lifetime = .keepAlways; add(a)
        if let dir = ProcessInfo.processInfo.environment["SGGS_SHOT_DIR"] {
            try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
        }
    }

    /// A cold launch straight to sggs://hukamnama/<date> — as a notification tap does — while a
    /// full (cold) integrity verify runs: the sheet waits for the check, then shows the shabad
    /// read from the app's own corpus, its text equal to the corpus, with the Ang citation.
    func testColdLaunchOpensHukamnamaAfterIntegrity() throws {
        let fx = try fixture()
        let app = XCUIApplication()
        app.launchEnvironment["SGGS_UITEST"] = "1"
        app.launchEnvironment["SGGS_UITEST_COLD_VERIFY"] = "1"
        app.launchEnvironment["SGGS_UITEST_HUKAMNAMA"] = fx.json
        app.launchEnvironment["SGGS_UITEST_OPEN_URL"] = "sggs://hukamnama/\(fx.date)"
        app.launch()
        let header = app.descendants(matching: .any)["hukamnamaHeader"].firstMatch
        XCTAssertTrue(header.waitForExistence(timeout: 90), "the Hukamnama sheet did not open after the integrity check")
        XCTAssertTrue(app.staticTexts["Sri Guru Granth Sahib Ji · Ang \(fx.ang)"].firstMatch.waitForExistence(timeout: 10),
                      "the Ang citation is missing")
        // the opening verse, as the corpus stores it (rows speak the verbatim Gurmukhi first)
        let verse = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", fx.opening)).firstMatch
        XCTAssertTrue(verse.waitForExistence(timeout: 10), "the opening verse is not the corpus text")
        XCTAssertFalse(app.descendants(matching: .any)["hukamnamaNeedsUpdate"].exists)
        shot(app, "hukamnama_sheet")
    }

    /// A TAP on a Hukamnama notification while the app is in the background opens the sheet.
    /// Device only (the app needs notification permission, which a fresh simulator lacks): set
    /// TEST_RUNNER_SGGS_DEVICE_CHECKLIST=1. The Debug hook SGGS_DEBUG_LOCAL_HUKAMNAMA posts a local
    /// notification on the Hukamnama thread; its tap takes the same NotificationRouter path as a push.
    func testNotificationTapFromBackgroundOpensTheSheet() throws {
        guard ProcessInfo.processInfo.environment["SGGS_DEVICE_CHECKLIST"] == "1" else {
            throw XCTSkip("device only: set TEST_RUNNER_SGGS_DEVICE_CHECKLIST=1")
        }
        let fx = try fixture()
        let app = XCUIApplication()
        app.launchEnvironment["SGGS_UITEST"] = "1"
        app.launchEnvironment["SGGS_UITEST_HUKAMNAMA"] = fx.json
        app.launchEnvironment["SGGS_DEBUG_LOCAL_HUKAMNAMA"] = "8"
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 90), "the app did not finish launching")
        XCUIDevice.shared.press(.home)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let banner = springboard.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "device check")).firstMatch
        XCTAssertTrue(banner.waitForExistence(timeout: 30), "the Hukamnama notification never appeared")
        banner.tap()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15), "the tap did not bring the app forward")
        let header = app.descendants(matching: .any)["hukamnamaHeader"].firstMatch
        XCTAssertTrue(header.waitForExistence(timeout: 20), "the tap did not open the Hukamnama sheet")
        XCTAssertTrue(app.staticTexts["Sri Guru Granth Sahib Ji · Ang \(fx.ang)"].firstMatch.waitForExistence(timeout: 10))
        shot(app, "hukamnama_from_notification_tap")
    }

    /// A malformed date is ignored: the app opens normally, no sheet.
    func testMalformedDateIsIgnored() throws {
        let fx = try fixture()
        let app = XCUIApplication()
        app.launchEnvironment["SGGS_UITEST"] = "1"
        app.launchEnvironment["SGGS_UITEST_HUKAMNAMA"] = fx.json
        app.launchEnvironment["SGGS_UITEST_OPEN_URL"] = "sggs://hukamnama/2026-02-30"
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Nitnem"].firstMatch.waitForExistence(timeout: 60))
        XCTAssertFalse(app.descendants(matching: .any)["hukamnamaHeader"].waitForExistence(timeout: 4))
    }

    /// Reminders → the Hukamnama section: on registers (fake registrar + fake service), the mode
    /// switches to a chosen time, off unregisters. The state line is shown only under SGGS_UITEST.
    func testReminderToggleRegistersAndUnregisters() throws {
        let app = XCUIApplication()
        app.launchEnvironment["SGGS_UITEST"] = "1"
        app.launch()
        let more = app.tabBars.buttons["More"].firstMatch
        XCTAssertTrue(more.waitForExistence(timeout: 60))
        more.tap()
        let link = app.buttons["nitnemRemindersLink"].firstMatch
        XCTAssertTrue(link.waitForExistence(timeout: 12))
        link.tap()
        let toggle = app.switches["hukamnamaToggle"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 8), "Hukamnama toggle missing")
        let state = app.staticTexts["hukamnamaDebugState"].firstMatch
        XCTAssertTrue(state.waitForExistence(timeout: 5))
        XCTAssertTrue(state.label.contains("wanted=false"), state.label)

        flip(toggle)
        XCTAssertTrue(waitLabel(state, contains: "effective=true"), "turning on did not register: \(state.label)")
        XCTAssertTrue(app.staticTexts["hukamnamaEstimate"].firstMatch.waitForExistence(timeout: 5), "estimate line missing")
        shot(app, "hukamnama_reminders_on")

        let atTime = app.buttons["At a time I choose"].firstMatch
        XCTAssertTrue(atTime.waitForExistence(timeout: 5))
        atTime.tap()
        XCTAssertTrue(waitLabel(state, contains: "mode=scheduled"), state.label)
        XCTAssertTrue(app.datePickers["hukamnamaTime"].firstMatch.waitForExistence(timeout: 5), "time picker missing")

        flip(toggle)
        XCTAssertTrue(waitLabel(state, contains: "wanted=false"), "turning off did not unregister: \(state.label)")
    }

    /// A SwiftUI Toggle in a List: tap the switch itself (its right edge), then fall back.
    private func flip(_ toggle: XCUIElement) {
        let before = toggle.value as? String
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        if waitValue(toggle, differsFrom: before) { return }
        toggle.switches.firstMatch.exists ? toggle.switches.firstMatch.tap() : toggle.tap()
        _ = waitValue(toggle, differsFrom: before)
    }

    private func waitValue(_ e: XCUIElement, differsFrom v: String?, timeout: TimeInterval = 4) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if (e.value as? String) != v { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return false
    }

    private func waitLabel(_ e: XCUIElement, contains s: String, timeout: TimeInterval = 10) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if e.exists, e.label.contains(s) { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        return e.label.contains(s)
    }
}
