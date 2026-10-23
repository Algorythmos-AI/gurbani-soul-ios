import SwiftUI
import GurbaniSearchKit

/// The 22 Vaars. Each card shows a Vaar's printed title, its voices and — in the voice strip —
/// the interleaving of saloks and pauris, all read from the print (`VaarText`). Structure, never a
/// ranking of scripture: the default order is the Granth's own, and "longest" only re-sorts.
struct VaarsScreen: View {
    @Environment(AppContainer.self) private var container
    @State private var summaries: [VaarSummary]?
    @State private var texts: [Int: VaarText] = [:]
    @State private var ribbonPick: Int?
    @State private var dhuniShown: DhuniItem?
    @SceneStorage("vaars.filter") private var filterKey = VaarFilter.all.key
    @SceneStorage("vaars.sort") private var sortKey = VaarSort.granth.rawValue

    var body: some View {
        Group {
            if let summaries {
                if summaries.isEmpty {
                    ContentUnavailableView("Vaar tables not in this build", systemImage: "list.number")
                } else {
                    content(summaries)
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Ink.canvas.ignoresSafeArea())
        .navigationTitle("Vaars")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Order", selection: $sortKey) {
                        ForEach(VaarSort.allCases) { Label($0.title, systemImage: $0.icon).tag($0.rawValue) }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .accessibilityLabel("Order")
                .accessibilityIdentifier("vaars.sort")
            }
        }
        .sheet(item: $dhuniShown) { DhuniSheet(item: $0) }
        .task {
            guard summaries == nil, let corpus = container.corpus else { return }
            async let s = corpus.vaars()
            async let t = corpus.vaarTexts()
            let (loaded, built) = await (s, t)
            texts = built
            summaries = loaded
        }
    }

    private var filter: VaarFilter { VaarFilter(key: filterKey) }
    private var sort: VaarSort { VaarSort(rawValue: sortKey) ?? .granth }

    private func content(_ all: [VaarSummary]) -> some View {
        let filters = VaarFilter.available(in: all, texts: texts)
        let active = filters.contains(filter) ? filter : .all
        let shown = sort.apply(all.filter { active.matches($0, texts[$0.vaarId]) }, texts: texts)
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Theme.Space.m) {
                    hero(all)
                    filterRow(filters, active: active)
                    ForEach(shown) { v in
                        VaarCard(summary: v, text: texts[v.vaarId], isPicked: v.vaarId == ribbonPick) { line in
                            dhuniShown = DhuniItem(line: line, raag: v.raag)
                        }
                        .id(v.vaarId)
                    }
                    if shown.isEmpty {
                        Text("No Vaar matches this filter.").font(.callout).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity).padding(.vertical, Theme.Space.xl)
                    }
                }
                .padding(.horizontal, Theme.Space.l)
                .padding(.bottom, Theme.Space.xl)
            }
            .onChange(of: ribbonPick) { _, id in
                guard let id else { return }
                if !shown.contains(where: { $0.vaarId == id }) { filterKey = VaarFilter.all.key }
                MotionGate.run(Motion.gentle) { proxy.scrollTo(id, anchor: .top) }
            }
        }
    }

    private func hero(_ all: [VaarSummary]) -> some View {
        let built = all.compactMap { texts[$0.vaarId] }
        let complete = built.count == all.count
        return Card {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                SectionEyebrow(text: "Sri Guru Granth Sahib Ji")
                Text("Twenty-two ballads, many voices")
                    .font(Brand.heading(.title3))
                    .accessibilityAddTraits(.isHeader)
                HStack(spacing: Theme.Space.s) {
                    StatTile(value: "\(all.count)", caption: "Vaars")
                    StatTile(value: complete ? "\(built.reduce(0) { $0 + $1.nPauris })" : "—", caption: "pauris")
                    StatTile(value: complete ? "\(built.reduce(0) { $0 + $1.nSaloks })" : "—", caption: "saloks")
                }
                VaarSpanRibbon(marks: all.map { v in
                    VaarSpanRibbon.Mark(id: v.vaarId, firstAng: texts[v.vaarId]?.firstAng ?? v.firstAng,
                                      lastAng: texts[v.vaarId]?.lastAng ?? v.lastAng, author: v.pauriAuthor,
                                      label: "\(v.roman ?? v.raag ?? "Vaar"), \(angSpan(v.firstAng, v.lastAng))")
                }, selected: $ribbonPick)
                .accessibilityIdentifier("vaars.ribbon")
            }
        }
        .padding(.top, Theme.Space.s)
    }

    private func filterRow(_ filters: [VaarFilter], active: VaarFilter) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Space.s) {
                ForEach(filters, id: \.key) { f in
                    ModePill(title: f.title, dot: f.dot, isSelected: f == active,
                             accessibilityID: "vaars.filter.\(f.key)") {
                        MotionGate.run { filterKey = f.key }
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
    }
}

/// One Vaar on the home list.
private struct VaarCard: View {
    let summary: VaarSummary
    let text: VaarText?
    let isPicked: Bool
    let showDhuni: (VaarLine) -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        NavigationLink(value: Route.vaar(summary.vaarId)) { card }
            .buttonStyle(.plain)
            .accessibilityIdentifier("vaar.card.\(summary.vaarId)")
            .overlay(alignment: .bottomTrailing) {
                if let dhuni = text?.dhuni {
                    Button { showDhuni(dhuni) } label: {
                        Text("ਧੁਨੀ").font(Brand.gurmukhi(15))
                            .padding(.horizontal, Theme.Space.m).frame(minHeight: 30)
                            .background(Capsule().fill(Ink.raised))
                            .overlay(Capsule().strokeBorder(palette.accent.opacity(0.6)))
                            .foregroundStyle(palette.accentText)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, Theme.Space.l + 14)
                    .padding(.bottom, Theme.Space.l - 7)
                    .accessibilityLabel("Dhuni: the tune this Vaar is set to")
                    .accessibilityIdentifier("vaar.dhuni.\(summary.vaarId)")
                }
            }
    }

    private var card: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                    if let raag = summary.raag { GurmukhiText(verbatim: raag, size: 19, weight: .medium) }
                    if let roman = summary.roman {
                        Text(roman).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: Theme.Space.s)
                    if let text { VoiceDots(voices: text.voices) }
                }
                ForEach(titleLines, id: \.self) { GurmukhiText(verbatim: $0, size: 16) }
                if let text {
                    VoiceStrip(text: text).padding(.vertical, 2)
                }
                HStack(alignment: .center, spacing: Theme.Space.s) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(meta).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        if let pa = summary.pauriAuthor {
                            Text("Pauris · \(pa)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: Theme.Space.s)
                    // room for the ਧੁਨੀ button, which sits over the card (outside the link)
                    if text?.dhuni != nil { Color.clear.frame(width: 64, height: 30) }
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                }
            }
        }
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card)
            .strokeBorder(palette.accent, lineWidth: isPicked ? 1.5 : 0))
    }

    /// The printed title; when the Vaar could not be read, the table title (never the invocation).
    private var titleLines: [String] {
        if let text { return text.titleLines.map(\.gurmukhi) }
        if let t = summary.title, !t.isEmpty, !VaarStructure.isInvocation(t) { return [t] }
        return []
    }

    private var meta: String {
        let p = text?.nPauris ?? summary.nPauris, s = text?.nSaloks ?? summary.nSaloks
        let span = angSpan(text?.firstAng ?? summary.firstAng, text?.lastAng ?? summary.lastAng)
        return (s > 0 ? "\(p) pauris · \(s) saloks" : "\(p) pauris") + " · " + span
    }
}

