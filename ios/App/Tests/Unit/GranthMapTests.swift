import XCTest
import GurbaniDB
import GurbaniSearchKit
@testable import SGGS

/// The Index's map of the Granth on the SHIPPED bundle DB: the three movements partition the
/// sections exactly, every raag has a familiar English name and a unique slug, and the slice bar
/// never draws outside its track.
final class GranthMapTests: XCTestCase {

    private func meta() throws -> CorpusMeta {
        guard let path = Bundle.main.url(forResource: "sggs-ios", withExtension: "sqlite")?.path
            ?? Bundle(for: Self.self).url(forResource: "sggs-ios", withExtension: "sqlite")?.path
        else { throw XCTSkip("bundled DB not found in host app") }
        return try SQLiteCandidateSource(path: path).fetchMeta()
    }

    func testMovementsFollowTheSaroop() throws {
        let m = try meta()
        let map = GranthMap(meta: m)
        XCTAssertEqual(map.raags.count, 31)
        XCTAssertEqual(map.raags.map(\.seq), Array(1...31))
        XCTAssertEqual(map.raagSpan, 14...1353)
        XCTAssertEqual(map.opening.map(\.firstAng).first, 1, "Japji opens the Granth")
        XCTAssertEqual(map.openingSpan?.upperBound, 13)
        XCTAssertEqual(map.closingSpan?.upperBound, 1430, "Raagmala closes it")
        XCTAssertEqual(map.opening.count + map.closing.count, m.sections.count, "every section in exactly one movement")
        // The raags tile Ang 14…1353 with no gap and no overlap.
        for (a, b) in zip(map.raags, map.raags.dropFirst()) {
            XCTAssertEqual(a.lastAng + 1, b.firstAng, "\(a.name) → \(b.name)")
        }
        XCTAssertEqual(map.raag(containing: 262)?.name, "ਗਉੜੀ")
        XCTAssertNil(map.raag(containing: 5))
        XCTAssertNil(map.raag(containing: 1400))
    }

    func testEveryRaagAndSectionHasAnEnglishName() throws {
        let m = try meta()
        for r in m.raags { XCTAssertNotNil(GranthNames.raags[r.name], "no English name for \(r.name)") }
        for s in m.sections { XCTAssertNotNil(GranthNames.section(s.name), "no English name for \(s.name)") }
    }

    /// The pinned data's ਚਉਬੋਲੇ row also holds the Kabir and Farid saloks; the Index must say so
    /// rather than call 22 Angs "Chaubole" — and must go back to "Chaubole" once the data is split.
    func testChauboleNamesWhatItsSpanHolds() {
        XCTAssertEqual(GranthNames.section("ਚਉਬੋਲੇ", firstAng: 1363, lastAng: 1384),
                       "Chaubole, Salok Bhagat Kabir Ji, Salok Sheikh Farid Ji")
        XCTAssertEqual(GranthNames.section("ਚਉਬੋਲੇ", firstAng: 1363, lastAng: 1364), "Chaubole")
        XCTAssertEqual(GranthNames.section("ਗਾਥਾ", firstAng: 1360, lastAng: 1361), "Gatha")
    }

    func testRaagSlugsAreUniqueAndRoundTrip() throws {
        let m = try meta()
        let pairs = m.raags.map { (name: $0.name, roman: $0.roman) }
        let slugs = m.raags.map { GranthNames.slug(forRaag: $0.name, roman: $0.roman) }
        XCTAssertEqual(Set(slugs).count, slugs.count)
        for (r, slug) in zip(m.raags, slugs) {
            XCTAssertTrue(slug.allSatisfy { ("a"..."z").contains($0) || $0 == "-" }, slug)
            XCTAssertEqual(GranthNames.raagName(forSlug: slug, in: pairs), r.name)
            // the corpus roman (the Raag Clock's deep-link form) resolves too
            if let roman = r.roman {
                XCTAssertEqual(GranthNames.raagName(forSlug: roman.replacingOccurrences(of: " ", with: "-"), in: pairs), r.name)
            }
        }
        XCTAssertEqual(GranthNames.slug(forRaag: "ਨਟ", roman: "nat"), "nat-narayan")
        XCTAssertNil(GranthNames.raagName(forSlug: "", in: pairs))
        XCTAssertNil(GranthNames.raagName(forSlug: "not-a-raag", in: pairs))
    }

