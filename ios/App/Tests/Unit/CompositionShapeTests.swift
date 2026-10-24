import XCTest
import GurbaniDB
import GurbaniSearchKit
@testable import SGGS

/// The Index cards' composition shapes on the SHIPPED registry: each hero's steps are the reader's
/// own steps, tile the bani without overlap, and progress fills them in order. Plus Find in Index.
final class CompositionShapeTests: XCTestCase {

    private func source() throws -> SQLiteCandidateSource {
        guard let path = Bundle.main.url(forResource: "sggs-ios", withExtension: "sqlite")?.path
            ?? Bundle(for: Self.self).url(forResource: "sggs-ios", withExtension: "sqlite")?.path
        else { throw XCTSkip("bundled DB not found in host app") }
        return try SQLiteCandidateSource(path: path)
    }

    func testHeroShapesMatchThePrintedRhythm() throws {
        let db = try source()
        var units: [String: (Int, String?)] = [:]
        for hero in CompositionCatalog.heroes {
            let bani = try XCTUnwrap(db.fetchBani(key: hero.key, variant: hero.variant), "\(hero.key) missing")
            let shape = CompositionShape(bani: bani)
            units[hero.key] = (shape.steps.count, shape.unit)
            for (a, b) in zip(shape.steps, shape.steps.dropFirst()) {
                XCTAssertLessThan(a.endSeq, b.startSeq, "\(hero.key) steps overlap")
            }
            XCTAssertEqual(shape.steps.map(\.startSeq),
                           BaniPager.steps(in: BaniOutline.sections(for: bani)).map(\.startSeq),
                           "\(hero.key): the card must step exactly as the reader does")
        }
        XCTAssertEqual(units["sukhmani"]?.0, 24)
        XCTAssertEqual(units["sukhmani"]?.1, "ashtapadis")
        XCTAssertEqual(units["anand"]?.0, 40)
    }

    func testFillFollowsTheSavedPosition() {
        let shape = CompositionShape(steps: [.init(startSeq: 1, endSeq: 10), .init(startSeq: 11, endSeq: 20),
                                             .init(startSeq: 21, endSeq: 30)],
                                     unit: "pauris", firstSeq: 1, lastSeq: 30)
        XCTAssertEqual(shape.fill(at: nil, completed: false), [0, 0, 0])
        XCTAssertEqual(shape.fill(at: 15, completed: false), [1, 0.5, 0])
        XCTAssertEqual(shape.fill(at: 3, completed: true), [1, 1, 1])
        XCTAssertEqual(shape.stepNumber(at: 15), 2)
        XCTAssertNil(shape.stepNumber(at: 0))
    }

    func testFindLandsOnFamiliarAndCorpusSpellings() throws {
        let db = try source()
        let meta = try db.fetchMeta()
        let registry = db.fetchBanis().banis
        let offered = CompositionCatalog.heroes.compactMap { CompositionCatalog.resolve($0, in: registry) }
            + CompositionCatalog.more(from: registry)
        XCTAssertEqual(IndexFind.run("gauri", meta: meta, compositions: offered).raags.first?.name, "ਗਉੜੀ")
        XCTAssertEqual(IndexFind.run("gaurhee", meta: meta, compositions: offered).raags.first?.name, "ਗਉੜੀ")
        XCTAssertEqual(IndexFind.run("ਗਉੜੀ", meta: meta, compositions: offered).raags.first?.name, "ਗਉੜੀ")
        XCTAssertEqual(IndexFind.run("sukhmani", meta: meta, compositions: offered).compositions.first?.key, "sukhmani")
        XCTAssertEqual(IndexFind.run("raagmala", meta: meta, compositions: offered).sections.first?.name, "ਰਾਗ ਮਾਲਾ")
        XCTAssertFalse(IndexFind.run("kabir", meta: meta, compositions: offered).voices.isEmpty)
        XCTAssertTrue(IndexFind.run("   ", meta: meta, compositions: offered).isEmpty)
        XCTAssertTrue(IndexFind.run("zzzzqq", meta: meta, compositions: offered).isEmpty)
    }
}
