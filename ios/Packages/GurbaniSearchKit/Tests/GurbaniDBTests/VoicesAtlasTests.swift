import XCTest
@testable import GurbaniDB
@testable import GurbaniSearchKit

/// Voices of the Granth on the shipped iOS DB. A dataset without the voices tables must read
/// as "absent" (nil, capability off) — never zeros; a dataset with them must reconcile with
/// author_analytics line for line.
final class VoicesAtlasTests: XCTestCase {

    private func source() throws -> SQLiteCandidateSource {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<12 {
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent("contract/_meta.json").path) { break }
            dir = dir.deletingLastPathComponent()
        }
        let dbPath = dir.appendingPathComponent("ios/Resources/sggs-ios.sqlite").path
        guard FileManager.default.fileExists(atPath: dbPath) else {
            throw XCTSkip("ios/Resources/sggs-ios.sqlite missing — run pipeline/build_ios_db.py")
        }
        return try SQLiteCandidateSource(path: dbPath)
    }

    func testAtlasIsAbsentExactlyWhenTheTablesAre() throws {
        let db = try source()
        let atlas = try db.voicesAtlas()
        XCTAssertEqual(atlas == nil, !db.detectCapabilities().hasVoices,
                       "voicesAtlas() must be nil iff the voices tables are missing")
    }

    func testAtlasReconcilesWithAuthorAnalytics() throws {
        let db = try source()
        guard let atlas = try db.voicesAtlas() else {
            throw XCTSkip("this dataset predates the voices tables (sggs-data build_voices.py)")
        }
        let stats = try db.authorAnalytics()
        XCTAssertEqual(Set(atlas.histogram.keys), Set(stats.map(\.author)), "ribbon voices != analytics voices")
        for s in stats {
            let row = try XCTUnwrap(atlas.histogram[s.author])
            XCTAssertEqual(row.count, VoicesAtlas.bucketCount)
            XCTAssertEqual(row.reduce(0, +), s.nLines, "\(s.author): ribbon lines != author_analytics.n_lines")
            let places = atlas.places[s.author] ?? []
            XCTAssertEqual(places.filter(\.isRaag).count, s.nRaags, "\(s.author): raag places != n_raags")
            XCTAssertEqual(places.map(\.nLines), places.map(\.nLines).sorted(by: >), "\(s.author): places not most-lines first")
            let entry = try XCTUnwrap(atlas.entries[s.author], "\(s.author): no entry line")
            let page = try db.fetchAng(entry.ang)
            let line = try XCTUnwrap(page.lines.first(where: { $0.id == entry.lineId }), "\(s.author): entry not on its Ang")
            XCTAssertFalse(line.isHeader, "\(s.author): 'begin with' must be a verse, not a heading")
            XCTAssertEqual(line.compId, entry.compId)
        }
    }

    func testBucketsCoverTheGranthExactly() {
        XCTAssertEqual(VoicesAtlas.bucket(forAng: 1), 0)
        XCTAssertEqual(VoicesAtlas.bucket(forAng: 10), 0)
        XCTAssertEqual(VoicesAtlas.bucket(forAng: 11), 1)
        XCTAssertEqual(VoicesAtlas.bucket(forAng: 1430), VoicesAtlas.bucketCount - 1)
        XCTAssertEqual(VoicesAtlas.angs(inBucket: 0), 1...10)
        XCTAssertEqual(VoicesAtlas.angs(inBucket: VoicesAtlas.bucketCount - 1), 1421...1430)
        XCTAssertEqual(VoicesAtlas.bucket(forAng: 0), 0, "out-of-range Angs clamp, never trap")
        XCTAssertEqual(VoicesAtlas.bucket(forAng: 99_999), VoicesAtlas.bucketCount - 1)
    }
}
