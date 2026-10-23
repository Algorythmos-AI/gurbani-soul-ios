import XCTest
import GurbaniDB
import GurbaniSearchKit
@testable import SGGS

/// The Forms tab on the SHIPPED DB: every genre appears once, in the order the saroop first meets
/// it, every heading is accounted for, and continuation labels fold into the run they belong to.
final class PoeticFormGroupsTests: XCTestCase {

    private func forms() throws -> [PoeticFormEntry] {
        guard let path = Bundle.main.url(forResource: "sggs-ios", withExtension: "sqlite")?.path
            ?? Bundle(for: Self.self).url(forResource: "sggs-ios", withExtension: "sqlite")?.path
        else { throw XCTSkip("bundled DB not found in host app") }
        return try SQLiteCandidateSource(path: path).poeticForms()
    }

    func testEveryHeadingIsAccountedForInSaroopOrder() throws {
        let all = try forms()
        let groups = PoeticFormGroups.groups(all)
        XCTAssertEqual(groups.count, Set(all.map(\.genre)).count, "one group per genre")
        XCTAssertEqual(groups.flatMap(\.entries).reduce(0) { $0 + $1.headings }, all.count, "no heading lost")
        let firsts = groups.map { $0.entries[0].first.firstAng }
        XCTAssertEqual(firsts, firsts.sorted(), "genres in the order the Granth first meets them")
        XCTAssertEqual(groups.first?.genre, "pahare", "Sri Raag's Pahare (Ang 74) comes first")
        for g in groups { XCTAssertNotNil(PoeticForms.genreNames[g.genre], "no display name for \(g.genre)") }
    }

    func testRunsFoldButDistinctCompositionsStayApart() throws {
        let groups = PoeticFormGroups.groups(try forms())
        func g(_ k: String) -> PoeticFormGroups.Group? { groups.first { $0.genre == k } }
        // Dakhne: Gauri's salok dakhna (Ang 322) and the run inside Maru Vaar Mahalla 5 (Ang 1094–1102).
        let dakhne = try XCTUnwrap(g("dakhne"))
        XCTAssertEqual(dakhne.entries.count, 2)
        XCTAssertEqual(dakhne.entries.map(\.first.firstAng), [322, 1094])
        XCTAssertEqual(dakhne.entries[1].lastAng, 1102)
        XCTAssertEqual(dakhne.entries[1].headings, 22)
        // Barah Maha in Majh (Guru Arjan Dev Ji) and Tukhari (Guru Nanak Dev Ji) stay two.
        XCTAssertEqual(g("barah_maha")?.entries.map(\.first.firstAng), [133, 1107])
        // Thitti by Guru Arjan Dev Ji, Bhagat Kabir Ji and Guru Nanak Dev Ji: three, not merged.
        XCTAssertEqual(g("thitti")?.entries.count, 3)
        // Patti by Guru Nanak Dev Ji (Ang 432) and Guru Amar Das Ji (Ang 434).
        XCTAssertEqual(g("patti")?.entries.count, 2)
        // Each Bhatt / Mukhbak Savaiye set is its own heading with a Mahala.
        XCTAssertEqual(g("savaiye")?.entries.count, 7)
    }

    func testFindReachesForms() throws {
        let all = try forms()
        guard let path = Bundle.main.url(forResource: "sggs-ios", withExtension: "sqlite")?.path
            ?? Bundle(for: Self.self).url(forResource: "sggs-ios", withExtension: "sqlite")?.path
        else { throw XCTSkip("bundled DB not found in host app") }
        let meta = try SQLiteCandidateSource(path: path).fetchMeta()
        let r = IndexFind.run("barah maha", meta: meta, compositions: [], forms: all)
        XCTAssertEqual(r.forms.map(\.genre), ["barah_maha"], "one row per form")
        XCTAssertEqual(r.forms.first?.firstAng, 133)
    }
}
