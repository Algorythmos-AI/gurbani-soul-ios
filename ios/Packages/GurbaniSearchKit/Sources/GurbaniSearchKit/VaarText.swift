import Foundation

/// One Vaar as it is printed: its heading run, then every salok and pauri in reading order,
/// each holding its own verbatim lines. Built by `VaarStructure.build` from a contiguous run of
/// corpus lines — the structure is READ from the print (the ਸਲੋਕ / ਮਃ / ਪਉੜੀ label lines and the
/// ॥N॥ pauri numbers), never re-typed, and every string is the corpus `gurmukhi` unchanged.
///
/// Why not `vaar_units`: on the shipped DB that table carries a phantom salok (Ramkali M3's
/// ਧੁਨੀ rubric), misses the 17 inner ਡਖਣੇ saloks of Maru M5, and lets the last unit of several
/// Vaars run into the bani that follows. `vaar_units` still supplies what the print leaves
/// implicit (a salok whose label names no author, the kind of an unlabelled unit), and
/// `build` refuses (nil) whenever the print and the pauri numbering disagree.
public struct VaarText: Sendable, Equatable {
    public let vaarId: Int
    /// The printed heading run: invocation, title line(s) and any ਧੁਨੀ rubric, in order.
    public let heading: [VaarLine]
    /// The ਧੁਨੀ / ਧੁਨਿ line, when the heading carries one (9 of the 22 Vaars).
    public let dhuni: VaarLine?
    public let units: [VaarTextUnit]

    public init(vaarId: Int, heading: [VaarLine], dhuni: VaarLine?, units: [VaarTextUnit]) {
        self.vaarId = vaarId; self.heading = heading; self.dhuni = dhuni; self.units = units
    }

    /// The title as printed: the heading lines that are not the ੴ invocation.
    public var titleLines: [VaarLine] { heading.filter { !VaarStructure.isInvocation($0.gurmukhi) } }
    public var pauris: [VaarTextUnit] { units.filter { $0.kind == .pauri } }
    public var nPauris: Int { units.reduce(0) { $0 + ($1.kind == .pauri ? 1 : 0) } }
    public var nSaloks: Int { units.count - nPauris }
    public var firstAng: Int { heading.first?.ang ?? units.first?.firstAng ?? 0 }
    public var lastAng: Int { units.last?.lastAng ?? firstAng }
    public var lineCount: Int { heading.count + units.reduce(0) { $0 + $1.lines.count } }
    /// Distinct voices in first-appearance order (pauri author first).
    public var voices: [String] {
        var seen: [String] = []
        for u in units { if let a = u.author, !seen.contains(a) { seen.append(a) } }
        return seen
    }
    /// The unit holding `lineId`, if any.
    public func unitIndex(containing lineId: Int) -> Int? {
        units.firstIndex { u in u.lines.first.map { $0.id <= lineId } == true && u.lines.last.map { lineId <= $0.id } == true }
    }
}

public struct VaarLine: Sendable, Equatable, Identifiable {
    public let id: Int
    public let ang: Int
    public let isHeader: Bool
    public let gurmukhi: String
    public init(id: Int, ang: Int, isHeader: Bool, gurmukhi: String) {
        self.id = id; self.ang = ang; self.isHeader = isHeader; self.gurmukhi = gurmukhi
    }
}

public struct VaarTextUnit: Sendable, Equatable, Identifiable {
    public enum Kind: String, Sendable { case salok, pauri }
    /// 0-based position in reading order.
    public let index: Int
    public let kind: Kind
    /// 1-based, pauris only — proven against the ॥N॥ the print closes the pauri with.
    public let pauriNo: Int?
    /// The printed label line (ਸਲੋਕ ਮਃ ੧ ॥, ਪਉੜੀ ॥ …), nil when the print has none here.
    public let label: VaarLine?
    public let author: String?
    /// Every line of the unit, the label first when there is one.
    public let lines: [VaarLine]
    public var id: Int { index }

