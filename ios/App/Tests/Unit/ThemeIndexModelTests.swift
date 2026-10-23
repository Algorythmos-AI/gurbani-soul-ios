import XCTest
import GurbaniDB
import GurbaniSearchKit
@testable import SGGS

/// The Themes index rules on the bundled DB: search finds a theme by name, meaning or Gurmukhi
/// word; arrangements never drop a theme; glosses and the "most in Angs" phrase are honest.
final class ThemeIndexModelTests: XCTestCase {

    private func rows() throws -> [ThemeIndexRow] {
        guard let url = Bundle.main.url(forResource: "sggs-ios", withExtension: "sqlite") else {
            throw XCTSkip("sggs-ios.sqlite not bundled")
        }
        return try SQLiteCandidateSource(path: url.path).themeIndex()
    }

    func testSearchFindsByNameMeaningAndGurmukhiWord() throws {
        let all = try rows()
        func found(_ q: String) -> [String] { ThemeIndexModel.search(all, q).map(\.concept) }
        XCTAssertEqual(found("naam").first, "naam", "a name match comes first")
        XCTAssertEqual(found("NAAM").first, "naam", "case-insensitive")
        XCTAssertEqual(found("  sahaj ").first, "sahaj", "trimmed")
        XCTAssertTrue(found("ego").contains("haumai"))
        XCTAssertTrue(found("ego").contains("ahankar"))
        XCTAssertTrue(found("ego").contains("garab"))
        XCTAssertEqual(found("ਹਉਮੈ").first, "haumai", "a Gurmukhi word finds its theme")
        XCTAssertTrue(found("ਹੰਉਮੈ").contains("haumai"), "the tippi spelling is one of Haumai's words")
        XCTAssertTrue(found("kal").contains("kaal") && found("kal").contains("akal"), "Kāl folds to kal")
        XCTAssertTrue(found("dukh sukh").contains("dukh_sukh"), "underscore slugs match with a space")
        XCTAssertEqual(found("zzzz"), [])
        XCTAssertEqual(found("   "), [], "a blank query is no search")
        // a decomposed query compares equal to the stored (NFC) word
        let decomposed = "ਸਹਜਿ".decomposedStringWithCanonicalMapping
        XCTAssertTrue(found(decomposed).contains("sahaj"))
    }

    func testEveryArrangementKeepsEveryTheme() throws {
        let all = try rows()
        XCTAssertEqual(all.count, 54)
        for a in ThemeIndexModel.Arrangement.allCases {
            XCTAssertEqual(Set(ThemeIndexModel.arranged(all, a).map(\.concept)), Set(all.map(\.concept)), "\(a)")
        }
        let grouped = ThemeIndexModel.grouped(all).flatMap(\.rows).map(\.concept)
        XCTAssertEqual(grouped.count, 54, "a theme appears in exactly one family")
        XCTAssertEqual(Set(grouped), Set(all.map(\.concept)))
        let bySize = ThemeIndexModel.arranged(all, .size).map(\.nVerses)
        XCTAssertEqual(bySize, bySize.sorted(by: >))
        // an unknown slug still shows, under More Themes
        let extra = ThemeIndexRow(concept: "zz_new", description: "", terms: ["ਨਵਾਂ"], headword: "ਨਵਾਂ",
                                  nVerses: 1, nShabads: 1, nRahao: 0, angBins: Array(repeating: 0, count: 15))
        let withExtra = ThemeIndexModel.grouped(all + [extra])
        XCTAssertNil(withExtra.last?.group)
        XCTAssertEqual(withExtra.last?.rows.map(\.concept), ["zz_new"])
    }

    func testGlossIsTheDescriptionsOpeningPhrase() throws {
        let byKey = Dictionary(uniqueKeysWithValues: try rows().map { ($0.concept, $0) })
        XCTAssertEqual(ThemeIndexModel.gloss(byKey["naam"]!.description), "The divine Name")
        XCTAssertEqual(ThemeIndexModel.gloss(byKey["haumai"]!.description), "The ego-self")
        XCTAssertEqual(ThemeIndexModel.gloss(byKey["karam_nadar"]!.description), "Divine grace in multiple registers")
        XCTAssertEqual(ThemeIndexModel.gloss("Contentment."), "Contentment")
        XCTAssertEqual(ThemeIndexModel.gloss(""), "")
        for r in byKey.values {
            XCTAssertFalse(ThemeIndexModel.gloss(r.description).isEmpty, "\(r.concept): empty gloss")
            XCTAssertTrue(r.description.hasPrefix(ThemeIndexModel.gloss(r.description)), "\(r.concept): the gloss must be the description's own words")
        }
    }

    func testPeakPhraseAndSummary() throws {
        var bins = Array(repeating: 0, count: 15)
        XCTAssertNil(ThemeIndexModel.peakPhrase(bins))
        bins[11] = 9; bins[3] = 9
        XCTAssertEqual(ThemeIndexModel.peakPhrase(bins), "Most in Angs 301–400", "earliest stretch on a tie")
        bins[14] = 20
        XCTAssertEqual(ThemeIndexModel.peakPhrase(bins), "Most in Angs 1401–1430", "the last stretch ends at 1430")
        let naam = try XCTUnwrap(try rows().first { $0.concept == "naam" })
        let head = try XCTUnwrap(naam.headword)
        XCTAssertTrue(ThemeIndexModel.accessibilitySummary(naam).hasPrefix("Naam, \(head), 5,672 verses in 2,472 shabads, most in Angs "),
                      "VoiceOver hears the name, the Gurmukhi headword, then the counts")
    }
}
