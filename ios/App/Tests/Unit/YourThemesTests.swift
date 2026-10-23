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
}
