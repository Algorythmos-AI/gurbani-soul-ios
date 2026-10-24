import Foundation
import GurbaniSearchKit

/// A composition's printed rhythm, reduced to what an Index card draws: its reading steps (the
/// same pauris / ashtapadis the reader's bottom bar steps by — `BaniPager.steps`) with their
/// lengths, so the card can show the work's real shape and how far the reader has come. Computed
/// once from the verbatim markers; when the markers give no trustworthy outline, `steps` is empty
/// and the card falls back to a plain progress bar.
struct CompositionShape: Equatable, Sendable {
    struct Step: Equatable, Sendable {
        let startSeq: Int
        let endSeq: Int
        var length: Int { max(1, endSeq - startSeq + 1) }
    }

    let steps: [Step]
    /// "ashtapadis", "pauris" — the plural of the steps' kind; nil when there are no steps.
    let unit: String?
    /// The bani's first and last line `seq`, for the no-steps progress bar.
    let firstSeq: Int
    let lastSeq: Int

    init(steps: [Step], unit: String?, firstSeq: Int, lastSeq: Int) {
        self.steps = steps; self.unit = unit; self.firstSeq = firstSeq; self.lastSeq = lastSeq
    }

    init(bani: Bani) {
        let outline = BaniPager.steps(in: BaniOutline.sections(for: bani))
        steps = outline.map { Step(startSeq: $0.startSeq, endSeq: $0.endSeq) }
        unit = outline.first.map { Self.plural($0.kind) }
        firstSeq = bani.lines.first?.seq ?? 0
        lastSeq = bani.lines.last?.seq ?? 0
    }

    static func plural(_ k: BaniSectionKind) -> String {
        switch k {
        case .salok: return "saloks"
        case .pauri: return "pauris"
        case .ashtapadi: return "ashtapadis"
        case .chhant: return "chhants"
        case .verse: return "verses"
        case .part: return "parts"
        }
    }

    /// How much of each step has been read, 0…1, for a saved position `seq` (nil = not started).
    /// A completed composition reads as all 1s.
    func fill(at seq: Int?, completed: Bool) -> [Double] {
        if completed { return steps.map { _ in 1 } }
        guard let seq else { return steps.map { _ in 0 } }
        return steps.map { s in
            if seq > s.endSeq { return 1 }
            if seq < s.startSeq { return 0 }
            return Double(seq - s.startSeq + 1) / Double(s.length)
        }
    }

    /// The 1-based step a saved position sits in, or nil before the first step.
    func stepNumber(at seq: Int) -> Int? {
        guard let i = steps.lastIndex(where: { $0.startSeq <= seq }) else { return nil }
        return i + 1
    }
}
