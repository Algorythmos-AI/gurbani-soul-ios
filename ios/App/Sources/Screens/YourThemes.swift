import SwiftUI
import SwiftData
import GurbaniSearchKit

/// "Your themes": the themes the reader's own saved verses carry, worked out on this device from
/// the saved store and the bundled DB — never sent anywhere, never synced, never a score. The
/// reader can turn it off in Settings.
enum YourThemes {
    static let enabledKey = "sggs_your_themes"
    /// Fewer saved verses than this shows an invitation instead of a tally.
    static let minimumSaved = 3

    /// A saved verse as saved (verbatim copy from the model), detached from SwiftData.
    struct Verse: Identifiable, Equatable, Sendable {
        let lineId: Int, compId: Int, ang: Int
        let gurmukhi: String, translit: String
        var id: Int { lineId }
    }

    struct Summary: Equatable {
        let savedCount: Int
        /// Themes the saved verses carry, most first (ties by slug), with the verses themselves.
        let carried: [(concept: String, verses: [Verse])]
        /// A few themes none of the saved verses carry yet (rotating by day), as an invitation.
        let notYet: [String]
        /// The saved store or the theme lookup failed: say nothing about what the verses carry
        /// (an empty result would read as a fact), only that it could not be counted.
        var unavailable = false

        static func unavailable(savedCount: Int) -> Summary {
            Summary(savedCount: savedCount, carried: [], notYet: [], unavailable: true)
        }

        static func == (a: Summary, b: Summary) -> Bool {
            a.savedCount == b.savedCount && a.notYet == b.notYet && a.unavailable == b.unavailable
                && a.carried.map { "\($0.concept):\($0.verses.map(\.lineId))" } == b.carried.map { "\($0.concept):\($0.verses.map(\.lineId))" }
        }
    }

    /// Pure: the summary from the saved verses, their theme membership, and the themes there are.
    static func summarize(saved: [Verse], members: [String: Set<Int>], themes: [ThemeIndexRow], day: Int,
                          notYetCount: Int = 3) -> Summary {
        let byId = Dictionary(saved.map { ($0.lineId, $0) }, uniquingKeysWith: { a, _ in a })
        let carried = members
            .map { c, ids in (concept: c, verses: ids.compactMap { byId[$0] }.sorted { $0.lineId < $1.lineId }) }
            .filter { !$0.verses.isEmpty }
            .sorted { $0.verses.count != $1.verses.count ? $0.verses.count > $1.verses.count : $0.concept < $1.concept }
        let have = Set(carried.map(\.concept))
        let candidates = themes.filter { $0.nVerses > 0 && !have.contains($0.concept) }.map(\.concept).sorted()
        var notYet: [String] = []
        if !candidates.isEmpty {
            let start = ThemeOfTheDay.index(day: day, count: candidates.count)
            for k in 0..<min(notYetCount, candidates.count) { notYet.append(candidates[(start + k) % candidates.count]) }
        }
        return Summary(savedCount: saved.count, carried: carried, notYet: notYet)
    }
}

