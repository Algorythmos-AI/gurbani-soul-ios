import Foundation

/// Display-only shaping repair, applied next to the saroop painter in `GurmukhiText`.
///
/// Jaap Sahib pauris 79 and 80 (Sri Dasam Granth layer, from ShabadOS) store ਜਤੱ੍ਰ / ਤਤੱ੍ਰ as
/// ਤ + ੱ ADDAK + ੍ VIRAMA + ਰ — the order the source's legacy font was typed in ("q`R"). A Unicode
/// shaper cannot place a mark between a consonant and the virama that joins its conjunct, so Sant
/// Lipi draws the addak on a dotted circle ("ਜਤ◌ੱ੍ਰ"). Moving the addak after the conjunct
/// (ਤ + ੍ + ਰ + ੱ) draws the same glyphs the printed gutka shows: the addak over ਤ and the
/// subscript ਰ under it. No other line in the app contains the sequence (`GlyphRepairTests`).
///
/// FLAGGED FOR SCHOLAR REVIEW (with the earlier Unicode repairs); to be reported upstream to
/// ShabadOS. NEVER applied to stored, searched, copied, shared or spoken text — only at render.
enum GlyphRepair {
    static let addak: UInt32 = 0x0A71
    static let virama: UInt32 = 0x0A4D

    static func forDisplay(_ s: String) -> String {
        // fast path: nothing to do unless an addak is present
        guard s.unicodeScalars.contains(where: { $0.value == addak }) else { return s }
        let cp = Array(s.unicodeScalars)
        var out = String.UnicodeScalarView()
        var i = 0
        while i < cp.count {
            // ADDAK VIRAMA <consonant>  →  VIRAMA <consonant> ADDAK
            if cp[i].value == addak, i + 2 < cp.count, cp[i + 1].value == virama,
               isConsonant(cp[i + 2]) {
                out.append(cp[i + 1]); out.append(cp[i + 2]); out.append(cp[i])
                i += 3
            } else {
                out.append(cp[i]); i += 1
            }
        }
        return String(out)
    }

    private static func isConsonant(_ s: Unicode.Scalar) -> Bool {
        (0x0A15...0x0A39).contains(s.value) || (0x0A59...0x0A5E).contains(s.value)
    }
}
