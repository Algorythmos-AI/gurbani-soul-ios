import XCTest
import GurbaniSearchKit
@testable import SGGS

/// The Lineage roster and the labels drawn from it: roster v2 fields decode leniently (a newer
/// or malformed field never empties the list), honorific names, Gurmukhi medallions, and the one
/// canonical count line.
final class ContributorsTests: XCTestCase {

    private func decode(_ entries: String) -> [Contributor]? {
        ContributorsStore.decode(Data(#"{"contributors": [\#(entries)]}"#.utf8))
    }

    private let v1 = #"""
    {"name": "Bhagat Jaidev Ji", "roman": "Jaidev", "kind": "bhagat", "seq": null, "born": 1170, "died": 1245,
     "circa": true, "era": "12th–13th century", "region": "Bengal", "tradition": "Vaishnava poet", "blurb": "b"}
    """#

    func testBundledRosterDecodes() throws {
        let roster = try XCTUnwrap(ContributorsStore.load())
        XCTAssertGreaterThanOrEqual(roster.count, 30)
        XCTAssertEqual(Set(roster.map(\.name)).count, roster.count)
    }

    func testV1EntryHasNoV2Fields() throws {
        let c = try XCTUnwrap(decode(v1)?.first)
        XCTAssertNil(c.display); XCTAssertNil(c.gurmukhi); XCTAssertNil(c.sources); XCTAssertNil(c.review)
        XCTAssertEqual(c.displayName, "Bhagat Jaidev Ji", "falls back to the honorific stored name")
        XCTAssertFalse(c.awaitingReview)
        XCTAssertEqual(c.lifeText, "b")
    }

    func testV2FieldsDecode() throws {
        let entry = v1.dropLast(1) + #"""
        , "display": "Bhagat Jaidev Ji", "gurmukhi": "ਭਗਤ ਜੈਦੇਵ ਜੀ", "chhap": ["ਜੈਦੇਵ"], "context": "c",
          "sources": [{"ref": "Encyclopaedia of Sikhism", "entry": "Jaidev"}],
          "review": {"status": "pending"}, "notable": [{"title": "Gita Govinda", "comp_id": 7}]}
        """#
        let c = try XCTUnwrap(decode(String(entry))?.first)
        XCTAssertEqual(c.gurmukhi, "ਭਗਤ ਜੈਦੇਵ ਜੀ")
        XCTAssertEqual(c.chhap, ["ਜੈਦੇਵ"])
        XCTAssertEqual(c.sources?.first?.ref, "Encyclopaedia of Sikhism")
        XCTAssertEqual(c.notable?.first?.compId, 7)
        XCTAssertTrue(c.awaitingReview)
        XCTAssertNil(c.reviewedContext)
        XCTAssertEqual(c.lifeText, "b", "pending context is gated: the v1 blurb shows instead (G3)")
    }

    /// G3: roster context is shown only once approved; draft, pending or unreviewed context is gated.
    func testContextIsGatedOnItsReviewStatus() throws {
        func entry(_ review: String) throws -> Contributor {
            try XCTUnwrap(decode(String(v1.dropLast(1) + #", "context": "reviewed prose"\#(review)}"#))?.first)
        }
        let approved = try entry(#", "review": {"status": "approved", "reviewer": "scholar"}"#)
        XCTAssertEqual(approved.lifeText, "reviewed prose")
        XCTAssertFalse(approved.awaitingReview)
        for status in ["draft", "pending", "Rejected"] {
            let gated = try entry(#", "review": {"status": "\#(status)"}"#)
            XCTAssertEqual(gated.lifeText, "b", "\(status) context must not show")
            XCTAssertTrue(gated.awaitingReview, status)
        }
        let unreviewed = try entry("")
        XCTAssertEqual(unreviewed.lifeText, "b", "context with no review record is not shown")
        XCTAssertTrue(unreviewed.awaitingReview)
    }

    /// A v2 field of an unexpected shape drops that field only — never the roster.
    func testMalformedV2FieldIsIgnored() throws {
        let entry = v1.dropLast(1) + #", "sources": "Wikipedia", "review": 3, "gurmukhi": 12}"#
        let c = try XCTUnwrap(decode(String(entry))?.first, "the whole roster must still load")
        XCTAssertNil(c.sources); XCTAssertNil(c.review); XCTAssertNil(c.gurmukhi)
    }

    func testGuruMedallionIsTheMahalaInGurmukhi() throws {
        let roster = try XCTUnwrap(ContributorsStore.load())
        let m9 = try XCTUnwrap(roster.first { $0.name == "Guru Tegh Bahadur Ji (M9)" })
        XCTAssertEqual(VoiceMedallion.of(m9).text, "ਮ: ੯")
        XCTAssertTrue(VoiceMedallion.of(m9).isGurmukhi)
        XCTAssertEqual(m9.displayName, "Guru Tegh Bahadur Ji")
        XCTAssertEqual(VoiceMedallion.gurmukhiNumeral(10), "੧੦")
    }

    func testGurmukhiInitialSkipsHonorifics() {
        XCTAssertEqual(VoiceMedallion.gurmukhiInitial("ਭਗਤ ਕਬੀਰ ਜੀ"), "ਕ")
        XCTAssertEqual(VoiceMedallion.gurmukhiInitial("ਬਾਬਾ ਸੁੰਦਰ ਜੀ"), "ਸ")
        XCTAssertEqual(VoiceMedallion.gurmukhiInitial("ਸ਼ੇਖ ਫ\u{0A3C}ਰੀਦ ਜੀ"), "ਫ\u{0A3C}", "a nukta stays with its letter")
        XCTAssertNil(VoiceMedallion.gurmukhiInitial("Kabir"))
        XCTAssertEqual(VoiceMedallion.latinInitial("Bhatt Kalsahar"), "K")
        XCTAssertEqual(VoiceMedallion.latinInitial("The Bhatts"), "B")
    }

    /// The count line on a card is the same canonical count the Voice page shows.
    func testCountLine() {
        let s = VoiceSummary(author: "Guru Tegh Bahadur Ji (M9)", nVerses: 536, nCompositions: 61, nRaags: 15,
                             firstAng: 219, lastAng: 1429, angs: AngSet([219, 1429]))
        XCTAssertEqual(LineageScreen.countLine(s), "536 verses · 61 compositions · Angs 219–1429")
        let one = VoiceSummary(author: "x", nVerses: 1, nCompositions: 1, nRaags: 0, firstAng: 5, lastAng: 5,
                               angs: AngSet([5]))
        XCTAssertEqual(LineageScreen.countLine(one), "1 verse · 1 composition · Ang 5")
    }

    // MARK: deep link + intent (I5)

    func testSlugs() throws {
        XCTAssertEqual(Contributor.slug(for: "Guru Tegh Bahadur Ji (M9)"), "guru-tegh-bahadur-ji")
        XCTAssertEqual(Contributor.slug(for: "Bhatt Kalsahar (ਭਟ)"), "bhatt-kalsahar")
        XCTAssertEqual(Contributor.slug(for: "Satta & Balwand"), "satta-balwand")
        let roster = try XCTUnwrap(ContributorsStore.load())
        XCTAssertEqual(Set(roster.map(\.slug)).count, roster.count, "slugs are unique")
        XCTAssertTrue(roster.allSatisfy { Router.isValidVoiceSlug($0.slug) })
        XCTAssertEqual(Set(VoiceQuery.all().map(\.id)), Set(roster.map(\.slug)))
    }

    @MainActor
    func testVoiceDeepLink() {
        let c = AppContainer(); let r = Router()
        r.handle(URL(string: "sggs://voice/guru-tegh-bahadur-ji")!, container: c)
        XCTAssertEqual(r.selectedTab, .explore)
        XCTAssertEqual(r.explorePath.count, 2, "Lineage, then the voice")
        let r2 = Router()
        for bad in ["sggs://voice/", "sggs://voice/Guru%20Nanak", "sggs://voice/-x", "sggs://voice/a--b",
                    "sggs://voice/" + String(repeating: "a", count: 65)] {
            r2.handle(URL(string: bad)!, container: c)
        }
        XCTAssertEqual(r2.explorePath.count, 0, "malformed slugs are ignored")
        XCTAssertNotEqual(r2.selectedTab, .explore)
    }
}
