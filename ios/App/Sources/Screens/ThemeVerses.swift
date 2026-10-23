import SwiftUI
import GurbaniSearchKit

/// The loaded part of a theme's verse list: what is on screen, the true total, where the next
/// page starts, and which of the theme's words each verse contains. Pages are appended only when
/// they continue the page asked for, so a stale reply (after a filter change, or a double
/// trigger) can never duplicate or reorder verses.
struct ThemeFeed: Equatable, Sendable {
    var lines: [SearchLine] = []
    var total = 0
    var nextAfterId: Int?
    var matched: [Int: [String]] = [:]
    var loadingMore = false
    var moreFailed: String?

    var hasMore: Bool { nextAfterId != nil }
    /// The cursor to request next, or nil when nothing should be requested right now.
    var cursorToLoad: Int? { loadingMore || moreFailed != nil ? nil : nextAfterId }

    init() {}
    init(first: ThemePage) {
        lines = first.lines; total = first.total; nextAfterId = first.nextAfterId; matched = first.matched
    }

    /// Append the page fetched from `cursor`; ignored unless `cursor` is still the open cursor.
    mutating func append(_ page: ThemePage, from cursor: Int) {
        guard cursor == nextAfterId else { return }
        let seen = lines.last?.id ?? 0
        let fresh = page.lines.filter { $0.id > seen }
        lines += fresh
        for l in fresh { matched[l.id] = page.matched[l.id] }
        total = page.total
        nextAfterId = page.nextAfterId
        loadingMore = false
        moreFailed = nil
    }

    /// Consecutive verses of one shabad, together. A shabad that straddles a page boundary stays
    /// one group, because grouping runs over everything loaded so far.
    struct Group: Identifiable, Equatable, Sendable {
        let compId: Int
        var lines: [SearchLine]
        var id: Int { lines.first?.id ?? compId }
    }
    var groups: [Group] {
        var out: [Group] = []
        for l in lines {
            if let last = out.indices.last, out[last].compId == l.compId { out[last].lines.append(l) }
            else { out.append(Group(compId: l.compId, lines: [l])) }
        }
        return out
    }

    var footer: String {
        if lines.isEmpty { return "" }
        if !hasMore { return lines.count == 1 ? "1 verse" : "All \(lines.count.formatted()) verses shown" }
        return "Showing \(lines.count.formatted()) of \(total.formatted()) verses"
    }
}

/// Plain-language description of a filter, for the list's header and VoiceOver.
enum ThemeFilterText {
    static func parts(_ f: ThemeFilter, raagName: (String) -> String) -> [String] {
        var out: [String] = []
        if let t = f.term { out.append(t) }
        if f.lens.rahaoOnly { out.append("Rahao lines only") }
        if let a = f.lens.author { out.append(a.replacingOccurrences(of: " Ji", with: "")) }
        if let r = f.lens.raag { out.append(raagName(r)) }
        if f.lens.angMin > 1 || f.lens.angMax < 1430 { out.append("Angs \(f.lens.angMin)–\(f.lens.angMax)") }
        return out
    }
}

/// Every verse that carries a theme, in reading order, paged to the end — never a sample —
/// grouped by shabad, narrowed by word form, voice, raag, refrains or Ang range, and each verse
/// saying which of the theme's words put it here.
struct ThemeResultsScreen: View {
    let concept: String
    @State private var filter: ThemeFilter
    @Environment(AppContainer.self) private var container
    @Environment(\.palette) private var palette
    @State private var state: LoadState<Bool> = .loading
    @State private var feed = ThemeFeed()
    @State private var words: [ThemeWord] = []
    @AppStorage("sggs_theme_grouped") private var grouped = true

    private static let pageSize = 50

    init(concept: String, filter: ThemeFilter = .none) {
        self.concept = concept
        _filter = State(initialValue: filter)
    }

