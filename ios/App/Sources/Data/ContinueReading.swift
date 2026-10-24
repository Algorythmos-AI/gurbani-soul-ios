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

    /// The compositions worth checking for resumability: part-way and not finished today.
    static func inProgress(offered: [BaniSummary], isCompleted: (String) -> Bool,
                           fraction: (BaniSummary) -> Double) -> [BaniSummary] {
        offered.filter { !isCompleted($0.id) && fraction($0) > 0 }
    }
}
