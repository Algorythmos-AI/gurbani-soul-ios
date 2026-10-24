import Foundation
import GurbaniSearchKit

/// Which composition the Index's "Continue reading" card offers. A card that promises a place must
/// land on it: a composition counts only when its saved position RESUMES (`resumeSeq` is non-nil
/// against the bani's current lines). A position at the top, or one whose anchor a corpus update
/// removed, would open at the top while the card said "Ashtapadi 5 of 24", so it is left out.
/// Pure, so the rule is unit-tested without a view.
enum ContinueReading {

    /// The most recently read composition that is part-way, not finished today, and resumable.
    static func target(offered: [BaniSummary],
                       isCompleted: (String) -> Bool,
                       fraction: (BaniSummary) -> Double,
                       resumes: (String) -> Bool,
                       lastReadAt: (String) -> Date?) -> BaniSummary? {
        offered
            .filter { !isCompleted($0.id) && fraction($0) > 0 && resumes($0.id) }
            .max { (lastReadAt($0.id) ?? .distantPast) < (lastReadAt($1.id) ?? .distantPast) }
    }

    /// Whether a saved position resumes, decided WITHOUT the bani's lines when that is certain —
    /// mirroring `NitnemProgressStore.resumeSeq`: nil progress or `lastSeq <= 1` never resumes; a
    /// position saved against the same line count (`nLines == summary.nLines`) resumes by `seq`;
    /// a 1.2.x save with no `nLines` resumes when `lastSeq` is in range. Only a CHANGED line count
    /// (a corpus update) needs the anchor check against the loaded lines, so this returns nil then.
    static func resumesWithoutLines(_ p: BaniProgress?, nLines total: Int) -> Bool? {
        guard let p, p.lastSeq > 1 else { return false }
        if let n = p.nLines {
            if n == total { return p.lastSeq <= total }
            return nil                                 // line count changed: anchor decides
        }
        return p.lastSeq <= total
    }

    /// The compositions worth checking for resumability: part-way and not finished today.
    static func inProgress(offered: [BaniSummary], isCompleted: (String) -> Bool,
                           fraction: (BaniSummary) -> Double) -> [BaniSummary] {
        offered.filter { !isCompleted($0.id) && fraction($0) > 0 }
    }
}
