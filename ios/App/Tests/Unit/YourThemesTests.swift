import XCTest
import SwiftUI
import GurbaniSearchKit
@testable import SGGS

/// "Your themes" (on-device only), the theme Spotlight entries, the Open-a-theme route, and the
/// share text: each is computed from what it is given and nothing else.
final class YourThemesTests: XCTestCase {

    private func verse(_ id: Int) -> YourThemes.Verse {
        YourThemes.Verse(lineId: id, compId: 1, ang: 1, gurmukhi: "ਨਾਮੁ", translit: "naam")
    }
    private func row(_ c: String, n: Int = 10) -> ThemeIndexRow {
        ThemeIndexRow(concept: c, description: "", terms: [], headword: nil, nVerses: n, nShabads: 1, nRahao: 0,
                      angBins: Array(repeating: 0, count: 15))
    }

    func testSummaryCountsOnlyTheSavedVerses() {
        let saved = [verse(1), verse(2), verse(3)]
        let members: [String: Set<Int>] = ["naam": [1, 2, 99], "sahaj": [3], "kaam": [77]]   // 99, 77 are not saved
        let themes = ["naam", "sahaj", "kaam", "seva", "daya", "anand", "akal"].map { row($0) }
        let s = YourThemes.summarize(saved: saved, members: members, themes: themes, day: 0)
        XCTAssertEqual(s.savedCount, 3)
        XCTAssertEqual(s.carried.map(\.concept), ["naam", "sahaj"], "most first; a theme only an unsaved id carries is not shown")
        XCTAssertEqual(s.carried.first?.verses.map(\.lineId), [1, 2])
        XCTAssertEqual(s.notYet.count, 3)
        XCTAssertTrue(Set(s.notYet).isDisjoint(with: ["naam", "sahaj"]), "not-met themes are ones no saved verse carries")
        XCTAssertNotEqual(YourThemes.summarize(saved: saved, members: members, themes: themes, day: 1).notYet, s.notYet,
                          "the invitation rotates by day")
        XCTAssertEqual(YourThemes.summarize(saved: saved, members: members, themes: themes, day: 0), s, "deterministic")
    }

    func testEmptyAndUntaggedThemesAreNeverInvited() {
        let s = YourThemes.summarize(saved: [], members: [:], themes: [row("empty", n: 0), row("naam")], day: 5)
        XCTAssertEqual(s.carried.count, 0)
        XCTAssertEqual(s.notYet, ["naam"])
    }

    func testThemeSpotlightIdentifiersRoundTrip() {
        XCTAssertEqual(SpotlightIndex.themeSlug(fromIdentifier: SpotlightIndex.themeIdentifier("dukh_sukh")), "dukh_sukh")
        XCTAssertNil(SpotlightIndex.themeSlug(fromIdentifier: "theme-Naam'--"), "a malformed slug is not routed")
        XCTAssertNil(SpotlightIndex.themeSlug(fromIdentifier: "saved-1-comp-2"))
        XCTAssertNil(SpotlightIndex.compId(fromIdentifier: "theme-naam"), "a theme is never read as a saved verse")
    }

    func testShareTextIsNamesAndCountsNeverVerseText() {
        let r = ThemeIndexRow(concept: "sahaj", description: "Intuitive poise — the effortless state.", terms: ["ਸਹਜਿ"],
                              headword: "ਸਹਜਿ", nVerses: 940, nShabads: 700, nRahao: 74, angBins: Array(repeating: 0, count: 15))
        let text = ThemeShare.text(r)
        XCTAssertTrue(text.hasPrefix("Sahaj · ਸਹਜਿ\nIntuitive poise\n940 verses in 700 shabads of Sri Guru Granth Sahib Ji"))
    }

    @MainActor
    func testThemesDeepLinkOpensTheIndex() {
        let c = AppContainer(); let r = Router()
        r.handle(URL(string: "sggs://themes")!, container: c)
        XCTAssertEqual(r.selectedTab, .explore)
        XCTAssertEqual(r.explorePath.count, 1)
    }

    /// A well-formed name that is not one of the 54 themes (e.g. Siri's "mercy") lands on the
    /// index, never a not-found page; a real theme still opens its page.
    @MainActor
    func testUnknownThemeNameOpensTheIndex() async throws {
        let c = AppContainer(); let r = Router()
        await c.loadMeta()
        guard c.meta != nil else { throw XCTSkip("no bundled DB") }
        r.handle(URL(string: "sggs://theme/mercy")!, container: c)
        XCTAssertEqual(r.explorePath.count, 1, "unknown theme → the index")
        r.handle(URL(string: "sggs://theme/sahaj")!, container: c)
        XCTAssertEqual(r.explorePath.count, 2, "a real theme → its page")
    }

    /// Clearing the saved store (reconcile / removeAll on the saved domain) cannot touch the theme
    /// entries: Spotlight deletes a domain and its sub-domains, so neither may contain the other.
    func testThemeSpotlightDomainSurvivesASavedStoreReset() {
        XCTAssertNotEqual(SpotlightIndex.domain, SpotlightIndex.themeDomain)
        XCTAssertFalse(SpotlightIndex.themeDomain.hasPrefix(SpotlightIndex.domain + "."))
        XCTAssertFalse(SpotlightIndex.domain.hasPrefix(SpotlightIndex.themeDomain + "."))
    }

    /// A failed lookup is reported as "could not be counted", never as a tally of nothing.
    func testUnavailableIsNotAnEmptyTally() {
        let u = YourThemes.Summary.unavailable(savedCount: 5)
        XCTAssertTrue(u.unavailable)
        XCTAssertTrue(u.carried.isEmpty && u.notYet.isEmpty)
        let real = YourThemes.summarize(saved: [verse(1), verse(2), verse(3)], members: [:], themes: [row("naam")], day: 0)
        XCTAssertFalse(real.unavailable, "summarize only ever describes a lookup that succeeded")
        XCTAssertNotEqual(u, YourThemes.summarize(saved: [], members: [:], themes: [], day: 0))
    }
}
