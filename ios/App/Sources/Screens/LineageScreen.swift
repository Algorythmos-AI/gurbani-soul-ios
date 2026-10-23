import SwiftUI
import GurbaniSearchKit

/// The Contributors: the voices across five centuries gathered into one Granth — the Gurus,
/// the Bhagats of the Bhakti and Sufi traditions, the court Bhatts, the Gursikh companions.
/// Native parity with the web /lineage: timeline (grouped by century, sized by preserved
/// Bani volume), kind filters, full profiles (life + stylometry + signature themes +
/// distinctive terms), and ⇄ compare two voices. A voice's size reflects how much of its
/// Bani is preserved here — NEVER its importance (stated on-screen, as on the web).
struct LineageScreen: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.palette) private var palette
    @State private var contributors: [Contributor]?
    /// author → canonical counts + Angs (verses = `lines` with is_header=0: the ONE count shown).
    @State private var summaries: [String: VoiceSummary] = [:]
    @State private var kindFilter: String = "all"
    @State private var groupMode = "time"                      // time | kind | volume (web parity)
    /// The card → voice page zoom (iOS 18+).
    @Namespace private var voiceZoom
    @State private var lens: Lens = .roll
    @State private var signatureRaags: [SignatureRaag] = []
    @State private var dialogueSpan: DialogueSpan?
    @State private var voiceOfTheDay: VoiceOfTheDay?

    /// How the voices are laid out: the card list (Roll) or one timeline (River).
    enum Lens: String, CaseIterable, Identifiable {
        case roll = "Roll", river = "River"
        var id: String { rawValue }
    }

    struct VoiceOfTheDay: Equatable {
        let contributor: Contributor
        let verse: VoiceVerse
    }
    @State private var compareMode = false
    @State private var comparePicks: [Contributor] = []
    @State private var comparePair: ComparePair?

    struct ComparePair: Identifiable {
        let a: Contributor; let b: Contributor
        var id: String { "\(a.name)⇄\(b.name)" }
    }

    private static let kinds: [(id: String, label: String)] = [
        ("all", "All"), ("guru", "Gurus"), ("bhagat", "Bhagats"),
        ("bhatt", "Bhatts"), ("gursikh", "Gursikhs"),
    ]
    private static let groupModes: [(id: String, label: String)] = [
        ("time", "Timeline"), ("kind", "By tradition"), ("volume", "Most Bani"),
    ]
    /// Web KIND_DESC — the "By tradition" band titles.
    private static let kindBands: [(kind: String, title: String)] = [
        ("guru", "The Sikh Gurus"), ("bhagat", "Bhakti & Sufi saints"),
        ("bhatt", "Court bards (Bhatts)"), ("gursikh", "Gursikh companions"),
    ]

    var body: some View {
        Group {
            if let contributors {
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Space.l) {
                        hero(contributors)
                        if let voiceOfTheDay { voiceOfTheDayCard(voiceOfTheDay) }
                        didYouKnow
                        Picker("Lens", selection: $lens) {
                            ForEach(Lens.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("lineageLens")
                        controls
                        switch lens {
                        case .roll:
                            ForEach(bands(contributors), id: \.title) { band in
                                bandView(band.title, band.members)
                            }
                        case .river:
                            VoiceRiverView(voices: contributors.filter { kindFilter == "all" || $0.kind == kindFilter }) { c in
                                open(c)
                            }
                        }
                    }
                    .padding(Theme.Space.l)
                    .appAnimation(Motion.gentle, value: groupMode)
                    .appAnimation(Motion.gentle, value: kindFilter)
                    .appAnimation(Motion.gentle, value: lens)
                }
                .background(Ink.canvas)
                .contentMargins(.bottom, Theme.Space.xl, for: .scrollContent)
            } else {
                ContentUnavailableView("Contributor roster unavailable", systemImage: "person.2.slash")
            }
        }
        .navigationTitle("Lineage")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    compareMode.toggle()
                    comparePicks = []
                } label: {
                    Label(compareMode ? "Cancel compare" : "Compare two voices",
                          systemImage: "arrow.left.arrow.right")
                }
                .accessibilityIdentifier("compareVoices")
            }
        }
        .navigationDestination(for: VoiceLink.self) { link in
            if let c = contributors?.first(where: { $0.name == link.name }) {
                VoicePage(contributor: c, summary: summaries[c.name], roster: contributors ?? [])
                    .modifier(VoiceZoomDestination(id: c.name, namespace: voiceZoom))
            } else {
                ContentUnavailableView("Voice not found", systemImage: "person.slash")
            }
        }
        .sheet(item: $comparePair) { pair in
            CompareVoicesSheet(a: pair.a, b: pair.b, summaryA: summaries[pair.a.name], summaryB: summaries[pair.b.name])
        }
        .task {
            if contributors == nil { contributors = ContributorsStore.load() }
            if summaries.isEmpty, let corpus = container.corpus {
                let list = await corpus.voiceSummaries()
                summaries = Dictionary(list.map { ($0.author, $0) }, uniquingKeysWith: { a, _ in a })
                // Voices the DB carries that the roster does not list yet still get a card.
                if let roster = contributors {
                    let known = Set(roster.map(\.name))
                    contributors = roster + list.filter { !known.contains($0.author) }
                        .map { Contributor(placeholderFor: $0.author) }
                }
                signatureRaags = await corpus.signatureRaags()
                dialogueSpan = await corpus.dialogueSpan()
                voiceOfTheDay = await pickVoiceOfTheDay(corpus)
            }
        }
    }

    // MARK: hero — web .lin-hero parity

    private func hero(_ list: [Contributor]) -> some View {
        let years = list.map(\.timelineYear).filter { $0 != 9999 }
        let span = years.isEmpty ? "" :
            "\(String((years.min()! / 100) + 1))th–\(String((years.max()! / 100) + 1))th"
        let verses = summaries.values.reduce(0) { $0 + $1.nVerses }
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text("THE CONTRIBUTORS")
                .font(.caption2.weight(.semibold)).kerning(1.2)
                .foregroundStyle(palette.accentText)
            // With the bundled roster this renders "30 voices · 12th–17th century" —
            // the exact header string testLineageAndVaars asserts.
            Text("\(String(list.count)) voices · \(span) century").font(.headline)
            Text("Every verse here is verbatim and cited by Ang.")
                .font(.caption).foregroundStyle(.secondary)
            Text("Five centuries of voices gathered into one Granth — the Gurus, the Bhagats of the Bhakti and Sufi traditions, the court Bhatts, and the Gursikh companions. Tap any voice for their page"
                 + (compareMode ? " — compare mode: pick two." : "; ⇄ compares two."))
                .font(.caption).foregroundStyle(.secondary)
            Text("Dates are historical approximations. Each strip marks the Angs that carry a voice's Bani — how much is preserved here, never its importance.")
                .font(.caption2).foregroundStyle(.tertiary)
            HStack(spacing: Theme.Space.s) {
                StatTile(value: "\(String(list.count))", caption: "contributors")
                StatTile(value: verses.formatted(), caption: "verses preserved here")
                StatTile(value: span.isEmpty ? "—" : "\(span) c.", caption: "span of voices")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Space.l)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: Theme.Radius.card).fill(Ink.card)
                RoundedRectangle(cornerRadius: Theme.Radius.card)
                    .fill(LinearGradient(colors: [palette.accent.opacity(0.14), .clear],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
            }
        )
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(Ink.hairline))
    }

    // MARK: controls

    private var controls: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Space.s) {
                    ForEach(Self.kinds, id: \.id) { k in
                        let count = k.id == "all" ? (contributors?.count ?? 0)
                            : (contributors?.filter { $0.kind == k.id }.count ?? 0)
                        ModePill(title: "\(k.label) · \(count)",
                                 dot: k.id == "all" ? nil : Contributor.kindColor(k.id),
                                 isSelected: kindFilter == k.id) { kindFilter = k.id }
                    }
                }
            }
            if lens == .roll {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.Space.s) {
                        ForEach(Self.groupModes, id: \.id) { g in
                            ModePill(title: g.label, isSelected: groupMode == g.id) { groupMode = g.id }
                        }
                    }
                }
            }
        }
    }

    private func open(_ c: Contributor) {
        container.router.explorePath.append(VoiceLink(name: c.name))
    }

    // MARK: voice of the day — one voice and one of its rahao verses, the same all day

    private func pickVoiceOfTheDay(_ corpus: CorpusActor) async -> VoiceOfTheDay? {
        let candidates = (contributors ?? []).filter { summaries[$0.name] != nil }.sorted { $0.name < $1.name }
        guard !candidates.isEmpty else { return nil }
        let day = max(0, HukamOfTheDay.dayNumber(of: Date()))
        let c = candidates[day % candidates.count]
        let deck = await corpus.authorRahao(c.name)
        if !deck.verses.isEmpty {
            return VoiceOfTheDay(contributor: c, verse: deck.verses[(day / candidates.count) % deck.verses.count])
        }
        guard let first = await corpus.authorCompositions(c.name).first else { return nil }
        return VoiceOfTheDay(contributor: c, verse: VoiceVerse(id: first.firstLineId, ang: first.ang,
                                                               compId: first.compId, gurmukhi: first.opening))
    }

    private func voiceOfTheDayCard(_ v: VoiceOfTheDay) -> some View {
        Button { open(v.contributor) } label: {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                SectionEyebrow(text: "Voice of the day")
                HStack(spacing: Theme.Space.s) {
                    VoiceMedallionView(contributor: v.contributor, diameter: 32)
                    Text(v.contributor.displayName).font(.headline)
                }
                GurmukhiText(verbatim: v.verse.gurmukhi, size: 22)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Ang \(v.verse.ang)").font(.caption).foregroundStyle(.secondary)
            }
            .padding(Theme.Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Ink.card, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(Ink.hairline))
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressableCard)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens their page")
        .accessibilityIdentifier("voiceOfTheDay")
    }

    // MARK: did you know — only facts computed from the DB, each cited by Ang

    @ViewBuilder private var didYouKnow: some View {
        let bhatts = summaries.values.filter { $0.author.hasPrefix("Bhatt ") }
        let facts = didYouKnowFacts(bhatts: bhatts)
        if !facts.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                SectionEyebrow(text: "Did you know")
                ForEach(facts, id: \.id) { f in
                    Button { if let c = f.voice { open(c) } } label: {
                        HStack(alignment: .top, spacing: Theme.Space.s) {
                            if let g = f.gurmukhi { GurmukhiText(verbatim: g, size: 20) }
                            Text(f.text).font(.callout)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if f.voice != nil {
                                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                        .padding(Theme.Space.m)
                        .background(Ink.card, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
                        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(Ink.hairline))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(f.voice == nil)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    struct Fact { let id: String; let gurmukhi: String?; let text: String; let voice: Contributor? }

    private func voice(_ author: String) -> Contributor? { contributors?.first { $0.name == author } }
    private func displayName(_ author: String) -> String { voice(author)?.displayName ?? AuthorName(author).english }

    private func didYouKnowFacts(bhatts: [VoiceSummary]) -> [Fact] {
        var out: [Fact] = []
        for r in signatureRaags.prefix(2) {
            out.append(Fact(id: "raag-\(r.raag)", gurmukhi: r.raag,
                            text: "appears in the Granth only in \(displayName(r.author))'s Bani, from Ang \(r.firstAng).",
                            voice: voice(r.author)))
        }
        if let d = dialogueSpan {
            let gurus = d.gurus.map(displayName).joined(separator: " and ")
            let bhagats = d.bhagats.map(displayName).joined(separator: " and ")
            out.append(Fact(id: "dialogues", gurmukhi: nil,
                            text: "Saloks of \(gurus) are set beside saloks of \(bhagats), Angs \(d.firstAng)–\(d.lastAng).",
                            voice: nil))
        }
        if bhatts.count > 1, let first = bhatts.map(\.firstAng).min(), let last = bhatts.map(\.lastAng).max() {
            out.append(Fact(id: "bhatts", gurmukhi: nil,
                            text: "\(bhatts.count) Bhatts each have Swaiyye in the Granth, Angs \(first)–\(last).",
                            voice: nil))
        }
        return out
    }

    // MARK: bands (time / kind / volume)

    private func bands(_ list: [Contributor]) -> [(title: String, members: [Contributor])] {
        let filtered = list.filter { kindFilter == "all" || $0.kind == kindFilter }
        switch groupMode {
        case "kind":
            return Self.kindBands.compactMap { band in
                let members = filtered.filter { $0.kind == band.kind }
                    .sorted { $0.timelineYear != $1.timelineYear ? $0.timelineYear < $1.timelineYear : $0.name < $1.name }
                return members.isEmpty ? nil : (band.title, members)
            }
        case "volume":
            let sorted = filtered.sorted {
                let na = summaries[$0.name]?.nVerses ?? 0, nb = summaries[$1.name]?.nVerses ?? 0
                return na != nb ? na > nb : $0.name < $1.name
            }
            return sorted.isEmpty ? [] : [("Ordered by how much Bani is preserved here", sorted)]
        default:
            let sorted = filtered
                .sorted { $0.timelineYear != $1.timelineYear ? $0.timelineYear < $1.timelineYear : $0.name < $1.name }
            var groups: [(String, [Contributor])] = []
            for c in sorted {
                let label = c.timelineYear == 9999 ? "Undated"
                    : "\(String((c.timelineYear / 100) + 1))th century"
                if let i = groups.firstIndex(where: { $0.0 == label }) { groups[i].1.append(c) }
                else { groups.append((label, [c])) }
            }
            return groups.map { (title: $0.0, members: $0.1) }
        }
    }

    private func bandView(_ title: String, _ members: [Contributor]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack {
                Text(title).font(.subheadline.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Text("\(members.count) voice\(members.count == 1 ? "" : "s")")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            LazyVStack(spacing: 0) {
                ForEach(Array(members.enumerated()), id: \.element.id) { i, c in
                    node(c, isFirst: i == 0, isLast: i == members.count - 1)
                }
            }
        }
    }

    // MARK: timeline node — year column · glowing rail · voice card

    private func node(_ c: Contributor, isFirst: Bool, isLast: Bool) -> some View {
        let summary = summaries[c.name]
        let picked = comparePicks.contains(c)
        let k = c.kindColor
        return Button {
            if compareMode {
                if picked { comparePicks.removeAll { $0 == c } }
                else {
                    comparePicks.append(c)
                    if comparePicks.count == 2 {
                        comparePair = ComparePair(a: comparePicks[0], b: comparePicks[1])
                        compareMode = false
                        comparePicks = []
                    }
                }
            } else {
                container.router.explorePath.append(VoiceLink(name: c.name))
            }
        } label: {
            HStack(alignment: .top, spacing: Theme.Space.s) {
                // year column
                Text(c.timelineYear == 9999 ? "—" : (c.circa ? "c. " : "") + String(c.timelineYear))
                    .font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .frame(minWidth: 44, alignment: .trailing)   // grows with Dynamic Type
                    .padding(.top, Theme.Space.l + 2)
                // the rail: continuous line + a glowing kind-colored node dot
                ZStack {
                    VStack(spacing: 0) {
                        Rectangle().fill(isFirst ? Color.clear : Ink.hairline).frame(width: 2)
                        Rectangle().fill(isLast ? Color.clear : Ink.hairline).frame(width: 2)
                    }
                    Circle().fill(k)
                        .frame(width: 9, height: 9)
                        .shadow(color: k.opacity(0.55), radius: 4)
                        .padding(.top, Theme.Space.l + 4)
                        .frame(maxHeight: .infinity, alignment: .top)
                }
                .frame(width: 12)
                // the voice card
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top, spacing: Theme.Space.s) {
                        VoiceMedallionView(contributor: c)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(c.displayName).font(.subheadline.weight(.semibold))
                            if let g = c.gurmukhi { GurmukhiText(verbatim: g, size: 17) }
                            Text(c.kindTag)
                                .font(.caption2.weight(.semibold)).kerning(0.5)
                                .foregroundStyle(k)
                        }
                        Spacer(minLength: 0)
                        if compareMode {
                            Image(systemName: picked ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(picked ? Theme.accent : .secondary)
                        }
                    }
                    if !c.era.isEmpty {
                        Text([c.era, c.region].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let summary {
                        AngBarcode(angs: summary.angs, color: k, height: 8)
                            .padding(.vertical, 2)
                        Text(Self.countLine(summary))
                            .font(.caption2).foregroundStyle(.secondary)
                    } else {
                        Text("Attribution under review").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .padding(Theme.Space.m)
                .background(Ink.card, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(Ink.hairline))
                .modifier(VoiceZoomSource(id: c.name, namespace: voiceZoom))
                .padding(.vertical, Theme.Space.xs)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressableCard)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("\(c.displayName), \(c.kind), \(c.era.isEmpty ? "undated" : c.era), "
                            + (summary.map { Self.countLine($0) } ?? "attribution under review"))
        .accessibilityHint(compareMode ? "Selects for comparison" : "Opens their page")
    }

    /// "536 verses · 61 compositions · Angs 219–1429" — the one canonical count.
    static func countLine(_ s: VoiceSummary) -> String {
        let verses = s.nVerses == 1 ? "1 verse" : "\(s.nVerses.formatted()) verses"
        let comps = s.nCompositions == 1 ? "1 composition" : "\(s.nCompositions.formatted()) compositions"
        let angs = s.firstAng == s.lastAng ? "Ang \(s.firstAng)" : "Angs \(s.firstAng)–\(s.lastAng)"
        return "\(verses) · \(comps) · \(angs)"
    }
}

// MARK: shared kind identity (screen + sheets)

extension Contributor {
    var kindColor: Color { Self.kindColor(kind) }

    static func kindColor(_ kind: String) -> Color {
        switch kind {
        case "guru": return Theme.accent
        case "bhagat": return Ink.info
        case "bhatt": return Ink.special
        default: return AccentPalette.teal.accent   // gursikh — web parity teal
        }
    }

    /// "GURU · M5" / "BHAGAT" style tag.
    var kindTag: String {
        if kind == "guru", let seq { return "GURU · M\(seq)" }
        return kind.uppercased()
    }

    /// "c. 1173–1266" lifespan chip text; nil when nothing is known.
    var lifespan: String? {
        guard let born else { return died.map { "d. \(String($0))" } }
        let prefix = circa ? "c. " : ""
        return died.map { "\(prefix)\(String(born))–\(String($0))" } ?? "\(prefix)b. \(String(born))"
    }
}

/// Signature themes: the theme's English label (from `concepts`), its lift as a gradient track.
struct SignatureThemesList: View {
    let themes: [TopTheme]
    let color: Color
    let descriptions: [String: String]
    /// concept → its head Gurmukhi term (`concepts.gurmukhi_terms[0]`), drawn in Sant Lipi.
    var terms: [String: String] = [:]
    var onOpen: ((String) -> Void)? = nil

    var body: some View {
        let maxLift = max(themes.map(\.lift).max() ?? 1, 0.001)
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text("Signature themes").font(.headline).accessibilityAddTraits(.isHeader)
            Text("Theme emphasis vs the corpus baseline (lift) — descriptive, never a ranking of scripture.")
                .font(.caption2).foregroundStyle(.secondary)
            ForEach(themes) { t in
                let label = ConceptName.label(t.concept, description: descriptions[t.concept])
                Button { onOpen?(t.concept) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                            if let g = terms[t.concept] { GurmukhiText(verbatim: g, size: 19) }
                            Text(label).font(.subheadline)
                            Spacer(minLength: Theme.Space.s)
                            Text(String(format: "%.1f×", t.lift)).font(.caption).monospacedDigit()
                                .foregroundStyle(.secondary)
                            if onOpen != nil {
                                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                        // the web .ld-ttrack treatment: a lift/maxLift gradient track
                        GeometryReader { geo in
                            Capsule().fill(Ink.raised)
                                .overlay(alignment: .leading) {
                                    Capsule()
                                        .fill(LinearGradient(colors: [color, AccentPalette.gold.accent],
                                                             startPoint: .leading, endPoint: .trailing))
                                        .frame(width: max(4, geo.size.width * CGFloat(t.lift / maxLift)))
                                }
                        }
                        .frame(height: 6)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(onOpen == nil)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(label), \(String(format: "%.1f", t.lift)) times the corpus baseline")
                .accessibilityHint(onOpen == nil ? "" : "Opens this theme")
                .accessibilityAddTraits(onOpen == nil ? [] : .isButton)
            }
        }
    }
}

struct FlowTermChips: View {
    let terms: [DistinctiveTerm]
    var onOpen: ((String) -> Void)? = nil
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96))], alignment: .leading, spacing: Theme.Space.s) {
            ForEach(terms) { t in
                Button { onOpen?(t.term) } label: {
                    GurmukhiText(verbatim: t.term, size: 18)
                        .padding(.horizontal, Theme.Space.s).padding(.vertical, 4)
                        .background(Capsule().fill(Ink.raised))
                        .overlay(Capsule().strokeBorder(Ink.hairline))
                }
                .buttonStyle(.plain)
                .disabled(onOpen == nil)
                .accessibilityHint(onOpen == nil ? "" : "Searches the Granth for this word")
            }
        }
    }
}

/// Small capsule chips for the profile's life facts (kind · lifespan · region · tradition).
struct FlowChipsRow: View {
    let chips: [String]
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 90))], alignment: .leading, spacing: Theme.Space.xs) {
            ForEach(chips, id: \.self) { chip in
                Text(chip)
                    .font(.caption2)
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .padding(.horizontal, Theme.Space.s).padding(.vertical, 4)
                    .background(Capsule().fill(Ink.raised))
                    .overlay(Capsule().strokeBorder(Ink.hairline))
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// ⇄ Compare two voices: radar overlay of their 12-axis theme fingerprints + stat columns.
struct CompareVoicesSheet: View {
    let a: Contributor
    let b: Contributor
    /// Canonical counts (`lines`, headers excluded) — the same numbers as the cards.
    var summaryA: VoiceSummary? = nil
    var summaryB: VoiceSummary? = nil
    @Environment(AppContainer.self) private var container
    @Environment(\.dismiss) private var dismiss
    @State private var pa: AuthorProfile?
    @State private var pb: AuthorProfile?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    HStack {
                        legendDot(Theme.accent, a.displayName)
                        Spacer()
                        legendDot(Ink.info, b.displayName)
                    }
                    if let pa, let pb {
                        RadarCompareView(a: pa, b: pb, colorA: Theme.accent, colorB: Ink.info)
                            .frame(height: 280)
                            .accessibilityHidden(true)   // the table below is the a11y path
                        radarTable(pa, pb)
                        statColumns(pa, pb)
                    } else {
                        ProgressView().frame(maxWidth: .infinity)
                    }
                    Text("Theme emphasis = lift vs the corpus baseline; stylometry on the English translation. Descriptive only — never a ranking of scripture.")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                .padding()
            }
            .navigationTitle("\(a.displayName) ⇄ \(b.displayName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .task {
            if container.meta == nil { await container.loadMeta() }
            guard pa == nil, let corpus = container.corpus else { return }
            pa = await corpus.authorProfile(a.name, full: false)
            pb = await corpus.authorProfile(b.name, full: false)
        }
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).font(.caption.weight(.medium))
        }
    }

    private var descriptions: [String: String] {
        Dictionary((container.meta?.concepts ?? []).map { ($0.concept, $0.description) }, uniquingKeysWith: { a, _ in a })
    }

    /// Accessible/table alternative for the radar (also the exact numbers).
    private func radarTable(_ pa: AuthorProfile, _ pb: AuthorProfile) -> some View {
        let axes = RadarCompareView.axes(pa, pb)
        return VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text("Theme emphasis (lift)").font(.headline)
            Grid(alignment: .leading, horizontalSpacing: Theme.Space.m, verticalSpacing: Theme.Space.xs) {
                GridRow {
                    Text("Theme").font(.caption.weight(.semibold))
                    Text(a.displayName).font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
                    Text(b.displayName).font(.caption.weight(.semibold)).foregroundStyle(Ink.info)
                }
                ForEach(axes, id: \.self) { axis in
                    GridRow {
                        Text(ConceptName.label(axis, description: descriptions[axis])).font(.caption)
                        Text(String(format: "%.2f", RadarCompareView.lift(pa, axis))).font(.caption).monospacedDigit()
                        Text(String(format: "%.2f", RadarCompareView.lift(pb, axis))).font(.caption).monospacedDigit()
                    }
                }
            }
        }
    }

    private func statColumns(_ pa: AuthorProfile, _ pb: AuthorProfile) -> some View {
        Grid(alignment: .leading, horizontalSpacing: Theme.Space.m, verticalSpacing: Theme.Space.xs) {
            GridRow {
                Text("").font(.caption)
                Text(a.displayName).font(.caption.weight(.semibold))
                Text(b.displayName).font(.caption.weight(.semibold))
            }
            statRow("Verses", summaryA?.nVerses, summaryB?.nVerses)
            statRow("Compositions", summaryA?.nCompositions, summaryB?.nCompositions)
            GridRow {
                Text("Raags").font(.caption)
                raagCell(summaryA)
                raagCell(summaryB)
            }
        }
    }

    private func statRow(_ label: String, _ va: Int?, _ vb: Int?) -> some View {
        GridRow {
            Text(label).font(.caption)
            Text(va.map { $0.formatted() } ?? "—").font(.caption).monospacedDigit()
            Text(vb.map { $0.formatted() } ?? "—").font(.caption).monospacedDigit()
        }
    }

    /// "Outside the raag sections" for a voice with no raag (the Bhatts), never "0".
    @ViewBuilder private func raagCell(_ s: VoiceSummary?) -> some View {
        if let s, s.nRaags == 0 {
            Text(VoiceCopy.outsideRaags).font(.caption)
        } else {
            Text(s.map { $0.nRaags.formatted() } ?? "—").font(.caption).monospacedDigit()
        }
    }
}

