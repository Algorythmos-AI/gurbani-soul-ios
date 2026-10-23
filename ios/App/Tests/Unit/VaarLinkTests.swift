import XCTest
import GurbaniDB
import GurbaniSearchKit
@testable import SGGS

/// sggs://vaars · sggs://vaar/<id>[/read][?pauri=|?line=] and the Siri Vaar list.
final class VaarLinkTests: XCTestCase {

    @MainActor
    func testVaarLinksBuildTheExploreStack() {
        let c = AppContainer(); let r = Router()
        r.handle(URL(string: "sggs://vaars")!, container: c)
        XCTAssertEqual(r.selectedTab, .explore)
        XCTAssertEqual(r.explorePath.count, 1)

        r.handle(URL(string: "sggs://vaar/5")!, container: c)
        XCTAssertEqual(r.explorePath.count, 2, "home → weave")

        r.handle(URL(string: "sggs://vaar/5/read")!, container: c)
        XCTAssertEqual(r.explorePath.count, 3, "home → weave → reader")

        r.handle(URL(string: "sggs://vaar/5?pauri=12")!, container: c)
        XCTAssertEqual(r.explorePath.count, 3, "a pauri opens the reader")

        r.handle(URL(string: "sggs://vaar/2?line=5700")!, container: c)
        XCTAssertEqual(r.explorePath.count, 3, "a line opens the reader")
    }

    @MainActor
    func testHostileVaarLinksChangeNothing() {
        let c = AppContainer(); let r = Router()
        r.handle(URL(string: "sggs://vaar/2")!, container: c)
        let before = r.explorePath
        for bad in ["sggs://vaar/0", "sggs://vaar/23", "sggs://vaar/-1", "sggs://vaar/abc", "sggs://vaar/",
                    "sggs://vaar/99999999999999999999", "sggs://vaar/%20"] {
            r.handle(URL(string: bad)!, container: c)
            XCTAssertEqual(r.explorePath, before, bad)
        }
        // an out-of-range pauri is dropped: the link still opens the weave, not a bogus reader
        r.handle(URL(string: "sggs://vaar/19?pauri=500")!, container: c)
        XCTAssertEqual(r.explorePath.count, 2)
    }

    /// The Siri list names every Vaar the DB has, in its raag and pauri voice.
    func testSiriVaarListMatchesTheShippedDB() throws {
        guard let path = Bundle.main.url(forResource: "sggs-ios", withExtension: "sqlite")?.path else {
            throw XCTSkip("bundled DB not found in host app")
        }
        let vaars = try SQLiteCandidateSource(path: path).vaars()
        XCTAssertEqual(vaars.map(\.vaarId), VaarChoice.allCases.map(\.rawValue))
        XCTAssertEqual(Set(vaars.map(\.vaarId)), Set(Router.vaarIds))
        for v in vaars {
            let choice = try XCTUnwrap(VaarChoice(rawValue: v.vaarId))
            let name = String(localized: VaarChoice.caseDisplayRepresentations[choice]!.title)
            let voice = v.pauriAuthor.map(VoiceInk.short) ?? ""
            XCTAssertTrue(name.contains("(\(voice))"), "\(name) vs \(voice)")
        }
    }
}
