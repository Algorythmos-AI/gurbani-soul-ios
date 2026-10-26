import Foundation
import GurbaniSearchKit

/// The voices of the Granth — static biographical metadata bundled from the web app's
/// frontend/public/contributors.json (single source of truth; referenced, not copied).
/// Dates are historical approximations; volume comes from the DB, never from here.
///
/// Roster v2 adds optional fields (honorific `display`, `gurmukhi` name, `chhap`, `context`,
/// `sources`, `review`, `notable`…). They decode leniently: a missing field or one of an
/// unexpected shape is nil, so a newer roster never stops this app from loading the list.
struct Contributor: Decodable, Identifiable, Sendable, Hashable {
    let name: String        // matches authors/author_analytics.author exactly (verified: 30/30)
    let roman: String
    let kind: String        // guru | bhagat | bhatt | gursikh
    let seq: Int?
    let born: Int?
    let died: Int?
    let circa: Bool
    let era: String
    let region: String
    let tradition: String
    let blurb: String
    // Roster v2 (all optional).
    let display: String?
    let gurmukhi: String?
    let chhap: [String]?
    let rangeNote: String?
    let birthplace: String?
    let context: String?
    let sources: [Source]?
    let review: Review?
    let notable: [Notable]?
    /// Roster v2 `attribution_note`: set when the lines that are this voice's are tagged to
    /// another voice in the data, pending the scholar (G3). Prose; `reviewAng` is read from it.
    let attributionNote: String?
    var id: String { name }

    struct Source: Decodable, Sendable, Hashable { let ref: String; let entry: String? }
    struct Review: Decodable, Sendable, Hashable {
        let status: String
        let reviewer: String?
        let date: String?
        var isApproved: Bool { status.lowercased() == "approved" }
    }
    struct Notable: Decodable, Sendable, Hashable {
        let title: String
        let compId: Int?
        enum CodingKeys: String, CodingKey { case title, compId = "comp_id" }
    }

    private enum CodingKeys: String, CodingKey {
        case name, roman, kind, seq, born, died, circa, era, region, tradition, blurb
        case display, gurmukhi, chhap, birthplace, context, sources, review, notable
        case rangeNote = "range_note", attributionNote = "attribution_note"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        roman = try c.decode(String.self, forKey: .roman)
        kind = try c.decode(String.self, forKey: .kind)
        seq = try c.decodeIfPresent(Int.self, forKey: .seq)
        born = try c.decodeIfPresent(Int.self, forKey: .born)
        died = try c.decodeIfPresent(Int.self, forKey: .died)
        circa = try c.decodeIfPresent(Bool.self, forKey: .circa) ?? false
        era = try c.decode(String.self, forKey: .era)
        region = try c.decode(String.self, forKey: .region)
        tradition = try c.decode(String.self, forKey: .tradition)
        blurb = try c.decode(String.self, forKey: .blurb)
        func lenient<T: Decodable>(_ type: T.Type, _ key: CodingKeys) -> T? {
            (try? c.decodeIfPresent(type, forKey: key)) ?? nil
        }
        display = lenient(String.self, .display).flatMap { $0.isEmpty ? nil : $0 }
        gurmukhi = lenient(String.self, .gurmukhi).flatMap { $0.isEmpty ? nil : $0 }
        chhap = lenient([String].self, .chhap)
        rangeNote = lenient(String.self, .rangeNote)
        birthplace = lenient(String.self, .birthplace)
        context = lenient(String.self, .context)
        sources = lenient([Source].self, .sources)
        review = lenient(Review.self, .review)
        notable = lenient([Notable].self, .notable)
        attributionNote = lenient(String.self, .attributionNote).flatMap { $0.isEmpty ? nil : $0 }
    }

    /// A voice the DB carries but the bundled roster does not list yet (a dataset release can
    /// land before the roster that describes it). Shown with what the DB knows; no dates.
    init(placeholderFor author: String) {
        let english = AuthorName(author).english
        name = author
        roman = english
        kind = AuthorName(author).mahala != nil ? "guru"
            : english.hasPrefix("Bhagat") ? "bhagat" : english.hasPrefix("Bhatt") ? "bhatt" : "gursikh"
        seq = AuthorName(author).mahala
        born = nil; died = nil; circa = false
        era = ""; region = ""; tradition = ""; blurb = ""
        display = nil; gurmukhi = nil; chhap = nil; rangeNote = nil; birthplace = nil
        context = nil; sources = nil; review = nil; notable = nil; attributionNote = nil
    }

    /// Sort key for the timeline (birth year; unknowns last).
    var timelineYear: Int { born ?? died ?? 9999 }

    /// The honorific English name: roster v2 `display`, else the stored name without its
    /// "(M5)" / "(ਭਟ)" suffix ("Bhagat Kabir Ji", "Guru Tegh Bahadur Ji").
    var displayName: String { display ?? AuthorName(name).english }