/// Canvas polar radar: the union of both authors' top themes as axes, lift as radius.
/// Decorative — CompareVoicesSheet renders the numbers as a Grid for accessibility.
struct RadarCompareView: View {
    let a: AuthorProfile
    let b: AuthorProfile
    let colorA: Color
    let colorB: Color

    /// Up to 12 shared axes: union of both fingerprints ranked by combined lift.
    static func axes(_ a: AuthorProfile, _ b: AuthorProfile) -> [String] {
        var combined: [String: Double] = [:]
        for ax in a.fingerprint { combined[ax.concept, default: 0] += ax.lift }
        for ax in b.fingerprint { combined[ax.concept, default: 0] += ax.lift }
        return combined.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(12).map { $0.key }
    }

    static func lift(_ p: AuthorProfile, _ concept: String) -> Double {
        p.fingerprint.first { $0.concept == concept }?.lift ?? 0
    }

    var body: some View {
        Canvas { ctx, size in
            let axes = Self.axes(a, b)
            guard axes.count >= 3 else { return }
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2 - 36
            let maxLift = max(axes.map { max(Self.lift(a, $0), Self.lift(b, $0)) }.max() ?? 1, 0.001)

            func point(_ i: Int, _ value: Double) -> CGPoint {
                let angle = -Double.pi / 2 + 2 * .pi * Double(i) / Double(axes.count)
                let r = radius * CGFloat(value / maxLift)
                return CGPoint(x: center.x + cos(angle) * r, y: center.y + sin(angle) * r)
            }
            // rings + spokes
            for ring in [0.25, 0.5, 0.75, 1.0] {
                var path = Path()
                for i in 0...axes.count {
                    let pt = point(i % axes.count, maxLift * ring)
                    i == 0 ? path.move(to: pt) : path.addLine(to: pt)
                }
                ctx.stroke(path, with: .color(.secondary.opacity(0.2)), lineWidth: 0.5)
            }
            for (i, axis) in axes.enumerated() {
                var spoke = Path(); spoke.move(to: center); spoke.addLine(to: point(i, maxLift))
                ctx.stroke(spoke, with: .color(.secondary.opacity(0.15)), lineWidth: 0.5)
                let labelPt = point(i, maxLift * 1.16)
                ctx.draw(Text(ConceptName.display(axis)).font(.system(size: 8)).foregroundStyle(.secondary), at: labelPt)
            }
            // polygons
            for (profile, color) in [(a, colorA), (b, colorB)] {
                var poly = Path()
                for (i, axis) in axes.enumerated() {
                    let pt = point(i, Self.lift(profile, axis))
                    i == 0 ? poly.move(to: pt) : poly.addLine(to: pt)
                }
                poly.closeSubpath()
                ctx.fill(poly, with: .color(color.opacity(0.18)))
                ctx.stroke(poly, with: .color(color), lineWidth: 1.5)
            }
        }
    }
}
