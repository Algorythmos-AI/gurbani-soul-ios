import Foundation

/// Display names for the heading-derived forms the corpus records: the 23 poetic genres of
/// `shabd_poetic_genre` and the structural forms of `shabd_structural_form`. These are the names
/// the printed headings use, transliterated; the verbatim Gurmukhi heading is always shown with
/// them. Explanations of what a form IS belong to a separately reviewed layer, not here.
enum PoeticForms {

    static let genreNames: [String: String] = [
        "alahunian": "Alahunian", "anjulian": "Anjulian", "barah_maha": "Barah Maha",
        "bavan_akhri": "Bavan Akhri", "birhare": "Birhare", "chaubole": "Chaubole",
        "dakhne": "Dakhne", "din_raini": "Din Raini", "funhe": "Funhe", "gatha": "Gatha",
        "ghorian": "Ghorian", "gunvanti": "Gunvanti", "karhale": "Karhale", "kuchaji": "Kuchaji",
        "mundavani": "Mundavani", "pahare": "Pahare", "patti": "Patti", "ruti": "Ruti",
        "sadd": "Sadd", "savaiye": "Savaiye", "suchaji": "Suchaji", "thitti": "Thitti",
        "vanjara": "Vanjara",
    ]

    /// Plural display names for the structural forms, in `RaagFacts.formOrder`.
    static let formNames: [String: String] = [
        "pada": "Padas", "ashtpadi": "Ashtpadis", "chhant": "Chhants", "solahe": "Solahe",
        "vaar": "Vaars", "pauri": "Pauris", "salok": "Saloks",
    ]

    /// "Barah Maha" for `barah_maha`; an unknown key reads as its words, capitalised.
    static func genre(_ key: String) -> String {
        genreNames[key] ?? key.replacingOccurrences(of: "_", with: " ").capitalized
    }

    static func form(_ key: String) -> String {
        formNames[key] ?? key.replacingOccurrences(of: "_", with: " ").capitalized
    }
}
