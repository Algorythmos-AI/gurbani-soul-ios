import Foundation

/// Read models for Explore › Lineage ("Voices of the Granth"). Every count is computed from the
/// verbatim `lines` table with headers excluded (`is_header = 0`), so a card and a voice page can
/// never disagree. Descriptive only — the volume of a voice's Bani is never its importance.

/// The Angs (1…1430) on which a voice's verses appear, as a fixed 1430-bit set.
public struct AngSet: Sendable, Equatable {
    public static let angCount = 1430
    private var words: [UInt64]

    public init<S: Sequence>(_ angs: S) where S.Element == Int {
        words = Array(repeating: 0, count: (Self.angCount + 63) / 64)
        for a in angs where (1...Self.angCount).contains(a) {
            words[(a - 1) / 64] |= 1 << UInt64((a - 1) % 64)
        }
    }

    public func contains(_ ang: Int) -> Bool {
        guard (1...Self.angCount).contains(ang) else { return false }
        return words[(ang - 1) / 64] & (1 << UInt64((ang - 1) % 64)) != 0
    }

    /// How many distinct Angs carry this voice.
    public var count: Int { words.reduce(0) { $0 + $1.nonzeroBitCount } }
    public var isEmpty: Bool { words.allSatisfy { $0 == 0 } }

    /// The Angs in ascending order.
    public var angs: [Int] { (1...Self.angCount).filter(contains) }

    /// True when any Ang in `range` is present (one barcode column covers a run of Angs).
    public func intersects(_ range: ClosedRange<Int>) -> Bool {
        let lo = max(1, range.lowerBound), hi = min(Self.angCount, range.upperBound)
        guard lo <= hi else { return false }
        return (lo...hi).contains(where: contains)
    }

    /// The present Ang closest to `ang` (ties go to the earlier one); nil when the set is empty.
    public func nearest(to ang: Int) -> Int? {
        guard !isEmpty else { return nil }
        for d in 0..<Self.angCount {
            if contains(ang - d) { return ang - d }
            if contains(ang + d) { return ang + d }
        }
        return nil
    }
}

/// One voice in the Granth, counted from `lines` (headers excluded).
public struct VoiceSummary: Sendable, Equatable, Identifiable {
    public let author: String
    /// Verses: `lines` rows by this voice with `is_header = 0`. The ONE count shown everywhere.
    public let nVerses: Int
    /// Distinct compositions (`comp_id`) carrying at least one of those verses.
    public let nCompositions: Int
    /// Distinct raags among those verses; 0 when every verse sits outside the raag sections.
    public let nRaags: Int
    public let firstAng: Int
    public let lastAng: Int
    public let angs: AngSet
    public var id: String { author }
    public init(author: String, nVerses: Int, nCompositions: Int, nRaags: Int,
                firstAng: Int, lastAng: Int, angs: AngSet) {
        self.author = author; self.nVerses = nVerses; self.nCompositions = nCompositions
        self.nRaags = nRaags; self.firstAng = firstAng; self.lastAng = lastAng; self.angs = angs
    }
}

/// A voice's verses in one raag. `isSignature`: no other voice has a verse in that raag.
public struct RaagShare: Sendable, Equatable, Identifiable {
    public let raag: String
    public let roman: String
    public let nVerses: Int
    public let nCompositions: Int
    public let isSignature: Bool
    public var id: String { raag }
    public init(raag: String, roman: String, nVerses: Int, nCompositions: Int, isSignature: Bool) {
        self.raag = raag; self.roman = roman; self.nVerses = nVerses
        self.nCompositions = nCompositions; self.isSignature = isSignature
    }
}

/// One verbatim verse, cited by Ang.
public struct VoiceVerse: Sendable, Equatable, Identifiable {
    public let id: Int          // lines.id
    public let ang: Int
    public let compId: Int
    public let gurmukhi: String
    public init(id: Int, ang: Int, compId: Int, gurmukhi: String) {
        self.id = id; self.ang = ang; self.compId = compId; self.gurmukhi = gurmukhi
    }
}

