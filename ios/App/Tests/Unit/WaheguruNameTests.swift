import XCTest
import SwiftUI
import GurbaniDB
import GurbaniSearchKit
@testable import SGGS

/// The theme keyed `vahiguru` is shown as "Waheguru", the spelling most readers know. The slug
/// stays the key (routes, Spotlight ids, saved themes, contract vectors); every other spelling a
/// reader types or links finds the same theme.
final class WaheguruNameTests: XCTestCase {

    static let spellings = ["waheguru", "Waheguru", "vaheguru", "Vaheguru", "vahiguru", "wahiguru"]

    private func rows() throws -> [ThemeIndexRow] {
        guard let url = Bundle.main.url(forResource: "sggs-ios", withExtension: "sqlite") else {
            throw XCTSkip("sggs-ios.sqlite not bundled")
        }
        return try SQLiteCandidateSource(path: url.path).themeIndex()
    }

    func testTheThemeIsShownAsWaheguru() {
        XCTAssertEqual(ConceptName.display("vahiguru"), "Waheguru")
        XCTAssertEqual(ConceptName.display("naam"), "Naam", "other themes keep their slug's name")
        XCTAssertEqual(ConceptName.label("vahiguru", description: nil), "Waheguru")
    }

    func testEverySpellingResolvesToTheSlug() {
        for s in Self.spellings { XCTAssertEqual(ConstellationLink.slug(s), "vahiguru", s) }
        XCTAssertEqual(ConstellationLink.slug("naam"), "naam")
        XCTAssertNil(ConstellationLink.slug("waheguru'"), "an alias never relaxes the allowlist")
        XCTAssertNil(ConstellationLink.slug("wahe guru"))
    }

    func testThemesIndexSearchFindsWaheguruUnderEverySpelling() throws {
        let all = try rows()
        XCTAssertTrue(all.contains { $0.concept == "vahiguru" }, "the bundled DB keeps the slug")
        for s in Self.spellings {
            XCTAssertEqual(ThemeIndexModel.search(all, s).first?.concept, "vahiguru", s)
        }
        XCTAssertEqual(ThemeIndexModel.search(all, "wahe").first?.concept, "vahiguru", "a prefix finds it too")
    }

    func testSpotlightTitleChangesButTheIdentifierDoesNot() throws {
        guard let row = try rows().first(where: { $0.concept == "vahiguru" }) else { return XCTFail("no vahiguru row") }
        let item = SpotlightIndex.themeItem(row)
        XCTAssertEqual(item.uniqueIdentifier, "theme-vahiguru")
        XCTAssertEqual(SpotlightIndex.themeSlug(fromIdentifier: item.uniqueIdentifier), "vahiguru")
        XCTAssertTrue(item.attributeSet.title?.hasPrefix("Waheguru") == true, item.attributeSet.title ?? "nil")
        let keywords = item.attributeSet.keywords ?? []
        for s in ["Waheguru", "vahiguru", "waheguru", "vaheguru", "wahiguru"] { XCTAssertTrue(keywords.contains(s), s) }
    }

    /// The themes index is stamped per build AND per name revision: a renamed theme re-indexes
    /// system search even when the build number is unchanged.
    func testTheIndexStampCarriesTheNameRevision() {
        XCTAssertTrue(ConceptName.revision.contains("vahiguru=Waheguru"))
        XCTAssertTrue(SpotlightIndex.themesIndexStamp(bundle: .main).hasSuffix("+" + ConceptName.revision))
    }

    @MainActor
    func testWaheguruLinkOpensTheThemePage() async throws {
        let c = AppContainer(); let r = Router()
        await c.loadMeta()
        guard c.meta != nil else { throw XCTSkip("no bundled DB") }
        for link in ["sggs://theme/waheguru", "sggs://theme/Waheguru", "sggs://theme/vahiguru"] {
            r.explorePath = NavigationPath()
            r.handle(URL(string: link)!, container: c)
            XCTAssertEqual(r.explorePath.count, 2, "\(link) → the theme page, not the index")
        }
    }
}
