import Foundation

/// English names for the Granth's raags and sections, keyed by the Gurmukhi name the corpus
/// stores (the `raags` / `sections` tables). The corpus's own `roman` column is a ShabadOS-style
/// transliteration ("gaurhee", "raamakalee") — exact, but not what a reader calls the raag — so
/// the Index shows these familiar spellings beside the verbatim Gurmukhi, which always leads.
///
/// Spellings follow the common English usage of the printed Sri Guru Granth Sahib Ji's table of
/// contents. A name missing here falls back to the corpus roman, capitalised — never to nothing.
enum GranthNames {

    /// The 31 raags, by their corpus Gurmukhi name. ਨਟ is printed "ਰਾਗੁ ਨਟ ਨਾਰਾਇਨ" (Ang 975).
    static let raags: [String: String] = [
        "ਸਿਰੀਰਾਗੁ": "Sri Raag", "ਮਾਝ": "Majh", "ਗਉੜੀ": "Gauri", "ਆਸਾ": "Asa", "ਗੂਜਰੀ": "Gujri",
        "ਦੇਵਗੰਧਾਰੀ": "Devgandhari", "ਬਿਹਾਗੜਾ": "Bihagra", "ਵਡਹੰਸੁ": "Vadhans", "ਸੋਰਠਿ": "Sorath",
        "ਧਨਾਸਰੀ": "Dhanasri", "ਜੈਤਸਰੀ": "Jaitsri", "ਟੋਡੀ": "Todi", "ਬੈਰਾੜੀ": "Bairari",
        "ਤਿਲੰਗ": "Tilang", "ਸੂਹੀ": "Suhi", "ਬਿਲਾਵਲੁ": "Bilaval", "ਗੋਂਡ": "Gond", "ਰਾਮਕਲੀ": "Ramkali",
        "ਨਟ": "Nat Narayan", "ਮਾਲੀ ਗਉੜਾ": "Mali Gaura", "ਮਾਰੂ": "Maru", "ਤੁਖਾਰੀ": "Tukhari",
        "ਕੇਦਾਰਾ": "Kedara", "ਭੈਰਉ": "Bhairo", "ਬਸੰਤੁ": "Basant", "ਸਾਰੰਗ": "Sarang", "ਮਲਾਰ": "Malar",
        "ਕਾਨੜਾ": "Kanra", "ਕਲਿਆਨੁ": "Kalyan", "ਪ੍ਰਭਾਤੀ": "Prabhati", "ਜੈਜਾਵੰਤੀ": "Jaijavanti",
    ]

    /// The corpus `roman` of each raag → its Gurmukhi name. Lets a deep link that uses the corpus
    /// spelling (the Raag Clock's form) resolve before the DB opens; a unit test pins it to the DB.
    static let romanToRaag: [String: String] = [
        "sireeraag": "ਸਿਰੀਰਾਗੁ", "maajh": "ਮਾਝ", "gaurhee": "ਗਉੜੀ", "aasaa": "ਆਸਾ", "goojaree": "ਗੂਜਰੀ",
        "devagandhaaree": "ਦੇਵਗੰਧਾਰੀ", "bihaagarhaa": "ਬਿਹਾਗੜਾ", "vadahans": "ਵਡਹੰਸੁ", "sorath": "ਸੋਰਠਿ",
        "dhanaasaree": "ਧਨਾਸਰੀ", "jaitasaree": "ਜੈਤਸਰੀ", "todee": "ਟੋਡੀ", "bairaarhee": "ਬੈਰਾੜੀ",
        "tilang": "ਤਿਲੰਗ", "soohee": "ਸੂਹੀ", "bilaaval": "ਬਿਲਾਵਲੁ", "gond": "ਗੋਂਡ", "raamakalee": "ਰਾਮਕਲੀ",
        "nat": "ਨਟ", "maalee gaurhaa": "ਮਾਲੀ ਗਉੜਾ", "maaroo": "ਮਾਰੂ", "tukhaaree": "ਤੁਖਾਰੀ",
        "kedaaraa": "ਕੇਦਾਰਾ", "bhairau": "ਭੈਰਉ", "basant": "ਬਸੰਤੁ", "saarang": "ਸਾਰੰਗ", "malaar": "ਮਲਾਰ",
        "kaanarhaa": "ਕਾਨੜਾ", "kaliaan": "ਕਲਿਆਨੁ", "prabhaatee": "ਪ੍ਰਭਾਤੀ", "jaijaavantee": "ਜੈਜਾਵੰਤੀ",
    ]

