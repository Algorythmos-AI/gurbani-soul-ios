import SwiftUI
import WidgetKit

/// The "Hukamnama · Sri Harmandir Sahib" widget's face, every family. It lives in Shared/ (not
/// the extension) so the unit tests render THIS view, not a mirror of it.
///
/// It reads like the letter it is: the name and the Amritsar date at the head, the verse, and the
/// citation at the foot — the same order as the app's Hukamnama sheet. The large size adds the
/// opening verse's transliteration and the shabad's ਰਹਾਉ couplet under a gold rule, as the sheet
/// marks it.
///
/// Fidelity: the opening verse and the ਰਹਾਉ lines are the entry's `opening_gurmukhi` /
/// `rahao_gurmukhi`, which our server copied from our own corpus; they are drawn verbatim in ink
/// Sant Lipi and never cut. Every layout offers whole text first and, when it cannot fit whole,
/// steps down (smaller type, then fewer parts) and finally drops the verse rather than show a
/// fragment (`ViewThatFits`). A corpus-fingerprint mismatch shows the Ang and date only. The
/// citation is always the full "Sri Guru Granth Sahib Ji · Ang N" on the Home Screen. Never
/// called the Hukam of the day (G3 R6).
struct HukamnamaWidgetView: View {
    let entry: HukamnamaTimeline.Entry
    let family: WidgetFamily

    static let name = "Hukamnama · Sri Harmandir Sahib"
    static let emptyText = "Turn on the Hukamnama in Gurbani Soul."
    static let notYetText = "Not yet published today"
    static let delayedText = "Delayed today"
    /// The sheet's own label under the refrain (`LineRow`), reused so the two read alike.
    static let rahaoLabel = "ਰਹਾਉ · refrain"

    /// The citation's point size per family (the render tests measure it at this size).
    static func citationSize(_ family: WidgetFamily) -> CGFloat { family == .systemSmall ? 10.5 : 12 }

    @Environment(\.widgetRenderingMode) private var renderingMode

