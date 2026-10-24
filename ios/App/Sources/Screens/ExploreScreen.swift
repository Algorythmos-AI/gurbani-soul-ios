import SwiftUI

/// The Explore hub: one place for the browse/insight surfaces (web-navbar parity without
/// burying them under settings). Owns the Explore tab's NavigationStack; every destination
/// below is stack-less and pushed via `Route`. New surfaces (Lineage, Vaars, Raag Clock
/// detail…) get a card + a Route case here — that's the whole checklist for adding one.
struct ExploreScreen: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.palette) private var palette
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private struct Entry: Identifiable {
        let route: Route
        let title: String
        let caption: String
        let icon: String
        var id: String { title }
    }

    /// Captions with counts are derived from the bundled data (never a hard-coded fact that a
    /// DB-profile or roster change could silently falsify); the wording holds while loading.
    private var entries: [Entry] {
        let concepts = container.meta.map { "\(String($0.concepts.count)) concepts" } ?? "Every concept"
        let voices = container.contributorCount.map { "\(String($0)) voices" } ?? "Every voice"
        let vaars = container.vaarCount.map { "\(String($0)) ballads" } ?? "The ballads"
        return [
            .init(route: .index, title: "Index",
                  caption: "Raags, sections & authors — jump anywhere", icon: "list.bullet"),
            .init(route: .themes, title: "Themes",
                  caption: "\(concepts), every tagged verse", icon: "circle.grid.2x2"),
            .init(route: .lineage, title: "Lineage",
                  caption: "\(voices) across five centuries", icon: "person.2"),
            .init(route: .insights, title: "Insights",
                  caption: "Contributors, network, resonance & flow", icon: "chart.bar.xaxis"),
            .init(route: .constellation, title: "Constellation",
                  caption: "Which other themes a theme's verses carry", icon: "circle.hexagongrid"),
            .init(route: .vaars, title: "Vaars",
                  caption: "\(vaars) — their voices, woven", icon: "list.number"),
            .init(route: .clock, title: "Raag Clock",
                  caption: "Which raags are sung in this watch", icon: "clock"),
        ]
    }

    var body: some View {
        @Bindable var router = container.router
        NavigationStack(path: $router.explorePath) {
            ScrollView {
                VStack(spacing: Theme.Space.l) {
                    // Hero: the one gradient moment on this screen (restraint elsewhere).
                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        Text("ੴ")
                            .font(Brand.gurmukhi(30, relativeTo: .title))
                            .accessibilityHidden(true)
                        Text("Explore the Granth").font(Brand.heading(.title3))
                        Text("Index, themes, voices, patterns, time — seven ways into 1,430 Angs.")
                            .font(.caption).opacity(0.9)
                    }
                    .foregroundStyle(palette.onAccent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Theme.Space.l)
                    .background(palette.heroGradient, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
                    .accessibilityElement(children: .combine)

                    let columns = dynamicTypeSize.isAccessibilitySize
                        ? [GridItem(.flexible())]
                        : [GridItem(.flexible(), spacing: Theme.Space.m), GridItem(.flexible())]
                    LazyVGrid(columns: columns, spacing: Theme.Space.m) {
                        ForEach(entries) { e in
                            NavigationLink(value: e.route) {
                                Card {
                                    VStack(alignment: .leading, spacing: Theme.Space.s) {
                                        Image(systemName: e.icon)
                                            .font(.title2)
                                            .foregroundStyle(palette.accent)
                                        Text(e.title).font(.headline).foregroundStyle(.primary)
                                        Text(e.caption)
                                            .font(.caption).foregroundStyle(Ink.muted)
                                            .multilineTextAlignment(.leading)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                            }
                            .buttonStyle(.pressableCard)
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel(e.title)
                            .accessibilityHint(e.caption)
                            .accessibilityIdentifier(e.title)
                        }
                    }
                }
                .padding(Theme.Space.l)
                .frame(maxWidth: 720)                 // regular width: cards stay card-sized
                .frame(maxWidth: .infinity)
            }
            .background(Ink.canvas)
            .contentMargins(.bottom, Theme.Space.xl, for: .scrollContent)
            .navigationTitle("Explore")
            .task { await container.loadMeta() }   // captions + Index/Themes need meta
            .navigationDestination(for: Route.self) { route in RouteDestination(route: route) }
        }
    }
}

/// Every pushed surface, in one place, so the Explore and Nitnem stacks resolve a `Route`
/// identically (a deep link may land a bani on either).
struct RouteDestination: View {
    let route: Route
    var body: some View {
        switch route {
        case .index: IndexScreen()
        case .themes: ThemesScreen()
        case .lineage: LineageScreen()
        case .insights: InsightsScreen()
        case .constellation: ConstellationScreen()
        case .vaars: VaarsScreen()
        case .vaar(let id): VaarWeaveScreen(vaarId: id)
        case .vaarReader(let id, let paurisOnly, let line):
            VaarReaderScreen(vaarId: id, paurisOnly: paurisOnly, startLineId: line)
        case .clock: ClockScreen()
        case .nitnemJourney: NitnemJourneyScreen()
        case .theme(let name): ThemeChapterScreen(concept: name)
        case .themeVerses(let name, let filter): ThemeResultsScreen(concept: name, filter: filter)
        case .bani(let key): BaniReaderScreen(key: key)
        case .composition(let key, let variant):
            BaniReaderScreen(key: key, variantOverride: variant.isEmpty ? nil : variant, context: .explore)
        // keyed by raag, so a link from one raag page to another starts the next one fresh
        case .raag(let name): RaagScreen(raag: name).id(name)
        }
    }
}
