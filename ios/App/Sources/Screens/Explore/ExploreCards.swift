import SwiftUI

/// The hub's header: today's date, the one serif hero line, and the Granth's measure — every
/// number derived (`ExploreDigest.mastheadLine`), so a loading page says less, never a guess.
struct ExploreMasthead: View {
    let date: Date
    let line: String
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text(date, format: .dateTime.weekday(.wide).day().month(.wide))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(palette.accentText)
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                GurmukhiText(verbatim: "ੴ", size: 26)
                    .accessibilityHidden(true)
                // "Explore the Granth" is load-bearing: the capture test waits on this text.
                Text("Explore the Granth")
                    .font(Brand.heading(.title3))
                    .accessibilityAddTraits(.isHeader)
            }
            if !line.isEmpty {
                Text(line)
                    .font(.subheadline).foregroundStyle(Ink.muted)
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// How a card draws: today's Feature, a wide card (a full row, or two of three columns) or a
/// square (one column of two or three).
enum ExploreCardForm: Equatable {
    case feature, wide, square
}

/// One destination's card: a preview of the screen it opens, its title, and what the preview shows
/// in words. ONE accessibility element and one button, whose label and identifier are the
/// destination's title (the UI tests' handle), whose value states the preview's facts, and whose
/// hint is the hub's shipped caption.
struct ExploreCard: View {
    let destination: ExploreDestination
    let form: ExploreCardForm
    let digest: ExploreDigest
    let roster: [String: Contributor]

    @Environment(\.palette) private var palette
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Preview heights grow a little with text, capped so a chart never pushes its words away.
    @ScaledMetric(relativeTo: .caption) private var squareHeight: CGFloat = 64
    @ScaledMetric(relativeTo: .caption) private var wideHeight: CGFloat = 40
    @ScaledMetric(relativeTo: .caption) private var featureHeight: CGFloat = 96

    private var accessibilitySize: Bool { dynamicTypeSize.isAccessibilitySize }

    var body: some View {
        NavigationLink(value: destination.route) {
            Card {
                content.frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .buttonStyle(.pressableCard)
        // `.combine` (not `.ignore`) keeps the link's button trait on the merged element, so it
        // is still `app.buttons[title]`; the explicit label/value replace the merged child text.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(destination.title)
        .accessibilityValue(digest.spokenSummary(destination))
        .accessibilityHint(ExploreDigest.legacyCaption(destination))
        .accessibilityIdentifier(destination.title)
    }

    @ViewBuilder private var content: some View {
        switch form {
        case .feature:
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                FeaturedChip()
                titleRow(font: .title2.weight(.semibold))
                preview(height: min(featureHeight, 96 * 1.4))
                captionText
            }
        case .wide:
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                titleRow(font: .headline)
                captionText
                preview(height: min(wideHeight, 40 * 1.4))
                    .padding(.top, Theme.Space.xs)
            }
        case .square:
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                preview(height: min(squareHeight, 64 * 1.4))
                titleRow(font: .headline)
                captionText
            }
        }
    }

    private func titleRow(font: Font) -> some View {
        HStack(spacing: Theme.Space.s) {
            Image(systemName: destination.symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(palette.accent)
            Text(destination.title).font(font).foregroundStyle(.primary)
        }
    }

    private var captionText: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(digest.caption(destination))
                .font(.subheadline).foregroundStyle(Ink.muted)
                .monospacedDigit()
            // At accessibility sizes the words carry what a small chart cannot.
            if accessibilitySize {
                Text(ExploreDigest.legacyCaption(destination))
                    .font(.caption).foregroundStyle(Ink.muted)
            }
        }
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func preview(height: CGFloat) -> some View {
        Group {
            switch destination {
            case .index:
                if let ribbon = digest.ribbon {
                    RibbonGlyph(layout: ribbon, pins: digest.pins, hereAng: digest.lastAng)
                } else { PreviewPlaceholder() }
            case .insights:
                if digest.raagMass.isEmpty { PreviewPlaceholder() } else { RaagMassGlyph(mass: digest.raagMass) }
            case .lineage:
                if digest.voices.isEmpty { PreviewPlaceholder() } else { DotGlyph(voices: digest.voices, roster: roster) }
            case .vaars:
                if let angs = digest.angRange, !digest.vaarMarks.isEmpty {
                    VaarSpanGlyph(marks: digest.vaarMarks, angs: angs)
                } else { PreviewPlaceholder() }
            case .themes, .constellation, .clock:
                SymbolWell(symbol: destination.symbol)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// The one gold moment on the hub: `accentFill` with an `accent` border and `onAccent` label (the
/// ProminentPillStyle recipe) — never the literal gold as text.
private struct FeaturedChip: View {
    @Environment(\.palette) private var palette
    var body: some View {
        Text("Featured today")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(palette.accentFill))
            .overlay(Capsule().strokeBorder(palette.accent))
            .foregroundStyle(palette.onAccent)
    }
}

/// A still block where a preview will be once its data is read: no shimmer, no motion.
private struct PreviewPlaceholder: View {
    var body: some View {
        RoundedRectangle(cornerRadius: Theme.Radius.chip).fill(Ink.raised)
    }
}

/// A quiet well with the destination's symbol, for a card whose live preview is not drawn yet.
private struct SymbolWell: View {
    let symbol: String
    @Environment(\.palette) private var palette
    var body: some View {
        RoundedRectangle(cornerRadius: Theme.Radius.chip)
            .fill(Ink.raised)
            .overlay(
                Image(systemName: symbol)
                    .font(.title2)
                    .foregroundStyle(palette.accent)
            )
    }
}

/// Lays a row of cards out by column span: in a `columns`-wide grid each card gets `span`
/// columns' width, and every card takes the row's tallest height, so cards in a row line up.
struct ExploreSpanRow: Layout {
    let columns: Int
    let spans: [Int]
    var spacing: CGFloat = Theme.Space.m

    private func widths(_ total: CGFloat) -> [CGFloat] {
        let cols = CGFloat(max(columns, 1))
        let unit = max(0, (total - spacing * (cols - 1)) / cols)
        return spans.map { unit * CGFloat($0) + spacing * CGFloat(max($0 - 1, 0)) }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 360
        let ws = widths(width)
        let height = zip(subviews, ws)
            .map { $0.sizeThatFits(ProposedViewSize(width: $1, height: nil)).height }
            .max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        for (view, w) in zip(subviews, widths(bounds.width)) {
            view.place(at: CGPoint(x: x, y: bounds.minY), proposal: ProposedViewSize(width: w, height: bounds.height))
            x += w + spacing
        }
    }
}
