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

    /// The bench's D10 outside XCTest copies this file out of the container (device_bench.sh d10).
    func testTheTimelineIsLeftForTheBenchAndAnOldOneIsDiscarded() throws {
        LaunchClock.mark(.appInit)
        let before = Date().timeIntervalSince1970
        LaunchClock.persist(LaunchClock.report(cachedHash: false))
        let data = try Data(contentsOf: LaunchClock.persistedURL)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNotNil((object["since_process_start"] as? [String: Double])?["appInit"])
        XCTAssertEqual(object["cached_hash"] as? Bool, false)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(object["written_at"] as? Double), before - 1)
        LaunchClock.discardPersisted()
        XCTAssertFalse(FileManager.default.fileExists(atPath: LaunchClock.persistedURL.path))
    }
}
