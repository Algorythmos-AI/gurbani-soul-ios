import SwiftUI
import GurbaniSearchKit

/// The Explore hub, "The Granth Today": one place for the browse/insight surfaces. A dated
/// masthead, today's Feature (turning over by the Hukam's day key), then every other destination
/// as a card that previews the screen it opens. Owns the Explore tab's NavigationStack; every
/// destination is stack-less and pushed via `Route`. A new surface gets an `ExploreDestination`
/// case + a Route case here — that's the whole checklist for adding one.
struct ExploreScreen: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    /// The Index's own last-read Ang; nil until the reader has opened one (no marker then).
    @AppStorage("sggs_last_ang") private var lastAng: Int?
    /// Today, refreshed at the reader's midnight so the Feature turns over with the Hukam.
    @State private var today = Date()

    /// The bundled roster, read once (it never changes at runtime).
    private static let roster: [Contributor]? = ContributorsStore.load()
    private static let rosterIndex: [String: Contributor] =
        Dictionary((roster ?? []).map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })

    private var digest: ExploreDigest {
        let current = container.vaarProgress.current()
        return ExploreDigest(meta: container.meta, vaars: container.vaars, roster: Self.roster, lastAng: lastAng,
                             continueVaar: current.map {
                                 ($0.vaarId, $0.position.lineId, container.vaarProgress.fraction(for: $0.vaarId))
                             })
    }

    private var columns: Int {
        if dynamicTypeSize.isAccessibilitySize { return 1 }
        return horizontalSizeClass == .regular ? 3 : 2
    }

    /// Today's Feature. A DEBUG/XCUITest pin (`SGGS_EXPLORE_FEATURE`) wins; under the UI tests
    /// with no pin the page is held on the Index so layout never depends on the test's date.
    private var featured: ExploreDestination? {
        let eligible = ExploreLayout.eligible(vaarsAvailable: container.vaars.map { !$0.isEmpty } ?? true)
        var pinned = DebugHooks.exploreFeature.flatMap(ExploreDestination.init(rawValue:))
        if pinned == nil, DebugHooks.isUITest { pinned = .index }
        return ExploreLayout.feature(day: HukamOfTheDay.dayNumber(of: today), eligible: eligible, pinned: pinned)
    }

    var body: some View {
        @Bindable var router = container.router
        let digest = digest
        let featured = featured
        let rows = ExploreLayout.pack(ExploreDestination.allCases.filter { $0 != featured }, columns: columns)
        NavigationStack(path: $router.explorePath) {
            ScrollView {
                // Non-lazy on purpose: every card exists in the tree, so the UI tests find a card
                // below the fold (a lazy row would not be built until scrolled to).
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    ExploreMasthead(date: today, line: digest.mastheadLine)
                    if let featured {
                        ExploreCard(destination: featured, form: .feature, digest: digest, roster: Self.rosterIndex,
                                    live: container.exploreLive)
                    }
                    ForEach(rows, id: \.first?.id) { row in
                        ExploreSpanRow(columns: columns, spans: row.map(\.span)) {
                            ForEach(row) { cell in
                                ExploreCard(destination: cell.destination,
                                            form: cell.span >= 2 || columns == 1 ? .wide : .square,
                                            digest: digest, roster: Self.rosterIndex, live: container.exploreLive)
                            }
                        }
                    }
                }
                .padding(Theme.Space.l)
                .frame(maxWidth: horizontalSizeClass == .regular ? 1040 : 720)   // regular width: cards stay card-sized
                .frame(maxWidth: .infinity)
            }
            .background(Ink.canvas)
            .contentMargins(.bottom, Theme.Space.xl, for: .scrollContent)
            .navigationTitle("Explore")
            .task { await container.loadMeta() }   // previews + Index/Themes need meta
            // Today's theme and the theme sky: deferred, once per process (and again on a new day).
            .task(id: HukamOfTheDay.dayNumber(of: today)) {
                await container.exploreLive.load(corpus: container.corpus, day: HukamOfTheDay.dayNumber(of: today))
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in today = Date() }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
                today = Date()
            }
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
        case .vaarReader(let id, let paurisOnly, let line, let pauri):
            VaarReaderScreen(vaarId: id, paurisOnly: paurisOnly, startLineId: line, startPauri: pauri)
        case .clock: ClockScreen()
        case .nitnemJourney: NitnemJourneyScreen()
        case .theme(let name): ThemeChapterScreen(concept: name)
        case .themeVerses(let name, let filter): ThemeResultsScreen(concept: name, filter: filter)
        case .yourTheme(let name): YourThemeVersesScreen(concept: name)
        case .voice(let slug): VoiceRouteView(slug: slug)
        case .bani(let key): BaniReaderScreen(key: key)
        case .composition(let key, let variant):
            BaniReaderScreen(key: key, variantOverride: variant.isEmpty ? nil : variant, context: .explore)
        // keyed by raag, so a link from one raag page to another starts the next one fresh
        case .raag(let name): RaagScreen(raag: name).id(name)
        }
    }
}
