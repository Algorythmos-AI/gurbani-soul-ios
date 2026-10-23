import XCTest
@testable import SGGS

/// Constellation v2 invariants that live in the app target: the Sky's layout is deterministic
/// (seeded SplitMix64, fixed iterations — byte-identical across runs, so the same themes sit in
/// the same places for every reader and every screenshot), and every one of the 54 themes has a
/// group and a colour.
final class ConstellationLayoutTests: XCTestCase {

    private func sampleGraph() -> (Int, [(Int, Int, Double)]) {
        // a small ring with chords: enough structure for the springs and the repulsion to matter
        let n = 12
        var edges: [(Int, Int, Double)] = []
        for i in 0..<n { edges.append((i, (i + 1) % n, 1.0 + Double(i % 3))) }
        edges += [(0, 6, 2.5), (2, 9, 0.4), (4, 10, 3.0)]
        return (n, edges)
    }

    func testSkyLayoutIsByteIdenticalAcrossRuns() {
        let (n, edges) = sampleGraph()
        let a = ForceLayout.layout(nodeCount: n, edges: edges, iterations: 300, seed: 54)
        let b = ForceLayout.layout(nodeCount: n, edges: edges, iterations: 300, seed: 54)
        XCTAssertEqual(a.count, n)
        XCTAssertEqual(a.map { [Double($0.x).bitPattern, Double($0.y).bitPattern] }, b.map { [Double($0.x).bitPattern, Double($0.y).bitPattern] },
                       "the seeded layout must not move between runs")
        XCTAssertTrue(a.allSatisfy { (0...1).contains($0.x) && (0...1).contains($0.y) }, "positions stay in the unit square")
        let c = ForceLayout.layout(nodeCount: n, edges: edges, iterations: 300, seed: 55)
        XCTAssertNotEqual(a.map(\.x), c.map(\.x), "the seed is what fixes the layout")
    }

    func testEveryCorpusThemeHasExactlyOneGroup() {
        let keys = ThemeGroup.all.flatMap(\.keys)
        XCTAssertEqual(keys.count, 54, "the six groups name all 54 corpus themes")
        XCTAssertEqual(Set(keys).count, keys.count, "no theme sits in two groups")
        XCTAssertEqual(ThemeGroup.of("kaal")?.key, "condition", "kaal (time/death) sits with the Human Condition")
        XCTAssertEqual(ThemeGroup.of("akal")?.key, "divine")
        XCTAssertNil(ThemeGroup.of("not_a_theme"))
    }
}
