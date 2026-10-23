import Foundation

// The Index's facts about one raag and about the Granth's named poetic forms. iOS-only reads (no
// serve.py endpoint mirrors them yet), built from the same tables the web already ships — raags,
// lines, shabd_raag_map and the heading-derived shabd_* form layer — so nothing is inferred.
//
// What these deliberately do NOT carry: counts of padas. `shabd_structural_form.form` is set only
// where a printed heading names the form, so most shabads have no form at all and a "3 padas"
// count would mislead. Forms are reported as PRESENT (with their first instance), never tallied.

/// One voice's verses inside a raag (non-heading lines, attributed author only).
public struct RaagVoice: Sendable, Equatable, Identifiable {
    public let author: String
    public let nLines: Int
    public var id: String { author }
    public init(author: String, nLines: Int) { self.author = author; self.nLines = nLines }
}

/// A heading-named structural form present in a raag, with the first composition that carries it.
public struct RaagForm: Sendable, Equatable, Identifiable {
    /// pada | ashtpadi | chhant | solahe | vaar | pauri | salok (as `shabd_structural_form` spells it)
    public let form: String
    public let firstCompId: Int
    public let firstAng: Int
    public var id: String { form }
    public init(form: String, firstCompId: Int, firstAng: Int) {
        self.form = form; self.firstCompId = firstCompId; self.firstAng = firstAng
    }
}

/// One composition whose printed heading names a poetic genre (Barah Maha, Pahare, Sadd, …).
public struct PoeticFormEntry: Sendable, Equatable, Identifiable {
    /// The genre key as `shabd_poetic_genre` spells it (`barah_maha`, `pahare`, …).
    public let genre: String
    public let compId: Int
    public let firstAng: Int
    /// The raag it sits in; nil after the raags (Gatha, Funhe, Savaiye, …).
    public let raag: String?
    public let raagRoman: String?
    /// The printed heading the genre was read from — verbatim Gurmukhi.
    public let sourceLabel: String?
    public var id: Int { compId }
    public init(genre: String, compId: Int, firstAng: Int, raag: String?, raagRoman: String?, sourceLabel: String?) {
        self.genre = genre; self.compId = compId; self.firstAng = firstAng
        self.raag = raag; self.raagRoman = raagRoman; self.sourceLabel = sourceLabel
    }
}

/// Everything the Raag page shows that `CorpusMeta.raags` does not already carry.
public struct RaagFacts: Sendable, Equatable {
    public let raag: RaagRow
    /// Non-heading lines (verses) in the raag — what the voice counts add up to, plus any verses
    /// the print leaves unattributed. `raag.nLines` also counts heading lines.
    public let nVerses: Int
    /// Attributed voices, most verses first (ties by name, so the order is stable).
    public let voices: [RaagVoice]
    /// Heading-named forms present, in a fixed reading order (see `RaagFacts.formOrder`).
    public let forms: [RaagForm]
    /// Named poetic genres inside this raag, in Ang order.
    public let genres: [PoeticFormEntry]
    /// The ghar numbers printed in this raag's headings, ascending.
    public let ghars: [Int]
    /// Compositions whose heading says ਪੜਤਾਲ (partaal), in Ang order.
    public let partaalCompIds: [Int]
    /// False when this DB build carries no shabd_* form layer — forms/genres/ghars are then empty
    /// because the data is absent, not because the raag has none.
    public let hasFormLayer: Bool

    public static let formOrder = ["pada", "ashtpadi", "chhant", "solahe", "vaar", "pauri", "salok"]

    public init(raag: RaagRow, nVerses: Int, voices: [RaagVoice], forms: [RaagForm], genres: [PoeticFormEntry],
                ghars: [Int], partaalCompIds: [Int], hasFormLayer: Bool) {
        self.raag = raag; self.nVerses = nVerses; self.voices = voices; self.forms = forms; self.genres = genres
        self.ghars = ghars; self.partaalCompIds = partaalCompIds; self.hasFormLayer = hasFormLayer
    }
}
