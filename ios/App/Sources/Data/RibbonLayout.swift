import Foundation
import GurbaniSearchKit

/// The geometry of the Granth Ribbon: every bani and raag of the saroop laid end to end in Ang
/// units, proportional to how many Angs it fills. Pure — no SwiftUI — so contiguity and hit-testing
/// are unit-tested.
///
/// Neighbouring works can share an Ang (Japji ends on Ang 8 where So Dar begins; Mundavani shares
/// Ang 1429 with Salok Mahalla 9 and Raagmala). A shared Ang is split equally among the works on
/// it, so the strip covers exactly the Angs the data covers, with no gap, no overlap and no work
/// drawn at zero width.
struct RibbonLayout: Equatable, Sendable {

    enum Movement: String, Sendable { case opening, raags, closing }

    struct Segment: Equatable, Sendable, Identifiable {
        let movement: Movement
        /// Verbatim Gurmukhi name (raag or section, as the corpus stores it).
        let name: String
        let english: String?
        let firstAng: Int
        let lastAng: Int
        /// The raag's saroop order (1…31); nil for a section.
        let seq: Int?
        let nShabads: Int?
        /// [x0, x1) in Ang units along the strip.
        let x0: Double
        let x1: Double
        var id: String { "\(movement.rawValue):\(name)" }
        var width: Double { x1 - x0 }

        /// The Ang under a strip position inside this segment (clamped to its span).
        func ang(at x: Double) -> Int {
            let n = lastAng - firstAng + 1
            guard width > 0, n > 1 else { return firstAng }
            let f = min(max((x - x0) / width, 0), 0.999_999)
            return firstAng + Int(f * Double(n))
        }

        /// Where an Ang sits on the strip, inside this segment.
        func x(forAng a: Int) -> Double {
            let n = lastAng - firstAng + 1
            let c = min(max(a, firstAng), lastAng)
            return x0 + width * (Double(c - firstAng) + 0.5) / Double(max(n, 1))
        }
    }

    let segments: [Segment]
    /// Total strip length in Ang units (== the number of distinct Angs covered).
    let length: Double

    init(map: GranthMap) {
        struct Item { let movement: Movement; let name: String; let english: String?
                      let first: Int; let last: Int; let seq: Int?; let shabads: Int? }
        var items: [Item] = []
        items += map.opening.map { Item(movement: .opening, name: $0.name,
                                        english: GranthNames.section($0.name, firstAng: $0.firstAng, lastAng: $0.lastAng),
                                        first: $0.firstAng, last: $0.lastAng, seq: nil, shabads: nil) }
        items += map.raags.map { Item(movement: .raags, name: $0.name, english: GranthNames.raag($0.name, roman: $0.roman),
                                      first: $0.firstAng, last: $0.lastAng, seq: $0.seq, shabads: $0.nShabads) }
        items += map.closing.map { Item(movement: .closing, name: $0.name,
                                        english: GranthNames.section($0.name, firstAng: $0.firstAng, lastAng: $0.lastAng),
                                        first: $0.firstAng, last: $0.lastAng, seq: nil, shabads: nil) }
        items = items.filter { $0.first >= 1 && $0.last >= $0.first }

        // How many works sit on each Ang.
        var share: [Int: Int] = [:]
        for it in items { for a in it.first...it.last { share[a, default: 0] += 1 } }

        var x = 0.0
        var out: [Segment] = []
        for it in items {
            let w = (it.first...it.last).reduce(0.0) { $0 + 1.0 / Double(share[$1] ?? 1) }
            out.append(Segment(movement: it.movement, name: it.name, english: it.english,
                               firstAng: it.first, lastAng: it.last, seq: it.seq, nShabads: it.shabads,
                               x0: x, x1: x + w))
            x += w
        }
        segments = out
        length = x
    }

    /// The segment under strip position `x` (clamped to the strip). nil only when empty.
    func segment(at x: Double) -> Segment? {
        guard let first = segments.first, let last = segments.last else { return nil }
        if x <= first.x0 { return first }
        if x >= last.x1 { return last }
        // binary search: segments are sorted and contiguous
        var lo = 0, hi = segments.count - 1
        while lo < hi {
            let mid = (lo + hi) / 2
            if segments[mid].x1 <= x { lo = mid + 1 } else { hi = mid }
        }
        return segments[lo]
    }

    /// The strip position of an Ang: inside the first segment that holds it.
    func x(forAng a: Int) -> Double? {
        segments.first { ($0.firstAng...$0.lastAng).contains(a) }?.x(forAng: a)
    }

    /// [x0, x1) of a whole movement, for its caption under the strip.
    func extent(of m: Movement) -> (x0: Double, x1: Double)? {
        let s = segments.filter { $0.movement == m }
        guard let a = s.first, let b = s.last else { return nil }
        return (a.x0, b.x1)
    }

    /// The words VoiceOver reads for a segment.
    static func spokenLabel(_ s: Segment, raagCount: Int) -> String {
        let span = (s.firstAng...s.lastAng).angLabel
        switch s.movement {
        case .raags:
            var parts = ["Raag \(s.english ?? s.name)"]
            if let seq = s.seq { parts.append("raag \(String(seq)) of \(String(raagCount))") }
            parts.append(span)
            if let n = s.nShabads { parts.append("\(String(n)) shabads") }
            return parts.joined(separator: ", ")
        case .opening: return "\(s.english ?? s.name), before the raags, \(span)"
        case .closing: return "\(s.english ?? s.name), after the raags, \(span)"
        }
    }
}
