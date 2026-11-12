import SwiftUI

/// A heading line (raag · mahala · ghar label, a Sri Dasam Granth chhand title, or the ੴ
/// invocation), one style everywhere: Sant Lipi ExtraBold a step above the verse labels, centred,
/// ink, verbatim, with an optional gold hairline above (a heading that follows verses) and its
/// transliteration small and centred underneath. The invocation is set at full verse size.
struct VerseHeading: View {
    let verbatim: String
    var translit: String = ""
    /// Draw the short gold rule above — the caller sets it for a heading that opens a new run
    /// after verses, never for the second of two stacked headings.
    var rule: Bool = false
    @AppStorage("sggs_translit") private var translitPref = true
    @Environment(\.palette) private var palette

    var body: some View {
        let invocation = VerseTypography.isInvocation(verbatim)
        VStack(spacing: Theme.Space.xs) {
            if rule {
                Capsule().fill(palette.accent.opacity(0.7)).frame(width: 44, height: 1.5)
                    .padding(.bottom, Theme.Space.s)
                    .accessibilityHidden(true)
            }
            GurmukhiText(verbatim: verbatim, size: invocation ? 24 : 21, weight: .heavy)
                .multilineTextAlignment(.center)
            if translitPref && !translit.isEmpty {
                Text(translit).font(.footnote).tracking(0.2).foregroundStyle(Ink.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(true)          // a reading aid, not scripture
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, rule ? Theme.Space.l : Theme.Space.xs)
        .padding(.bottom, Theme.Space.xs)
        // One element: the verbatim heading spoken in Punjabi, announced as a heading.
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("verseHeading")
    }
}

extension View {
    /// Constrain to the reading measure and centre it (no effect on iPhone widths).
    func readingColumn() -> some View {
        frame(maxWidth: VerseTypography.readingColumn).frame(maxWidth: .infinity)
    }
}
