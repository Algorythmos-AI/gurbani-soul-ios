import XCTest

/// The bench probe: is the phone fit for a UI run? XCTest runs classes in name order, so this runs
/// before every other UI test. When it fails, `device_run.py summarize` gives its cause to the
/// bundle's other unexplained failures (docs/ios/device-evidence.md).
///
/// Each check here once cost a device run: a phone in landscape (four false failures, 2026-10-25)
/// and another app in front (eleven, 2026-10-27). A locked phone fails before this test can run,
/// with "Timed out while enabling automation mode", which the summary already reads as `env:locked`.
/// Messages start with "BENCH:" so the summary can classify them.
final class BenchGuardTests: XCTestCase {
    override func setUp() { continueAfterFailure = true }

    /// End of the class: one ordinary launch hands the device's real data back (UITestVault).
    override class func tearDown() {
        MainActor.assumeIsolated {
            let app = XCUIApplication()
            app.launch()
            _ = app.wait(for: .runningForeground, timeout: 30)
            app.terminate()
        }
        super.tearDown()
    }

    func testBenchIsReadyForADeviceRun() {
        let app = XCUIApplication()
        app.launchEnvironment["SGGS_UITEST"] = "1"
        app.launch()
        let foreground = app.wait(for: .runningForeground, timeout: 30)
        let window = app.windows.firstMatch
        let frame = window.waitForExistence(timeout: 10) ? window.frame : .zero
        // Another app taking the screen shows up as the app leaving the foreground, if only for a
        // moment: sample the state every 250 ms through the 3 s hold, not once at its end.
        let foregroundState = Int(XCUIApplication.State.runningForeground.rawValue)
        var samples: [Int] = []          // XCUIApplication.State raw values, in order
        for _ in 0..<12 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
            samples.append(Int(app.state.rawValue))
        }
        let away = samples.filter { $0 != foregroundState }.count

        let facts: [String: Any] = [
            "window": [Int(frame.width), Int(frame.height)],
            "device_orientation": XCUIDevice.shared.orientation.rawValue,
            "foreground_at_launch": foreground,
            "foreground_state": foregroundState,
            "hold_samples": samples,          // every 250 ms for 3 s
            "hold_samples_away": away,
        ]
        if let data = try? JSONSerialization.data(withJSONObject: facts, options: [.sortedKeys]) {
            let a = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
            a.name = "BENCH facts"
            a.lifetime = .keepAlways
            add(a)
        }

        XCTAssertTrue(foreground, "BENCH: org.sggs.app did not reach the foreground — another app is in front, or the screen is off")
        XCTAssertEqual(away, 0, "BENCH: org.sggs.app left the foreground during the 3 s hold (\(away) of \(samples.count) samples, every 250 ms) — another app took the screen; quit it and keep hands off")
        XCTAssertGreaterThan(frame.height, 0, "BENCH: the app has no window")
        XCTAssertLessThan(frame.width, frame.height,
                          "BENCH: the orientation is landscape (window \(Int(frame.width))×\(Int(frame.height))) — set portrait and turn the orientation lock on")
        app.terminate()
    }
}
