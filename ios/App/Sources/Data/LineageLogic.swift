import Foundation
import GurbaniSearchKit

/// The Voice of the day: deterministic by day number (`HukamOfTheDay.dayNumber`), the same all
/// day on every device. Voices rotate one per day; each full rotation moves every voice on to its
/// next rahao verse.
enum VoiceOfTheDayPick {
    /// Index into the candidate voices (sorted by stored name) for `day`.
    static func voiceIndex(day: Int, count: Int) -> Int? {
        count > 0 ? ((day % count) + count) % count : nil
    }

    /// Index into that voice's rahao verses for `day`.
    static func verseIndex(day: Int, voiceCount: Int, verseCount: Int) -> Int? {
        guard voiceCount > 0, verseCount > 0 else { return nil }
        let round = day >= 0 ? day / voiceCount : (day - voiceCount + 1) / voiceCount
        return ((round % verseCount) + verseCount) % verseCount
    }

    /// The verse to show: a rahao verse when the voice has any, else `fallback` (the opening
    /// verse of their first composition).
    static func verse(day: Int, voiceCount: Int, rahao: [VoiceVerse], fallback: VoiceVerse?) -> VoiceVerse? {
        verseIndex(day: day, voiceCount: voiceCount, verseCount: rahao.count).map { rahao[$0] } ?? fallback
    }
}

/// "Did you know" — only facts computed from the DB, each cited by Ang.
enum LineageFacts {
    struct Fact: Equatable, Identifiable {
        let id: String
        /// Verbatim Gurmukhi shown before the sentence (a raag name), or nil.
        let gurmukhi: String?
        let text: String
        /// The voice a tap opens, or nil.
        let author: String?
    }

    static func build(signatureRaags: [SignatureRaag], dialogue: DialogueSpan?, bhatts: [VoiceSummary],
                      name: (String) -> String, locale: Locale = .current) -> [Fact] {
        var out: [Fact] = []
        for r in signatureRaags.prefix(2) {
            out.append(Fact(id: "raag-\(r.raag)", gurmukhi: r.raag,
                            text: "appears in the Granth only in \(name(r.author))'s Bani, from Ang \(r.firstAng).",
                            author: r.author))
        }
        if let d = dialogue, !d.gurus.isEmpty, !d.bhagats.isEmpty {
            out.append(Fact(id: "dialogues", gurmukhi: nil,
                            text: "Saloks of \(join(d.gurus.map(name), locale)) are set beside saloks of \(join(d.bhagats.map(name), locale)), Angs \(d.firstAng)–\(d.lastAng).",
                            author: nil))
        }
        if bhatts.count > 1, let first = bhatts.map(\.firstAng).min(), let last = bhatts.map(\.lastAng).max() {
            out.append(Fact(id: "bhatts", gurmukhi: nil,
                            text: "\(bhatts.count) Bhatts each have Swaiyye in the Granth, Angs \(first)–\(last).",
                            author: nil))
        }
        return out
    }

    /// "A and B", "A, B and C" in the reader's language.
    static func join(_ names: [String], _ locale: Locale) -> String {
        let f = ListFormatter()
        f.locale = locale
        return f.string(from: names) ?? names.joined(separator: ", ")
    }
}

/// Who was alive in a year, by the roster's approximate dates (River's scrubber readout).
enum LifespanLogic {
    /// A voice's span; a single known date is widened by 40 years (drawn faded as uncertain).
    static func bounds(_ c: Contributor) -> ClosedRange<Int>? {
        switch (c.born, c.died) {
        case let (b?, d?): return b...max(b, d)
        case let (b?, nil): return b...(b + 40)
        case let (nil, d?): return (d - 40)...d
        default: return nil
        }
    }

    static func alive(_ voices: [Contributor], year: Int) -> [Contributor] {
        voices.filter { bounds($0)?.contains(year) ?? false }
    }

    static func readout(year: Int?, voices: [Contributor]) -> String {
        guard let y = year else { return "Drag along the years to see who was alive." }
        let alive = alive(voices, year: y)
        return alive.isEmpty ? "c. \(y): none of these voices by the dates given"
            : "c. \(y): " + alive.map(\.displayName).joined(separator: ", ")
    }
}
