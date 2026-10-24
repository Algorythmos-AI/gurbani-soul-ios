import SwiftUI
import GurbaniSearchKit

/// A pushed voice on Explore › Lineage (sggs-data/Lineage v2 §2b). Every verse is verbatim from
/// the DB and cited by Ang; every count is the canonical one (`lines`, headers excluded). Sections
/// whose data is absent — a pipeline table an older DB lacks, a roster v2 field not yet written —
/// hide themselves. Descriptive throughout: the size of a voice's Bani is never its importance.
struct VoicePage: View {
    let contributor: Contributor
    let summary: VoiceSummary?
    /// The whole roster, for names of other voices and "Lived alongside".
    let roster: [Contributor]

    @Environment(AppContainer.self) private var container
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.colorScheme) private var scheme
    @State private var data: VoiceData?
    @State private var raagSheet: RaagShare?
    @State private var shareImage: Image?

    /// Everything the page reads, in one Sendable value (loaded off the main thread by CorpusActor).
    struct VoiceData: Sendable {
        var raags: [RaagShare] = []
        var rahao: RahaoDeck = .empty
        var compositions: [VoiceComposition] = []
        var facts: AuthorFacts?
        var profile: AuthorProfile?
        var mentions: VoiceMentions = .empty
        var dialogues: [VoiceDialogue] = []
        var echoes: [VoiceEcho] = []
        var signatureVerses: [VoiceVerse] = []
        var headTerms: [String: String] = [:]
    }

    private var k: Color { contributor.kindColor }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                hero
                if let summary { baniSection(summary) }
                if let data {
                    raagSection(data)
                    rahaoSection(data)
                    notableSection
                    signatureSection(data)
                    themesSection(data)
                    wordsSection(data)
                    dialoguesSection(data)
                    mentionsSection(data)
                    contemporariesSection
                    echoesSection(data)
                    actions(data)
                } else {
                    ProgressView().frame(maxWidth: .infinity)
                }
            }
            .padding(Theme.Space.l)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .background(Ink.canvas)
        .contentMargins(.bottom, Theme.Space.xl, for: .scrollContent)
        .navigationTitle(contributor.displayName)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if let shareImage {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: shareImage,
                              preview: SharePreview(contributor.displayName, image: shareImage)) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
        .sheet(item: $raagSheet) { r in
            RaagCompositionsSheet(author: contributor.name, voice: contributor.displayName, raag: r)
        }
        .task { await load() }
    }

    // MARK: load

    private func load() async {
        guard data == nil, let corpus = container.corpus else { return }
        if container.meta == nil { await container.loadMeta() }
        let name = contributor.name
        var d = VoiceData()
        d.raags = await corpus.authorRaags(name)
        d.rahao = await corpus.authorRahao(name)
        d.compositions = await corpus.authorCompositions(name)
        d.facts = await corpus.authorFacts(name)
        d.profile = await corpus.authorProfile(name, full: false)
        d.mentions = await corpus.authorMentions(name)
        d.dialogues = await corpus.authorDialogues(name)
        d.echoes = await corpus.authorEchoes(name)
        d.headTerms = await corpus.conceptHeadTerms()
        for token in signatureTokens {
            d.signatureVerses = await corpus.authorVerses(name, containing: token, limit: 3)
            if !d.signatureVerses.isEmpty { break }
        }
        data = d
        shareImage = renderShareCard(d)
    }

    /// The pen-name a voice signs with: roster v2 `chhap`, or "Nanak" for every Guru. A token is
    /// only ever shown inside the verbatim verses that contain it.
    private var signatureTokens: [String] {
        if let chhap = contributor.chhap, !chhap.isEmpty { return chhap }
        return contributor.mahala != nil ? ["ਨਾਨਕ"] : []
    }

    private func name(of author: String) -> String {
        roster.first { $0.name == author }?.displayName ?? AuthorName(author).english
    }

    // MARK: hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack(alignment: .center, spacing: Theme.Space.l) {
                VoiceMedallionView(contributor: contributor, diameter: 84)
                    .visualEffect { content, proxy in
                        // A gentle parallax as the page scrolls; none under Reduce Motion.
                        content.offset(y: reduceMotion ? 0 : max(0, -proxy.frame(in: .scrollView).minY) * 0.35)
                    }
                VStack(alignment: .leading, spacing: 4) {
                    if let g = contributor.gurmukhi { GurmukhiText(verbatim: g, size: 30) }
                    Text(contributor.kindTag)
                        .font(.caption.weight(.semibold)).kerning(0.6)
                        .foregroundStyle(.secondary)
                }
            }
            FlowChipsRow(chips: [contributor.lifespan, contributor.birthplace ?? contributor.region,
                                 contributor.tradition].compactMap { $0 }.filter { !$0.isEmpty })
            if let note = contributor.rangeNote {
                Text(note).font(.caption).foregroundStyle(.secondary)
            }
            if !contributor.lifeText.isEmpty {
                Text(contributor.lifeText).font(.body)
            }
            if contributor.awaitingReview {
                Label("Context pending scholarly review", systemImage: "hourglass")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let sources = contributor.sources, !sources.isEmpty {
                DisclosureGroup("Sources") {
                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        ForEach(sources, id: \.self) { s in
                            Text([s.ref, s.entry].compactMap { $0 }.joined(separator: " — "))
                                .font(.caption).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.top, Theme.Space.xs)
                }
                .font(.subheadline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Space.l)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: Theme.Radius.card).fill(Ink.card)
                RoundedRectangle(cornerRadius: Theme.Radius.card)
                    .fill(RadialGradient(colors: [k.opacity(0.24), .clear], center: .topLeading,
                                         startRadius: 0, endRadius: 360))
            }
        )
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(Ink.hairline))
    }

    // MARK: 1. their Bani in the Granth

    private func baniSection(_ s: VoiceSummary) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            SectionEyebrow(text: "Their Bani in the Granth")
            AngBarcode(angs: s.angs, color: k, height: 32, marksRaagEnd: true) { ang in
                container.router.openAng(ang)
            }
            Text("On \(s.angs.count.formatted()) of 1,430 Angs, from Ang \(s.firstAng) to Ang \(s.lastAng). Tap a mark to open that Ang; the thin line is Ang 1353, where the raag sections end.")
                .font(.caption).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: Theme.Space.s) {
                StatTile(value: s.nVerses.formatted(), caption: s.nVerses == 1 ? "verse" : "verses")
                StatTile(value: s.nCompositions.formatted(), caption: s.nCompositions == 1 ? "composition" : "compositions")
                if let total = data?.rahao.totalLines, total > 0 {
                    StatTile(value: total.formatted(), caption: total == 1 ? "rahao verse" : "rahao verses")
                }
                if s.nRaags == 0 {
                    StatTile(value: "—", caption: VoiceCopy.outsideRaags)
                } else {
                    StatTile(value: s.nRaags.formatted(), caption: s.nRaags == 1 ? "raag" : "raags")
                }
                if let outside = data?.facts?.outsideRaagVerses, outside > 0, s.nRaags > 0 {
                    StatTile(value: outside.formatted(), caption: "verses after the raag sections")
                }
                // Gurmukhi stylometry (author_facts). The English-translation figures are not shown.
                if let m = data?.facts?.mattr100 {
                    StatTile(value: String(format: "%.2f", m), caption: "vocabulary range")
                }
            }
        }
    }

    // MARK: 2. raags

    @ViewBuilder private func raagSection(_ d: VoiceData) -> some View {
        if !d.raags.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                SectionEyebrow(text: "Raags")
                RaagRibbon(raags: d.raags, color: k)
                    .frame(height: 14)
                    .accessibilityHidden(true)   // the rows below carry the numbers
                if d.raags.contains(where: \.isSignature) {
                    Text("✦ marks a raag in which no other voice of the Granth sings.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                VStack(spacing: 0) {
                    ForEach(d.raags) { r in
                        Button { raagSheet = r } label: { raagRow(r) }
                            .buttonStyle(.plain)
                        if r.id != d.raags.last?.id { Divider() }
                    }
                }
                .padding(.horizontal, Theme.Space.m)
                .background(Ink.card, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(Ink.hairline))
            }
        }
    }

    private func raagRow(_ r: RaagShare) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
            GurmukhiText(verbatim: r.raag, size: 20)
            if r.isSignature {
                Text("✦").font(.caption).foregroundStyle(.secondary).accessibilityHidden(true)
            }
            Spacer(minLength: Theme.Space.s)
            Text("\(r.nVerses.formatted()) \(r.nVerses == 1 ? "verse" : "verses") · \(r.nCompositions) \(r.nCompositions == 1 ? "shabad" : "shabads")")
                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                .multilineTextAlignment(.trailing)
            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.vertical, Theme.Space.s)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityValue(r.isSignature ? "Only this voice sings in this raag" : "")
        .accessibilityHint("Lists their compositions in this raag")
    }

    // MARK: 3. rahao

    @ViewBuilder private func rahaoSection(_ d: VoiceData) -> some View {
        if !d.rahao.verses.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                SectionEyebrow(text: "The heart of each shabad · Rahao")
                // Interpretation waits for the scholar (G3); the count is a structural fact.
                if EditorialGate.aboutCopy {
                    Text("The rahao verse holds a shabad's centre.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text("\(d.rahao.shabads.formatted()) of their shabads carry a rahao verse; tap one to read the whole shabad.")
                    .font(.caption).foregroundStyle(.secondary)
                if typeSize.isAccessibilitySize {
                    VStack(spacing: Theme.Space.s) {
                        ForEach(d.rahao.verses.prefix(8)) { v in verseCard(v) }
                    }
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(alignment: .top, spacing: Theme.Space.m) {
                            ForEach(d.rahao.verses) { v in verseCard(v).frame(width: 290) }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollTargetBehavior(.viewAligned)
                }
            }
        }
    }

    private func verseCard(_ v: VoiceVerse) -> some View {
        Button {
            container.present(.shabad(compId: v.compId, focusLineId: v.id))
        } label: {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                GurmukhiText(verbatim: v.gurmukhi, size: 21)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 0)
                Text("Ang \(v.ang)").font(.caption).foregroundStyle(.secondary)
            }
            .padding(Theme.Space.m)
            .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
            .background(Ink.card, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(Ink.hairline))
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressableCard)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the shabad")
    }

    /// A compact verbatim verse row with its Ang (signatures, dialogues, mentions).
    private func verseRow(_ v: VoiceVerse) -> some View {
        Button {
            container.present(.shabad(compId: v.compId, focusLineId: v.id))
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                GurmukhiText(verbatim: v.gurmukhi, size: 19)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Ang \(v.ang)").font(.caption2).foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the shabad")
    }

    // MARK: 4. notable Banis (roster v2)

    @ViewBuilder private var notableSection: some View {
        let items = (contributor.notable ?? []).filter { $0.compId != nil }
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                SectionEyebrow(text: "Notable Banis")
                ForEach(items, id: \.self) { n in
                    Button {
                        if let c = n.compId { container.present(.shabad(compId: c)) }
                    } label: {
                        Label(n.title, systemImage: "book.closed")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    // MARK: 5. how they sign

    @ViewBuilder private func signatureSection(_ d: VoiceData) -> some View {
        if !d.signatureVerses.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                SectionEyebrow(text: "How they sign")
                if EditorialGate.aboutCopy {
                    Text(contributor.mahala != nil
                         ? "Every Guru signs the Bani with the name Nanak; the Mahala number in each heading tells the Gurus apart."
                         : "This voice signs the Bani with their own name, usually in a shabad's closing verse.")
                        .font(.callout)
                }
                if let n = d.facts?.chhapCount, n > 0 {
                    Text("\(n.formatted()) of their verses carry the signature.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(d.signatureVerses) { v in verseRow(v) }
            }
        }
    }

    // MARK: 6. themes

    @ViewBuilder private func themesSection(_ d: VoiceData) -> some View {
        if let themes = d.profile?.stylometry?.topThemes, !themes.isEmpty {
            SignatureThemesList(themes: themes, color: k, descriptions: conceptDescriptions,
                                terms: d.headTerms) { slug in
                container.router.explorePath.append(Route.theme(slug))
            }
        }
    }

    private var conceptDescriptions: [String: String] {
        Dictionary((container.meta?.concepts ?? []).map { ($0.concept, $0.description) }, uniquingKeysWith: { a, _ in a })
    }

    // MARK: 7. distinctive words (Gurmukhi only)

    @ViewBuilder private func wordsSection(_ d: VoiceData) -> some View {
        if let terms = d.profile?.distinctiveTerms, AuthorProfileCopy.isGurmukhi(terms) {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                SectionEyebrow(text: "Distinctive words")
                Text("Words this voice uses far more than the rest of the Granth. Tap one to search for it.")
                    .font(.caption).foregroundStyle(.secondary)
                FlowTermChips(terms: terms) { term in
                    container.router.pendingSearchQuery = term
                    container.router.selectedTab = .search
                }
            }
        }
    }

    // MARK: 8. in dialogue

    @ViewBuilder private func dialoguesSection(_ d: VoiceData) -> some View {
        if !d.dialogues.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                SectionEyebrow(text: "In dialogue")
                if EditorialGate.aboutCopy {
                    Text("In the salok collections, saloks of the Gurus are set beside saloks of the Bhagats.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(d.dialogues.prefix(6)) { pair in
                    VStack(alignment: .leading, spacing: Theme.Space.s) {
                        Text(name(of: pair.bhagatAuthor)).font(.subheadline.weight(.semibold))
                        ForEach(pair.bhagat) { v in verseRow(v) }
                        Label("Saloks of the Gurus set beside this salok", systemImage: "arrow.down")
                            .font(.caption).foregroundStyle(.secondary)
                        Text(name(of: pair.guruAuthor)).font(.subheadline.weight(.semibold))
                        ForEach(pair.guru) { v in verseRow(v) }
                    }
                    .padding(Theme.Space.m)
                    .background(Ink.card, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(Ink.hairline))
                }
                if d.dialogues.count > 6 {
                    Text("\(d.dialogues.count - 6) more in the salok collections.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: 9. named in Gurbani / they name

    @ViewBuilder private func mentionsSection(_ d: VoiceData) -> some View {
        if !d.mentions.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                if !d.mentions.namedBy.isEmpty {
                    SectionEyebrow(text: "Named in Gurbani")
                    ForEach(d.mentions.namedBy.prefix(6)) { m in mentionRow(m, who: name(of: m.speaker)) }
                }
                if !d.mentions.names.isEmpty {
                    SectionEyebrow(text: "They name")
                    ForEach(d.mentions.names.prefix(6)) { m in mentionRow(m, who: name(of: m.named)) }
                }
            }
        }
    }

    private func mentionRow(_ m: VoiceMention, who: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(who).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            verseRow(m.verse)
        }
    }

    // MARK: 10. lived alongside

    private var contemporaries: [Contributor] {
        guard let b = contributor.born, let e = contributor.died else { return [] }
        return roster.filter { o in
            guard o.name != contributor.name, let ob = o.born, let oe = o.died else { return false }
            return ob <= e && b <= oe
        }
        .sorted { ($0.born ?? 0) < ($1.born ?? 0) }
    }

    @ViewBuilder private var contemporariesSection: some View {
        let list = contemporaries
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                SectionEyebrow(text: "Lived alongside")
                Text("From circa dates — an overlap of lifetimes, not a record of meeting.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(list) { o in
                    Button {
                        container.router.explorePath.append(VoiceLink(name: o.name))
                    } label: {
                        HStack {
                            Text(o.displayName).font(.subheadline)
                            Spacer()
                            Text(o.lifespan ?? "").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens their page")
                }
            }
        }
    }

    // MARK: 11. echoes

    @ViewBuilder private func echoesSection(_ d: VoiceData) -> some View {
        if !d.echoes.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                SectionEyebrow(text: "Echoes")
                Text("Voices whose verses share the most wording and themes with theirs — descriptive, never a ranking.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(d.echoes) { e in
                    Button {
                        container.router.explorePath.append(VoiceLink(name: e.author))
                    } label: {
                        HStack {
                            Text(name(of: e.author)).font(.subheadline)
                            Spacer()
                            Text("\(e.edges) verse links").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens their page")
                }
            }
        }
    }

    // MARK: 12. actions

    @ViewBuilder private func actions(_ d: VoiceData) -> some View {
        if let first = d.compositions.first {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Button {
                    container.router.openAng(first.ang, lineId: first.firstLineId)
                } label: {
                    Label("Begin their first shabad · Ang \(String(first.ang))", systemImage: "book")
                }
                .buttonStyle(.prominentPill)
                .accessibilityIdentifier("voiceBeginFirst")
                let whole = d.compositions.filter { $0.nVerses >= 2 }
                if !whole.isEmpty {
                    Button {
                        if let c = whole.randomElement() {
                            container.present(.shabad(compId: c.compId, focusLineId: c.firstLineId))
                        }
                    } label: {
                        Label("A shabad by them", systemImage: "shuffle")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    // MARK: share card

    @MainActor private func renderShareCard(_ d: VoiceData) -> Image? {
        guard let verse = d.rahao.verses.first ?? d.compositions.first.map({
            VoiceVerse(id: $0.firstLineId, ang: $0.ang, compId: $0.compId, gurmukhi: $0.opening)
        }) else { return nil }
        let renderer = ImageRenderer(content: VoiceShareCard(name: contributor.displayName,
                                                             gurmukhiName: contributor.gurmukhi,
                                                             verse: verse)
            .environment(\.colorScheme, scheme))
        renderer.scale = 3
        return renderer.uiImage.map { Image(uiImage: $0) }
    }
}

/// Pushes a voice's page on the Explore stack (Lineage registers the destination).
struct VoiceLink: Hashable { let name: String }

/// Shared copy rules for the voice surfaces.
enum AuthorProfileCopy {
    /// Distinctive terms are shown only when they are Gurmukhi tokens. Today's table is built on
    /// the English translation — an unlicensed layer — so it stays hidden until sggs-data ships
    /// the Gurmukhi rebuild.
    static func isGurmukhi(_ terms: [DistinctiveTerm]) -> Bool {
        !terms.isEmpty && terms.allSatisfy { t in
            t.term.unicodeScalars.contains { (0x0A00...0x0A7F).contains($0.value) }
        }
    }
}

/// Proportional raag segments (verses per raag); ✦ on a signature raag when the segment is wide enough.
private struct RaagRibbon: View {
    let raags: [RaagShare]
    let color: Color
    var body: some View {
        GeometryReader { geo in
            let total = max(1, raags.reduce(0) { $0 + $1.nVerses })
            let gaps = CGFloat(max(0, raags.count - 1))
            let usable = max(0, geo.size.width - gaps)
            HStack(spacing: 1) {
                ForEach(Array(raags.enumerated()), id: \.element.id) { i, r in
                    let w = max(2, usable * CGFloat(r.nVerses) / CGFloat(total))
                    Rectangle()
                        .fill(color.opacity(i.isMultiple(of: 2) ? 0.85 : 0.5))
                        .frame(width: w)
                        .overlay {
                            if r.isSignature && w > 14 {
                                Text("✦").font(.system(size: 9)).foregroundStyle(.primary)
                            }
                        }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 3))
        }
    }
}

/// A voice's compositions in one raag, each opening verse verbatim; tap → the Reader at that verse.
struct RaagCompositionsSheet: View {
    let author: String
    let voice: String
    let raag: RaagShare
    @Environment(AppContainer.self) private var container
    @Environment(\.dismiss) private var dismiss
    @State private var compositions: [VoiceComposition]?

    var body: some View {
        NavigationStack {
            Group {
                if let compositions {
                    List(compositions) { c in
                        Button {
                            dismiss()
                            container.router.openAng(c.ang, lineId: c.firstLineId)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                GurmukhiText(verbatim: c.opening, size: 19)
                                Text("Ang \(c.ang) · \(c.nVerses) \(c.nVerses == 1 ? "verse" : "verses")")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityHint("Opens the Reader at this shabad")
                    }
                } else {
                    ProgressView()
                }
            }
            .safeAreaInset(edge: .top) {
                HStack(spacing: Theme.Space.s) {
                    GurmukhiText(verbatim: raag.raag, size: 22)
                    Text("· \(voice)").font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal).padding(.vertical, Theme.Space.s)
                .background(.bar)
            }
            .navigationTitle(raag.roman.isEmpty ? "Raag" : raag.roman.prefix(1).uppercased() + raag.roman.dropFirst())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .task {
            guard compositions == nil, let corpus = container.corpus else { return }
            compositions = await corpus.authorCompositions(author, raag: raag.raag)
        }
    }
}

/// The share image: the voice's name, one rahao verse verbatim, the full citation. Fixed size by
/// design (like VerseCardView): Dynamic Type must not reflow a shared image.
private struct VoiceShareCard: View {
    let name: String
    let gurmukhiName: String?
    let verse: VoiceVerse

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(name).font(.system(size: 20, weight: .semibold, design: .serif)).foregroundStyle(.primary)
            if let gurmukhiName {
                Text(gurmukhiName).font(Brand.gurmukhi(24)).foregroundStyle(.primary)
            }
            Text(verse.gurmukhi)
                .font(Brand.gurmukhi(30))
                .lineSpacing(16)
                .foregroundStyle(.primary)
            HStack {
                RoundedRectangle(cornerRadius: 1)
                    .fill(AccentPalette.brandDefault.heroGradient)
                    .frame(width: 44, height: 2.5)
                Text("Sri Guru Granth Sahib Ji · Ang \(String(verse.ang))")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AccentPalette.gold.accentText)
            }
            Text("Gurbani Soul · Voices of the Granth")
                .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
        }
        .padding(28)
        .frame(width: 480, alignment: .leading)
        .background(Ink.paper)
    }
}

/// The zoom from a Lineage card into its voice page (iOS 18+; a plain push before that and under
/// Reduce Motion).
struct VoiceZoomSource: ViewModifier {
    let id: String
    let namespace: Namespace.ID
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.matchedTransitionSource(id: id, in: namespace)
        } else {
            content
        }
    }
}

struct VoiceZoomDestination: ViewModifier {
    let id: String
    let namespace: Namespace.ID
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *), !reduceMotion {
            content.navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            content
        }
    }
}