    var body: some View {
        LoadStateView(state: state, emptyTitle: "No verses",
                      emptyMessage: "No verse carries this theme under these filters.",
                      onRetry: { Task { await reload() } }) { _ in
            List {
                Section {
                    summary
                }
                .listRowBackground(Ink.base)
                .listRowSeparator(.hidden)
                if grouped {
                    ForEach(feed.groups) { g in
                        Section {
                            ForEach(g.lines, id: \.id) { row($0) }
                        } header: {
                            groupHeader(g)
                        }
                    }
                } else {
                    Section { ForEach(feed.lines, id: \.id) { row($0) } }
                }
                Section { footer }
                    .listRowBackground(Ink.base)
                    .listRowSeparator(.hidden)
            }
            .listStyle(.plain)
            .inkPlainList()
        }
        .overlay {
            if case .empty = state, filter.isActive {
                VStack {
                    Spacer()
                    Button("Clear filters") { Haptics.tap(); filter = .none }
                        .buttonStyle(.borderedProminent)
                        .padding(.bottom, Theme.Space.xl)
                }
            }
        }
        .navigationTitle(ConceptName.display(concept))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { filterMenu } }
        .task(id: filter) { await reload() }
        .task { await loadWords() }
    }

    // MARK: rows

    private func row(_ line: SearchLine) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            LineRow(gurmukhi: line.gurmukhi, translit: line.translit, meta: line.metaLine,
                    en: line.en, lineId: line.id, ang: line.ang, compId: line.compId,
                    shareContext: ConceptName.display(concept)) {
                container.present(.shabad(compId: line.compId, focusLineId: line.id))
            }
            if let m = feed.matched[line.id], !m.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("contains").font(.caption2).foregroundStyle(Ink.muted)
                    GurmukhiText(verbatim: m.joined(separator: " · "), size: 15).foregroundStyle(palette.accentText)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("themes.verse.contains")
            }
        }
        .readingColumn()
        .listRowSeparator(.hidden)
        .listRowBackground(Ink.base)
        .onAppear { if line.id == feed.lines.last?.id { Task { await loadMore() } } }
    }

    private func groupHeader(_ g: ThemeFeed.Group) -> some View {
        let first = g.lines[0]
        var bits = ["Ang \(first.ang)"]
        if let r = first.raag { bits.append(raagName(r)) }
        if let a = first.author { bits.append(a.replacingOccurrences(of: " Ji", with: "")) }
        return HStack {
            Text(bits.joined(separator: " · ")).font(.caption.weight(.semibold)).foregroundStyle(Ink.muted)
            Spacer()
            if g.lines.count > 1 {
                Text("\(g.lines.count) verses").font(.caption2.monospacedDigit()).foregroundStyle(Ink.muted)
            }
        }
        .textCase(nil)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder private var summary: some View {
        let name = ConceptName.display(concept)
        let parts = ThemeFilterText.parts(filter, raagName: raagName)
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text("\(feed.total.formatted()) \(feed.total == 1 ? "verse carries" : "verses carry") \(name), in reading order")
                .font(.subheadline.weight(.semibold))
                .accessibilityIdentifier("themes.verses.total")
            if !parts.isEmpty {
                HStack(alignment: .firstTextBaseline) {
                    Text("Filtered: " + parts.joined(separator: " · "))
                        .font(.caption).foregroundStyle(Ink.muted)
                    Spacer()
                    Button("Clear") { Haptics.tap(); filter = .none }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(palette.accentText)
                        .accessibilityLabel("Clear filters")
                }
            }
        }
        .padding(.vertical, Theme.Space.xs)
    }

    @ViewBuilder private var footer: some View {
        VStack(spacing: Theme.Space.s) {
            Text(feed.footer)
                .font(.caption).foregroundStyle(Ink.muted)
                .accessibilityIdentifier("themes.verses.footer")
            if let message = feed.moreFailed {
                Text(message).font(.caption).foregroundStyle(Ink.muted)
                Button("Try again") { feed.moreFailed = nil; Task { await loadMore() } }
                    .buttonStyle(.bordered)
            } else if feed.loadingMore {
                ProgressView()
            } else if feed.hasMore {
                Button("Load more verses") { Task { await loadMore() } }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("themes.verses.more")
            }
            Text("Each verse is shown because it contains one of this theme's verified Gurmukhi words — a word match, not an interpretation.")
                .font(.caption2).foregroundStyle(Ink.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Space.m)
    }

    // MARK: filters

    private var filterMenu: some View {
        Menu {
            Toggle("Group by shabad", isOn: $grouped)
            if !words.isEmpty {
                Picker("Word", selection: termBinding) {
                    Text("Any of its words").tag(String?.none)
                    ForEach(words) { w in Text("\(w.term)  \(w.n.formatted())").tag(String?.some(w.term)) }
                }
            }
            Toggle("Rahao lines only", isOn: rahaoBinding)
            if let meta = container.meta {
                Picker("Voice", selection: authorBinding) {
                    Text("Every voice").tag(String?.none)
                    ForEach(meta.authors, id: \.name) { a in Text(a.name.replacingOccurrences(of: " Ji", with: "")).tag(String?.some(a.name)) }
                }
                Picker("Raag", selection: raagBinding) {
                    Text("Every raag").tag(String?.none)
                    ForEach(meta.raags, id: \.name) { r in Text(r.roman.map { "Raag \($0)" } ?? r.name).tag(String?.some(r.name)) }
                }
            }
            if filter.isActive {
                Button("Clear filters", role: .destructive) { filter = .none }
            }
        } label: {
            Image(systemName: filter.isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
        .accessibilityLabel(filter.isActive ? "Filters, on" : "Filters")
        .accessibilityIdentifier("themes.verses.filter")
    }

    private var termBinding: Binding<String?> {
        Binding(get: { filter.term }, set: { filter.term = $0 })
    }
    private var rahaoBinding: Binding<Bool> {
        Binding(get: { filter.lens.rahaoOnly }, set: { filter.lens.rahaoOnly = $0 })
    }
    private var authorBinding: Binding<String?> {
        Binding(get: { filter.lens.author }, set: { filter.lens.author = $0 })
    }
    private var raagBinding: Binding<String?> {
        Binding(get: { filter.lens.raag }, set: { filter.lens.raag = $0 })
    }

    private func raagName(_ gurmukhi: String) -> String {
        "Raag " + (container.meta?.raags.first { $0.name == gurmukhi }?.roman ?? gurmukhi)
    }

    // MARK: data

    private func reload() async {
        guard let corpus = container.corpus else { state = .failed("No database"); return }
        state = .loading
        feed = ThemeFeed()
        let asked = filter
        do {
            let first = try await corpus.themePage(concept, filter: asked, limit: Self.pageSize)
            try Task.checkCancellation()
            guard asked == filter else { return }
            feed = ThemeFeed(first: first)
            state = first.lines.isEmpty ? .empty : .loaded(true)
        } catch is CancellationError {
        } catch { state = .failed(UserMessage.load(error)) }
    }

    private func loadMore() async {
        guard let corpus = container.corpus, let cursor = feed.cursorToLoad else { return }
        feed.loadingMore = true
        let asked = filter
        do {
            let page = try await corpus.themePage(concept, filter: asked, afterId: cursor, limit: Self.pageSize)
            guard asked == filter else { return }                 // a newer filter owns the list
            feed.append(page, from: cursor)
        } catch is CancellationError {
            feed.loadingMore = false
        } catch {
            feed.loadingMore = false
            feed.moreFailed = UserMessage.load(error)
        }
    }

    private func loadWords() async {
        guard let corpus = container.corpus, words.isEmpty else { return }
        words = (try? await corpus.themeWords(concept)) ?? []
    }
}
