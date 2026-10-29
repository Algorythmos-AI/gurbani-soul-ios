import SwiftUI
import UIKit
import CoreText
import LinkPresentation

// The share system (brand book §6, "Share card"). Every image the app shares is one card: paper,
// the app mark and "Gurbani Soul" at the top, the verse in ink, the gold rule (a fill, with its
// accent edge in light mode), the full citation, the site at the foot. Gold is never text; no red.
// The same design draws gurbanisoul.com's link cards and its "Share as image"
// (sggs-platform frontend/src/og/render.ts, src/scripts/shareimage.ts), so a verse looks the same
// wherever it is shared from.
//
// FIXED-SIZE by design: cards render at 360 pt wide (1080 px at 3×), square unless the verse needs
// more height; Dynamic Type must not reflow a shared image (the recipient's settings apply in
// their own viewer). Text is typeset from the verbatim string, never re-encoded.

/// The links a share carries. `/ang/N` unfurls as Ang N's own card in any chat (sggs-platform
/// src/pages/ang) and opens the web Reader at that Ang; `?line=` lands on the verse.
enum ShareLinks {
    static let site = URL(string: "https://gurbanisoul.com")!

    static func ang(_ ang: Int, line: Int? = nil) -> URL {
        var c = URLComponents(string: "https://gurbanisoul.com/ang/\(String(ang))")!
        if let line { c.queryItems = [URLQueryItem(name: "line", value: String(line))] }
        return c.url!
    }

    static func citation(_ ang: Int) -> String { "Sri Guru Granth Sahib Ji · Ang \(String(ang))" }

    /// A verse as text: the verbatim line, then its source, then (for a Sri Guru Granth Sahib Ji
    /// line with an identity) the link. Never bare scripture without its source.
    static func verseText(gurmukhi: String, ang: Int, line: Int?, sourceLabel: String? = nil) -> String {
        var out = gurmukhi
        if let sourceLabel { out += "\n— \(sourceLabel)" }
        else if ang > 0 {
            out += "\n— \(citation(ang))"
            out += "\n\(self.ang(ang, line: line).absoluteString)"
        }
        return out
    }
}

/// Fixed-size type for share images (no Dynamic Type): Source Serif 4 at a `wght`, Sant Lipi.
enum ShareType {
    static func serif(_ size: CGFloat, weight: CGFloat = 600) -> Font {
        guard let face = UIFont(name: Brand.headingFontName, size: size) else {
            return .system(size: size, weight: weight >= 600 ? .semibold : .regular, design: .serif)
        }
        let wght = 0x77676874   // 'wght'
        let d = face.fontDescriptor.addingAttributes([
            UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String): [wght: weight],
        ])
        return Font(UIFont(descriptor: d, size: size))
    }
}

/// The app icon as a small tile: ink mark on top-lit gold (light), gold mark on warm ink (dark) —
/// the icon's own two faces (brand book §5). The mark is the launch logo (ੴ above the pothi).
struct AppMarkTile: View {
    let size: CGFloat
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        let shape = RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
        shape
            .fill(LinearGradient(colors: dark ? [IconField.inkTop, IconField.inkBottom]
                                              : [IconField.goldTop, IconField.goldBottom],
                                 startPoint: .top, endPoint: .bottom))
            .overlay { Image("LaunchLogo").resizable().scaledToFit().padding(size * 0.12) }
            .overlay { if dark { shape.strokeBorder(IconField.inkEdge, lineWidth: 0.5) } }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// The gold rule under a verse: the share-card gradient, with the 1-pt accent edge every
/// light-mode gold fill carries.
struct ShareRule: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Capsule()
            .fill(AccentPalette.brandDefault.heroGradient)
            .overlay { if scheme == .light { Capsule().strokeBorder(AccentPalette.brandDefault.accent, lineWidth: 0.34) } }
            .frame(width: 35, height: 2)
            .accessibilityHidden(true)
    }
}