    private var shown: HukamnamaEntry? { HukamnamaTimeline.shown(entry.state) }
    private var verse: String? { entry.verseShown ? shown?.openingGurmukhi : nil }
    private var rahao: [String] { entry.verseShown ? (shown?.rahaoLines ?? []) : [] }
    private var translit: String? {
        guard entry.verseShown, let t = shown?.openingTranslit?.trimmingCharacters(in: .whitespaces),
              !t.isEmpty else { return nil }
        return t
    }
    /// A shabad that opens with its ਰਹਾਉ: the couplet IS the opening, so it is drawn once, marked.
    private var opensWithRahao: Bool { verse != nil && rahao.first == verse }
    /// Today's or the still-current Hukamnama reads at full strength; a previous one is dimmed.
    private var isCurrent: Bool {
        switch entry.state {
        case .today, .current: return true
        default: return false
        }
    }
    private var isToday: Bool { if case .today = entry.state { return true } else { return false } }
    private var status: String? {
        switch entry.state {
        case .notYet: return Self.notYetText
        case .delayed: return Self.delayedText
        default: return nil
        }
    }
    private var dateLabel: String? { shown.flatMap { AmritsarDate.label($0.amritsarDate) } }
    private var shortDate: String? { shown.flatMap { AmritsarDate.shortLabel($0.amritsarDate) } }
    private var url: URL? { shown?.url ?? URL(string: "sggs://hukamnama") }
    private var fullColor: Bool { renderingMode == .fullColor }
    /// Today's date reads in ink, an older one in grey: the gold stays with the name and the marks.
    private var dateStyle: AnyShapeStyle { isToday ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary) }

    var body: some View {
        content
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .widgetURL(url)
    }

    @ViewBuilder private var content: some View {
        switch family {
        case .accessoryInline: inline
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        case .systemSmall: small
        case .systemLarge: large
        default: medium
        }
    }

    // MARK: Home Screen — shared pieces

    /// The head of the letter: the name, then the Amritsar date (ink when it is today's) and,
    /// when nothing new has come, the status beside it.
    private func head(markSize: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .center) {
                Eyebrow(text: Self.name).widgetAccentable()
                Spacer(minLength: 4)
                Mark(size: markSize).widgetAccentable()
            }
            dateAndStatus
        }
    }

    @ViewBuilder private var dateAndStatus: some View {
        if dateLabel != nil || status != nil {
            HStack(spacing: 0) {
                if let dateLabel {
                    Text(dateLabel)
                        .font(.system(size: 11, weight: isToday ? .medium : .regular))
                        .foregroundStyle(dateStyle)
                }
                if dateLabel != nil, status != nil {
                    Text("  ·  ").font(.system(size: 11)).foregroundStyle(.tertiary)
                }
                if let status {
                    Text(status).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.85)
        }
    }

    /// A verse line, verbatim. Its closing marker run (॥, ॥੧॥, ਰਹਾਉ ॥) is bound to the word before
    /// it for display only (`VerseTypography`, as the reader does), so a lone ॥ never wraps onto a
    /// line of its own; VoiceOver reads the verbatim line.
    private func gurmukhi(_ text: String, size: CGFloat, lineSpacing: CGFloat) -> some View {
        Text(VerseTypography.bindingClosingMarkers(text))
            .font(WidgetType.gurmukhi(size))
            .lineSpacing(lineSpacing)
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(Text(punjabi(text)))
    }

    /// The ਰਹਾਉ couplet: a gold rule down its side and, when there is room, the sheet's label.
    private func rahaoBlock(size: CGFloat, label: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(fullColor ? AnyShapeStyle(AccentPalette.brandDefault.accentFill) : AnyShapeStyle(.primary))
                .frame(width: 3)
                .widgetAccentable()
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: size * 0.35) {
                ForEach(Array(rahao.enumerated()), id: \.offset) { _, line in
                    gurmukhi(line, size: size, lineSpacing: size * 0.25)
                }
                if label {
                    Text(Self.rahaoLabel)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var emptyBody: some View {
        Text(Self.emptyText).font(.system(size: 13)).foregroundStyle(.secondary)
    }

    // MARK: Large — the opening verse, its transliteration, and the ਰਹਾਉ

    private var large: some View {
        VStack(alignment: .leading, spacing: 0) {
            head(markSize: 22)
            if let shown {
                Spacer(minLength: 12)
                largeVerse.opacity(isCurrent ? 1 : 0.55)
                Spacer(minLength: 12)
                if let ang = shown.ang {
                    Citation(ang: ang, action: "Tap to read the shabad", size: Self.citationSize(family))
                }
            } else {
                Spacer(minLength: 8)
                emptyBody
                Spacer(minLength: 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Whole parts only, richest first: verse + transliteration + ਰਹਾਉ, then smaller type, then
    /// without the transliteration, then without the ਰਹਾਉ, then nothing.
    @ViewBuilder private var largeVerse: some View {
        if let verse {
            ViewThatFits(in: .vertical) {
                if opensWithRahao {
                    ForEach([24, 22, 20, 18] as [CGFloat], id: \.self) { rahaoBlock(size: $0, label: true) }
                } else if !rahao.isEmpty {
                    largeStack(verse, size: 25, translit: true, rahaoSize: 19)
                    largeStack(verse, size: 23, translit: true, rahaoSize: 18)
                    largeStack(verse, size: 22, translit: false, rahaoSize: 17)
                    largeStack(verse, size: 20, translit: false, rahaoSize: 16)
                }
                largeStack(verse, size: 26, translit: true, rahaoSize: nil)
                largeStack(verse, size: 23, translit: false, rahaoSize: nil)
                largeStack(verse, size: 20, translit: false, rahaoSize: nil)
                Color.clear.frame(height: 0)
            }
        }
    }

    private func largeStack(_ verse: String, size: CGFloat, translit showTranslit: Bool, rahaoSize: CGFloat?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            gurmukhi(verse, size: size, lineSpacing: size * 0.3)
            if showTranslit, let translit {
                Text(translit)
                    .font(.system(size: 12))
                    .italic()
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
                    .accessibilityHidden(true)
            }
            if let rahaoSize {
                rahaoBlock(size: rahaoSize, label: true).padding(.top, 16)
            }
        }
    }

    // MARK: Medium — the opening verse

    private var medium: some View {
        VStack(alignment: .leading, spacing: 0) {
            head(markSize: 16)
            if let shown {
                Spacer(minLength: 6)
                if let verse {
                    ViewThatFits(in: .vertical) {
                        if opensWithRahao {
                            ForEach([20, 18, 16] as [CGFloat], id: \.self) { rahaoBlock(size: $0, label: false) }
                        }
                        ForEach([21, 19, 17, 15] as [CGFloat], id: \.self) {
                            gurmukhi(verse, size: $0, lineSpacing: $0 * 0.25)
                        }
                        Color.clear.frame(height: 0)
                    }
                    .opacity(isCurrent ? 1 : 0.55)
                }
                Spacer(minLength: 6)
                if let ang = shown.ang {
                    Citation(ang: ang, action: "Tap to read", size: Self.citationSize(family))
                }
            } else {
                Spacer(minLength: 8)
                emptyBody
                Spacer(minLength: 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Small — the opening verse, when it fits whole

    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Eyebrow(text: "Hukamnama").widgetAccentable()
                Spacer(minLength: 2)
                Mark(size: 13).widgetAccentable()
            }
            Text("Sri Harmandir Sahib").font(.system(size: 9.5)).foregroundStyle(.secondary)
                .lineLimit(1).padding(.top, 1)
            if let shown {
                if let status {
                    Text(status).font(.system(size: 9.5, weight: .medium)).foregroundStyle(.secondary)
                        .lineLimit(1).minimumScaleFactor(0.8).padding(.top, 2)
                }
                Spacer(minLength: 4)
                if let verse {
                    ViewThatFits(in: .vertical) {
                        ForEach([16, 15, 14, 13, 12] as [CGFloat], id: \.self) {
                            gurmukhi(verse, size: $0, lineSpacing: 2)
                        }
                        Color.clear.frame(height: 0)
                    }
                    .opacity(isCurrent ? 1 : 0.55)
                }
                Spacer(minLength: 4)
                if let ang = shown.ang {
                    Citation(ang: ang, size: Self.citationSize(family))
                }
                if let shortDate {
                    Text(shortDate)
                        .font(.system(size: 9.5, weight: isToday ? .medium : .regular))
                        .foregroundStyle(dateStyle)
                        .lineLimit(1)
                        .padding(.leading, 30).padding(.top, 2)
                }
            } else {
                Spacer(minLength: 4)
                Text(Self.emptyText).font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer(minLength: 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Lock Screen

    private var angText: String? { shown?.ang.map { "Hukamnama · Ang \(String($0))" } }

    private var inline: some View {
        Text(angText ?? "Hukamnama")
    }

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            if let ang = shown?.ang {
                VStack(spacing: 0) {
                    Text("Ang").font(.system(size: 9, weight: .medium))
                    Text(String(ang)).font(.system(size: 16, weight: .semibold)).minimumScaleFactor(0.6)
                }
            } else {
                Text("ੴ").font(WidgetType.gurmukhi(20)).accessibilityLabel("Hukamnama")
            }
        }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(angText ?? "Hukamnama").font(.system(size: 13, weight: .semibold)).widgetAccentable()
            ViewThatFits(in: .vertical) {
                if let verse, isCurrent {
                    ForEach([14, 13, 12] as [CGFloat], id: \.self) { size in
                        Text(VerseTypography.bindingClosingMarkers(verse)).font(WidgetType.gurmukhi(size))
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityLabel(Text(punjabi(verse)))
                    }
                }
                Text(status ?? dateLabel ?? "Sri Harmandir Sahib").font(.system(size: 12))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func punjabi(_ s: String) -> AttributedString {
        var a = AttributedString(s); a.languageIdentifier = "pa"; return a
    }
}
