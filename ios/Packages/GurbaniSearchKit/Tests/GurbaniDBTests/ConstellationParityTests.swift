import XCTest
@testable import GurbaniDB
@testable import GurbaniSearchKit

/// Parity gate for Constellation v2 (the Focus model under each lens, the Sky, pair pages, solo
/// pages and theme cards) vs Python serve.py, against the shipped iOS DB. Pinned by
/// contract/golden_constellation.ndjson. Also asserts the invariants the UI's copy relies on:
/// total = solo + shared, the Ang strip sums to the total, every pair verse carries both words.
final class ConstellationParityTests: XCTestCase {

    private func repoRoot() -> URL {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<12 {
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent("contract/_meta.json").path) { return dir }
            dir = dir.deletingLastPathComponent()
        }
        return URL(fileURLWithPath: #filePath)
    }

    private func r6(_ x: Double) -> Double { (x * 1e6).rounded() / 1e6 }
    private func close(_ a: Double, _ b: Any?) -> Bool { abs(a - ((b as? NSNumber)?.doubleValue ?? .nan)) <= 1e-6 }

    private func lens(_ raw: [String: Any]?) -> ConstellationLens {
        var l = ConstellationLens()
        guard let raw else { return l }
        if let a = raw["author"] as? String { l.author = a }
        if let r = raw["raag"] as? String { l.raag = r }
        if let rs = raw["raags"] as? String { l.raags = rs.split(separator: ",").map(String.init) }
        if let r = raw["rahao"] as? String { l.rahaoOnly = (r == "1" || r == "true") }
        if let m = raw["min_themes"] as? String, let n = Int(m) { l.minThemes = n }
        if let a = raw["ang_min"] as? String, let n = Int(a) { l.angMin = n }
        if let a = raw["ang_max"] as? String, let n = Int(a) { l.angMax = n }
        return l
    }

