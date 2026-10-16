import Foundation

/// Display-only "traditional saroop" transform, kept in step with frontend/src/scripts/saroop.ts.
///
/// The corpus stores every subjoined yayya the way the source PDF's font encoded it: a doubled
/// VIRAMA+YA pair (268 words on 78 Angs; a single pair never occurs). The printed Bir draws one
/// yayya tucked under the letter — Unicode's GURMUKHI SIGN YAKASH U+0A75, which the bundled Sant
/// Lipi draws as that deep subscript in every context, sihari included. So each (VIRAMA YA)+ run
/// becomes one yakash. NEVER applied to stored, searched, copied or spoken text — only at render
/// (`GurmukhiText`; VoiceOver reads the verbatim string).
enum Saroop {
    private static let VIRAMA: UInt32 = 0x0A4D
    private static let YA: UInt32 = 0x0A2F
    /// U+0A75 GURMUKHI SIGN YAKASH. The corpus contains none of its own, so on screen it can only
    /// be ours and `toVerbatim` maps it back without ambiguity (`SaroopTests` checks the corpus).
    static let yakash = Unicode.Scalar(0x0A75)!
    static let verbatimPair = "\u{0A4D}\u{0A2F}\u{0A4D}\u{0A2F}"

    static func toTraditional(_ s: String) -> String {
        // fast path: nothing to do unless a subjoined-ya is present
        guard s.unicodeScalars.contains(where: { $0.value == YA }) else { return s }
        let cp = Array(s.unicodeScalars)
        var out = String.UnicodeScalarView()
        var i = 0
        while i < cp.count {
            if cp[i].value == VIRAMA, i + 1 < cp.count, cp[i + 1].value == YA {
                var j = i                                        // consume the whole (VIRAMA YA)+ run
                while j + 1 < cp.count, cp[j].value == VIRAMA, cp[j + 1].value == YA { j += 2 }
                out.append(yakash)
                i = j
            } else {
                out.append(cp[i]); i += 1
            }
        }
        return String(out)
    }

    /// The display form back to the stored characters: each yakash becomes the doubled pair, and
    /// any Variation Selector (an older build's markup) is dropped.
    static func toVerbatim(_ s: String) -> String {
        var out = String.UnicodeScalarView()
        for c in s.unicodeScalars {
            if c == yakash { out.append(contentsOf: verbatimPair.unicodeScalars) }
            else if !(0xFE00...0xFE0F).contains(c.value) { out.append(c) }
        }
        return String(out)
    }
}
