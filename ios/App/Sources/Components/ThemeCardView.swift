import SwiftUI
import GurbaniSearchKit

/// Where a theme falls in reading order, at a glance: 15 bars of 100 Angs (the Constellation's Ang
/// strip in miniature). Decorative — the card's text and VoiceOver label carry the same fact.
struct AngSparkline: View {
    let bins: [Int]
    let color: Color
    var height: CGFloat = 18

    var body: some View {
        let peak = max(bins.max() ?? 1, 1)
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(Array(bins.enumerated()), id: \.offset) { _, n in
                RoundedRectangle(cornerRadius: 1)
                    .fill(color.opacity(n == 0 ? 0.18 : 0.85))
                    .frame(height: n == 0 ? 2 : max(3, height * CGFloat(n) / CGFloat(peak)))
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: height, alignment: .bottom)
        .accessibilityHidden(true)
    }
}

/// One theme in the Themes index: its family colour, English name, Gurmukhi headword (Sant Lipi,
/// verbatim), the description's opening phrase, where it falls in the Granth, and honest counts.
struct ThemeCardView: View {
    enum Style: String { case grid, row }
    let row: ThemeIndexRow
    var style: Style = .grid
    @Environment(\.palette) private var palette

    private var color: Color { ThemeGroup.color(row.concept) }

    var body: some View {
        switch style {
        case .grid: grid
        case .row: compact
        }
    }

    private var grid: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                Text(ConceptName.display(row.concept))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
            if let head = row.headword {
                GurmukhiText(verbatim: head, size: 20)
                    .foregroundStyle(.primary)
            }
            let g = ThemeIndexModel.gloss(row.description)
            if !g.isEmpty {
                Text(g)
                    .font(.caption).foregroundStyle(Ink.muted)
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)
            }
            AngSparkline(bins: row.angBins, color: color)
                .padding(.top, 2)
            Text("\(row.nVerses.formatted()) verses · \(row.nShabads.formatted()) shabads")
                .font(.caption2.weight(.medium).monospacedDigit())
                .foregroundStyle(palette.accentText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Space.m)
        .padding(.leading, 4)
        .background(Ink.card, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
        .overlay(alignment: .leading) {
            // the family colour as an edge accent, never as the text colour of the scripture
            Rectangle().fill(color).frame(width: 4).accessibilityHidden(true)
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(Ink.hairline))
        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
    }

    private var compact: some View {
        HStack(alignment: .center, spacing: Theme.Space.m) {
            Circle().fill(color).frame(width: 10, height: 10).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                    Text(ConceptName.display(row.concept)).font(.body.weight(.semibold)).foregroundStyle(.primary)
                    if let head = row.headword { GurmukhiText(verbatim: head, size: 18).foregroundStyle(.primary) }
                }
                Text("\(row.nVerses.formatted()) verses · \(row.nShabads.formatted()) shabads")
                    .font(.caption.monospacedDigit()).foregroundStyle(Ink.muted)
            }
            Spacer(minLength: Theme.Space.s)
            AngSparkline(bins: row.angBins, color: color, height: 14).frame(width: 64)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Ink.muted)
                .accessibilityHidden(true)
        }
        .padding(.vertical, Theme.Space.s)
        .contentShape(Rectangle())
    }
}