    /// The Mahala number for the Gurus, read from the stored name ("(M9)") or the roster `seq`.
    var mahala: Int? { kind == "guru" ? (AuthorName(name).mahala ?? seq) : nil }

    /// The stable key in `sggs://voice/<slug>`: the English name without its "(M9)" suffix,
    /// lowercased, every run of other characters a single "-" ("guru-tegh-bahadur-ji").
    var slug: String { Self.slug(for: name) }

    static func slug(for author: String) -> String {
        AuthorName(author).english.lowercased()
            .split { !(("a"..."z").contains($0) || ("0"..."9").contains($0)) }
            .joined(separator: "-")
    }

    /// The biographical paragraph: the roster `context` once approved, else `blurb`.
    var lifeText: String { reviewedContext ?? blurb }

    /// Roster v2 `context`, only once the scholar has approved it (brand gate G3). Draft or
    /// pending prose — or context with no review record at all — is never shown as biography.
    var reviewedContext: String? { (review?.isApproved ?? false) ? context : nil }

    /// The Ang the roster's `attribution_note` cites first ("… (Ang 1253, …)"): where the lines
    /// under review are printed. Nil without a note or a valid Ang in it.
    var reviewAng: Int? { attributionNote.flatMap(Self.firstAng(in:)) }

    static func firstAng(in text: String) -> Int? {
        guard let r = text.range(of: #"\bAng [0-9]{1,4}\b"#, options: .regularExpression),
              let n = Int(text[r].dropFirst(4)), GranthAngs.all.contains(n) else { return nil }
        return n
    }

    /// True when the entry carries roster `context` the scholar has not approved (it is gated).
    var awaitingReview: Bool { context != nil && !(review?.isApproved ?? false) }
}

/// The medallion on a voice's card and page. A Guru shows the Mahala in Gurmukhi ("ਮ: ੯"),
/// every other voice the first letter of their Gurmukhi name. Until roster v2 brings the
/// Gurmukhi name, a non-Guru voice shows its Latin initial (honorifics dropped).
enum VoiceMedallion {
    case gurmukhi(String)
    case latin(String)

    var text: String {
        switch self { case .gurmukhi(let s), .latin(let s): return s }
    }
    var isGurmukhi: Bool { if case .gurmukhi = self { return true } else { return false } }

    static func of(_ c: Contributor) -> VoiceMedallion {
        if let m = c.mahala { return .gurmukhi("ਮ: \(gurmukhiNumeral(m))") }
        if let g = c.gurmukhi, let initial = gurmukhiInitial(g) { return .gurmukhi(initial) }
        return .latin(latinInitial(c.displayName))
    }

    /// 9 → "੯", 10 → "੧੦".
    static func gurmukhiNumeral(_ n: Int) -> String {
        String(String(n).unicodeScalars.map { s -> Character in
            guard let d = Int(String(s)) else { return Character(s) }
            return Character(Unicode.Scalar(0x0A66 + UInt32(d))!)
        })
    }

    /// Titles that precede a name in Gurmukhi and are not part of it.
    private static let gurmukhiHonorifics: Set<String> = ["ਗੁਰੂ", "ਭਗਤ", "ਬਾਬਾ", "ਭਾਈ", "ਭਟ", "ਭੱਟ", "ਸ਼ੇਖ", "ਸੇਖ", "ਸ੍ਰੀ", "ਜੀ", "ਜੀਉ"]

    /// The first letter of the name (its consonant, with a nukta if it carries one).
    static func gurmukhiInitial(_ name: String) -> String? {
        let word = name.split(separator: " ").map(String.init).first { !gurmukhiHonorifics.contains($0) }
        guard let scalars = word?.unicodeScalars, let first = scalars.first,
              (0x0A00...0x0A7F).contains(first.value) else { return nil }
        var out = String(first)
        if scalars.count > 1, scalars[scalars.index(after: scalars.startIndex)].value == 0x0A3C { out.append("\u{0A3C}") }
        return out
    }

    private static let latinHonorifics: Set<String> = ["baba", "bhai", "bhagat", "bhatt", "guru", "sant", "sheikh", "the", "ji"]

    static func latinInitial(_ name: String) -> String {
        let word = name.split(separator: " ").first { !latinHonorifics.contains($0.lowercased()) }
        return (word ?? Substring(name)).prefix(1).uppercased()
    }
}

enum ContributorsStore {
    struct File: Decodable { let contributors: [Contributor] }

    /// Loads the bundled roster (nil only if the resource is missing/corrupt — the Lineage
    /// screen shows its designed empty state then, never crashes).
    static func load(bundle: Bundle = .main) -> [Contributor]? {
        guard let url = bundle.url(forResource: "contributors", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return decode(data)
    }

    static func decode(_ data: Data) -> [Contributor]? {
        guard let file = try? JSONDecoder().decode(File.self, from: data), !file.contributors.isEmpty else { return nil }
        return file.contributors
    }
}
