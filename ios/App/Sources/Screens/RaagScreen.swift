import SwiftUI
import GurbaniSearchKit

/// One raag of the Granth, as a page: where it sits in the saroop, how much of it it fills, whose
/// voices are in it, the forms its printed headings name, its Vaars, and the hour tradition gives
/// it (cited, and labelled as tradition). Every figure is read from the DB; nothing is ranked.
///
/// Pushed on the Explore stack from the Index (card or Ribbon) or `sggs://raag/<slug>`.
struct RaagScreen: View {
    /// A corpus raag name (Gurmukhi) or its corpus roman — `raagFacts` resolves either.
    let raag: String

    @Environment(AppContainer.self) private var container
    @Environment(\.palette) private var palette
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage("sggs_last_ang") private var lastAng = 1

    private enum Load: Equatable { case loading, missing, ready(RaagFacts) }
    @State private var load: Load = .loading
    @State private var timing: RaagTiming?
    @State private var vaars: [VaarSummary] = []
    @State private var raagCount = 31
    @State private var voicesExpanded = false

    var body: some View {
        Group {
            switch load {
            case .loading:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .missing:
                ContentUnavailableView("Raag not found", systemImage: "music.note",
                                       description: Text("This raag is not in the Index."))
            case .ready(let f):
                page(f)
            }
        }
        .background(Ink.canvas)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: raag) { await fetch() }
    }

    private var title: String {
        if case .ready(let f) = load, let en = GranthNames.raag(f.raag.name, roman: f.raag.roman) { return "Raag \(en)" }
        return "Raag"
    }

    private func fetch() async {
        guard let corpus = container.corpus else { return }
        guard let f = await corpus.raagFacts(name: raag) else { load = .missing; return }
        if corpus.capabilities.hasTiming {
            let t = await corpus.timingRaag(name: f.raag.name)
            timing = t.available ? t : nil
        }
        vaars = await corpus.vaars().filter { $0.raag == f.raag.name }
        if let n = container.meta?.raags.count, n > 0 { raagCount = n }
        load = .ready(f)
    }

    // MARK: page

    private func page(_ f: RaagFacts) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                hero(f)
                glance(f)
                if !f.voices.isEmpty { voices(f) }
                if f.hasFormLayer && (!f.forms.isEmpty || !f.genres.isEmpty || !f.ghars.isEmpty) { forms(f) }
                if !vaars.isEmpty { vaarsSection }
                if let timing, !timing.claims.isEmpty { hours(timing, f) }
                Text("Counts are read from the corpus and its printed headings. Sri Guru Granth Sahib Ji · \((f.raag.firstAng...f.raag.lastAng).angLabel)")
                    .font(.caption2).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Theme.Space.l)
        }
        .contentMargins(.bottom, Theme.Space.xl, for: .scrollContent)
    }

    // MARK: hero

    private func hero(_ f: RaagFacts) -> some View {
        let r = f.raag
        let continueAng = (r.firstAng...r.lastAng).contains(lastAng) && lastAng != r.firstAng ? lastAng : nil
        return VStack(alignment: .leading, spacing: Theme.Space.m) {
            SectionEyebrow(text: "Raag \(String(r.seq)) of \(String(raagCount))", symbol: "music.note")
            GurmukhiText(verbatim: r.name, size: 40)
            if let en = GranthNames.raag(r.name, roman: r.roman) {
                Text(en).font(Brand.heading(.title2))
            }
            VStack(alignment: .leading, spacing: 4) {
                AngSliceBar(first: r.firstAng, last: r.lastAng, height: 6)
                HStack {
                    Text("Ang 1").font(.caption2).foregroundStyle(.tertiary)
                    Spacer()
                    Text((r.firstAng...r.lastAng).angLabel).font(.caption.weight(.semibold)).monospacedDigit()
                    Spacer()
                    Text("Ang \(String(GranthMap.totalAngs))").font(.caption2).foregroundStyle(.tertiary)
                }
                .monospacedDigit()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\((r.firstAng...r.lastAng).angLabel) of \(String(GranthMap.totalAngs))")
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Theme.Space.s) { actions(r, continueAng: continueAng) }
                VStack(alignment: .leading, spacing: Theme.Space.s) { actions(r, continueAng: continueAng) }
            }
            .padding(.top, Theme.Space.xs)
        }
    }

    @ViewBuilder
    private func actions(_ r: RaagRow, continueAng: Int?) -> some View {
        Button { container.router.openAng(r.firstAng) } label: {
            Label("Begin at Ang \(String(r.firstAng))", systemImage: "book")
        }
        .buttonStyle(.prominentPill)
        .accessibilityIdentifier("raagBegin")
        if let a = continueAng {
            Button { container.router.openAng(a) } label: {
                Label("Continue at Ang \(String(a))", systemImage: "bookmark")
                    .font(.subheadline.weight(.medium))
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("raagContinue")
        }
    }

    // MARK: at a glance

    private func glance(_ f: RaagFacts) -> some View {
        let r = f.raag
        let cols = Array(repeating: GridItem(.flexible(), spacing: Theme.Space.s),
                         count: dynamicTypeSize.isAccessibilitySize ? 2 : 4)
        return LazyVGrid(columns: cols, spacing: Theme.Space.s) {
            StatTile(value: r.nShabads.formatted(), caption: "shabads")
            StatTile(value: r.nLines.formatted(), caption: "lines")
            StatTile(value: (r.lastAng - r.firstAng + 1).formatted(), caption: "Angs")
            StatTile(value: f.voices.count.formatted(), caption: f.voices.count == 1 ? "voice" : "voices")
        }
    }

    // MARK: voices

    private func voices(_ f: RaagFacts) -> some View {
        let total = max(1, f.voices.reduce(0) { $0 + $1.nLines })
        let shown = voicesExpanded ? f.voices : Array(f.voices.prefix(5))
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            SectionEyebrow(text: "Voices in this raag", symbol: "person.2")
            Text("Verses by each voice, from the attribution in the print.")
                .font(.footnote).foregroundStyle(.secondary)
            VoiceShareBar(voices: f.voices, total: total)
                .frame(height: 10)
            VStack(spacing: 0) {
                ForEach(Array(shown.enumerated()), id: \.element.id) { i, v in
                    HStack(spacing: Theme.Space.s) {
                        Circle().fill(VoiceShareBar.color(i, palette: palette)).frame(width: 8, height: 8)
                        Text(v.author).font(.subheadline)
                        Spacer(minLength: Theme.Space.s)
                        Text("\(v.nLines.formatted()) lines").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                    .padding(.horizontal, Theme.Space.l).padding(.vertical, 10)
                    .accessibilityElement(children: .combine)
                    if i < shown.count - 1 { Divider().padding(.leading, Theme.Space.l) }
                }
                if f.voices.count > 5 {
                    Divider()
                    Button(voicesExpanded ? "Show fewer" : "Show all \(String(f.voices.count)) voices") {
                        withAnimation(Motion.gentle) { voicesExpanded.toggle() }
                    }
                    .font(.footnote.weight(.medium))
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                }
            }
            .background(Ink.card, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(Ink.hairline))
        }
    }

    // MARK: forms

    private func forms(_ f: RaagFacts) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            SectionEyebrow(text: "Forms in this raag", symbol: "square.grid.3x3")
            Text("As the printed headings name them. Tap one to read its first composition.")
                .font(.footnote).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !f.forms.isEmpty {
                FlowChips(items: f.forms.map { ($0.id, PoeticForms.form($0.form), $0.firstCompId, $0.firstAng) }) { compId in
                    container.present(.shabad(compId: compId))
                }
            }
            if !f.genres.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(f.genres.enumerated()), id: \.element.id) { i, g in
                        Button { container.present(.shabad(compId: g.compId)) } label: {
                            HStack(spacing: Theme.Space.m) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(PoeticForms.genre(g.genre)).font(.subheadline.weight(.medium))
                                    if let label = g.sourceLabel { GurmukhiText(verbatim: label, size: 15) }
                                }
                                Spacer(minLength: Theme.Space.s)
                                Text("Ang \(String(g.firstAng))").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, Theme.Space.l).padding(.vertical, Theme.Space.m)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(PoeticForms.genre(g.genre)), Ang \(String(g.firstAng))")
                        .accessibilityAddTraits(.isButton)
                        if i < f.genres.count - 1 { Divider().padding(.leading, Theme.Space.l) }
                    }
                }
                .background(Ink.card, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(Ink.hairline))
            }
            if !f.ghars.isEmpty || !f.partaalCompIds.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    if !f.ghars.isEmpty {
                        Text("Ghar \(f.ghars.map(String.init).joined(separator: ", "))")
                            .font(.footnote).monospacedDigit()
                    }
                    if let first = f.partaalCompIds.first {
                        Button {
                            container.present(.shabad(compId: first))
                        } label: {
                            Text(f.partaalCompIds.count == 1 ? "1 partaal composition"
                                 : "\(String(f.partaalCompIds.count)) partaal compositions")
                                .font(.footnote)
                        }
                    }
                }
                .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: vaars

    private var vaarsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            SectionEyebrow(text: vaars.count == 1 ? "Its Vaar" : "Its \(String(vaars.count)) Vaars", symbol: "list.number")
            VStack(spacing: 0) {
                ForEach(Array(vaars.enumerated()), id: \.element.id) { i, v in
                    NavigationLink { VaarAnatomyScreen(summary: v) } label: {
                        HStack(spacing: Theme.Space.m) {
                            VStack(alignment: .leading, spacing: 2) {
                                if let author = v.pauriAuthor { Text(author).font(.subheadline.weight(.medium)) }
                                Text("\(String(v.nPauris)) pauris · \(String(v.nSaloks)) saloks · \((v.firstAng...v.lastAng).angLabel)")
                                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                            }
                            Spacer(minLength: Theme.Space.s)
                            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, Theme.Space.l).padding(.vertical, Theme.Space.m)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if i < vaars.count - 1 { Divider().padding(.leading, Theme.Space.l) }
                }
            }
            .background(Ink.card, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(Ink.hairline))
        }
    }

    // MARK: traditional hour

    private func hours(_ t: RaagTiming, _ f: RaagFacts) -> some View {
        let primary = t.claims.filter { $0.claimType == "primary" }.compactMap(\.pahar)
        let variant = t.claims.filter { $0.claimType == "variant" }.compactMap(\.pahar)
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            SectionEyebrow(text: "Traditional time", symbol: "clock")
            Text("When this raag is customarily sung — tradition, not scripture. Each claim names its source.")
                .font(.footnote).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !primary.isEmpty || !variant.isEmpty {
                PaharStrip(primary: primary, variant: variant)
            }
            Card {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    ForEach(Array(t.claims.enumerated()), id: \.offset) { i, c in
                        if let p = c.pahar, c.claimType != "ceremonial" && c.claimType != "seasonal" {
                            Text("\(Pahar.label(p).capitalizedFirst) · \(timeText(c, pahar: p))")
                                .font(.subheadline.weight(.medium))
                        }
                        ClaimRow(claim: c)
                        if i < t.claims.count - 1 { Divider() }
                    }
                }
            }
            Button { container.router.openClock(raag: f.raag.roman ?? f.raag.name) } label: {
                Label("See it on the Raag Clock", systemImage: "clock.arrow.circlepath")
                    .font(.footnote.weight(.medium))
            }
            .accessibilityIdentifier("raagOpenClock")
        }
    }

    /// The claim's own hours as its source gives them ("3 PM–6 PM"); else the pahar's fixed window.
    private func timeText(_ c: TimingClaim, pahar p: Int) -> String {
        if let a = c.timeStart, let b = c.timeEnd, !a.isEmpty, !b.isEmpty {
            return "\(Pahar.fmt12(a))–\(Pahar.fmt12(b))"
        }
        return Pahar.range(p)
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

// MARK: - components

/// The voices of a raag as one proportional bar (decorative; the list beside it carries the words).
struct VoiceShareBar: View {
    let voices: [RaagVoice]
    let total: Int
    @Environment(\.palette) private var palette

    /// Accent at falling strength for the five largest voices; one ink tone for the rest.
    static func color(_ i: Int, palette: AccentPalette) -> Color {
        let steps: [Double] = [1.0, 0.72, 0.52, 0.36, 0.24]
        return i < steps.count ? palette.accent.opacity(steps[i]) : Color.primary.opacity(0.22)
    }

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 1) {
                ForEach(Array(voices.enumerated()), id: \.element.id) { i, v in
                    Rectangle().fill(Self.color(i, palette: palette))
                        .frame(width: max(1, geo.size.width * CGFloat(v.nLines) / CGFloat(max(total, 1)) - 1))
                }
            }
        }
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(Ink.hairline, lineWidth: 0.5))
        .accessibilityHidden(true)
    }
}

