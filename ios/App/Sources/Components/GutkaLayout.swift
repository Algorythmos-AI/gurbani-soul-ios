import Foundation

/// The bani reader's "Gutka layout" switch. On by default only for the banis whose lines are
/// short enough to be printed two to a row in a gutka; the reader can turn it on or off for any
/// bani. One storage key holds every choice that differs from that default ("jaap=0,anand=1"),
/// so the UI-test wipe (`UITestVault.resetKeys`) resets them all at once.
enum GutkaPrefs {
    static let storageKey = "sggs_gutka_layout"
    static let shortLineBanis: Set<String> = ["jaap", "chaupai", "savaiye", "savaiye_deenan",
                                              "shabad_hazare_p10", "aarti"]

    static func defaultOn(_ baniKey: String) -> Bool { shortLineBanis.contains(baniKey) }

    static func isOn(_ baniKey: String, stored: String) -> Bool {
        overrides(stored)[baniKey] ?? defaultOn(baniKey)
    }

    /// The stored string after the reader sets `on` for `baniKey`. A choice equal to the default
    /// is dropped, so the string only ever lists real overrides.
    static func setting(_ baniKey: String, on: Bool, in stored: String) -> String {
        var map = overrides(stored)
        map[baniKey] = on == defaultOn(baniKey) ? nil : on
        return map.keys.sorted().map { "\($0)=\(map[$0]! ? 1 : 0)" }.joined(separator: ",")
    }

    private static func overrides(_ stored: String) -> [String: Bool] {
        var out: [String: Bool] = [:]
        for part in stored.split(separator: ",") {
            let kv = part.split(separator: "=", maxSplits: 1)
            guard kv.count == 2, !kv[0].isEmpty, kv[1] == "0" || kv[1] == "1" else { continue }
            out[String(kv[0])] = kv[1] == "1"
        }
        return out
    }
}

/// Packs a bani's lines into reading rows the way a printed gutka sets them: two consecutive
/// half-lines side by side ("ਨਮਸਤ੍ਵੰ ਅਕਾਲੇ ॥ ਨਮਸਤ੍ਵੰ ਕ੍ਰਿਪਾਲੇ ॥"), the verse number closing the
/// second. DISPLAY ONLY: a row is a list of the original lines, in order, each still drawn,
/// copied, shared and spoken on its own — nothing is joined into a new scripture string. Whether
/// a pair actually sits on one line is decided at render time (both halves must fit the column
/// at the current size); otherwise the pair falls back to one line per row.
enum GutkaRows {
    struct Line: Equatable {
        let seq: Int
        let gurmukhi: String
        let lineGroup: Int
        /// Drawn as a heading (never paired, and it opens what follows).
        let heading: Bool
        /// False for a line that must keep a row of its own: ਰਹਾਉ, or a line showing English.
        let pairable: Bool
        /// An outline section (pauri / ashtapadi / salok) starts at this line.
        let opensSection: Bool
    }

    struct Row: Equatable {
        /// The original lines' seqs, in reading order — one or two.
        let seqs: [Int]
        /// The row begins a verse (or follows a heading / boundary): it gets the larger gap.
        let opensVerse: Bool
        /// The row is a heading line (always a row of its own).
        var heading: Bool = false
        var id: Int { seqs[0] }
        var isPair: Bool { seqs.count == 2 }
    }

    /// Display separator between two halves' transliterations (a reading aid, not scripture).
    static let translitSeparator = "   "

    static func pack(_ lines: [Line], enabled: Bool) -> [Row] {
        var rows: [Row] = []
        var i = 0
        var opensNext = true
        while i < lines.count {
            let a = lines[i]
            let opens = opensNext || a.heading || a.opensSection
                || (i > 0 && lines[i - 1].lineGroup != a.lineGroup)
            if enabled, i + 1 < lines.count, canPair(a, lines[i + 1]) {
                let b = lines[i + 1]
                rows.append(Row(seqs: [a.seq, b.seq], opensVerse: opens))
                opensNext = VerseTypography.closesVerse(b.gurmukhi)
                i += 2
            } else {
                rows.append(Row(seqs: [a.seq], opensVerse: opens, heading: a.heading))
                opensNext = a.heading || VerseTypography.closesVerse(a.gurmukhi)
                i += 1
            }
        }
        return rows
    }

    /// Never across a verse number (॥N॥), a heading, a stanza boundary or a line-group change.
    static func canPair(_ a: Line, _ b: Line) -> Bool {
        a.pairable && b.pairable && !a.heading && !b.heading
            && !VerseTypography.closesVerse(a.gurmukhi)
            && a.lineGroup == b.lineGroup && !b.opensSection
    }

    /// The row holding `seq` (its first line's seq), so a resume or jump to the second half of a
    /// pair lands on the row that draws it.
    static func rowStart(of seq: Int, in rows: [Row]) -> Int {
        rows.first { $0.seqs.contains(seq) }?.id ?? seq
    }

    static func joinedTranslit(_ parts: [String]) -> String {
        parts.filter { !$0.isEmpty }.joined(separator: translitSeparator)
    }
}
