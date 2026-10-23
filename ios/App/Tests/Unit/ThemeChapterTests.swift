import XCTest
import SwiftUI
import GurbaniSearchKit
@testable import SGGS

/// The theme page's pure rules: shabad grouping across pages, companions, the filter summary,
/// the Gurmukhi runs of a description, and the theme deep link.
final class ThemeChapterTests: XCTestCase {

    private func line(_ id: Int, comp: Int) -> SearchLine {
        SearchLine(id: id, ang: 1, gurmukhi: "ਸਹਜਿ", translit: "", raag: nil, section: nil, author: nil,
                   compId: comp, isRahao: false, isHeader: false)
    }

    func testAShabadSplitAcrossPagesStaysOneGroup() {
        var feed = ThemeFeed(first: ThemePage(concept: "sahaj", total: 5, lines: [line(1, comp: 7), line(2, comp: 8)],
                                              nextAfterId: 2, matched: [1: ["ਸਹਜਿ"], 2: ["ਸਹਜਿ"]]))
        feed.append(ThemePage(concept: "sahaj", total: 5, lines: [line(3, comp: 8), line(4, comp: 8), line(5, comp: 9)],
                              nextAfterId: nil, matched: [3: ["ਸਹਜ"], 4: ["ਸਹਜਿ"], 5: ["ਸਹਜੇ"]]), from: 2)
        XCTAssertEqual(feed.groups.map(\.compId), [7, 8, 9])
        XCTAssertEqual(feed.groups[1].lines.map(\.id), [2, 3, 4])
        XCTAssertEqual(feed.matched[3], ["ਸਹਜ"], "matches arrive with their page")
        XCTAssertEqual(Set(feed.matched.keys), [1, 2, 3, 4, 5])
    }

    func testCompanionsAreTheDistinctiveOnesThatShareVerses() {
        let all = [
            ConstellationCompanion(co: "satguru", n: 900, ppmi: 0.1, jaccard: 0.3, shabadCount: 500),
            ConstellationCompanion(co: "bani", n: 90, ppmi: 1.2, jaccard: 0.1, shabadCount: 80),
            ConstellationCompanion(co: "amrit", n: 120, ppmi: 1.2, jaccard: 0.1, shabadCount: 90),
            ConstellationCompanion(co: "kaam", n: 0, ppmi: 2.0, jaccard: 0, shabadCount: 3),
            ConstellationCompanion(co: "maya", n: 40, ppmi: 0, jaccard: 0, shabadCount: 0),
        ]
        XCTAssertEqual(ThemePageModel.companions(all, limit: 5).map(\.co), ["amrit", "bani", "satguru"],
                       "PPMI first, ties by name; no shared verse or no surprise = not shown")
        XCTAssertEqual(ThemePageModel.companions(all, limit: 1).map(\.co), ["amrit"])
    }

    func testFilterSummaryNamesEveryNarrowing() {
        let f = ThemeFilter(term: "ਸਹਜਿ", lens: ConstellationLens(author: "Guru Nanak Dev Ji", raag: "ਗਉੜੀ",
                                                                  rahaoOnly: true, angMin: 101, angMax: 200))
        XCTAssertEqual(ThemeFilterText.parts(f, raagName: { _ in "Raag Gauri" }),
                       ["ਸਹਜਿ", "Rahao lines only", "Guru Nanak Dev", "Raag Gauri", "Angs 101–200"])
        XCTAssertEqual(ThemeFilterText.parts(.none, raagName: { $0 }), [])
    }

    func testDescriptionGurmukhiRunsKeepEveryCharacter() {
        let d = "The cycle of birth (ਜਨਮ) and death (ਮਰਣ/ਮਰਨ), the condition"
        let runs = MixedScriptText.runs(d)
        XCTAssertEqual(runs.map(\.0).joined(), d, "no character is lost, added or reordered")
        XCTAssertTrue(runs.contains { $0.0 == "ਜਨਮ" && $0.1 })
        XCTAssertTrue(runs.contains { $0.0 == "ਮਰਣ/ਮਰਨ" && $0.1 }, "a slash inside a Gurmukhi phrase stays in it")
        XCTAssertEqual(MixedScriptText.runs("").count, 0)
        XCTAssertEqual(MixedScriptText.runs("Contentment").map(\.1), [false])
    }

    @MainActor
    func testThemeDeepLinks() {
        let c = AppContainer(); let r = Router()
        r.handle(URL(string: "sggs://theme/naam")!, container: c)
        XCTAssertEqual(r.selectedTab, .explore)
        XCTAssertEqual(r.explorePath.count, 2, "Themes → the theme page")
        r.handle(URL(string: "sggs://theme/sahaj?term=%E0%A8%B8%E0%A8%B9%E0%A8%9C%E0%A8%BF&rahao=1")!, container: c)
        XCTAssertEqual(r.explorePath.count, 3, "a narrowed link lands on the verse list")
        r.explorePath = NavigationPath()
        r.handle(URL(string: "sggs://theme/Naam'%20OR%201=1")!, container: c)
        XCTAssertEqual(r.explorePath.count, 0, "a malformed slug is ignored")
        r.handle(URL(string: "sggs://theme/")!, container: c)
        XCTAssertEqual(r.explorePath.count, 0)
    }
}