/// The eight pahars as two rows of four (day, night), the raag's primary hours lit and any
/// disputed variant hour outlined.
struct PaharStrip: View {
    let primary: [Int]
    let variant: [Int]
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            row("Day", symbol: "sun.max", pahars: 1...4)
            row("Night", symbol: "moon.stars", pahars: 5...8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    private var spoken: String {
        var parts: [String] = []
        if !primary.isEmpty { parts.append("Traditionally sung in the " + primary.map(Pahar.label).joined(separator: " and ")) }
        if !variant.isEmpty { parts.append("some charts give the " + variant.map(Pahar.label).joined(separator: " and ")) }
        return parts.joined(separator: "; ")
    }

    private func row(_ label: String, symbol: String, pahars: ClosedRange<Int>) -> some View {
        HStack(spacing: 6) {
            Label(label, systemImage: symbol).labelStyle(.iconOnly)
                .font(.caption).foregroundStyle(.secondary).frame(width: 20)
            ForEach(Array(pahars), id: \.self) { p in
                let lit = primary.contains(p), alt = variant.contains(p)
                RoundedRectangle(cornerRadius: 6)
                    .fill(lit ? palette.accentFill : Ink.raised)
                    .overlay(RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(lit || alt ? palette.accent : Ink.hairline,
                                      style: StrokeStyle(lineWidth: alt && !lit ? 1.5 : 1, dash: alt && !lit ? [3, 2] : [])))
                    .overlay(Text(Pahar.range(p)).font(.caption2.weight(.medium)).monospacedDigit()
                        .foregroundStyle(lit ? palette.onAccent : Color.secondary)
                        .minimumScaleFactor(0.6).lineLimit(1).padding(.horizontal, 2))
                    .frame(height: 30)
            }
        }
    }
}

/// Chips that wrap onto as many lines as they need.
struct FlowChips: View {
    let items: [(id: String, title: String, compId: Int, ang: Int)]
    let tap: (Int) -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        FlowLayout(spacing: Theme.Space.s) {
            ForEach(items, id: \.id) { item in
                Button { tap(item.compId) } label: {
                    Text(item.title)
                        .font(.footnote.weight(.medium))
                        .padding(.horizontal, Theme.Space.m).padding(.vertical, 6)
                        .background(Ink.raised, in: Capsule())
                        .overlay(Capsule().strokeBorder(Ink.hairline))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(item.title), first at Ang \(String(item.ang))")
            }
        }
    }
}

/// A minimal wrapping layout: rows of subviews at their ideal size.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, maxX: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x > 0 && x + sz.width > width { x = 0; y += rowH + spacing; rowH = 0 }
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
            maxX = max(maxX, x - spacing)
        }
        return CGSize(width: min(maxX, width), height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x > bounds.minX && x + sz.width > bounds.maxX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(sz))
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
    }
}
