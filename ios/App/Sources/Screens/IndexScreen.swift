import SwiftUI
import GurbaniSearchKit

/// Browse the Granth in its own order. Pill-switched: Compositions (the hero rail and the
/// registry shelf), Raags (the banis before the raags, the 31 raags, the banis after them) and
/// Voices. Stack-less: pushed inside the Explore NavigationStack.
///
/// A major composition opens its OWN reader (`Route.composition`, pushed on this same stack) so
/// Sukhmani Sahib reads as one work — cover, contents, saved position — instead of dropping the
/// Ang reader mid-page. Raags, sections and voices jump the Reader to their first Ang, and so
/// does a composition when this DB profile carries no bani registry.
struct IndexScreen: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.palette) private var palette
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// The open pill survives leaving and returning to the Index (and state restoration).
    @SceneStorage("index_tab") private var tab = "compositions"
    /// The bani registry — summary rows only, one query, never any lines; empty when this profile
    /// has no registry. Until it arrives a hero card falls back to opening its first Ang.
    @State private var registry: [BaniSummary] = []
    /// Raag name → cited primary pahars; empty when this DB carries no timing layer.
    @State private var pahars: [String: [Int]] = [:]
    /// The Reader's last Ang (its own resume key) — the Ribbon's "you are here".
    @AppStorage("sggs_last_ang") private var lastAng = 1
    /// Each hero's printed rhythm (by `Hero.id`), read once from its verbatim markers.
    @State private var shapes: [String: CompositionShape] = [:]
    /// Find in Index.
    @State private var query = ""
    /// `resumeKey` → whether that saved position resumes (filled by `checkResumable`).
    @State private var resumable: [String: Bool] = [:]
    /// The compositions whose printed headings name a poetic form (empty without the form layer).
    @State private var forms: [PoeticFormEntry] = []
    /// True once the forms read has returned (with rows, or none on a build without the layer).
    @State private var formsLoaded = false

    /// The pills. Forms appears only once the DB has shown it carries the heading-genre layer: a
    /// build without it gets no Forms pill rather than an empty tab.
    private var tabs: [(id: String, label: String)] {
        [("compositions", "Compositions"), ("raags", "Raags")]
            + (forms.isEmpty ? [] : [("forms", "Forms")])
            + [("authors", "Voices")]
    }

    private var columns: [GridItem] {
        let n = dynamicTypeSize.isAccessibilitySize ? 1 : 2
        return Array(repeating: GridItem(.flexible(), spacing: Theme.Space.m, alignment: .top), count: n)
    }

    var body: some View {
        Group {
            if let meta = container.meta {
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Space.l) {
                      if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                        IndexFindResults(query: query, meta: meta, registry: registry, forms: forms,
                                         openRaag: { openRaag($0, at: $0.firstAng) },
                                         openAng: { container.router.openAng($0) },
                                         openComposition: { container.present(.shabad(compId: $0)) })
                      } else {
                        ribbon(meta)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: Theme.Space.s) {
                                ForEach(tabs, id: \.id) { t in
                                    ModePill(title: t.label, isSelected: tab == t.id,
                                             accessibilityID: "index_\(t.id)") { tab = t.id }
                                }
                            }
                        }
                        switch tab {
                        case "raags":
                            IndexRaagsTab(map: GranthMap(meta: meta), pahars: pahars,
                                          openRaag: { openRaag($0, at: $0.firstAng) },
                                          openSection: { container.router.openAng($0.firstAng) },
                                          openClock: { container.router.explorePath.append(Route.clock) })
                        case "forms" where !forms.isEmpty || !formsLoaded:
                            IndexFormsTab(forms: forms, loaded: formsLoaded) { container.present(.shabad(compId: $0)) }
                        case "authors": authorsList(meta)
                        default: compositionsGrid
                        }
                      }
                    }
                    .padding(Theme.Space.l)
                    .appAnimation(Motion.gentle, value: tab)
                }
                .background(Ink.canvas)
                .contentMargins(.bottom, Theme.Space.xl, for: .scrollContent)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Index")
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .automatic),
                    prompt: "Find a raag, bani or voice")
        // One load, in order; each step is a no-op once its data is in (re-appearing costs
        // nothing). The reading rings come from `container.nitnem`, which is @Observable, so they
        // refresh themselves when a composition reader writes a position.
        .task(id: inProgress.map { resumeKey($0.id) }) { await checkResumable() }
        .task {
            await container.loadMeta()
            await loadRegistry()
            await loadPahars()
            await loadForms()
            await loadShapes()
        }
    }

    // MARK: the Ribbon

    private func ribbon(_ meta: CorpusMeta) -> some View {
        let map = GranthMap(meta: meta)
        return SaroopRibbon(layout: RibbonLayout(map: map), raagCount: map.raags.count,
                            pins: CompositionCatalog.heroes.map(\.ang),
                            hereAng: lastAng > 1 ? lastAng : nil) { segment, ang in
            if segment.movement == .raags, let r = map.raags.first(where: { $0.name == segment.name }) {
                openRaag(r, at: ang)
            } else {
                container.router.openAng(ang)
            }
        }
    }

    /// A raag opens its own page, pushed on this Explore stack (back returns to the Index).
    private func openRaag(_ r: RaagRow, at ang: Int) {
        container.router.explorePath.append(Route.raag(r.name))
    }

    private func loadRegistry() async {
        guard registry.isEmpty, let corpus = container.corpus, corpus.capabilities.hasBanis else { return }
        registry = await corpus.banis().banis
    }

    /// The heroes' outlines, read one bani at a time (the largest, Sukhmani, is ~2,000 lines).
    /// Only the reduced shape is kept; the lines are dropped as soon as it is computed.
    private func loadShapes() async {
        guard shapes.isEmpty, !registry.isEmpty, let corpus = container.corpus else { return }
        var out: [String: CompositionShape] = [:]
        for hero in CompositionCatalog.heroes where CompositionCatalog.resolve(hero, in: registry) != nil {
            if let bani = await corpus.bani(key: hero.key, variant: hero.variant) {
                out[hero.id] = CompositionShape(bani: bani)
            }
        }
        shapes = out
    }

    private func loadForms() async {
        guard !formsLoaded, let corpus = container.corpus else { return }
        forms = await corpus.poeticForms()
        formsLoaded = true
    }

    private func loadPahars() async {
        guard pahars.isEmpty, let corpus = container.corpus, corpus.capabilities.hasTiming else { return }
        pahars = GranthMap.primaryPahars(await corpus.timingClock())
    }

    // MARK: compositions — the hero rail

    private var compositionsGrid: some View {
        let heroes = CompositionCatalog.heroes
        return VStack(alignment: .leading, spacing: Theme.Space.l) {
            if let c = continueTarget { continueCard(c) }
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text("MAJOR COMPOSITIONS")
                    .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)
                // The opening bani spans the row: the rail starts where the Granth starts.
                if let lead = heroes.first { heroCard(lead, featured: true) }
                LazyVGrid(columns: columns, spacing: Theme.Space.m) {
                    ForEach(heroes.dropFirst()) { hero in
                        heroCard(hero, featured: false)
                    }
                }
            }
            let more = CompositionCatalog.more(from: registry)
            if !more.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    SectionEyebrow(text: "More compositions", symbol: "text.book.closed")
                    VStack(spacing: 0) {
                        ForEach(Array(more.enumerated()), id: \.element.id) { i, b in
                            NavigationLink(value: Route.composition(key: b.key, variant: b.variant)) {
                                BaniRow(bani: b, date: Date())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("composition_\(b.key)")
                            if i < more.count - 1 {
                                Divider().padding(.leading, Theme.Space.l * 2 + 28)
                            }
                        }
                    }
                    .background(Ink.card, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(Ink.hairline))
                }
            }
        }
    }

    /// One hero card. Titles and reading facts come from the registry when it resolves, so the
    /// card and the screen it opens always agree; the curated text is the no-registry fallback.
    @ViewBuilder
    private func heroCard(_ hero: CompositionCatalog.Hero, featured: Bool) -> some View {
        let summary = CompositionCatalog.resolve(hero, in: registry)
        let label = accessibilityLabel(hero, summary)
        if let summary {
            NavigationLink(value: Route.composition(key: hero.key, variant: hero.variant)) {
                heroCardBody(hero, summary, featured: featured)
            }
            .buttonStyle(.pressableCard)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(label)
            .accessibilityIdentifier("composition_\(hero.key)")
        } else {
            // No registry in this DB profile (or the key is missing): the card still works,
            // exactly as it always did, by opening the composition's first Ang.
            Button { container.router.openAng(hero.ang) } label: {
                heroCardBody(hero, nil, featured: featured)
            }
            .buttonStyle(.pressableCard)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(label)
            .accessibilityIdentifier("composition_\(hero.key)")
        }
    }

    private func heroCardBody(_ hero: CompositionCatalog.Hero, _ summary: BaniSummary?, featured: Bool) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                HStack(alignment: .top) {
                    GurmukhiText(verbatim: summary?.titleGm ?? hero.gm, size: featured ? 24 : 20)
                    Spacer(minLength: Theme.Space.xs)
                    if let summary, container.nitnem.isCompleted(summary.id) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.body).foregroundStyle(palette.accent)
                    } else if let summary, shapes[hero.id] == nil {
                        // No outline yet (or none to draw): the ring, once there is progress.
                        let frac = container.nitnem.fraction(for: summary.id, total: summary.nLines)
                        if frac > 0 { ProgressRing(fraction: frac, done: false).frame(width: 22, height: 22) }
                    }
                }
                Text(summary?.titleEn ?? hero.roman)
                    .font(.footnote.weight(.medium)).italic()
                    .foregroundStyle(palette.accentText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(place(hero))
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let summary, let shape = shapes[hero.id] {
                    let seq = container.nitnem.progress(for: summary.id)?.lastSeq
                    StructureStrip(shape: shape, seq: (seq ?? 0) > 0 ? seq : nil,
                                   completed: container.nitnem.isCompleted(summary.id))
                        .padding(.top, 4)
                    if let caption = shapeCaption(shape, summary) {
                        Text(caption).font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let m = summary?.estimatedMinutes {
                    MinutesChip(minutes: m)
                }
            }
        }
    }

    /// "24 ashtapadis", or "Ashtapadi 5 of 24" once begun.
    private func shapeCaption(_ shape: CompositionShape, _ summary: BaniSummary) -> String? {
        guard let unit = shape.unit, !shape.steps.isEmpty else { return nil }
        let n = shape.steps.count
        if !container.nitnem.isCompleted(summary.id),
           let seq = container.nitnem.progress(for: summary.id)?.lastSeq, seq > 0,
           let k = shape.stepNumber(at: seq) {
            return "\(String(unit.dropLast()).capitalized) \(String(k)) of \(String(n))"
        }
        return "\(String(n)) \(unit)"
    }

    // MARK: continue

    /// The compositions this Index offers: the heroes as the registry names them, then the shelf.
    private var offered: [BaniSummary] {
        CompositionCatalog.heroes.compactMap { CompositionCatalog.resolve($0, in: registry) }
            + CompositionCatalog.more(from: registry)
    }

    private var inProgress: [BaniSummary] {
        ContinueReading.inProgress(offered: offered, isCompleted: { container.nitnem.isCompleted($0) },
                                   fraction: { container.nitnem.fraction(for: $0.id, total: $0.nLines) })
    }

    /// The composition the reader most recently left part-way through (not finished today) whose
    /// saved position still resumes — see `ContinueReading`.
    private var continueTarget: BaniSummary? {
        ContinueReading.target(offered: offered, isCompleted: { container.nitnem.isCompleted($0) },
                               fraction: { container.nitnem.fraction(for: $0.id, total: $0.nLines) },
                               resumes: { resumable[resumeKey($0)] == true },
                               lastReadAt: { container.nitnem.progress(for: $0)?.lastReadAt })
    }

    /// A composition's id with its saved position, so a new save re-checks resumability.
    private func resumeKey(_ id: String) -> String {
        "\(id)@\(container.nitnem.progress(for: id)?.lastSeq ?? 0)"
    }

    /// Whether each in-progress composition's saved position resumes against its current lines.
    /// One bani read per newly saved position; nothing is read when nothing is in progress.
    private func checkResumable() async {
        guard let corpus = container.corpus else { return }
        for b in inProgress where resumable[resumeKey(b.id)] == nil {
            let key = resumeKey(b.id)
            let variant = CompositionCatalog.heroes.first { CompositionCatalog.resolve($0, in: registry)?.id == b.id }?
                .variant ?? b.variant
            let lines = await corpus.bani(key: b.key, variant: variant)?.lines ?? []
            resumable[key] = container.nitnem.resumeSeq(for: b.id, lines: lines) != nil
        }
    }

    private func continueCard(_ b: BaniSummary) -> some View {
        let pct = Int((container.nitnem.fraction(for: b.id, total: b.nLines) * 100).rounded())
        let hero = CompositionCatalog.heroes.first { CompositionCatalog.resolve($0, in: registry)?.id == b.id }
        let detail = hero.flatMap { h in shapes[h.id].flatMap { shapeCaption($0, b) } }
        return NavigationLink(value: Route.composition(key: b.key, variant: hero?.variant ?? b.variant)) {
            HStack(spacing: Theme.Space.m) {
                VStack(alignment: .leading, spacing: 3) {
                    SectionEyebrow(text: "Continue reading", symbol: "bookmark")
                    Text(b.titleEn).font(Brand.heading(.headline)).foregroundStyle(.primary)
                    GurmukhiText(verbatim: b.titleGm, size: 17)
                    Text([detail, "\(String(pct))% read"].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
                Spacer(minLength: Theme.Space.s)
                Image(systemName: "arrow.right.circle.fill")
                    .font(.title2).foregroundStyle(palette.accent)
            }
            .padding(Theme.Space.l)
            .background(Ink.card, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(palette.accent.opacity(0.55)))
        }
        .buttonStyle(.pressableCard)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Continue reading \(b.titleEn). \([detail, "\(pct) percent read"].compactMap { $0 }.joined(separator: ", ")).")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("index_continue")
    }

    /// Where the work sits: "Ang 262 · Raag Gauri". Reading time is a separate chip so the line
    /// never breaks mid-phrase ("about / 15 min").
    private func place(_ hero: CompositionCatalog.Hero) -> String {
        hero.raag.isEmpty ? "Ang \(String(hero.ang))" : "Ang \(String(hero.ang)) · \(hero.raag)"
    }

    private func accessibilityLabel(_ hero: CompositionCatalog.Hero, _ summary: BaniSummary?) -> String {
        guard let summary else { return "\(hero.roman) — open Ang \(hero.ang)" }
        let pct = Int(container.nitnem.fraction(for: summary.id, total: summary.nLines) * 100)
        let progress = container.nitnem.isCompleted(summary.id) ? "read today"
            : (pct > 0 ? "\(pct) percent read" : "not started")
        var parts = ["\(summary.titleEn) — read the composition", place(hero)]
        if let shape = shapes[hero.id], let c = shapeCaption(shape, summary) { parts.append(c) }
        if let m = summary.estimatedMinutes { parts.append("about \(m) minutes") }
        parts.append(progress)
        return parts.joined(separator: ". ") + "."
    }

    // MARK: voices

    private func authorsList(_ meta: CorpusMeta) -> some View {
        VStack(spacing: Theme.Space.s) {
            ForEach(meta.authors) { a in
                Button { container.router.openAng(a.firstAng) } label: {
                    Card {
                        HStack {
                            Text(a.name).font(.subheadline.weight(.medium))
                            Spacer()
                            Text("\(a.nLines) lines")
                                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                            Image(systemName: "chevron.right")
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                }
                .buttonStyle(.pressableCard)
                .accessibilityLabel("\(a.name), \(a.nLines) lines, from Ang \(a.firstAng)")
            }
        }
    }
}

/// "≈ 15 min" — a reading-time chip on the raised surface.
struct MinutesChip: View {
    let minutes: Int
    var body: some View {
        Label("\(String(minutes)) min", systemImage: "clock")
            .labelStyle(.titleAndIcon)
            .font(.caption2.weight(.medium)).monospacedDigit()
            .foregroundStyle(.secondary)
            .padding(.horizontal, Theme.Space.s).padding(.vertical, 3)
            .background(Ink.raised, in: Capsule())
            .overlay(Capsule().strokeBorder(Ink.hairline))
            .padding(.top, 2)
            .accessibilityHidden(true)
    }
}