    func testRomanTableMatchesTheDB() throws {
        let m = try meta()
        XCTAssertEqual(GranthNames.romanToRaag.count, m.raags.count)
        for r in m.raags { XCTAssertEqual(GranthNames.romanToRaag[try XCTUnwrap(r.roman)], r.name) }
    }

    @MainActor
    func testRaagDeepLinkValuesResolveWithoutTheDB() {
        XCTAssertEqual(Router.raagName("gauri"), "ਗਉੜੀ")
        XCTAssertEqual(Router.raagName("Gauri"), "ਗਉੜੀ")
        XCTAssertEqual(Router.raagName("gaurhee"), "ਗਉੜੀ", "the corpus roman (Raag Clock form)")
        XCTAssertEqual(Router.raagName("maalee-gaurhaa"), "ਮਾਲੀ ਗਉੜਾ")
        XCTAssertEqual(Router.raagName("mali-gaura"), "ਮਾਲੀ ਗਉੜਾ")
        XCTAssertEqual(Router.raagName("nat-narayan"), "ਨਟ")
        XCTAssertEqual(Router.raagName("sri-raag"), "ਸਿਰੀਰਾਗੁ")
        XCTAssertEqual(Router.raagName("ਰਾਮਕਲੀ"), "ਰਾਮਕਲੀ")
        for bad in ["", "x", "../etc", "gauri;drop", String(repeating: "a", count: 200)] {
            XCTAssertNil(Router.raagName(bad), bad)
        }
    }

    func testPrimaryPaharsKeepOnlyPrimaryClaimsInRange() {
        func claim(_ raag: String, _ type: String, _ p: Int?) -> TimingClaim {
            TimingClaim(raagName: raag, roman: nil, firstAng: nil, seq: nil, claimType: type, pahar: p,
                        timeStart: nil, timeEnd: nil, season: nil, occasion: nil, confidence: "majority",
                        notes: nil, sourceName: "s", tradition: "gurmat_sangeet", sourceURL: nil)
        }
        let clock = TimingClock(available: true,
                                primary: [claim("ਬਿਲਾਵਲੁ", "primary", 2), claim("ਬਿਲਾਵਲੁ", "primary", 1),
                                          claim("ਬਿਲਾਵਲੁ", "primary", 1), claim("ਆਸਾ", "primary", 9)],
                                variant: [claim("ਗਉੜੀ", "variant", 5)], seasonal: [], ceremonial: [])
        XCTAssertEqual(GranthMap.primaryPahars(clock), ["ਬਿਲਾਵਲੁ": [1, 2]])
        XCTAssertEqual(GranthMap.primaryPahars(TimingClock(available: false)), [:])
    }

    func testSliceRectStaysInsideTheTrack() {
        let w: CGFloat = 160
        let gauri = AngSliceBar.sliceRect(first: 151, last: 346, total: 1430, width: w, height: 4)
        XCTAssertEqual(gauri.minX, 150 / 1430 * w, accuracy: 0.001)
        XCTAssertEqual(gauri.maxX, 346 / 1430 * w, accuracy: 0.001)
        let jaijavanti = AngSliceBar.sliceRect(first: 1352, last: 1353, total: 1430, width: w, height: 4)
        XCTAssertGreaterThanOrEqual(jaijavanti.width, 3, "a two-Ang raag is still visible")
        let raagmala = AngSliceBar.sliceRect(first: 1429, last: 1430, total: 1430, width: w, height: 4)
        XCTAssertLessThanOrEqual(raagmala.maxX, w + 0.0001, "never past the end of the track")
        XCTAssertEqual(AngSliceBar.sliceRect(first: 1, last: 1430, total: 1430, width: w, height: 4).width, w)
        XCTAssertEqual(AngSliceBar.sliceRect(first: 5, last: 9, total: 1430, width: 0, height: 4), .zero)
    }

    func testAngLabel() {
        XCTAssertEqual((12...12).angLabel, "Ang 12")
        XCTAssertEqual((1...8).angLabel, "Angs 1–8")
        XCTAssertEqual((1429...1429).angLabel, "Ang 1429")   // no thousands separator
    }
}
