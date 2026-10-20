import SwiftUI

/// The Reader's "AA" options — text size front and centre (elders resize here, not buried in
/// Settings), then what the page shows, then Sehaj focus. Bound to the same `sggs_gurmukhi_size`
/// key as Settings, so the choice is one setting everywhere. Presented as a compact popover.
struct ReaderOptionsPopover: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    @Environment(AppContainer.self) private var container
    @AppStorage("sggs_gurmukhi_size") private var gurmukhiSize = 24.0
    @AppStorage("sggs_translit") private var showTranslit = true
    @AppStorage("sggs_show_english") private var showEnglish = true
    @AppStorage("sggs_show_timing") private var showTiming = true
    @AppStorage("sggs_focus_mode") private var focusMode = false

    private let range = 18.0...32.0
    private let step = 2.0
    private let defaultSize = 24.0
    private var steps: Int { Int((range.upperBound - range.lowerBound) / step) + 1 }
    private var stepIndex: Int { Int(((gurmukhiSize - range.lowerBound) / step).rounded()) }

    /// A plain-language name for the size, so "bigger" has a word, not just a number.
    private var sizeName: String {
        switch gurmukhiSize {
        case ..<21: "Small"
        case ..<25: "Standard"
        case ..<28: "Large"
        case ..<31: "Larger"
        default: "Largest"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            // MARK: text size
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                HStack {
                    Text("Text size").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Text(sizeName).font(.subheadline.weight(.semibold)).foregroundStyle(palette.accentText)
                        .accessibilityIdentifier("textSizeName")
                }
                HStack(spacing: Theme.Space.m) {
                    sizeButton("A", delta: -step, disabled: gurmukhiSize <= range.lowerBound, label: "Smaller")
                    // live sample at the current size — a whole phrase, so the reader judges a line
                    Text("ੴ ਸਤਿ ਨਾਮੁ").font(Brand.gurmukhi(gurmukhiSize, relativeTo: .title3))
                        .lineLimit(1).minimumScaleFactor(0.6)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .accessibilityLabel("Sample, \(sizeName), \(Int(gurmukhiSize)) point")
                    sizeButton("A", delta: +step, disabled: gurmukhiSize >= range.upperBound, label: "Larger", big: true)
                }
                HStack(spacing: 6) {
                    ForEach(0..<steps, id: \.self) { i in
                        Capsule().fill(i <= stepIndex ? palette.accent : Ink.hairline)
                            .frame(height: 4)
                    }
                }
                .accessibilityHidden(true)
                if gurmukhiSize != defaultSize {
                    Button("Reset to standard") { Haptics.tap(); gurmukhiSize = defaultSize }
                        .font(.footnote.weight(.medium)).foregroundStyle(palette.accentText)
                        .accessibilityIdentifier("textSizeReset")
                }
            }

            Divider()

            // MARK: what the page shows
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                optionToggle("Transliteration", detail: "Roman letters under each line",
                             systemImage: "character.textbox", isOn: $showTranslit, id: "translitToggle")
                if container.corpus?.capabilities.hasEnglish == true {
                    optionToggle("English translation", detail: "A separate, labelled layer",
                                 systemImage: "text.bubble", isOn: $showEnglish, id: "englishToggle")
                }
                if container.corpus?.capabilities.hasTiming == true {
                    optionToggle("Raag timing", detail: "The watch of the day for this raag",
                                 systemImage: "clock", isOn: $showTiming, id: "timingToggle")
                }
            }
            .disabled(focusMode)
            .opacity(focusMode ? 0.45 : 1)

            // MARK: Sehaj focus
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                optionToggle("Sehaj focus", detail: "Only the Gurmukhi, with room to breathe. Bars and tabs step aside.",
                             systemImage: "leaf", isOn: $focusMode, id: "sehajToggle")
            }
            .padding(Theme.Space.m)
            .background(palette.wash, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(focusMode ? palette.accent : Ink.hairline))
        }
        .padding(Theme.Space.l)
        .frame(minWidth: 320, idealWidth: 340)
        .presentationCompactAdaptation(.popover)
        .appAnimation(value: focusMode)
    }

    private func optionToggle(_ title: String, detail: String, systemImage: String,
                              isOn: Binding<Bool>, id: String) -> some View {
        Toggle(isOn: isOn) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                Image(systemName: systemImage).foregroundStyle(palette.accent)
                    .frame(width: 22).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .tint(palette.accent)
        .accessibilityIdentifier(id)
    }

    private func sizeButton(_ glyph: String, delta: Double, disabled: Bool, label: String, big: Bool = false) -> some View {
        Button {
            Haptics.tap()
            gurmukhiSize = min(max(range.lowerBound, gurmukhiSize + delta), range.upperBound)
        } label: {
            Text(glyph)
                .font(.system(size: big ? 26 : 16, weight: .semibold))
                .frame(width: 56, height: 56)
                .background(Ink.card, in: RoundedRectangle(cornerRadius: Theme.Radius.chip))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.chip).strokeBorder(Ink.hairline))
        }
        .buttonStyle(.pressableCard)
        .disabled(disabled)
        .accessibilityLabel(label)
        .accessibilityIdentifier(delta < 0 ? "textSmaller" : "textLarger")
    }
}