/// The Your-themes card on the Themes index.
struct YourThemesCard: View {
    let summary: YourThemes.Summary
    var onRetry: () -> Void = {}
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack {
                SectionEyebrow(text: "Your themes", symbol: "bookmark")
                Spacer()
                Image(systemName: "lock").font(.caption).foregroundStyle(Ink.muted)
                    .accessibilityLabel("Worked out on this device")
            }
            if summary.unavailable {
                Text("Your themes could not be counted just now.")
                    .font(.callout).foregroundStyle(Ink.muted)
                Button("Try again") { Haptics.tap(); onRetry() }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.accentText)
            } else if summary.savedCount < YourThemes.minimumSaved {
                Text("Save verses as you read, and this shows the themes they carry. It is worked out on this device; nothing leaves it.")
                    .font(.callout).foregroundStyle(Ink.muted)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Your \(summary.savedCount) saved verses carry")
                    .font(.subheadline.weight(.semibold))
                let cols = [GridItem(.adaptive(minimum: 110), spacing: Theme.Space.s, alignment: .leading)]
                LazyVGrid(columns: cols, alignment: .leading, spacing: Theme.Space.s) {
                    ForEach(summary.carried.prefix(9), id: \.concept) { item in
                        NavigationLink(value: Route.yourTheme(item.concept)) {
                            chip(item.concept, count: item.verses.count)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(ConceptName.display(item.concept)), \(item.verses.count) of your saved verses")
                    }
                }
                if summary.carried.isEmpty {
                    Text("None of your saved verses carries one of the 54 themes' words yet.")
                        .font(.caption).foregroundStyle(Ink.muted)
                }
                if !summary.notYet.isEmpty {
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                        Text("Not met yet:").font(.caption).foregroundStyle(Ink.muted)
                        ForEach(summary.notYet, id: \.self) { c in
                            NavigationLink(value: Route.theme(c)) {
                                Text(ConceptName.display(c)).font(.caption.weight(.semibold)).foregroundStyle(palette.accentText)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(Theme.Space.l)
        .background(Ink.card, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(Ink.hairline))
        .accessibilityIdentifier("themes.yours")
    }

    private func chip(_ concept: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Circle().fill(ThemeGroup.color(concept)).frame(width: 8, height: 8)
            Text(ConceptName.display(concept)).font(.footnote.weight(.medium))
            Text("\(count)").font(.footnote.monospacedDigit()).foregroundStyle(Ink.muted)
        }
        .padding(.horizontal, Theme.Space.s).padding(.vertical, 5)
        .background(Ink.raised, in: Capsule())
        .foregroundStyle(.primary)
    }
}

/// The reader's own saved verses that carry one theme (each opens its shabad). Pushed by value
/// on the Explore stack and derived here from the saved store, so it survives path changes.
struct YourThemeVersesScreen: View {
    let concept: String
    @Environment(AppContainer.self) private var container
    @State private var verses: [YourThemes.Verse] = []
    @State private var failed = false

    var body: some View {
        if failed {
            EmptyStateView(title: "Something went wrong", message: "Your saved verses for this theme could not be read just now.",
                           isError: true, actionTitle: "Try again") { Task { await load() } }
                .navigationTitle("Your \(ConceptName.display(concept))")
                .navigationBarTitleDisplayMode(.inline)
        } else {
            list
        }
    }

    private var list: some View {
        List {
            Section {
                ForEach(verses) { v in
                    LineRow(gurmukhi: v.gurmukhi, translit: v.translit, meta: "Ang \(String(v.ang))",
                            lineId: v.lineId, ang: v.ang, compId: v.compId) {
                        container.present(.shabad(compId: v.compId, focusLineId: v.lineId))
                    }
                    .readingColumn()
                    .listRowSeparator(.hidden)
                    .listRowBackground(Ink.base)
                }
            } header: {
                Text("\(verses.count) of your saved verses carry \(ConceptName.display(concept))")
                    .font(.caption).foregroundStyle(Ink.muted).textCase(nil)
            } footer: {
                NavigationLink(value: Route.theme(concept)) {
                    Text("Open the \(ConceptName.display(concept)) page").font(.subheadline.weight(.semibold))
                }
                .padding(.vertical, Theme.Space.m)
            }
        }
        .listStyle(.plain)
        .inkPlainList()
        .navigationTitle("Your \(ConceptName.display(concept))")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: container.presentation != nil) { await load() }
    }

    private func load() async {
        guard let corpus = container.corpus, let store = container.modelContainer else { verses = []; return }
        do {
            let saved = try store.mainContext.fetch(FetchDescriptor<SavedLine>()).map {
                YourThemes.Verse(lineId: $0.lineId, compId: $0.compId, ang: $0.ang, gurmukhi: $0.gurmukhi, translit: $0.translit)
            }
            let ids = try await corpus.themeMembers(lineIds: saved.map(\.lineId))[concept] ?? []
            guard !Task.isCancelled else { return }
            failed = false
            verses = saved.filter { ids.contains($0.lineId) }.sorted { $0.lineId < $1.lineId }
        } catch is CancellationError {
        } catch {
            failed = true          // never show an empty list as if none of the verses carried it
        }
    }
}
