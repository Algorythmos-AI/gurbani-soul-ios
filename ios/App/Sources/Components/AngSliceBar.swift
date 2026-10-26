import SwiftUI
import GurbaniSearchKit

/// A hairline map of all 1,430 Angs with one span lit: where a raag or bani sits in the saroop and
/// how much of it it fills, at a glance (Gauri's 196 Angs vs Jaijavanti's 2). Decorative — the
/// owning control's accessibility label carries the Ang range in words.
struct AngSliceBar: View {
    let first: Int
    let last: Int
    var total: Int = GranthAngs.count
    var height: CGFloat = 4
    @Environment(\.palette) private var palette

    var body: some View {
        Canvas { ctx, size in
            let track = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: size.height / 2)
            ctx.fill(track, with: .color(StructureStrip.unread))
            let r = Self.sliceRect(first: first, last: last, total: total, width: size.width, height: size.height)
            ctx.fill(Path(roundedRect: r, cornerRadius: size.height / 2), with: .color(palette.accent))
        }
        .frame(height: height)
        .overlay(Capsule().strokeBorder(Ink.hairline, lineWidth: 0.5))
        .accessibilityHidden(true)
    }

    /// The lit rectangle: Ang n occupies [n-1, n) of `total`, never thinner than `minWidth` so a
    /// two-Ang raag is still visible, and clamped inside the track.
    static func sliceRect(first: Int, last: Int, total: Int, width: CGFloat, height: CGFloat,
                          minWidth: CGFloat = 3) -> CGRect {
        guard total > 0, width > 0 else { return .zero }
        let lo = CGFloat(max(1, min(first, last)) - 1) / CGFloat(total)
        let hi = CGFloat(min(total, max(first, last))) / CGFloat(total)
        var x = lo * width
        var w = max((hi - lo) * width, min(minWidth, width))
        if x + w > width { x = max(0, width - w) }
        w = min(w, width)
        return CGRect(x: x, y: 0, width: w, height: height)
    }
}
