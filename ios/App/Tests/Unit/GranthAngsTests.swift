import XCTest
import GurbaniDB
import GurbaniSearchKit
@testable import SGGS

/// `GranthAngs.count` is the one typed Ang count; the SHIPPED database must agree with it, and
/// everything sized from it (the Ang set, the ten-Ang buckets) must cover exactly those Angs.
final class GranthAngsTests: XCTestCase {

    func testTheBundledDatabaseCoversExactlyGranthAngs() throws {
        guard let path = Bundle.main.url(forResource: "sggs-ios", withExtension: "sqlite")?.path
            ?? Bundle(for: Self.self).url(forResource: "sggs-ios", withExtension: "sqlite")?.path
        else { throw XCTSkip("bundled DB not found in host app") }
        let db = try SQLiteCandidateSource(path: path)
        let map = GranthMap(meta: try db.fetchMeta())
        XCTAssertEqual(map.angCount, GranthAngs.count, "the data's last Ang is the saroop's")
        XCTAssertEqual(Int(RibbonLayout(map: map).length.rounded()), GranthAngs.count, "every Ang, once, no gap")
        XCTAssertFalse(try db.fetchAng(GranthAngs.count).lines.isEmpty, "the last Ang has lines")
    }

    @MainActor
    func testEverythingSizedFromTheCountCoversIt() {
        XCTAssertEqual(GranthAngs.all, 1...GranthAngs.count)
        XCTAssertEqual(AngSet.angCount, GranthAngs.count)
        XCTAssertEqual(AngSet(GranthAngs.all).angs.count, GranthAngs.count)
        let last = VoicesAtlas.bucketCount - 1
        XCTAssertEqual(VoicesAtlas.angs(inBucket: 0).lowerBound, 1)
        XCTAssertEqual(VoicesAtlas.angs(inBucket: last).upperBound, GranthAngs.count, "the last bucket ends on the last Ang")
        XCTAssertEqual(VoicesAtlas.bucket(forAng: GranthAngs.count), last)
        XCTAssertEqual(ReaderModel.bounds, GranthAngs.all)
        XCTAssertEqual(VaarSpanRibbon.angs, GranthAngs.all)
    }
}