    public init(index: Int, kind: Kind, pauriNo: Int?, label: VaarLine?, author: String?, lines: [VaarLine]) {
        self.index = index; self.kind = kind; self.pauriNo = pauriNo; self.label = label
        self.author = author; self.lines = lines
    }

    /// The verse lines (label and any invocation excluded).
    public var verse: [VaarLine] { lines.filter { $0.id != label?.id && !$0.isHeader } }
    public var firstVerse: VaarLine? { verse.first }
    public var firstAng: Int { lines.first?.ang ?? 0 }
    public var lastAng: Int { lines.last?.ang ?? 0 }
}

/// One row of `vaar_units` — only the fields the print does not spell out.
public struct VaarUnitHint: Sendable, Equatable {
    public let kind: String
    public let firstLineId: Int
    public let author: String?
    public init(kind: String, firstLineId: Int, author: String?) {
        self.kind = kind; self.firstLineId = firstLineId; self.author = author
    }
}

public enum VaarStructure {

    /// Words a printed unit label starts with. A label line never carries a ॥N॥ verse number.
    static let labelWords = ["ਸਲੋਕ", "ਸਲੋਕੁ", "ਮਃ", "ਮਹਲਾ", "ਪਉੜੀ", "ਪਵੜੀ", "ਡਖਣੇ", "ਡਖਣਾ", "ਮਰਦਾਨਾ"]
    static let pauriWords = ["ਪਉੜੀ", "ਪਵੜੀ"]

    /// Author names exactly as the corpus `author` column spells them.
    static let mahalla: [Character: String] = [
        "੧": "Guru Nanak Dev Ji (M1)", "੨": "Guru Angad Dev Ji (M2)", "੩": "Guru Amar Das Ji (M3)",
        "੪": "Guru Ram Das Ji (M4)", "੫": "Guru Arjan Dev Ji (M5)",
    ]

    private static func words(_ s: String) -> [Substring] { s.split(separator: " ", omittingEmptySubsequences: true) }

    /// Exact scalar comparison: Gurmukhi is matched code point for code point, never through
    /// canonical equivalence.
    private static func same(_ a: Substring, _ b: String) -> Bool {
        a.unicodeScalars.elementsEqual(b.unicodeScalars)
    }

    static func isGurmukhiDigit(_ c: Character) -> Bool {
        guard let v = c.unicodeScalars.first?.value, c.unicodeScalars.count == 1 else { return false }
        return (0x0A66...0x0A6F).contains(v)
    }

    /// Every ॥N॥ number in `s`, in order.
    static func verseNumbers(in s: String) -> [Int] {
        var out: [Int] = []
        let chars = Array(s)
        var i = 0
        while i < chars.count {
            if chars[i] == "॥" {
                var j = i + 1
                var n = 0
                var digits = 0
                while j < chars.count, isGurmukhiDigit(chars[j]) {
                    n = n * 10 + Int(chars[j].unicodeScalars.first!.value - 0x0A66)
                    digits += 1; j += 1
                }
                if digits > 0, j < chars.count, chars[j] == "॥" { out.append(n); i = j; continue }
            }
            i += 1
        }
        return out
    }

    public static func isInvocation(_ s: String) -> Bool { s.unicodeScalars.first?.value == 0x0A74 }  // ੴ

    public static func isDhuni(_ s: String) -> Bool { s.contains("ਧੁਨੀ") || s.contains("ਧੁਨਿ") }

    /// A printed salok/pauri label: starts with a label word, carries no verse number, and is
    /// either flagged as a header or a short rubric (the print's ਪਵੜੀ ॥ / ਮਰਦਾਨਾ ੧ ॥ are not flagged).
    public static func isLabel(_ line: VaarLine) -> Bool {
        let w = words(line.gurmukhi)
        guard let first = w.first, labelWords.contains(where: { same(first, $0) }) else { return false }
        if !verseNumbers(in: line.gurmukhi).isEmpty { return false }
        return line.isHeader || w.count <= 3
    }

    static func isPauriLabel(_ line: VaarLine) -> Bool {
        guard let first = words(line.gurmukhi).first else { return false }
        return pauriWords.contains { same(first, $0) }
    }

