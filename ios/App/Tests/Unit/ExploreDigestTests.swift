import XCTest
import GurbaniDB
import GurbaniSearchKit
@testable import SGGS

/// Every number the Explore hub states, on the SHIPPED DB and roster: derived from the data,
/// equal to what the destination screens count, and never a typed literal.
final class ExploreDigestTests: XCTestCase {

    private func shipped() throws -> (meta: CorpusMeta, vaars: [VaarSummary], roster: [Contributor]) {
        guard let path = Bundle.main.url(forResource: "sggs-ios", withExtension: "sqlite")?.path
            ?? Bundle(for: Self.self).url(forResource: "sggs-ios", withExtension: "sqlite")?.path
        else { throw XCTSkip("bundled DB not found in host app") }
        let db = try SQLiteCandidateSource(path: path)
        let roster = try XCTUnwrap(ContributorsStore.load(), "bundled roster missing")
        return (try db.fetchMeta(), db.vaars(), roster)
    }

    func testMastheadCountsComeFromTheData() throws {
        let (meta, vaars, roster) = try shipped()
        let d = ExploreDigest(meta: meta, vaars: vaars, roster: roster, lastAng: nil)
        let map = GranthMap(meta: meta)
        XCTAssertEqual(d.raagCount, map.raags.count)
        XCTAssertEqual(d.angCount, Int(RibbonLayout(map: map).length.rounded()))
        XCTAssertEqual(d.angRange?.lowerBound, 1)
        XCTAssertEqual(d.angRange?.upperBound, d.angCount, "the Angs the works cover run 1…N with no gap")
        XCTAssertEqual(d.voiceCount, roster.count)
        XCTAssertEqual(d.conceptCount, meta.concepts.count)
        XCTAssertEqual(d.vaarCount, vaars.count)
        XCTAssertEqual(d.mastheadLine,
                       "\(map.raags.count.formatted()) raags · \(roster.count.formatted()) voices · \(d.angCount!.formatted()) Angs")
    }

    func testPreviewsHoldTheWholeGranth() throws {
        let (meta, vaars, roster) = try shipped()
        let d = ExploreDigest(meta: meta, vaars: vaars, roster: roster, lastAng: 262)
        XCTAssertEqual(d.raagMass, GranthMap(meta: meta).raags.map(\.nLines), "one bar per raag, in saroop order")
        XCTAssertEqual(d.raagNames.count, d.raagMass.count)
        XCTAssertEqual(d.voices.count, meta.authors.count, "every voice draws")
        XCTAssertEqual(d.voices.map(\.lines).reduce(0, +), meta.authors.map(\.nLines).reduce(0, +))
        XCTAssertEqual(d.vaarMarks.count, vaars.count)
        XCTAssertNotNil(d.lastAngRaag, "Ang 262 sits inside a raag")
        XCTAssertTrue(d.spokenSummary(.index).contains("You last read Ang 262"))
        XCTAssertTrue(d.caption(.index).contains("262"))
    }

    func testCenturySpanComesFromTheRoster() throws {
        let (meta, vaars, roster) = try shipped()
        let d = ExploreDigest(meta: meta, vaars: vaars, roster: roster, lastAng: nil)
        let years = roster.map(\.timelineYear).filter { $0 != 9999 }
        let span = try XCTUnwrap(d.centurySpan)
        XCTAssertEqual(span.first, try XCTUnwrap(years.min()) / 100 + 1)
        XCTAssertEqual(span.last, try XCTUnwrap(years.max()) / 100 + 1)
        XCTAssertFalse(d.caption(.lineage).localizedCaseInsensitiveContains("five"), "no typed century count")
    }

    func testNothingLoadedSaysLessNeverAGuess() {
        let d = ExploreDigest(meta: nil, vaars: nil, roster: nil, lastAng: nil)
        XCTAssertEqual(d.mastheadLine, "")
        XCTAssertNil(d.ribbon)
        for dest in ExploreDestination.allCases {
            XCTAssertNil(d.caption(dest).rangeOfCharacter(from: .decimalDigits), "\(dest) shows a number before loading")
        }
    }

    func testContinueNamesTheVaarInProgress() throws {
        let (meta, vaars, roster) = try shipped()
        let v = try XCTUnwrap(vaars.first)
        let d = ExploreDigest(meta: meta, vaars: vaars, roster: roster, lastAng: nil, continueVaar: (v.vaarId, 1, 0.4))
        let raag = try XCTUnwrap(d.continueVaar?.raag)
        XCTAssertFalse(raag.isEmpty)
        XCTAssertEqual(d.caption(.vaars), "Continue · Raag \(raag)")
        XCTAssertTrue(d.spokenSummary(.vaars).hasSuffix("40 percent"))
    }
}