/// The frame every share image shares: mark + wordmark, the content, the site.
struct ShareCardFrame<Content: View>: View {
    var footer: String = "gurbanisoul.com"
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                AppMarkTile(size: 24)
                Text("Gurbani Soul").font(ShareType.serif(11)).foregroundStyle(.primary)
            }
            Spacer(minLength: 28)
            content
            Spacer(minLength: 28)
            Text(footer).font(ShareType.serif(8.7, weight: 500)).foregroundStyle(Ink.muted)
        }
        .padding(32)
        .frame(width: 360, alignment: .leading)
        .frame(minHeight: 360)
        .background {
            ZStack {
                Ink.paper
                // the brand Glow (≤ 14%): a light in the corner, never a text background
                RadialGradient(colors: [AccentPalette.brandDefault.accentFill.opacity(0.13), .clear],
                               center: UnitPoint(x: 0.92, y: 0.05), startRadius: 0, endRadius: 270)
            }
        }
    }
}

/// A shareable verse image: the verbatim line, an optional transliteration and English layer
/// (labelled as a translation, never presented as Gurbani), the rule and the citation.
struct VerseCardView: View {
    let gurmukhi: String
    let translit: String
    let en: String?
    let ang: Int
    /// Where the verse was found, e.g. "Naam ✦ Haumai" from the Constellation. When set, the card
    /// names it under the citation and carries the endorsement line.
    var context: String? = nil

    var body: some View {
        ShareCardFrame {
            VStack(alignment: .leading, spacing: 14) {
                Text(gurmukhi)
                    .font(Brand.gurmukhi(25))
                    .lineSpacing(12)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                if !translit.isEmpty {
                    Text(translit).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                if let en, !en.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("ENGLISH TRANSLATION").font(.system(size: 7.5, weight: .semibold)).tracking(0.8)
                            .foregroundStyle(Ink.muted)
                        Text(en).font(ShareType.serif(11, weight: 400)).foregroundStyle(.secondary)
                    }
                }
                ShareRule().padding(.top, 6)
                Text(ShareLinks.citation(ang)).font(ShareType.serif(11.3)).foregroundStyle(.primary)
                if let context, !context.isEmpty {
                    Text("Constellation · \(context) (matched by a shared word, not by meaning)")
                        .font(.system(size: 9)).foregroundStyle(.secondary)
                }
            }
        }
    }
}

@MainActor
enum VerseCardRenderer {
    /// nil only if rendering fails (caller falls back to sharing text).
    /// `scheme` must be passed explicitly: the card's colors are dynamic providers, and
    /// ImageRenderer resolves them against ITS environment, not the presenting window's —
    /// without this the shared image could silently flip scheme.
    static func render(gurmukhi: String, translit: String, en: String?, ang: Int,
                       context: String? = nil, scheme: ColorScheme) -> UIImage? {
        render(VerseCardView(gurmukhi: gurmukhi, translit: translit, en: en, ang: ang, context: context),
               scheme: scheme)
    }

    /// Any share card at 3× in a fixed scheme and the default text size.
    static func render(_ card: some View, scheme: ColorScheme) -> UIImage? {
        let renderer = ImageRenderer(content: card
            .environment(\.colorScheme, scheme)
            .environment(\.dynamicTypeSize, .large))
        renderer.scale = 3
        return renderer.uiImage
    }
}

/// A card image handed to the share sheet with its own header: the citation as the title, the
/// site as the subtitle and the card as the thumbnail (instead of iOS's bare "Image" row).
final class ShareCardItem: NSObject, UIActivityItemSource {
    let image: UIImage
    let title: String
    let url: URL

    init(image: UIImage, title: String, url: URL) {
        self.image = image; self.title = title; self.url = url
    }

    func activityViewControllerPlaceholderItem(_ controller: UIActivityViewController) -> Any { image }

    func activityViewController(_ controller: UIActivityViewController,
                                itemForActivityType activityType: UIActivity.ActivityType?) -> Any? { image }

    func activityViewControllerLinkMetadata(_ controller: UIActivityViewController) -> LPLinkMetadata? {
        let m = LPLinkMetadata()
        m.title = title
        m.originalURL = url       // the subtitle row shows its host
        m.url = url
        m.imageProvider = NSItemProvider(object: image)
        m.iconProvider = NSItemProvider(object: image)
        return m
    }
}
