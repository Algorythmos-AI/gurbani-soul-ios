import SwiftUI
import GurbaniSearchKit

/// What "Find in Index" matches: a raag, a bani before/after the raags, a composition, or a voice
/// whose English name, Gurmukhi name or corpus roman contains the query — directly, or after the
/// same Roman fold the search engine uses, so "gauri", "gaurhee", "ਗਉੜੀ" and "Sukhmani" all land.
/// Pure, so it is tested without a view.
enum IndexFind {
    struct Results: Equatable {
        var raags: [RaagRow] = []
        var sections: [SectionRow] = []
        var compositions: [BaniSummary] = []
        var voices: [AuthorRow] = []
        var isEmpty: Bool { raags.isEmpty && sections.isEmpty && compositions.isEmpty && voices.isEmpty }
    }

    static func matches(_ query: String, _ fields: [String?]) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return false }
        let fq = RomanNorm.fold(q)
        for case let f? in fields {
            let lf = f.lowercased()
            if lf.contains(q) { return true }
            if fq.count >= 2, RomanNorm.fold(lf).contains(fq) { return true }
        }
        return false
    }

    static func run(_ query: String, meta: CorpusMeta, compositions: [BaniSummary]) -> Results {
        var r = Results()
        r.raags = GranthMap(meta: meta).raags.filter {
            matches(query, [$0.name, $0.roman, GranthNames.raag($0.name, roman: $0.roman)])
        }
        r.sections = GranthMap(meta: meta).opening.filter { matches(query, [$0.name, GranthNames.section($0.name)]) }
            + GranthMap(meta: meta).closing.filter { matches(query, [$0.name, GranthNames.section($0.name)]) }
        var seen = Set<String>()
        r.compositions = compositions.filter { matches(query, [$0.titleEn, $0.titleGm]) && seen.insert($0.id).inserted }
        r.voices = meta.authors.filter { matches(query, [$0.name]) }
        return r
    }
}

/// The grouped results of Find in Index.
struct IndexFindResults: View {
    let query: String
    let meta: CorpusMeta
    let registry: [BaniSummary]
    let openRaag: (RaagRow) -> Void
    let openAng: (Int) -> Void

    @Environment(\.palette) private var palette

    /// The compositions this Index offers: the heroes (as the registry names them), then the shelf.
    private var offered: [BaniSummary] {
        CompositionCatalog.heroes.compactMap { CompositionCatalog.resolve($0, in: registry) }
            + CompositionCatalog.more(from: registry)
    }

    var body: some View {
        let r = IndexFind.run(query, meta: meta, compositions: offered)
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            if r.isEmpty {
                ContentUnavailableView.search(text: query)
                    .padding(.top, Theme.Space.xl)
            }
            if !r.raags.isEmpty {
                group("Raags", symbol: "music.note") {
                    ForEach(r.raags) { raag in
                        row(title: GranthNames.raag(raag.name, roman: raag.roman).map { "Raag \($0)" } ?? raag.name,
                            gurmukhi: raag.name, detail: (raag.firstAng...raag.lastAng).angLabel) { openRaag(raag) }
                    }
                }
            }
            if !r.compositions.isEmpty {
                group("Compositions", symbol: "text.book.closed") {
                    ForEach(r.compositions) { b in
                        let hero = CompositionCatalog.heroes.first { CompositionCatalog.resolve($0, in: registry)?.id == b.id }
                        NavigationLink(value: Route.composition(key: b.key, variant: hero?.variant ?? b.variant)) {
                            rowBody(title: b.titleEn, gurmukhi: b.titleGm,
                                    detail: b.estimatedMinutes.map { "\(String($0)) min" })
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("find_composition_\(b.key)")
                    }
                }
            }
            if !r.sections.isEmpty {
                group("Banis", symbol: "book.pages") {
                    ForEach(r.sections) { s in
                        row(title: GranthNames.section(s.name) ?? s.name, gurmukhi: s.name,
                            detail: (s.firstAng...s.lastAng).angLabel) { openAng(s.firstAng) }
                    }
                }
            }
            if !r.voices.isEmpty {
                group("Voices", symbol: "person.2") {
                    ForEach(r.voices) { a in
                        row(title: a.name, gurmukhi: nil, detail: "\(a.nLines.formatted()) lines") { openAng(a.firstAng) }
                    }
                }
            }
        }
        .accessibilityIdentifier("index_find")
    }

    private func group<C: View>(_ title: String, symbol: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            SectionEyebrow(text: title, symbol: symbol)
            VStack(spacing: 0) { content() }
                .background(Ink.card, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(Ink.hairline))
        }
    }

    private func row(title: String, gurmukhi: String?, detail: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) { rowBody(title: title, gurmukhi: gurmukhi, detail: detail) }
            .buttonStyle(.plain)
    }

    private func rowBody(title: String, gurmukhi: String?, detail: String?) -> some View {
        HStack(spacing: Theme.Space.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                if let gurmukhi { GurmukhiText(verbatim: gurmukhi, size: 16) }
            }
            Spacer(minLength: Theme.Space.s)
            if let detail { Text(detail).font(.caption).foregroundStyle(.secondary).monospacedDigit() }
            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, Theme.Space.l).padding(.vertical, Theme.Space.m)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([title, detail].compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(.isButton)
    }
}
