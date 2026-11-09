import Foundation
import CryptoKit
import GurbaniSearchKit

/// Where the Hukamnama sheet reads its lines: the app's own corpus (CorpusActor), or a fake in
/// tests. Nothing else.
protocol HukamnamaLineSource: Sendable {
    func lines(from first: Int, to last: Int) async throws -> [ReaderLine]
    func angLines(_ n: Int) async throws -> [ReaderLine]
}

extension CorpusActor: HukamnamaLineSource {
    func angLines(_ n: Int) async throws -> [ReaderLine] { try ang(n).lines }
}

/// What the sheet may show for an entry.
enum HukamnamaResolution: Equatable, Sendable {
    /// The entry's own ids, and their lines hash to `range_sha256`.
    case verified([ReaderLine])
    /// The ids did not prove out; the same text was found again by Ang + opening verse, and THAT
    /// range hashes to `range_sha256`.
    case relocated([ReaderLine])
    /// Nothing in this app's corpus proves the range: show the Ang only, never a line.
    case needsUpdate(ang: Int?)
}

/// Proves a Hukamnama range against the app's own corpus before a single line is shown.
/// Invariant: a line is rendered only when the range it belongs to hashes to the server's
/// `range_sha256` — there is no path that returns lines that failed the hash.
enum HukamnamaLocator {
    /// sha256 (lowercase hex) of the lines' NFC Gurmukhi joined by "\n" (no trailing newline).
    /// The same definition as the service and the shared golden vector.
    static func rangeSHA256(_ gurmukhi: [String]) -> String {
        let joined = gurmukhi.map(\.precomposedStringWithCanonicalMapping).joined(separator: "\n")
        return SHA256.hash(data: Data(joined.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// The most lines before the opening verse a relocated range may start (its heading run).
    static let maxLeadingHeaders = 8

    static func resolve(_ entry: HukamnamaEntry, source: HukamnamaLineSource) async -> HukamnamaResolution {
        guard entry.isLocatable, let first = entry.firstLineId, let last = entry.lastLineId,
              let expected = entry.rangeSHA256 else { return .needsUpdate(ang: entry.ang) }
        let count = last - first + 1
        if let lines = try? await source.lines(from: first, to: last), proves(lines, count: count, expected: expected) {
            return .verified(lines)
        }
        // Re-locate: the opening verse on its Ang (or the Ang either side — shabads cross Angs),
        // then every start that puts that verse within the first few lines of a same-length range.
        guard let ang = entry.ang, let opening = entry.openingGurmukhi?.precomposedStringWithCanonicalMapping,
              !opening.isEmpty else { return .needsUpdate(ang: entry.ang) }
        var tried = Set<Int>()
        for a in [ang, ang - 1, ang + 1] where GranthAngs.all.contains(a) {
            guard let page = try? await source.angLines(a) else { continue }
            for anchor in page where !anchor.isHeader && anchor.gurmukhi.precomposedStringWithCanonicalMapping == opening {
                for lead in 0..<min(count, maxLeadingHeaders) {
                    let start = anchor.id - lead
                    guard start > 0, tried.insert(start).inserted else { continue }
                    if let lines = try? await source.lines(from: start, to: start + count - 1),
                       proves(lines, count: count, expected: expected) {
                        return .relocated(lines)
                    }
                }
            }
        }
        return .needsUpdate(ang: entry.ang)
    }

    private static func proves(_ lines: [ReaderLine], count: Int, expected: String) -> Bool {
        lines.count == count && zip(lines, lines.dropFirst()).allSatisfy({ $1.id == $0.id + 1 })
            && rangeSHA256(lines.map(\.gurmukhi)) == expected
    }
}
