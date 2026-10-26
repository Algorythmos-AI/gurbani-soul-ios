import SwiftUI
import GurbaniSearchKit

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
/// hint is the hub's shipped caption. Today's Theme Feature adds the theme's verse below the link
/// as its own button (opens the shabad), so VoiceOver reads the Gurmukhi with its Punjabi tag.
struct ExploreCard: View {
    let destination: ExploreDestination
    let form: ExploreCardForm
    let digest: ExploreDigest
    let roster: [String: Contributor]
    let live: ExploreLive

    @Environment(AppContainer.self) private var container
    @Environment(\.palette) private var palette
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    /// Preview heights grow a little with text, capped so a chart never pushes its words away.
    @ScaledMetric(relativeTo: .caption) private var squareHeight: CGFloat = 64
    @ScaledMetric(relativeTo: .caption) private var wideHeight: CGFloat = 40
    @ScaledMetric(relativeTo: .caption) private var featureHeight: CGFloat = 96
    /// A ribbon is a line, not a block: the Feature draws it thin, whatever the card's size.
    @ScaledMetric(relativeTo: .caption) private var featureRibbonHeight: CGFloat = 48
    /// The Feature dial: large enough to read the lit watch and the hand.
    @ScaledMetric(relativeTo: .caption) private var featureDial: CGFloat = 112

    /// The Index ribbon and the Vaar spans read along a line.
    private var isRibbon: Bool { destination == .index || destination == .vaars }

    private var accessibilitySize: Bool { dynamicTypeSize.isAccessibilitySize }

    var body: some View {
        if destination == .clock {
            // The hand moves once a minute, and only this card redraws for it.
            TimelineView(.periodic(from: PaharFormat.nextMinuteBoundary(), by: 60)) { _ in
                card(clock: ExploreClockNow.now())
            }
        } else {
            card(clock: nil)
        }
    }

