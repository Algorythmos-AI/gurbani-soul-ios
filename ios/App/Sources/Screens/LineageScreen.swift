import SwiftUI
import GurbaniSearchKit

/// The Contributors: the voices across five centuries gathered into one Granth — the Gurus,
/// the Bhagats of the Bhakti and Sufi traditions, the court Bhatts, the Gursikh companions.
/// Lenses: Roll (cards by century, tradition or Bani preserved, each with an Ang barcode),
/// River (lifespans on one timeline) and, once the roster carries places, Map. A card pushes
/// the voice's page; ⇄ compares two voices. Counts are canonical (`lines`, headers excluded)
/// and describe how much Bani is preserved here — NEVER a voice's importance.
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
            if contributors != nil {
                let voices = split.voices
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Space.l) {
                        hero(voices)
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
                            ForEach(bands(voices), id: \.title) { band in
                                bandView(band.title, band.members)
                            }
                        case .river:
                            // River taps follow the same rule as cards: in compare mode they pick.
                            VoiceRiverView(voices: voices.filter { kindFilter == "all" || $0.kind == kindFilter }) { c in
                                select(c)
                            }
                        }
                        if !split.withoutBani.isEmpty {
                            Text("Not counted: \(LineageFacts.join(split.withoutBani.map(\.displayName), .current)). No verses carry this attribution in this edition of the data; it is under review.")
                                .font(.caption).foregroundStyle(.secondary)
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
        // The Voice of the day turns over at the reader's midnight even if Lineage stays open.
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in refreshVoiceOfTheDay() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            refreshVoiceOfTheDay()
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
                        let voices = split.voices
                        let count = k.id == "all" ? voices.count : voices.filter { $0.kind == k.id }.count
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

    /// Voices with Bani in the loaded DB (counted, listed) and roster entries without (a note).
    private var split: (voices: [Contributor], withoutBani: [Contributor]) {
        LineageCount.split(contributors ?? [], withBani: Set(summaries.keys))
    }

    private func open(_ c: Contributor) {
        container.router.explorePath.append(VoiceLink(name: c.name))
    }

    /// A tap on a voice (card or River lifespan): picks it in compare mode, else opens it.
    private func select(_ c: Contributor) {
        guard compareMode else { return open(c) }
        if comparePicks.contains(c) { comparePicks.removeAll { $0 == c }; return }
        comparePicks.append(c)
        if comparePicks.count == 2 {
            comparePair = ComparePair(a: comparePicks[0], b: comparePicks[1])
            compareMode = false
            comparePicks = []
        }
    }

    // MARK: voice of the day — one voice and one of its rahao verses, the same all day

    private func refreshVoiceOfTheDay() {
        guard let corpus = container.corpus else { return }
        Task { voiceOfTheDay = await pickVoiceOfTheDay(corpus) }
    }

    private func pickVoiceOfTheDay(_ corpus: CorpusActor) async -> VoiceOfTheDay? {
        let candidates = (contributors ?? []).filter { summaries[$0.name] != nil }.sorted { $0.name < $1.name }
        let day = HukamOfTheDay.dayNumber(of: Date())
        guard let i = VoiceOfTheDayPick.voiceIndex(day: day, count: candidates.count) else { return nil }
        let c = candidates[i]
        let deck = await corpus.authorRahao(c.name)
        let fallback = deck.verses.isEmpty ? await corpus.authorCompositions(c.name).first.map {
            VoiceVerse(id: $0.firstLineId, ang: $0.ang, compId: $0.compId, gurmukhi: $0.opening)
        } : nil
        return VoiceOfTheDayPick.verse(day: day, voiceCount: candidates.count, rahao: deck.verses, fallback: fallback)
            .map { VoiceOfTheDay(contributor: c, verse: $0) }
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
        let facts = LineageFacts.build(signatureRaags: signatureRaags, dialogue: dialogueSpan,
                                       bhatts: bhatts, name: displayName)
        if !facts.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                SectionEyebrow(text: "Did you know")
                ForEach(facts, id: \.id) { f in
                    Button { if let c = f.author.flatMap(voice) { open(c) } } label: {
                        HStack(alignment: .top, spacing: Theme.Space.s) {
                            if let g = f.gurmukhi { GurmukhiText(verbatim: g, size: 20) }
                            Text(f.text).font(.callout)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if f.author != nil {
                                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                        .padding(Theme.Space.m)
                        .background(Ink.card, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
                        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(Ink.hairline))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(f.author == nil)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func voice(_ author: String) -> Contributor? { contributors?.first { $0.name == author } }
    private func displayName(_ author: String) -> String { voice(author)?.displayName ?? AuthorName(author).english }


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
        return Button { select(c) } label: {
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
                            // Ink, not the tradition colour: the Gurus' colour is brand gold, which
                            // is never text (brand book); the rail dot and medallion ring carry it.
                            Text(c.kindTag)
                                .font(.caption2.weight(.semibold)).kerning(0.5)
                                .foregroundStyle(.secondary)
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
        // One element per card: the label goes on the Button itself. Wrapping the Button in
        // `.accessibilityElement(children: .ignore)` made a second element with the same frame —
        // VoiceOver read each card twice and a UI-test tap could land on the wrong one.
        .accessibilityLabel("\(c.displayName), \(c.kind), \(c.era.isEmpty ? "undated" : c.era), "
                            + (summary.map { Self.countLine($0) } ?? "attribution under review"))
        .accessibilityHint(compareMode ? "Selects for comparison" : "Opens their page")
        .accessibilityIdentifier("voiceCard_\(c.slug)")
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
                .accessibilityLabel("\(label), \(String(format: "%.1f", t.lift)) times the corpus baseline")
                .accessibilityHint(onOpen == nil ? "" : "Opens this theme")
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
