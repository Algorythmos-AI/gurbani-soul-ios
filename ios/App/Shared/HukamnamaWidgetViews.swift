import SwiftUI
import WidgetKit

/// The "Hukamnama · Sri Harmandir Sahib" widget's face, every family. It lives in Shared/ (not
/// the extension) so the unit tests render THIS view, not a mirror of it.
///
/// Fidelity: the verse is the entry's `opening_gurmukhi`, which our server copied from our own
/// corpus; it is drawn verbatim in ink Sant Lipi, and never cut: each layout offers the whole
/// verse first and, when it cannot fit whole, drops it rather than show a fragment
/// (`ViewThatFits`). A corpus-fingerprint mismatch shows the Ang and date only. The citation is
/// always the full "Sri Guru Granth Sahib Ji · Ang N" on the Home Screen. Never called the Hukam
/// of the day (G3 R6).
struct HukamnamaWidgetView: View {
    let entry: HukamnamaTimeline.Entry
    let family: WidgetFamily

    static let name = "Hukamnama · Sri Harmandir Sahib"
    static let emptyText = "Turn on the Hukamnama in Gurbani Soul."
    static let notYetText = "Not yet published today"
    static let delayedText = "Delayed today"

    private var shown: HukamnamaEntry? { HukamnamaTimeline.shown(entry.state) }
    private var verse: String? { entry.verseShown ? shown?.openingGurmukhi : nil }
    /// Today's or the still-current Hukamnama reads at full strength; a previous one is dimmed.
    private var isCurrent: Bool {
        switch entry.state {
        case .today, .current: return true
        default: return false
        }
    }
    private var status: String? {
        switch entry.state {
        case .notYet: return Self.notYetText
        case .delayed: return Self.delayedText
        default: return nil
        }
    }
    private var dateLabel: String? { shown.flatMap { AmritsarDate.label($0.amritsarDate) } }
    private var url: URL? { shown?.url ?? URL(string: "sggs://hukamnama") }

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
        default: home(large: family == .systemLarge)
        }
    }

    // MARK: Home Screen

    private func home(large: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                Eyebrow(text: Self.name)
                Spacer(minLength: 4)
                Mark(size: large ? 22 : 16)
            }
            if let status { statusLine(status).padding(.top, 6) }
            if let shown {
                Spacer(minLength: large ? 12 : 6)
                if let verse {
                    wholeVerse(verse, sizes: large ? [26, 22, 19] : [21, 18, 16], lineSpacing: large ? 8 : 5)
                        .opacity(isCurrent ? 1 : 0.55)
                }
                Spacer(minLength: large ? 12 : 6)
                if let ang = shown.ang {
                    Citation(ang: ang, action: large ? "Tap to read the shabad" : "Tap to read")
                }
                if let dateLabel { dateLine(dateLabel).padding(.top, 4) }
            } else {
                Spacer(minLength: 8)
                Text(Self.emptyText).font(.system(size: 13)).foregroundStyle(.secondary)
                Spacer(minLength: 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 1) {
                    Eyebrow(text: "Hukamnama")
                    Text("Sri Harmandir Sahib").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 2)
                Mark(size: 14)
            }
            if let status { statusLine(status).padding(.top, 4) }
            if let shown {
                Spacer(minLength: 4)
                if let verse {
                    wholeVerse(verse, sizes: [16, 14], lineSpacing: 3).opacity(isCurrent ? 1 : 0.55)
                }
                Spacer(minLength: 4)
                if let ang = shown.ang { Citation(ang: ang) }
                if let dateLabel { dateLine(dateLabel).padding(.top, 2) }
            } else {
                Spacer(minLength: 4)
                Text(Self.emptyText).font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer(minLength: 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// The verse, whole, at the first size that fits; nothing at all when none does.
    private func wholeVerse(_ text: String, sizes: [CGFloat], lineSpacing: CGFloat) -> some View {
        ViewThatFits(in: .vertical) {
            ForEach(sizes, id: \.self) { size in
                Text(text)
                    .font(WidgetType.gurmukhi(size))
                    .lineSpacing(lineSpacing)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(Text(punjabi(text)))
            }
            Color.clear.frame(height: 0)
        }
    }

    private func statusLine(_ text: String) -> some View {
        Text(text).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
    }

    private func dateLine(_ text: String) -> some View {
        Text(text).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).padding(.leading, 30)
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
            Text(angText ?? "Hukamnama").font(.system(size: 13, weight: .semibold))
            ViewThatFits(in: .vertical) {
                if let verse, isCurrent {
                    Text(verse).font(WidgetType.gurmukhi(13))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel(Text(punjabi(verse)))
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