    /// The author a label names: ਮਃ N / ਮਹਲਾ N → that Guru, ਮਰਦਾਨਾ → Bhai Mardana, else nil.
    static func author(ofLabel s: String) -> String? {
        let w = words(s)
        if w.contains(where: { same($0, "ਮਰਦਾਨਾ") }) { return "Bhai Mardana" }
        for (k, word) in w.enumerated() where (same(word, "ਮਃ") || same(word, "ਮਹਲਾ")) && k + 1 < w.count {
            let next = w[k + 1]
            if next.count == 1, let c = next.first, let name = mahalla[c] { return name }
        }
        return nil
    }

    /// Builds the printed structure of one Vaar from `lines` — the contiguous corpus run from the
    /// first line of its heading's composition to the last line of its final pauri's — plus the
    /// `vaar_units` hints. Returns nil (callers fall back to opening the Ang) when the result
    /// cannot be proven: a gap in line ids, an empty unit, or a pauri whose text does not close
    /// with its own number.
    public static func build(vaarId: Int, pauriAuthor: String?, lines: [VaarLine], hints: [VaarUnitHint]) -> VaarText? {
        guard !lines.isEmpty, !hints.isEmpty else { return nil }
        for k in 1..<max(lines.count, 1) where lines[k].id != lines[k - 1].id + 1 { return nil }

        // Heading: the leading header lines and any ਧੁਨੀ rubric, up to the first label or verse.
        var h = 0
        while h < lines.count, !isLabel(lines[h]), lines[h].isHeader || isDhuni(lines[h].gurmukhi) { h += 1 }
        let heading = Array(lines[..<h])
        guard !heading.isEmpty, h < lines.count else { return nil }

        // Unit starts: every label line; verse before the first label is a unit whose label the
        // title carries (Maru M5's opening ਡਖਣੇ). A Vaar printed without labels (Satta & Balwand,
        // Basant) is split at the vaar_units boundaries instead.
        let labelIdx = (h..<lines.count).filter { isLabel(lines[$0]) }
        var starts: [Int]
        if labelIdx.isEmpty {
            let base = lines[0].id
            starts = hints.map { $0.firstLineId - base }.filter { $0 >= h && $0 < lines.count }
            guard !starts.isEmpty else { return nil }
            starts[0] = h
        } else {
            starts = (labelIdx[0] > h ? [h] : []) + labelIdx
        }

        var units: [VaarTextUnit] = []
        var pauriNo = 0
        for (k, a) in starts.enumerated() {
            let b = k + 1 < starts.count ? starts[k + 1] : lines.count
            let slice = Array(lines[a..<b])
            let label = isLabel(lines[a]) ? lines[a] : nil
            let range = slice.first!.id...slice.last!.id
            let hint = hints.first { range.contains($0.firstLineId) }
            let kind: VaarTextUnit.Kind = label.map { isPauriLabel($0) ? .pauri : .salok }
                ?? (hint?.kind == "pauri" ? .pauri : .salok)
            let verse = slice.filter { $0.id != label?.id && !$0.isHeader }
            guard !verse.isEmpty else { return nil }
            var number: Int?
            if kind == .pauri {
                pauriNo += 1
                let closing = verse.flatMap { verseNumbers(in: $0.gurmukhi) }
                guard closing.contains(pauriNo) else { return nil }
                number = pauriNo
            }
            let named = label.flatMap { author(ofLabel: $0.gurmukhi) }
            let author: String?
            if kind == .pauri {
                author = named ?? pauriAuthor
            } else {
                author = named ?? hints.first { range.contains($0.firstLineId) && $0.kind == "salok" }?.author
            }
            units.append(VaarTextUnit(index: k, kind: kind, pauriNo: number, label: label, author: author, lines: slice))
        }
        guard pauriNo > 0 else { return nil }
        return VaarText(vaarId: vaarId, heading: heading, dhuni: heading.first { isDhuni($0.gurmukhi) }, units: units)
    }
}