    /// The banis before and after the raags, by their corpus Gurmukhi section name. The two
    /// salok collections are listed ahead of the sggs-data section fix that will name them.
    static let sections: [String: String] = [
        "ਜਪੁ": "Japji Sahib", "ਸੋ ਦਰੁ": "So Dar", "ਸੋ ਪੁਰਖੁ": "So Purakh", "ਸੋਹਿਲਾ": "Sohila",
        "ਸਲੋਕ ਸਹਸਕ੍ਰਿਤੀ": "Salok Sehskriti", "ਗਾਥਾ": "Gatha", "ਫੁਨਹੇ": "Funhe", "ਚਉਬੋਲੇ": "Chaubole",
        "ਸਲੋਕ ਭਗਤ ਕਬੀਰ ਜੀਉ ਕੇ": "Salok Bhagat Kabir Ji", "ਸਲੋਕ ਸੇਖ ਫਰੀਦ ਕੇ": "Salok Sheikh Farid Ji",
        "ਸਵਈਏ": "Savaiye", "ਸਲੋਕ ਵਾਰਾਂ ਤੇ ਵਧੀਕ": "Salok Varan Te Vadheek",
        "ਸਲੋਕ ਮਹਲਾ ੯": "Salok Mahalla 9", "ਮੁੰਦਾਵਣੀ": "Mundavani", "ਰਾਗ ਮਾਲਾ": "Raagmala",
    ]

    /// "Gauri" for ਗਉੜੀ; the corpus roman, capitalised, for an unknown raag; nil with neither.
    static func raag(_ gurmukhi: String, roman: String? = nil) -> String? {
        raags[gurmukhi] ?? roman.flatMap { $0.isEmpty ? nil : $0.capitalized }
    }

    static func section(_ gurmukhi: String) -> String? { sections[gurmukhi] }

    /// The English name for a section AS THE DATA SPANS IT. The pinned dataset's ਚਉਬੋਲੇ row runs
    /// Ang 1363–1384 because the corpus section detector does not yet open the two salok
    /// collections whose headings sit inside it (ਸਲੋਕ ਭਗਤ ਕਬੀਰ ਜੀਉ ਕੇ, Ang 1364; ਸਲੋਕ ਸੇਖ ਫਰੀਦ ਕੇ,
    /// Ang 1377). Until sggs-data splits it, the name says what the span really holds, so no
    /// reader is told Chaubole fills 22 Angs. Once the row ends by Ang 1364 this returns "Chaubole".
    static func section(_ gurmukhi: String, firstAng: Int, lastAng: Int) -> String? {
        if gurmukhi == "ਚਉਬੋਲੇ", lastAng > 1364 {
            return "Chaubole, Salok Bhagat Kabir Ji, Salok Sheikh Farid Ji"
        }
        return section(gurmukhi)
    }

    /// The URL slug a raag answers to: its English name, lowercased, words joined by "-"
    /// ("gauri", "nat-narayan", "sri-raag"). Lowercase ascii letters and "-" only.
    static func slug(forRaag gurmukhi: String, roman: String?) -> String {
        let base = raag(gurmukhi, roman: roman) ?? gurmukhi
        return base.lowercased().split(whereSeparator: { !$0.isLetter || !$0.isASCII }).joined(separator: "-")
    }

    /// Resolves a deep-link value to a corpus raag name: an English slug ("gauri", "nat-narayan"),
    /// or the corpus roman ("gaurhee", "maalee-gaurhaa" / "maalee gaurhaa"). nil if none matches.
    static func raagName(forSlug slug: String, in raags: [(name: String, roman: String?)]) -> String? {
        let s = slug.lowercased()
        guard !s.isEmpty, s.count <= 40 else { return nil }
        if let hit = raags.first(where: { Self.slug(forRaag: $0.name, roman: $0.roman) == s }) { return hit.name }
        let spaced = s.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ")
        return raags.first(where: { $0.roman?.lowercased() == spaced })?.name
    }
}
