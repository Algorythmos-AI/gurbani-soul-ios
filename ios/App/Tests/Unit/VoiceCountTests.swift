import XCTest
import GurbaniDB
import GurbaniSearchKit
@testable import SGGS

/// One voice count on every surface, on the SHIPPED DB and roster: Explore, Lineage, Insights ›
/// Contributors and the Voice pages all say the roster's count, 36. Figures computed from tagged
/// lines say so, and name the voice whose line is under review (Bhagat Surdas Ji, Ang 1253, with
/// dataset 1.2.0 — the G3 scholar rules before sggs-data changes the tag).
@MainActor
final class VoiceCountTests: XCTestCase {

    private func shipped() throws -> (db: SQLiteCandidateSource, roster: [Contributor], summaries: [VoiceSummary]) {
        guard let path = Bundle.main.url(forResource: "sggs-ios", withExtension: "sqlite")?.path
            ?? Bundle(for: Self.self).url(forResource: "sggs-ios", withExtension: "sqlite")?.path
        else { throw XCTSkip("bundled DB not found in host app") }
        let db = try SQLiteCandidateSource(path: path)
        let roster = try XCTUnwrap(ContributorsStore.load(), "bundled roster missing")
        return (db, roster, db.voiceSummaries())
    }

    /// The historical count: the roster lists 36 voices with Bani in the Granth.
    func testTheRosterListsThirtySixVoices() throws {
        let roster = try XCTUnwrap(ContributorsStore.load())
        XCTAssertEqual(roster.count, 36)
        XCTAssertEqual(Set(roster.map(\.name)).count, roster.count, "one entry per voice")
    }

    func testEverySurfaceSaysTheRosterCount() throws {
        let (db, roster, summaries) = try shipped()
        // Every voice with tagged lines is a roster voice, so no surface can count beyond it.
        XCTAssertTrue(Set(summaries.map(\.author)).isSubset(of: Set(roster.map(\.name))),
                      "a DB voice the roster does not list")
        let n = roster.count
        XCTAssertEqual(n, 36)

        // Explore (masthead and the Lineage card read the digest's count).
        let explore = ExploreDigest(meta: try db.fetchMeta(), vaars: db.vaars(), roster: roster, lastAng: nil)
        XCTAssertEqual(explore.voiceCount, n)
        XCTAssertTrue(explore.mastheadLine.contains("· \(n) voices ·"), explore.mastheadLine)

        // Lineage (the hero headline and the contributors tile count `split.voices`).
        let lineage = LineageCount.split(roster, withBani: Set(summaries.map(\.author)))
        XCTAssertEqual(lineage.voices.count, n)
        XCTAssertEqual(LineageScreen.headline(lineage.voices), "\(n) voices · 12th–17th century")

        // Insights › Contributors: the same split, over `author_analytics` rows.
        let insights = LineageCount.split(roster, withBani: Set(try db.authorAnalytics().map(\.author)))
        XCTAssertEqual(insights, lineage, "Insights and Lineage count and flag the same voices")
        XCTAssertEqual(ContributorsView.header(insights), "\(n) voices · one Granth")

        // The Voice pages: every counted voice has a page that resolves.
        for c in lineage.voices {
            let page = try XCTUnwrap(VoiceRouteView.resolve(slug: c.slug, roster: roster, summaries: summaries), c.name)
            XCTAssertEqual(page.contributor.name, c.name)
            XCTAssertEqual(page.roster.count, n, "\(c.name)'s page sees the same voices")
        }
    }

    /// Dataset 1.3.0 (G3 ruling): Bhagat Surdas Ji's line at Ang 1253 is tagged to him, so every
    /// roster voice has tagged lines, no voice is under review and no note sits under the figures.
    /// His page shows his verse, never a review line or "0 verses".
    func testEveryRosterVoiceIsTaggedSinceTheG3Ruling() throws {
        let (_, roster, summaries) = try shipped()
        let split = LineageCount.split(roster, withBani: Set(summaries.map(\.author)))
        XCTAssertEqual(split.underReview.map(\.name), [], "dataset 1.3.0: every roster voice has tagged lines")
        XCTAssertEqual(split.tagged, roster.count)
        XCTAssertNil(LineageCount.taggedNote(split, locale: Locale(identifier: "en_US")))
        let page = try XCTUnwrap(VoiceRouteView.resolve(slug: "bhagat-surdas-ji", roster: roster, summaries: summaries))
        XCTAssertNotNil(page.summary, "Surdas's page reads his tagged line")
    }
}
