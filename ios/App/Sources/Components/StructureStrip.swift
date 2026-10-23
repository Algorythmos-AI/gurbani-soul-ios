import SwiftUI

/// A composition's shape on its card: one segment per printed step (Sukhmani's 24 ashtapadis,
/// Sidh Gosht's 73 pauris), each as long as its verses, filling gold as it is read. The card
/// teaches the work's structure and shows progress in one line. With no trustworthy outline it
/// is a plain progress bar. Decorative — the card's accessibility label says the same in words.
struct StructureStrip: View {
    let shape: CompositionShape
    /// The saved reading position (`BaniProgress.lastSeq`), nil when not started.
    let seq: Int?
    let completed: Bool
    var height: CGFloat = 6
    @Environment(\.palette) private var palette

    var body: some View {
        Canvas { ctx, size in
            if shape.steps.isEmpty {
                drawBar(ctx, size)
            } else {
                drawSteps(ctx, size)
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }

    private func drawSteps(_ ctx: GraphicsContext, _ size: CGSize) {
        let n = shape.steps.count
        // Gaps shrink (to none) before the strip could ever overrun its width.
        var gap: CGFloat = n > 40 ? 0.75 : 1.5
        if gap * CGFloat(n - 1) > size.width / 3 { gap = 0 }
        let total = CGFloat(shape.steps.reduce(0) { $0 + $1.length })
        let usable = max(0, size.width - gap * CGFloat(n - 1))
        let fills = shape.fill(at: seq, completed: completed)
        var x: CGFloat = 0
        for (i, s) in shape.steps.enumerated() {
            // Exactly proportional, so the steps sum to `usable` and never pass the edge.
            let w = usable * CGFloat(s.length) / max(total, 1)
            let r = CGRect(x: x, y: 0, width: w, height: size.height)
            ctx.fill(Path(roundedRect: r, cornerRadius: min(2, w / 2)), with: .color(Ink.raised))
            let f = fills[i]
            if f > 0 {
                let fr = CGRect(x: x, y: 0, width: w * CGFloat(f), height: size.height)
                ctx.fill(Path(roundedRect: fr, cornerRadius: min(2, w / 2)), with: .color(palette.accent))
            }
            x += w + gap
        }
    }

    private func drawBar(_ ctx: GraphicsContext, _ size: CGSize) {
        let track = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: size.height / 2)
        ctx.fill(track, with: .color(Ink.raised))
        let span = max(1, shape.lastSeq - shape.firstSeq + 1)
        let f: Double = completed ? 1 : seq.map { min(1, max(0, Double($0 - shape.firstSeq + 1) / Double(span))) } ?? 0
        if f > 0 {
            let r = CGRect(x: 0, y: 0, width: max(size.height, size.width * f), height: size.height)
            ctx.fill(Path(roundedRect: r, cornerRadius: size.height / 2), with: .color(palette.accent))
        }
    }
}
