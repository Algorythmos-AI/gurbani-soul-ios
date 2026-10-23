import SwiftUI
import GurbaniSearchKit

/// The loaded part of a theme's verse list: what is on screen, the true total, and where the next
/// page starts. Pages are appended only when they continue the page asked for, so a stale reply
/// (after a filter change, or a double trigger) can never duplicate or reorder verses.
struct ThemeFeed: Equatable, Sendable {
    var lines: [SearchLine] = []
    var total = 0
    var nextAfterId: Int?
    var loadingMore = false
    var moreFailed: String?

    var hasMore: Bool { nextAfterId != nil }
    /// The cursor to request next, or nil when nothing should be requested right now.
    var cursorToLoad: Int? { loadingMore || moreFailed != nil ? nil : nextAfterId }

    init() {}
    init(first: ThemePage) {
        lines = first.lines; total = first.total; nextAfterId = first.nextAfterId
    }

    /// Append the page fetched from `cursor`; ignored unless `cursor` is still the open cursor.
    mutating func append(_ page: ThemePage, from cursor: Int) {
        guard cursor == nextAfterId else { return }
        let seen = lines.last?.id ?? 0
        lines += page.lines.filter { $0.id > seen }
        total = page.total
        nextAfterId = page.nextAfterId
        loadingMore = false
        moreFailed = nil
    }

    var footer: String {
        if lines.isEmpty { return "" }
        if !hasMore { return lines.count == 1 ? "1 verse" : "All \(lines.count.formatted()) verses shown" }
        return "Showing \(lines.count.formatted()) of \(total.formatted()) verses"
    }
}

/// Every verse that carries a theme, in reading order, paged to the end — never a sample.
struct ThemeResultsScreen: View {
    let concept: String
    var filter: ThemeFilter = .none
    @Environment(AppContainer.self) private var container
    @State private var state: LoadState<Bool> = .loading
    @State private var feed = ThemeFeed()

    private static let pageSize = 50

    var body: some View {
        LoadStateView(state: state, emptyTitle: "No verses",
                      emptyMessage: "No verse carries this theme under the current filter.",
                      onRetry: { Task { await reload() } }) { _ in
            List {
                Section {
                    ForEach(feed.lines, id: \.id) { line in
                        LineRow(gurmukhi: line.gurmukhi, translit: line.translit, meta: line.metaLine,
                                en: line.en, lineId: line.id, ang: line.ang, compId: line.compId) {
                            container.present(.shabad(compId: line.compId, focusLineId: line.id))
                        }
                        .listRowSeparator(.hidden)
                        .onAppear { if line.id == feed.lines.last?.id { Task { await loadMore() } } }
                    }
                } header: {
                    Text("\(feed.total.formatted()) \(feed.total == 1 ? "verse carries" : "verses carry") \(ConceptName.display(concept)), in reading order")
                        .font(.caption).foregroundStyle(Ink.muted).textCase(nil)
                } footer: {
                    footer
                }
            }
            .listStyle(.plain)
        }
        .navigationTitle(ConceptName.display(concept))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: filter) { await reload() }
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
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Space.m)
    }

    private func reload() async {
        guard let corpus = container.corpus else { state = .failed("No database"); return }
        state = .loading
        feed = ThemeFeed()
        do {
            let first = try await corpus.themePage(concept, filter: filter, limit: Self.pageSize)
            try Task.checkCancellation()
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
}
