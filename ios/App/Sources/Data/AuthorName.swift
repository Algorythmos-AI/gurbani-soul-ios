import Foundation

/// A contributor's stored name (`authors.name` / `author_analytics.author`, e.g.
/// "Guru Arjan Dev Ji (M5)", "Bhatt Kalsahar (ਭਟ)") split for display: the English name,
/// the Mahala number for the Gurus, and any Gurmukhi suffix. The stored string is never
/// altered — it stays the key for every query; this only decides how a label is drawn.
/// Gurmukhi is never inlined into an English label: callers render `gurmukhi` through
/// `GurmukhiText` (Sant Lipi).
struct AuthorName: Equatable, Sendable {
    let raw: String
    /// "Guru Arjan Dev Ji", "Bhatt Kalsahar", "Bhagat Kabir Ji".
    let english: String
    /// 5 for "(M5)"; nil for every non-Guru voice.
    let mahala: Int?
    /// "ਭਟ" for "(ਭਟ)"; nil when the name carries no Gurmukhi suffix.
    let gurmukhi: String?

    init(_ raw: String) {
        self.raw = raw
        var rest = raw.trimmingCharacters(in: .whitespaces)
        var mahala: Int?
        var gurmukhi: String?
        // Peel trailing "(…)" groups: "(M5)" → Mahala, a Gurmukhi group → suffix.
        while rest.hasSuffix(")"), let open = rest.lastIndex(of: "(") {
            let inner = String(rest[rest.index(after: open)..<rest.index(before: rest.endIndex)])
                .trimmingCharacters(in: .whitespaces)
            if inner.first == "M", let n = Int(inner.dropFirst()) {
                mahala = n
            } else if !inner.isEmpty, inner.unicodeScalars.contains(where: Self.isGurmukhi) {
                gurmukhi = inner
            } else {
                break
            }
            rest = String(rest[..<open]).trimmingCharacters(in: .whitespaces)
        }
        english = rest.isEmpty ? raw : rest
        self.mahala = mahala
        self.gurmukhi = gurmukhi
    }

    /// The small badge beside a Guru's name: "M5".
    var badge: String? { mahala.map { "M\($0)" } }

    /// What VoiceOver reads: "Guru Arjan Dev Ji, Mahala 5". The Gurmukhi suffix is left to
    /// `GurmukhiText`, which reads it tagged as Punjabi.
    var spoken: String { mahala.map { "\(english), Mahala \($0)" } ?? english }

    /// A label for dense canvases (network nodes, chart axes) where a full name cannot fit:
    /// "M5" for a Guru, otherwise the English name without "Bhagat " and " Ji". Never Gurmukhi.
    var compact: String {
        if let badge { return badge }
        var s = english
        if s.hasPrefix("Bhagat ") { s.removeFirst("Bhagat ".count) }
        if s.hasSuffix(" Ji") { s.removeLast(" Ji".count) }
        return s
    }

    private static func isGurmukhi(_ u: Unicode.Scalar) -> Bool { (0x0A00...0x0A7F).contains(u.value) }
}

/// Count labels for the Contributors views: "1 shabad", "2 shabads", "0 shabads" — never a
/// hand-rolled "s". Plural forms come from Localizable.xcstrings: Foundation's automatic
/// grammar agreement (`^[…](inflect: true)`) only knows its own English lexicon and leaves
/// "shabad" and "raag" unchanged ("2 shabad"), so these nouns carry explicit plural variants.
enum VoiceCopy {
    static func lines(_ n: Int, locale: Locale = .current) -> AttributedString {
        AttributedString(localized: "\(n) lines", locale: locale)
    }
    static func shabads(_ n: Int, locale: Locale = .current) -> AttributedString {
        AttributedString(localized: "\(n) shabads", locale: locale)
    }
    static func raags(_ n: Int, locale: Locale = .current) -> AttributedString {
        AttributedString(localized: "\(n) raags", locale: locale)
    }

    /// The Bhatts' Swaiyye sit after the raag sections, outside the raag framework — so a
    /// voice with no raag says that instead of "0 raags".
    static let outsideRaags = "Swaiyye · outside the raag framework"

    /// "Vocabulary range" (MATTR-100) is shown only where the sample is large enough.
    static let vocabularyRange = "Vocabulary range"
    static let tooFewLines = "Too few lines to measure fairly"
    static let vocabularyExplainer = "How varied a voice's wording is: the share of different words in each run of 100 words, averaged across all of its Bani (a moving-average type–token ratio, measured on the English translation). Higher means more varied wording. It describes style — never merit."

    /// "1,204 lines · 61 shabads · 15 raags", or "… · Swaiyye · outside the raag framework".
    static func summary(lines n: Int, shabads s: Int, raags r: Int, locale: Locale = .current) -> AttributedString {
        var out = lines(n, locale: locale)
        out += AttributedString(" · ")
        out += shabads(s, locale: locale)
        out += AttributedString(" · ")
        out += r == 0 ? AttributedString(outsideRaags) : raags(r, locale: locale)
        return out
    }
}
