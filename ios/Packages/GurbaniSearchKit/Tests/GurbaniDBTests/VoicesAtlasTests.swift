import XCTest
@testable import GurbaniDB
@testable import GurbaniSearchKit

/// Voices of the Granth on the shipped iOS DB: computed from `lines`, so every dataset answers,
/// and it must reconcile with author_analytics line for line.
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

    func testAtlasIsAvailableOnEveryDataset() throws {
        XCTAssertNotNil(try source().voicesAtlas(), "the atlas is computed from lines — never absent")
    }

    func testAtlasReconcilesWithAuthorAnalytics() throws {
        let db = try source()
        let atlas = try XCTUnwrap(try db.voicesAtlas())
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

    func testRandomVerseIsByThatVoiceAtItsOwnFirstLine() throws {
        let db = try source()
        for s in try db.authorAnalytics().prefix(12) {
            for _ in 0..<5 {
                let v = try XCTUnwrap(try db.randomVerse(by: s.author), "\(s.author): no verse")
                let page = try db.fetchAng(v.ang)
                let line = try XCTUnwrap(page.lines.first(where: { $0.id == v.lineId }))
                XCTAssertEqual(line.author, s.author, "random verse is by someone else")
                XCTAssertFalse(line.isHeader)
                XCTAssertEqual(line.compId, v.compId)
                // nothing earlier in the same composition is by this voice
                XCTAssertFalse(page.lines.contains { $0.compId == v.compId && $0.id < v.lineId
                                                     && $0.author == s.author && !$0.isHeader })
            }
        }
        XCTAssertNil(try db.randomVerse(by: "No Such Voice"))
        // Ang 695: one composition id holds Trilochan, Sain, Pipa and Dhanna — Sain's entry
        // must be Sain's own first line, not the composition's opening (Trilochan's).
        if try db.authorAnalytics().contains(where: { $0.author == "Bhagat Sain Ji" }) {
            let v = try XCTUnwrap(try db.randomVerse(by: "Bhagat Sain Ji"))
            let line = try XCTUnwrap(try db.fetchAng(v.ang).lines.first(where: { $0.id == v.lineId }))
            XCTAssertEqual(line.author, "Bhagat Sain Ji")
        }
    }

    func testVersePairsAreVerbatimEchoesBetweenTheTwoVoices() throws {
        let db = try source()
        let graph = db.resonance()
        let e = try XCTUnwrap(graph.edges.first, "no resonance edges in this build")
        let pairs = db.versePairs(from: e.source, to: e.target, limit: 3)
        XCTAssertFalse(pairs.isEmpty, "\(e.source) → \(e.target): resonance edge without a single verse pair")
        XCTAssertLessThanOrEqual(pairs.count, 3)
        XCTAssertEqual(pairs.map(\.score), pairs.map(\.score).sorted(by: >), "strongest first")
        XCTAssertEqual(Set(pairs.map(\.a.id)).count, pairs.count, "one pair per verse of the source voice")
        for p in pairs {
            let la = try XCTUnwrap(try db.fetchAng(p.a.ang).lines.first(where: { $0.id == p.a.id }))
            let lb = try XCTUnwrap(try db.fetchAng(p.b.ang).lines.first(where: { $0.id == p.b.id }))
            XCTAssertEqual(la.author, e.source); XCTAssertEqual(lb.author, e.target)
            XCTAssertEqual(la.gurmukhi, p.a.gurmukhi, "verse text must be the corpus text, verbatim")
            XCTAssertEqual(lb.gurmukhi, p.b.gurmukhi)
            XCTAssertFalse(la.isHeader || lb.isHeader)
        }
        XCTAssertTrue(db.versePairs(from: e.source, to: e.source).isEmpty)
        XCTAssertTrue(db.versePairs(from: "No Such Voice", to: e.target).isEmpty)
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