/// The rahao (ਰਹਾਉ) verse of each of a voice's shabads: the first rahao verse per composition.
public struct RahaoDeck: Sendable, Equatable {
    /// Every rahao verse by this voice (a shabad can carry more than one).
    public let totalLines: Int
    public let verses: [VoiceVerse]
    public static let empty = RahaoDeck(totalLines: 0, verses: [])
    public init(totalLines: Int, verses: [VoiceVerse]) { self.totalLines = totalLines; self.verses = verses }
}

/// One composition by a voice: where it opens and its first verse, verbatim.
public struct VoiceComposition: Sendable, Equatable, Identifiable {
    public let compId: Int
    public let ang: Int
    public let firstLineId: Int
    public let nVerses: Int
    public let raag: String?
    public let opening: String
    public var id: Int { compId }
    public init(compId: Int, ang: Int, firstLineId: Int, nVerses: Int, raag: String?, opening: String) {
        self.compId = compId; self.ang = ang; self.firstLineId = firstLineId
        self.nVerses = nVerses; self.raag = raag; self.opening = opening
    }
}

/// Optional pipeline facts (`author_facts`, sggs-data). Nil fields: column absent or NULL.
/// The stylometry here is measured on the Gurmukhi; `author_analytics` measures the English
/// translation and is never presented as the style of the Bani.
public struct AuthorFacts: Sendable, Equatable {
    public let nVerses: Int?
    /// Verses after the raag sections (Ang 1353 on).
    public let outsideRaagVerses: Int?
    /// How often the voice signs with its pen-name; nil = not measured (e.g. the Bhatts).
    public let chhapCount: Int?
    public let nTokens: Int?
    public let mattr100: Double?
    public let wordsPerVerse: Double?
    public init(nVerses: Int?, outsideRaagVerses: Int?, chhapCount: Int?, nTokens: Int?,
                mattr100: Double?, wordsPerVerse: Double?) {
        self.nVerses = nVerses; self.outsideRaagVerses = outsideRaagVerses; self.chhapCount = chhapCount
        self.nTokens = nTokens; self.mattr100 = mattr100; self.wordsPerVerse = wordsPerVerse
    }
}

/// A verse by `speaker` that names `named` (`author_mentions`); `form` is the name as written.
public struct VoiceMention: Sendable, Equatable, Identifiable {
    public let speaker: String
    public let named: String
    public let form: String?
    public let verse: VoiceVerse
    public var id: String { "\(verse.id)|\(speaker)|\(named)" }
    public init(speaker: String, named: String, form: String?, verse: VoiceVerse) {
        self.speaker = speaker; self.named = named; self.form = form; self.verse = verse
    }
}

public struct VoiceMentions: Sendable, Equatable {
    /// Verses by other voices that name this one.
    public let namedBy: [VoiceMention]
    /// Verses by this voice that name others.
    public let names: [VoiceMention]
    public static let empty = VoiceMentions(namedBy: [], names: [])
    public var isEmpty: Bool { namedBy.isEmpty && names.isEmpty }
    public init(namedBy: [VoiceMention], names: [VoiceMention]) { self.namedBy = namedBy; self.names = names }
}

/// A Bhagat's salok and the Guru's salok set directly beside it (`author_dialogues`), both verbatim.
public struct VoiceDialogue: Sendable, Equatable, Identifiable {
    public let seq: Int
    public let bhagatAuthor: String
    public let bhagat: [VoiceVerse]
    public let guruAuthor: String
    public let guru: [VoiceVerse]
    public var id: Int { seq }
    public init(seq: Int, bhagatAuthor: String, bhagat: [VoiceVerse], guruAuthor: String, guru: [VoiceVerse]) {
        self.seq = seq; self.bhagatAuthor = bhagatAuthor; self.bhagat = bhagat
        self.guruAuthor = guruAuthor; self.guru = guru
    }
}

/// Another voice whose verses resonate with this one's (`author_resonance`) — descriptive, never a ranking.
public struct VoiceEcho: Sendable, Equatable, Identifiable {
    public let author: String
    public let edges: Int
    public let lift: Double
    public var id: String { author }
    public init(author: String, edges: Int, lift: Double) { self.author = author; self.edges = edges; self.lift = lift }
}
