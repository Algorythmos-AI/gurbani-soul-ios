import SwiftUI

// The Explore hub's card previews: small, still, truthful pictures of the screens they open. Each
// is one Canvas over data the hub already holds (no query of its own), draws no text (words stay in
// SwiftUI `Text` beside it, where Dynamic Type reaches them) and is hidden from VoiceOver — the
// card's accessibility value says the same facts in words. The interactive originals
// (SaroopRibbon, VaarSpanRibbon, VoicesDotField) are left untouched.

/// The saroop in miniature: every bani and raag end to end in proportion to its Angs, the major
/// compositions pinned, and the last-read Ang marked — the Index's ribbon, at rest.
struct RibbonGlyph: View {
    let layout: RibbonLayout
    var pins: [Int] = []
    var hereAng: Int?
    @Environment(\.palette) private var palette

    var body: some View {
        Canvas { ctx, size in
            guard layout.length > 0 else { return }
            let scale = size.width / CGFloat(layout.length)
            let pinRoom: CGFloat = pins.isEmpty ? 0 : 7
            let markRoom: CGFloat = hereAng == nil ? 0 : 8
            let bar = CGRect(x: 0, y: pinRoom, width: size.width,
                             height: max(size.height - pinRoom - markRoom, 4))
            let clip = Path(roundedRect: bar, cornerRadius: min(6, bar.height / 3))
            ctx.drawLayer { layer in
                layer.clip(to: clip)
                var raagIndex = 0
                for s in layout.segments {
                    let r = CGRect(x: CGFloat(s.x0) * scale, y: bar.minY,
                                   width: max(CGFloat(s.width) * scale, 0.5), height: bar.height)
                    let fill: Color
                    if s.movement == .raags {
                        fill = palette.accent.opacity(raagIndex.isMultiple(of: 2) ? 0.42 : 0.24)
                        raagIndex += 1
                    } else {
                        fill = Color.primary.opacity(0.30)
                    }
                    layer.fill(Path(r), with: .color(fill))
                    if r.width > 2 {
                        layer.fill(Path(CGRect(x: r.maxX - 0.5, y: bar.minY, width: 0.5, height: bar.height)),
                                   with: .color(Ink.card))
                    }
                }
            }
            ctx.stroke(clip, with: .color(Ink.hairline), lineWidth: 0.5)
            for a in pins {
                guard let x = layout.x(forAng: a) else { continue }
                let cx = CGFloat(x) * scale
                ctx.fill(Path(ellipseIn: CGRect(x: cx - 2.5, y: 0, width: 5, height: 5)), with: .color(palette.accent))
            }
            if let a = hereAng, let x = layout.x(forAng: a) {
                let cx = CGFloat(x) * scale
                var tri = Path()
                tri.move(to: CGPoint(x: cx, y: bar.maxY + 1))
                tri.addLine(to: CGPoint(x: cx - 4, y: bar.maxY + 7))
                tri.addLine(to: CGPoint(x: cx + 4, y: bar.maxY + 7))
                tri.closeSubpath()
                ctx.fill(tri, with: .color(.primary))
            }
        }
        .accessibilityHidden(true)
    }
}

/// Verse lines per raag, one bar each, in saroop order — the order the Granth sets, never sorted
/// by size, so it reads as the shape of the Granth and not as a ranking.
struct RaagMassGlyph: View {
    let mass: [Int]
    @Environment(\.palette) private var palette

    var body: some View {
        Canvas { ctx, size in
            guard let top = mass.max(), top > 0, !mass.isEmpty else { return }
            let gap: CGFloat = mass.count > 1 ? max(1, size.width / CGFloat(mass.count) * 0.25) : 0
            let w = (size.width - gap * CGFloat(mass.count - 1)) / CGFloat(mass.count)
            for (i, n) in mass.enumerated() {
                let h = max(1.5, size.height * CGFloat(n) / CGFloat(top))
                let r = CGRect(x: CGFloat(i) * (w + gap), y: size.height - h, width: w, height: h)
                ctx.fill(Path(roundedRect: r, cornerRadius: min(1.5, w / 2)),
                         with: .color(palette.accent.opacity(i.isMultiple(of: 2) ? 0.62 : 0.40)))
            }
            ctx.fill(Path(CGRect(x: 0, y: size.height - 0.5, width: size.width, height: 0.5)),
                     with: .color(Ink.hairline))
        }
        .accessibilityHidden(true)
    }
}

/// Every verse line as a share of a dot (`DotFieldLayout.linesPerDot` lines each), gathered by
/// tradition and coloured by it — the Voices dot field, at rest. The dot size is the largest that
/// lets the whole field fit the frame, so no voice is ever clipped away.
struct DotGlyph: View {
    let voices: [ExploreDigest.VoiceLines]
    let roster: [String: Contributor]

    var body: some View {
        Canvas { ctx, size in
            guard size.width > 0, !voices.isEmpty else { return }
            let pairs = voices.map { (author: $0.author, lines: $0.lines) }
            var fitted: (layout: DotFieldLayout, dot: CGFloat)?
            for dot in stride(from: CGFloat(5), through: 1.2, by: -0.4) {
                let l = DotFieldLayout.make(voices: pairs, roster: roster, grouping: .tradition,
                                            width: size.width, dot: dot, gap: dot * 0.45, labelHeight: 0)
                fitted = (l, dot)
                if l.size.height <= size.height { break }
            }
            guard let layout = fitted?.layout, let dot = fitted?.dot else { return }
            for (i, p) in layout.positions.enumerated() {
                let rect = CGRect(x: p.x - dot / 2, y: p.y - dot / 2, width: dot, height: dot)
                ctx.fill(Path(ellipseIn: rect), with: .color(layout.dots[i].kind.color))
            }
        }
        .accessibilityHidden(true)
    }
}

/// One mark per Vaar over its Ang span, coloured by its pauri voice — the Vaars home's ribbon, at
/// rest. The axis is the Granth's Ang range from the data, not a typed constant.
struct VaarSpanGlyph: View {
    let marks: [ExploreDigest.VaarMark]
    let angs: ClosedRange<Int>

    var body: some View {
        Canvas { ctx, size in
            let n = CGFloat(max(angs.count - 1, 1))
            let mid = size.height / 2
            ctx.fill(Path(roundedRect: CGRect(x: 0, y: mid - 1, width: size.width, height: 2), cornerRadius: 1),
                     with: .color(Ink.hairline))
            let h = max(size.height * 0.62, 6)
            for m in marks {
                let x0 = CGFloat(m.firstAng - angs.lowerBound) / n * size.width
                let x1 = CGFloat(m.lastAng - angs.lowerBound) / n * size.width
                let w = max(x1 - x0, 3)
                let r = CGRect(x: min(x0, size.width - w), y: mid - h / 2, width: w, height: h)
                ctx.fill(Path(roundedRect: r, cornerRadius: 1.5), with: .color(VoiceInk.color(for: m.pauriAuthor)))
            }
        }
        .accessibilityHidden(true)
    }
}
