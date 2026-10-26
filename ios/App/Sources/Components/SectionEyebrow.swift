import SwiftUI

/// A small accent eyebrow — the app's section-header voice, in sentence case as the brand book asks
/// ("No all-caps. Emphasis by weight"): the text is shown and spoken exactly as written. (The widget
/// `Eyebrow` is a fixed 10 pt and hidden from accessibility, so it isn't reused here.) Scales to
/// AX5, honours the chosen accent, and reads as a header to VoiceOver.
struct SectionEyebrow: View {
    let text: String
    var symbol: String? = nil
    @Environment(\.palette) private var palette
    var body: some View {
        HStack(spacing: 5) {
            if let symbol {
                Image(systemName: symbol).font(.caption.weight(.semibold))
            }
            Text(text).font(.caption.weight(.semibold))
        }
        .foregroundStyle(palette.accentText)
        .accessibilityAddTraits(.isHeader)
    }
}
