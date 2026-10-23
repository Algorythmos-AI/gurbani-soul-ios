import SwiftUI
import GurbaniSearchKit

/// The Themes index: the 54 corpus themes as a living index — today's theme and the themes of
/// today's Hukam, search by English name, meaning or Gurmukhi word, the six theological families
/// one tap apart, and every card with its headword, where it falls in the Granth, and honest
/// counts. Web parity for the grouping: frontend/src/scripts/themegroups.ts (ThemeGroup.all).
/// Stack-less: pushed inside the Explore tab's NavigationStack, whose destination table resolves
/// Route.theme — theme deep links land here via Router.explorePath.
struct ThemesScreen: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.palette) private var palette
    @State private var state: LoadState<[ThemeIndexRow]> = .loading
    @State private var today: ThemesToday?
    @State private var query = ""
    @State private var sectionTops: [String: CGFloat] = [:]
    @AppStorage("sggs_themes_arrange") private var arrangeRaw = ThemeIndexModel.Arrangement.family.rawValue
    @AppStorage("sggs_themes_layout") private var layoutRaw = ThemeCardView.Style.grid.rawValue

    private var arrangement: ThemeIndexModel.Arrangement { .init(rawValue: arrangeRaw) ?? .family }
    private var style: ThemeCardView.Style { .init(rawValue: layoutRaw) ?? .grid }
    private var columns: [GridItem] {
        typeSize.isAccessibilitySize || style == .row
            ? [GridItem(.flexible())]
            : [GridItem(.flexible(), spacing: Theme.Space.m), GridItem(.flexible())]
    }
    private static let space = "themesScroll"

    var body: some View {
        LoadStateView(state: state, emptyTitle: "No themes", onRetry: { Task { await load() } }) { rows in
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Space.xl) {
                        if query.trimmingCharacters(in: .whitespaces).isEmpty {
                            index(rows)
                        } else {
                            results(ThemeIndexModel.search(rows, query))
                        }
                    }
                    .padding(Theme.Space.l)
                }
                .coordinateSpace(name: Self.space)
                .scrollDismissesKeyboard(.immediately)
                .safeAreaInset(edge: .top, spacing: 0) {
                    if query.isEmpty && arrangement == .family { familyBar(rows, proxy) }
                }
            }
            .background(Ink.canvas)
        }
        .background(Ink.canvas)
        .navigationTitle("Themes")
        .searchable(text: $query, prompt: "Name, meaning or Gurmukhi word")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { arrangeMenu } }
        .task { await load() }
    }

    // MARK: the index

    @ViewBuilder private func index(_ rows: [ThemeIndexRow]) -> some View {
        Text("Explore the Granth by idea — each theme gathers every verse that uses its corpus-verified Gurmukhi words, shown verbatim with its Ang.")
            .font(.caption).foregroundStyle(Ink.muted)
            .fixedSize(horizontal: false, vertical: true)
        if let today { TodayHero(today: today) }
        switch arrangement {
        case .family:
            ForEach(ThemeIndexModel.grouped(rows), id: \.group?.key) { section in
                familySection(section.group, section.rows)
            }
        case .alphabetical, .size:
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text(arrangement == .size ? "By number of verses" : "A to Z")
                    .font(.headline).accessibilityAddTraits(.isHeader)
                if arrangement == .size {
                    Text("A count of verses that carry each theme's words — not a measure of importance.")
                        .font(.caption).foregroundStyle(Ink.muted)
                }
                cards(ThemeIndexModel.arranged(rows, arrangement))
            }
        }
        Text("A theme is a set of verified Gurmukhi words; a verse carries it when it contains one of them. Sizes differ because some words are everywhere in the Granth and some are rare.")
            .font(.caption).foregroundStyle(Ink.muted)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, Theme.Space.s)
    }

    private func familySection(_ group: ThemeGroup?, _ rows: [ThemeIndexRow]) -> some View {
        let key = group?.key ?? "more"
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                Circle().fill(group?.color ?? Ink.muted).frame(width: 10, height: 10).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(group?.title ?? "More Themes").font(.headline).accessibilityAddTraits(.isHeader)
                    if let caption = group?.caption, !caption.isEmpty {
                        Text(caption).font(.caption).foregroundStyle(Ink.muted)
                    }
                }
            }
            cards(rows)
        }
        .id(key)
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(Self.space)).minY } action: { sectionTops[key] = $0 }
    }

    @ViewBuilder private func cards(_ rows: [ThemeIndexRow]) -> some View {
        if style == .row && !typeSize.isAccessibilitySize {
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { i, r in
                    if i > 0 { Divider().padding(.leading, 22) }
                    link(r)
                }
            }
            .padding(.horizontal, Theme.Space.m)
            .background(Ink.card, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(Ink.hairline))
        } else {
            LazyVGrid(columns: columns, spacing: Theme.Space.m) {
                ForEach(rows) { link($0) }
            }
        }
    }

    private func link(_ r: ThemeIndexRow) -> some View {
        NavigationLink(value: Route.theme(r.concept)) {
            ThemeCardView(row: r, style: typeSize.isAccessibilitySize ? .grid : style)
        }
        .buttonStyle(.pressableCard)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ThemeIndexModel.accessibilitySummary(r))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("theme_\(r.concept)")
    }

    // MARK: search results

    @ViewBuilder private func results(_ found: [ThemeIndexRow]) -> some View {
        if found.isEmpty {
            EmptyStateView(title: "No theme matches “\(query.trimmingCharacters(in: .whitespaces))”",
                           message: "Try an English word such as ego or grace, or a Gurmukhi word such as ਹਉਮੈ.")
                .frame(maxWidth: .infinity)
                .padding(.top, Theme.Space.xl)
        } else {
            Text(found.count == 1 ? "1 theme" : "\(found.count) themes")
                .font(.caption).foregroundStyle(Ink.muted)
                .accessibilityIdentifier("themes.search.count")
            cards(found)
        }
    }

    // MARK: chrome

    /// The six families one tap apart; the family under the top of the screen is the selected chip.
    private func familyBar(_ rows: [ThemeIndexRow], _ proxy: ScrollViewProxy) -> some View {
        let groups = ThemeIndexModel.grouped(rows)
        let current = groups.map { $0.group?.key ?? "more" }
            .last { (sectionTops[$0] ?? .infinity) <= 140 } ?? groups.first?.group?.key
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Space.s) {
                ForEach(groups, id: \.group?.key) { section in
                    let key = section.group?.key ?? "more"
                    let on = key == current
                    Button {
                        Haptics.tap()
                        MotionGate.run(Motion.gentle) { proxy.scrollTo(key, anchor: .top) }
                    } label: {
                        HStack(spacing: 6) {
                            Circle().fill(section.group?.color ?? Ink.muted).frame(width: 8, height: 8)
                            Text(section.group?.shortTitle ?? "More").font(.footnote.weight(on ? .semibold : .regular))
                        }
                        .padding(.horizontal, Theme.Space.m).padding(.vertical, 6)
                        .background(on ? Ink.raised : Color.clear, in: Capsule())
                        .overlay(Capsule().strokeBorder(on ? (section.group?.color ?? Ink.muted) : Ink.hairline))
                        .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(section.group?.title ?? "More Themes")
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .padding(.horizontal, Theme.Space.l).padding(.vertical, Theme.Space.s)
        }
        .background(.bar)
    }

    private var arrangeMenu: some View {
        Menu {
            Picker("Arrange", selection: $arrangeRaw) {
                ForEach(ThemeIndexModel.Arrangement.allCases) { Text($0.title).tag($0.rawValue) }
            }
            Picker("Layout", selection: $layoutRaw) {
                Label("Cards", systemImage: "square.grid.2x2").tag(ThemeCardView.Style.grid.rawValue)
                Label("List", systemImage: "list.bullet").tag(ThemeCardView.Style.row.rawValue)
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down.circle")
        }
        .accessibilityLabel("Arrange themes")
        .accessibilityIdentifier("themes.arrange")
    }

    // MARK: data

    private func load() async {
        guard let corpus = container.corpus else { state = .failed("No database"); return }
        if case .loaded = state {} else { state = .loading }
        do {
            let rows = try await corpus.themeIndex()
            state = rows.isEmpty ? .empty : .loaded(rows)
            let day = HukamOfTheDay.dayNumber(of: Date(), calendar: .current)
            // today's row is a gift, not a dependency: if it fails the index still stands
            if let theme = try? await corpus.themeOfTheDay(day: day) {
                let hukam = (try? await corpus.hukamThemes(day: day)) ?? []
                today = ThemesToday(theme: theme, hukam: hukam,
                                    row: rows.first { $0.concept == theme.concept })
            }
        } catch is CancellationError {
        } catch { state = .failed(UserMessage.load(error)) }
    }
}

struct ThemesToday: Equatable {
    let theme: ThemeOfTheDay
    let hukam: [ThemeTally]
    let row: ThemeIndexRow?
}

/// Today: one theme a day (in slug order, day by day) with a verbatim verse that carries it — a
/// refrain when it has one — and the themes today's Hukam carries.
private struct TodayHero: View {
    let today: ThemesToday
    @Environment(AppContainer.self) private var container
    @Environment(\.palette) private var palette

    var body: some View {
        let concept = today.theme.concept
        let line = today.theme.line
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            SectionEyebrow(text: "Theme of the day", symbol: "sun.max")
            NavigationLink(value: Route.theme(concept)) {
                HStack(spacing: Theme.Space.s) {
                    Circle().fill(ThemeGroup.color(concept)).frame(width: 10, height: 10).accessibilityHidden(true)
                    Text(ConceptName.display(concept)).font(.title3.weight(.semibold)).foregroundStyle(.primary)
                    if let head = today.row?.headword { GurmukhiText(verbatim: head, size: 20).foregroundStyle(.primary) }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Ink.muted)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Theme of the day: \(ConceptName.display(concept))")
            .accessibilityIdentifier("themes.today")

            Button {
                Haptics.tap()
                container.present(.shabad(compId: line.compId, focusLineId: line.id))
            } label: {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    GurmukhiText(verbatim: line.gurmukhi, size: 22).foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    if !line.translit.isEmpty {
                        Text(line.translit).font(.callout).foregroundStyle(Ink.muted)
                            .multilineTextAlignment(.leading)
                    }
                    Text("Sri Guru Granth Sahib Ji · Ang \(line.ang)\(today.theme.isRefrain ? " · a Rahao line" : "")")
                        .font(.caption).foregroundStyle(palette.accentText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the shabad")

            if !today.hukam.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    HStack {
                        Text("Today's Hukam carries").font(.subheadline.weight(.semibold))
                        Spacer()
                        Button("Read it") { Haptics.tap(); container.present(.hukamOfTheDay) }
                            .font(.subheadline)
                            .foregroundStyle(palette.accentText)
                    }
                    let chips = [GridItem(.adaptive(minimum: 110), spacing: Theme.Space.s, alignment: .leading)]
                    LazyVGrid(columns: chips, alignment: .leading, spacing: Theme.Space.s) {
                        ForEach(today.hukam.prefix(6)) { t in
                            NavigationLink(value: Route.theme(t.concept)) {
                                HStack(spacing: 6) {
                                    Circle().fill(ThemeGroup.color(t.concept)).frame(width: 8, height: 8)
                                    Text(ConceptName.display(t.concept)).font(.footnote.weight(.medium))
                                    Text("\(t.n)").font(.footnote.monospacedDigit()).foregroundStyle(Ink.muted)
                                }
                                .padding(.horizontal, Theme.Space.s).padding(.vertical, 5)
                                .background(Ink.raised, in: Capsule())
                                .foregroundStyle(.primary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(ConceptName.display(t.concept)), \(t.n) \(t.n == 1 ? "verse" : "verses") of today's Hukam")
                        }
                    }
                }
            }
        }
        .padding(Theme.Space.l)
        .background(Ink.card, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(Ink.hairline))
    }
}