    @ViewBuilder private func card(clock: ExploreClockNow?) -> some View {
        if form == .feature, destination == .themes, let today = live.themeToday {
            Card {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    accessible(NavigationLink(value: destination.route) { content(clock: nil) }
                        .buttonStyle(.plain), clock: nil)
                    Divider()
                    VerseQuoteBlock(line: today.line, isRefrain: today.isRefrain)
                }
            }
        } else {
            accessible(NavigationLink(value: destination.route) {
                Card { content(clock: clock).frame(maxHeight: .infinity, alignment: .top) }
            }
            .buttonStyle(.pressableCard), clock: clock)
        }
    }

    private func accessible<V: View>(_ v: V, clock: ExploreClockNow?) -> some View {
        let actions = secondaryActions
        return v
            // `.combine` (not `.ignore`) keeps the link's button trait on the merged element, so
            // it is still `app.buttons[title]`; the explicit label/value replace the merged text.
            .accessibilityElement(children: .combine)
            .accessibilityLabel(destination.title)
            .accessibilityValue(spoken(clock: clock))
            .accessibilityHint(ExploreDigest.legacyCaption(destination))
            .accessibilityIdentifier(destination.title)
            // Deep links the preview shows, without nesting a second tap target in the card:
            // VoiceOver actions and a long-press menu carry them.
            .accessibilityActions {
                ForEach(actions) { a in Button(a.title, action: a.run) }
            }
            .modifier(ActionMenu(actions: actions))
            .modifier(ChartDescription(descriptor: chartDescriptor))
    }

    // MARK: secondary actions + audio graphs


    private var secondaryActions: [ExploreAction] {
        let router = container.router
        switch destination {
        case .index:
            guard let a = digest.lastAng else { return [] }
            return [ExploreAction(title: "Read Ang \(a)", symbol: "book") { router.openAng(a) }]
        case .themes:
            guard let concept = live.themeToday?.concept else { return [] }
            return [ExploreAction(title: "Open \(ConceptName.display(concept))", symbol: "circle.grid.2x2") {
                router.explorePath.append(Route.theme(concept))
            }]
        case .constellation:
            guard let concept = live.themeToday?.concept else { return [] }
            return [ExploreAction(title: "Centre on \(ConceptName.display(concept))", symbol: "circle.hexagongrid") {
                router.openConstellation(ConstellationLink(theme: concept, with: nil, alone: false))
            }]
        case .vaars:
            guard let c = digest.continueVaar else { return [] }
            return [ExploreAction(title: "Continue the Vaar", symbol: "book") {
                router.openVaar(c.vaarId, read: true, line: c.lineId)
            }]
        case .lineage, .insights, .clock:
            return []
        }
    }

    /// Audio Graphs for the two chart previews (the preview itself is hidden from VoiceOver).
    private var chartDescriptor: ExploreBarsDescriptor? {
        switch destination {
        case .insights where !digest.raagMass.isEmpty:
            return ExploreBarsDescriptor(
                title: "Verse lines per raag", summary: "Each raag in the Granth's own order. Descriptive, never a ranking.",
                axis: "Raag", unit: "lines", names: digest.raagNames, values: digest.raagMass)
        case .lineage where !digest.voices.isEmpty:
            return ExploreBarsDescriptor(
                title: "Verse lines per voice", summary: "Each voice in the order its Bani first appears in the Granth. Descriptive, never a ranking.",
                axis: "Voice", unit: "lines", names: digest.voices.map { AuthorName($0.author).spoken },
                values: digest.voices.map(\.lines))
        default:
            return nil
        }
    }

    @ViewBuilder private func content(clock: ExploreClockNow?) -> some View {
        switch form {
        case .feature where horizontalSizeClass == .regular && !accessibilitySize:
            // Regular width: the words on the left, the preview given the room on the right.
            HStack(alignment: .center, spacing: Theme.Space.xl) {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    FeaturedChip()
                    titleRow(font: .title2.weight(.semibold))
                    captionText(clock: clock)
                }
                .frame(maxWidth: 280, alignment: .leading)
                featurePreview(clock: clock, scale: 1.6)
            }
        case .feature:
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                FeaturedChip()
                titleRow(font: .title2.weight(.semibold))
                featurePreview(clock: clock, scale: 1)
                captionText(clock: clock)
            }
        case .wide:
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                titleRow(font: .headline)
                captionText(clock: clock)
                preview(height: min(wideHeight, 40 * 1.4), clock: clock)
                    .padding(.top, Theme.Space.xs)
            }
        case .square:
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                preview(height: min(squareHeight, 64 * 1.4), clock: clock)
                titleRow(font: .headline)
                captionText(clock: clock)
            }
        }
    }

    @ViewBuilder private func featurePreview(clock: ExploreClockNow?, scale: CGFloat) -> some View {
        if destination == .clock, let clock {
            clockFeature(clock)
        } else {
            // A ribbon stays a line at any width; blocks (dots, bars, sky) take the extra room.
            preview(height: isRibbon || destination == .themes ? featureHeightFor : featureHeightFor * scale, clock: clock)
        }
    }

    private var featureHeightFor: CGFloat {
        if isRibbon { return min(featureRibbonHeight, 48 * 1.4) }
        if destination == .themes { return min(featureRibbonHeight, 48 * 1.4) }
        return min(featureHeight, 96 * 1.4)
    }

    private func titleRow(font: Font) -> some View {
        HStack(spacing: Theme.Space.s) {
            Image(systemName: destination.symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(palette.accent)
            Text(destination.title).font(font).foregroundStyle(.primary)
        }
    }

    private func captionText(clock: ExploreClockNow?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(caption(clock: clock))
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

    // MARK: words for the live cards (the rest come from the digest)

    private func caption(clock: ExploreClockNow?) -> String {
        switch destination {
        case .clock:
            return clock?.caption ?? ExploreDigest.legacyCaption(destination)
        case .themes:
            guard let t = live.themeToday else { return digest.caption(destination) }
            let name = ConceptName.display(t.concept)
            return digest.conceptCount.map { "Today: \(name) · \($0.formatted()) concepts" } ?? "Today: \(name)"
        case .constellation:
            return live.sky.map { "\($0.concepts.count.formatted()) themes, and which travel together" }
                ?? ExploreDigest.legacyCaption(destination)
        default:
            return digest.caption(destination)
        }
    }

    private func spoken(clock: ExploreClockNow?) -> String {
        switch destination {
        case .clock:
            return clock?.spoken ?? ""
        case .themes:
            let today = live.themeToday.map { "Theme of the day: \(ConceptName.display($0.concept))" }
            return [today, digest.conceptCount.map { "\($0) concepts" }].compactMap { $0 }.joined(separator: ". ")
        case .constellation:
            return live.sky.map { "All \($0.concepts.count) themes as a sky; lines join themes that share shabads" } ?? ""
        default:
            return digest.spokenSummary(destination)
        }
    }

    // MARK: previews

    @ViewBuilder private func preview(height: CGFloat, clock: ExploreClockNow?) -> some View {
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
            case .themes:
                if let t = live.themeToday { themePreview(t) } else { PreviewPlaceholder() }
            case .constellation:
                if let sky = live.sky {
                    SkyGlyph(sky: sky)
                        .padding(Theme.Space.xs)
                        .background(Ink.clockFace, in: RoundedRectangle(cornerRadius: Theme.Radius.chip))
                } else { PreviewPlaceholder() }
            case .clock:
                if let clock {
                    PaharDialRenderer(model: clock.model, style: .compact, palette: palette, analogFace: false)
                        .aspectRatio(1, contentMode: .fit)
                } else { PreviewPlaceholder() }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .appAnimation(Motion.gentle, value: live.sky != nil)
        .appAnimation(Motion.gentle, value: live.themeToday?.concept)
        .accessibilityHidden(true)
    }

    /// Today's theme: its name in its family colour and where its verses fall in the Granth.
    private func themePreview(_ t: ThemeOfTheDay) -> some View {
        let color = ThemeGroup.color(t.concept)
        return VStack(alignment: .leading, spacing: Theme.Space.xs) {
            // At accessibility sizes the name lives in the caption, where it can grow.
            if !accessibilitySize {
                HStack(spacing: 6) {
                    Circle().fill(color).frame(width: 8, height: 8)
                    Text(ConceptName.display(t.concept))
                        .font(.headline).foregroundStyle(.primary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
            }
            AngSparkline(bins: live.themeBins, color: color, height: 18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    }

    /// The Clock Feature: the dial with this watch lit, beside the raags sung in it — verbatim
    /// Gurmukhi names, in ink, never clipped (the row grows to fit them).
    private func clockFeature(_ clock: ExploreClockNow) -> some View {
        let dial = min(featureDial, 112 * 1.4)
        return HStack(alignment: .center, spacing: Theme.Space.l) {
            PaharDialRenderer(model: clock.model, style: .compact, palette: palette, analogFace: false)
                .frame(width: dial, height: dial)
                .accessibilityHidden(true)
            // The raag table is written to the widget snapshot after launch; until then the dial
            // and the watch (in the caption) are all the card claims.
            if clock.hasSnapshot {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text("Sung in this watch")
                        .font(.caption.weight(.semibold)).foregroundStyle(Ink.muted)
                    if clock.raagsGurmukhi.isEmpty {
                        Text(clock.raagCount == 0 ? "No raags are assigned to this watch."
                                                  : clock.raagsRoman.joined(separator: " · "))
                            .font(.subheadline).foregroundStyle(.primary)
                    } else {
                        FlowLayout(spacing: Theme.Space.s) {
                            ForEach(clock.raagsGurmukhi, id: \.self) { name in
                                GurmukhiText(verbatim: name, size: 18).foregroundStyle(.primary)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

/// Attaches an Audio Graphs descriptor when there is one.
private struct ChartDescription: ViewModifier {
    let descriptor: ExploreBarsDescriptor?
    func body(content: Content) -> some View {
        if let descriptor {
            content.accessibilityChartDescriptor(descriptor)
        } else {
            content
        }
    }
}

/// A bar run as Audio Graphs reads it: one category per bar, in the preview's own order.
struct ExploreBarsDescriptor: AXChartDescriptorRepresentable {
    let title: String
    let summary: String
    let axis: String
    let unit: String
    let names: [String]
    let values: [Int]

    func makeChartDescriptor() -> AXChartDescriptor {
        let top = Double(max(values.max() ?? 1, 1))
        let x = AXCategoricalDataAxisDescriptor(title: axis, categoryOrder: names)
        let y = AXNumericDataAxisDescriptor(title: unit.capitalized, range: 0...top, gridlinePositions: []) {
            "\(Int($0)) \(unit)"
        }
        let series = AXDataSeriesDescriptor(name: title, isContinuous: false,
                                            dataPoints: zip(names, values).map { AXDataPoint(x: $0, y: Double($1)) })
        return AXChartDescriptor(title: title, summary: summary, xAxis: x, yAxis: y, additionalAxes: [], series: [series])
    }
}

/// A deep link a card offers beside its own destination.
struct ExploreAction: Identifiable {
    let title: String
    let symbol: String
    let run: () -> Void
    var id: String { title }
}

/// A long-press menu only when the card has something to offer (an empty menu would still lift).
private struct ActionMenu: ViewModifier {
    let actions: [ExploreAction]
    func body(content: Content) -> some View {
        if actions.isEmpty {
            content
        } else {
            content.contextMenu {
                ForEach(actions) { a in Button(a.title, systemImage: a.symbol, action: a.run) }
            }
        }
    }
}
