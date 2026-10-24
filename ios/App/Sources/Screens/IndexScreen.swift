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

    private let tabs: [(id: String, label: String)] =
        [("compositions", "Compositions"), ("raags", "Raags"), ("authors", "Voices")]

    private var columns: [GridItem] {
        let n = dynamicTypeSize.isAccessibilitySize ? 1 : 2
        return Array(repeating: GridItem(.flexible(), spacing: Theme.Space.m, alignment: .top), count: n)
    }

    var body: some View {
        Group {
            if let meta = container.meta {
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Space.l) {
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
                                          openRaag: { container.router.openAng($0.firstAng) },
                                          openSection: { container.router.openAng($0.firstAng) })
                        case "authors": authorsList(meta)
                        default: compositionsGrid
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
        // One load, in order; each step is a no-op once its data is in (re-appearing costs
        // nothing). The reading rings come from `container.nitnem`, which is @Observable, so they
        // refresh themselves when a composition reader writes a position.
        .task {
            await container.loadMeta()
            await loadRegistry()
            await loadPahars()
        }
    }

    private func loadRegistry() async {
        guard registry.isEmpty, let corpus = container.corpus, corpus.capabilities.hasBanis else { return }
        registry = await corpus.banis().banis
    }

    private func loadPahars() async {
        guard pahars.isEmpty, let corpus = container.corpus, corpus.capabilities.hasTiming else { return }
        pahars = GranthMap.primaryPahars(await corpus.timingClock())
    }

    // MARK: compositions — the hero rail

    private var compositionsGrid: some View {
        let heroes = CompositionCatalog.heroes
        return VStack(alignment: .leading, spacing: Theme.Space.l) {
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
                    // The ring appears only once there IS something to show — an empty ring on
                    // every card would read as a checkbox and clutter a browsing surface.
                    if let summary {
                        let done = container.nitnem.isCompleted(summary.id)
                        let frac = container.nitnem.fraction(for: summary.id, total: summary.nLines)
                        if done || frac > 0 {
                            ProgressRing(fraction: frac, done: done).frame(width: 22, height: 22)
                        }
                    }
                }
                Text(summary?.titleEn ?? hero.roman)
                    .font(.footnote.weight(.medium)).italic()
                    .foregroundStyle(palette.accentText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(place(hero))
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let m = summary?.estimatedMinutes {
                    MinutesChip(minutes: m)
                }
            }
        }
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
