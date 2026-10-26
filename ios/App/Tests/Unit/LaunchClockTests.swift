import XCTest
@testable import SGGS

/// D10 reads the launch time from the app's own timeline (Debug only).
final class LaunchClockTests: XCTestCase {
    func testTheProcessStartIsKnownAndInThePast() throws {
        let start = try XCTUnwrap(LaunchClock.processStart())
        let now = Date().timeIntervalSince1970
        XCTAssertLessThan(start, now)
        XCTAssertGreaterThan(start, now - 24 * 3600, "a test host started within the last day")
    }

    func testTheReportCarriesEachMarkSinceProcessStart() throws {
        LaunchClock.mark(.appInit)
        let json = LaunchClock.report(cachedHash: true)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        let since = try XCTUnwrap(object["since_process_start"] as? [String: Double])
        let appInit = try XCTUnwrap(since["appInit"])
        XCTAssertGreaterThanOrEqual(appInit, 0)
        XCTAssertEqual(object["cached_hash"] as? Bool, true)
    }
}