    func testConstellationParity() throws {
        let root = repoRoot()
        let dbPath = root.appendingPathComponent("ios/Resources/sggs-ios.sqlite").path
        guard FileManager.default.fileExists(atPath: dbPath) else {
            throw XCTSkip("ios/Resources/sggs-ios.sqlite missing — run pipeline/build_ios_db.py")
        }
        let rows = try String(contentsOf: root.appendingPathComponent("contract/golden_constellation.ndjson"), encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: true)
        let db = try SQLiteCandidateSource(path: dbPath)
        var failures: [String] = []
        var asserted: [String: Int] = [:]

        for row in rows {
            guard let v = try JSONSerialization.jsonObject(with: Data(row.utf8)) as? [String: Any],
                  let kind = v["kind"] as? String else { continue }
            asserted[kind, default: 0] += 1
            switch kind {
            case "constellation_v2":
                let concept = v["concept"] as? String ?? ""
                let l = lens(v["lens"] as? [String: Any])
                let tag = "focus \(concept) \(String(describing: v["lens"]))"
                let f = try db.constellationFocus(concept: concept, lens: l)
                if f.total != v["total"] as? Int { failures.append("\(tag): total \(f.total)") }
                if f.solo != v["solo"] as? Int { failures.append("\(tag): solo \(f.solo)") }
                if f.shared != v["shared"] as? Int { failures.append("\(tag): shared \(f.shared)") }
                if f.total != f.solo + f.shared { failures.append("\(tag): total != solo + shared") }
                if f.angBins != (v["ang_bins"] as? [Int] ?? []) { failures.append("\(tag): ang bins \(f.angBins)") }
                if f.angBins.reduce(0, +) != f.total { failures.append("\(tag): ang bins do not sum to the total") }
                let want = v["companions"] as? [[Any]] ?? []
                if f.companions.count != want.count {
                    failures.append("\(tag): \(f.companions.count) companions, want \(want.count)")
                } else {
                    for (c, w) in zip(f.companions, want) where !(c.co == w[0] as? String && c.n == w[1] as? Int
                        && close(r6(c.ppmi), w[2]) && close(r6(c.jaccard), w[3]) && c.shabadCount == w[4] as? Int) {
                        failures.append("\(tag): companion \(c.co) \(c.n) \(c.ppmi) != \(w)"); break
                    }
                }
            case "sky":
                let s = try db.constellationSky()
                let nodes = v["nodes"] as? [[Any]] ?? []
                if s.nodes.map(\.concept) != nodes.map({ $0[0] as? String ?? "" }) { failures.append("sky: node keys differ") }
                if s.nodes.map(\.n) != nodes.map({ $0[1] as? Int ?? -1 }) { failures.append("sky: node counts differ") }
                let edges = v["edges"] as? [[Any]] ?? []
                if s.edges.map({ "\($0.source)~\($0.target)" }) != edges.map({ "\($0[0])~\($0[1])" }) {
                    failures.append("sky: edges differ (\(s.edges.count) vs \(edges.count))")
                } else if zip(s.edges, edges).contains(where: { !close(r6($0.ppmi), $1[2]) || !close(r6($0.jaccard), $1[3]) }) {
                    failures.append("sky: edge weights differ")
                }
            case "pair", "pair_alone":
                let concept = v["concept"] as? String ?? ""
                let other = kind == "pair" ? v["with"] as? String : nil
                let off = v["offset"] as? Int ?? 0
                let tag = "\(kind) \(concept)~\(other ?? "alone") @\(off)"
                let p = try db.constellationPair(concept: concept, with: other, lens: lens(v["lens"] as? [String: Any]), offset: off)
                if p.total != v["total"] as? Int { failures.append("\(tag): total \(p.total)") }
                let want = v["shabads"] as? [[Any]] ?? []
                // one string per shabad: "comp_id|id:term,term;id:term,…" on both sides
                let flatGot = p.shabads.map { sh in
                    "\(sh.compId)|" + sh.verses.map { "\($0.id):" + $0.terms.joined(separator: ",") }.joined(separator: ";")
                }
                let flatWant = want.map { sh -> String in
                    let verses = sh.count > 1 ? (sh[1] as? [[Any]] ?? []) : []
                    return "\(sh.first as? Int ?? -1)|" + verses.map { vv in
                        "\(vv.first as? Int ?? -1):" + vv.dropFirst().map { $0 as? String ?? "" }.joined(separator: ",")
                    }.joined(separator: ";")
                }
                if flatGot != flatWant { failures.append("\(tag): shabads differ (\(flatGot.count) vs \(flatWant.count))") }
                for sh in p.shabads { for verse in sh.verses where verse.terms.contains(where: { !verse.gurmukhi.contains($0) }) {
                    failures.append("\(tag): verse \(verse.id) does not carry its matched word")
                } }
            case "theme_card":
                let concept = v["concept"] as? String ?? ""
                guard let c = try db.themeCard(concept: concept) else { failures.append("card \(concept): missing"); continue }
                if c.nVerses != v["n_verses"] as? Int || c.nShabads != v["n_shabads"] as? Int || c.nRahao != v["n_rahao"] as? Int {
                    failures.append("card \(concept): counts \(c.nVerses)/\(c.nShabads)/\(c.nRahao)")
                }
                if c.terms != (v["terms"] as? [String] ?? []) { failures.append("card \(concept): terms differ") }
                for (name, got, want) in [("raags", c.raags, v["raags"]), ("authors", c.authors, v["authors"])] {
                    let w = want as? [[Any]] ?? []
                    if got.map(\.entityId) != w.map({ $0[0] as? String ?? "" })
                        || zip(got, w).contains(where: { !close(r6($0.lift), $1[1]) }) {
                        failures.append("card \(concept): \(name) differ")
                    }
                }
            default:
                asserted[kind, default: 0] -= 1
            }
        }
        for k in ["constellation_v2", "sky", "pair", "pair_alone", "theme_card"] {
            XCTAssertGreaterThan(asserted[k] ?? 0, 0, "no \(k) vectors were checked")
        }
        if !failures.isEmpty { XCTFail("constellation parity failures: \(failures.count)\n" + failures.prefix(20).joined(separator: "\n")) }
        XCTAssertNil(try db.themeCard(concept: "no_such_theme"))
    }
}
