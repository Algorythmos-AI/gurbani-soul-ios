import SwiftUI
import GurbaniSearchKit

/// A Vaar at a glance: every salok and pauri in reading order, as one bar. Each segment's width
/// is its share of the Vaar's lines and its colour is its voice; pauris stand full height, saloks
/// sit lower, so the rhythm of the ballad — saloks, then the pauri they lead into — is visible
/// before a word is read. One Canvas, no per-segment views (a Vaar can hold 110 units).
struct VoiceStrip: View {
    let text: VaarText
    var height: CGFloat = 14
    /// The unit to ring (reading position), if any.
    var highlight: Int? = nil

    var body: some View {
        Canvas { ctx, size in
            let segments = Self.layout(text, width: size.width)
            for s in segments {
                let unit = text.units[s.index]
                let h = unit.kind == .pauri ? size.height : size.height * 0.55
                let rect = CGRect(x: s.x, y: (size.height - h) / 2, width: s.width, height: h)
                let shape = Path(roundedRect: rect, cornerRadius: min(2, s.width / 2))
                ctx.fill(shape, with: .color(VoiceInk.color(for: unit.author)))
                if s.index == highlight {
                    ctx.stroke(Path(roundedRect: rect.insetBy(dx: -1.5, dy: -1.5), cornerRadius: 3),
                               with: .color(.primary), lineWidth: 1.5)
                }
            }
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.summary(text))
    }

    struct Segment: Equatable { let index: Int; let x: CGFloat; let width: CGFloat }

    /// Widths ∝ unit length, a 1-pt gap between units while every unit keeps ≥1 pt; at widths too
    /// small for gaps the units simply abut. Pure (unit-tested): total extent == `width`.
    static func layout(_ text: VaarText, width: CGFloat) -> [Segment] {
        let n = text.units.count
        guard n > 0, width > 0 else { return [] }
        let total = CGFloat(text.units.reduce(0) { $0 + max($1.lines.count, 1) })
        let gap: CGFloat = width - CGFloat(n - 1) >= CGFloat(n) * 2 ? 1 : 0
        let usable = width - gap * CGFloat(n - 1)
        var x: CGFloat = 0
        var out: [Segment] = []
        for (i, u) in text.units.enumerated() {
            let w = i == n - 1 ? max(width - x, 0) : usable * CGFloat(max(u.lines.count, 1)) / total
            out.append(Segment(index: i, x: x, width: w))
            x += w + gap
        }
        return out
    }

    /// "21 pauris by Guru Ram Das Ji (M4); 43 saloks by 4 voices."
    static func summary(_ t: VaarText) -> String {
        let pauriVoices = Set(t.pauris.compactMap(\.author))
        let salokVoices = Set(t.units.filter { $0.kind == .salok }.compactMap(\.author))
        func n(_ k: Int, _ word: String) -> String { "\(k) \(word)\(k == 1 ? "" : "s")" }
        func by(_ v: Set<String>) -> String { v.count == 1 ? v.first! : n(v.count, "voice") }
        var parts = [n(t.nPauris, "pauri") + " by " + by(pauriVoices)]
        if t.nSaloks > 0 { parts.append(n(t.nSaloks, "salok") + " by " + by(salokVoices)) }
        return parts.joined(separator: "; ")
    }
}

/// Up to five overlapping voice dots and a count — replaces the old "cross-voice" jargon badge.
struct VoiceDots: View {
    let voices: [String]
    var body: some View {
        HStack(spacing: Theme.Space.xs) {
            HStack(spacing: -3) {
                ForEach(Array(voices.prefix(5).enumerated()), id: \.offset) { _, v in
                    Circle().fill(VoiceInk.color(for: v))
                        .frame(width: 10, height: 10)
                        .overlay(Circle().strokeBorder(Ink.card, lineWidth: 1.5))
                }
            }
            Text(voices.count == 1 ? "1 voice" : "\(voices.count) voices")
                .font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(voices.count == 1 ? "One voice: \(voices[0])" : "\(voices.count) voices: \(voices.joined(separator: ", "))")
    }
}

/// The Ang span of a Vaar: "Ang 1193" for a single Ang, "Angs 137–150" otherwise.
func angSpan(_ first: Int, _ last: Int) -> String {
    first == last ? "Ang \(first)" : "Angs \(first)–\(last)"
}
