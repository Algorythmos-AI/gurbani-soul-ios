import SwiftUI
import GurbaniSearchKit

/// One whole verse, verbatim, with its full citation — the Theme of the day's verse, shared by the
/// Themes index and the Explore hub so both quote it identically. The Gurmukhi is never cut
/// (`GurmukhiText` claims its full wrapped height); tapping opens the shabad it belongs to.
struct VerseQuoteBlock: View {
    let line: SearchLine
    /// Appends "· a Rahao line" to the citation when the verse is a refrain.
    var isRefrain = false
    var size: CGFloat = 22
    @Environment(AppContainer.self) private var container
    @Environment(\.palette) private var palette

    var body: some View {
        Button {
            Haptics.tap()
            container.present(.shabad(compId: line.compId, focusLineId: line.id))
        } label: {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                GurmukhiText(verbatim: line.gurmukhi, size: size).foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                if !line.translit.isEmpty {
                    Text(line.translit).font(.callout).foregroundStyle(Ink.muted)
                        .multilineTextAlignment(.leading)
                }
                Text("Sri Guru Granth Sahib Ji · Ang \(String(line.ang))\(isRefrain ? " · a Rahao line" : "")")
                    .font(.caption).foregroundStyle(palette.accentText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the shabad")
    }
}