/// The ਧੁਨੀ line, verbatim, with its citation. The explanation is labelled as such.
struct DhuniItem: Identifiable {
    let line: VaarLine
    let raag: String?
    var id: Int { line.id }
}

private struct DhuniSheet: View {
    let item: DhuniItem
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            SectionEyebrow(text: "ਧੁਨੀ · as printed")
            GurmukhiText(verbatim: item.line.gurmukhi, size: 22)
            Text("Sri Guru Granth Sahib Ji · Ang \(item.line.ang)")
                .font(.footnote).foregroundStyle(.secondary)
            Text("The heading names the tune (ਧੁਨੀ) the Vaar is to be sung to — nine of the twenty-two carry one.")
                .font(.footnote).foregroundStyle(.secondary)
                .accessibilityLabel("About: The heading names the tune the Vaar is to be sung to. Nine of the twenty-two carry one.")
            Spacer(minLength: 0)
        }
        .padding(Theme.Space.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Ink.card.ignoresSafeArea())
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}

/// Home filters: everything, the Vaar's own (pauri) voice, those with a ਧੁਨੀ, short ones.
enum VaarFilter: Hashable {
    case all, voice(String), dhuni, short

    static let shortPauris = 10

    var key: String {
        switch self {
        case .all: "all"
        case .voice(let a): "voice:\(a)"
        case .dhuni: "dhuni"
        case .short: "short"
        }
    }

    init(key: String) {
        if key == "dhuni" { self = .dhuni }
        else if key == "short" { self = .short }
        else if key.hasPrefix("voice:") { self = .voice(String(key.dropFirst(6))) }
        else { self = .all }
    }

    var title: String {
        switch self {
        case .all: "All"
        case .voice(let a): VoiceInk.short(a)
        case .dhuni: "With ਧੁਨੀ"
        case .short: "Short"
        }
    }

    var dot: Color? { if case .voice(let a) = self { VoiceInk.color(for: a) } else { nil } }

    func matches(_ v: VaarSummary, _ t: VaarText?) -> Bool {
        switch self {
        case .all: true
        case .voice(let a): v.pauriAuthor == a
        case .dhuni: t?.dhuni != nil
        case .short: (t?.nPauris ?? v.nPauris) <= Self.shortPauris
        }
    }

    /// The filters with at least one match, voices in M1…M5 order then others.
    static func available(in all: [VaarSummary], texts: [Int: VaarText]) -> [VaarFilter] {
        let authors = Set(all.compactMap(\.pauriAuthor)).sorted { a, b in
            let ka = VoiceInk.short(a), kb = VoiceInk.short(b)
            let ma = ka.count == 2 && ka.hasPrefix("M"), mb = kb.count == 2 && kb.hasPrefix("M")
            return ma != mb ? ma : ka < kb
        }
        let candidates: [VaarFilter] = [.all] + authors.map { .voice($0) } + [.dhuni, .short]
        return candidates.filter { f in f == .all || all.contains { f.matches($0, texts[$0.vaarId]) } }
    }
}

enum VaarSort: String, CaseIterable, Identifiable {
    case granth, length
    var id: String { rawValue }
    var title: String { self == .granth ? "Granth order" : "Longest first" }
    var icon: String { self == .granth ? "book" : "text.line.first.and.arrowtriangle.forward" }
    func apply(_ v: [VaarSummary], texts: [Int: VaarText]) -> [VaarSummary] {
        switch self {
        case .granth: return v.sorted { $0.firstAng != $1.firstAng ? $0.firstAng < $1.firstAng : $0.vaarId < $1.vaarId }
        case .length:
            func n(_ s: VaarSummary) -> Int { texts[s.vaarId]?.lineCount ?? 0 }
            return v.sorted { n($0) != n($1) ? n($0) > n($1) : $0.firstAng < $1.firstAng }
        }
    }
}
