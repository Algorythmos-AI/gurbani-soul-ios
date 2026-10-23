import SwiftUI
import GurbaniSearchKit

/// Concept Constellation v2 — Focus: one theme at the centre and the themes its verses also
/// carry. Distance = the corpus bond (closer = higher PPMI), line weight = Jaccard, size = verses
/// shared, colour = theological group. "Most shared" ranks by verses shared; "Most distinctive"
/// by PPMI. The caption always adds up (total = shared + alone) and the verses that carry the
/// theme alone sit in a halo round the centre. Every lens re-runs the same read. A list twin
/// carries the same model for VoiceOver, Switch Control and large type. Descriptive structure —
/// never a ranking of scripture.
struct ConstellationScreen: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var concept = "naam"
    @State private var rank: Rank = .shared
    @State private var lens = ConstellationLens()
    @State private var asList = false
    @State private var showSky = false
    @State private var noRaagThisHour = false
    @State private var state: LoadState<ConstellationFocus> = .loading

    enum Rank: String, CaseIterable, Identifiable {
        case shared = "Most shared", distinctive = "Most distinctive"
        var id: String { rawValue }
    }

    private var concepts: [ConceptRow] { container.meta?.concepts ?? [] }
    /// The Ang-strip bin the lens is narrowed to (nil = all 1,430 Angs).
    private var selectedBin: Int? {
        guard lens.angMin > 1 || lens.angMax < 1430 else { return nil }
        return (lens.angMin - 1) / ConstellationFocus.binWidth
    }
    /// Large type reads better as a list; the map is still one tap away.
    private var showList: Bool { asList || typeSize.isAccessibilitySize }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                controls
                LoadStateView(state: state, onRetry: { Task { await load() } }) { focus in
                    content(focus)
                }
                .frame(minHeight: 300)
            }
            .padding(Theme.Space.l)
        }
        .background(Ink.base.ignoresSafeArea())
        .navigationTitle("Constellation")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { showSky = true } label: { Label("See the whole sky", systemImage: "sparkles") }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(showList ? "Map" : "List") { asList.toggle() }
                    .disabled(typeSize.isAccessibilitySize)
                    .accessibilityLabel(showList ? "View as map" : "View as list")
            }
        }
        .navigationDestination(isPresented: $showSky) {
            ConstellationSkyScreen(current: concept) { picked in
                concept = picked
                showSky = false          // tapping a star in the Sky returns to Focus on that theme
            }
        }
        .alert("No raag is attributed to this watch", isPresented: $noRaagThisHour) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The timing claims name no raag for the current pahar, so the lens stays off.")
        }
        .task {
            consumeLink()
            await container.loadMeta()
        }
        .onChange(of: container.router.pendingConstellation) { _, _ in consumeLink() }
        .task(id: LoadKey(concept: concept, lens: lens)) { await load() }
    }

    private struct LoadKey: Hashable { let concept: String; let lens: ConstellationLens }

    // MARK: controls

    private var controls: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(spacing: Theme.Space.s) {
                themePicker
                Spacer(minLength: 0)
                lensMenu
            }
            Picker("Which companions", selection: $rank) {
                ForEach(Rank.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
        }
    }

    private var themePicker: some View {
        let byKey = Dictionary(uniqueKeysWithValues: concepts.map { ($0.concept, $0) })
        let placed = Set(ThemeGroup.all.flatMap(\.keys))
        let leftover = concepts.filter { !placed.contains($0.concept) }
        return Menu {
            ForEach(ThemeGroup.all) { group in
                Section(group.title) {
                    ForEach(group.keys.compactMap { byKey[$0] }) { c in pickButton(c) }
                }
            }
            if !leftover.isEmpty {
                Section("More Themes") { ForEach(leftover) { c in pickButton(c) } }
            }
        } label: {
            HStack(spacing: 6) {
                Circle().fill(ThemeGroup.color(concept)).frame(width: 10, height: 10).accessibilityHidden(true)
                Text(ConceptName.display(concept)).font(.headline)
                Image(systemName: "chevron.up.chevron.down").font(.caption).accessibilityHidden(true)
            }
        }
        .accessibilityLabel("Theme: \(ConceptName.display(concept))")
        .accessibilityHint("Choose the theme at the centre")
    }

    private func pickButton(_ c: ConceptRow) -> some View {
        Button {
            concept = c.concept
            Haptics.tap()
        } label: {
            Text("\(ConceptName.display(c.concept)) · \(c.nLines.formatted()) verses")
        }
    }

    private var lensMenu: some View {
        Menu {
            Section("Voice") {
                Picker("Voice", selection: $lens.author) {
                    Text("All voices").tag(String?.none)
                    ForEach(container.meta?.authors ?? [], id: \.name) { a in
                        Text(a.name).tag(Optional(a.name))   // names in full, as stored
                    }
                }
            }
            Section("Raag") {
                Picker("Raag", selection: $lens.raag) {
                    Text("All raags").tag(String?.none)
                    ForEach(container.meta?.raags ?? [], id: \.name) { r in
                        Text(r.roman ?? r.name).tag(Optional(r.name))
                    }
                }
            }
            if container.corpus?.capabilities.hasTiming == true {
                Section("Time of day") {
                    Toggle("This hour", isOn: Binding(get: { !lens.raags.isEmpty }, set: { on in
                        Task { await setThisHour(on) }
                    }))
                }
            }
            Section {
                Toggle("Refrains only (Rahao)", isOn: $lens.rahaoOnly)
                Toggle("Many themes (5 or more)", isOn: Binding(
                    get: { lens.minThemes >= 5 }, set: { lens.minThemes = $0 ? 5 : 0 }))
            }
            if lens.isActive {
                Button("Clear the lens", role: .destructive) { lens = ConstellationLens() }
            }
        } label: {
            Label(lens.isActive ? "Lens on" : "Lens",
                  systemImage: lens.isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                .font(.subheadline.weight(.semibold))
        }
        .accessibilityLabel(lens.isActive ? "Lens: \(lensWords)" : "Lens")
    }

    /// The lens in words, for the caption and VoiceOver.
    private var lensWords: String {
        var w: [String] = []
        if let a = lens.author { w.append(a) }
        if let r = lens.raag {
            w.append("Raag " + (container.meta?.raags.first { $0.name == r }?.roman ?? r))
        }
        if !lens.raags.isEmpty { w.append("this hour") }
        if lens.rahaoOnly { w.append("refrains") }
        if lens.minThemes >= 5 { w.append("5+ themes") }
        return w.joined(separator: " · ")
    }

    // MARK: content

    @ViewBuilder private func content(_ f: ConstellationFocus) -> some View {
        let name = ConceptName.display(concept)
        let shown = Array((rank == .shared ? f.companions : f.distinctive).prefix(9))
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            caption(f, name: name)
            if f.angBins.count == ConstellationFocus.binCount && (f.total > 0 || selectedBin != nil) {
                AngStrip(concept: concept, bins: f.angBins, selected: selectedBin) { bin in
                    if let bin {
                        let r = ConstellationFocus.angRange(bin: bin)
                        lens.angMin = r.lowerBound; lens.angMax = r.upperBound
                    } else { lens.angMin = 1; lens.angMax = 1430 }
                }
            }
            if f.total == 0 {
                ContentUnavailableView("No verses under this lens", systemImage: "circle.dotted",
                                       description: Text("Try a different voice, raag or filter."))
            } else if f.companions.isEmpty {
                ContentUnavailableView("These verses carry no other theme", systemImage: "circle.dotted")
            } else if showList {
                ConstellationList(concept: concept, focus: f, shown: shown) { open($0) }
            } else {
                ConstellationMap(center: concept, solo: f.solo, companions: shown,
                                 onCentre: { container.present(.themeCard(concept)) }) { open($0) }
                    .frame(height: 380)
                    .background(RoundedRectangle(cornerRadius: Theme.Radius.card).fill(Ink.clockFace))   // the night sky
                    .accessibilityElement(children: .contain)
                Text("Nearer stars appear together more often than chance (PPMI); thicker lines share more shabads; larger stars share more verses.")
                    .font(.caption2).foregroundStyle(Ink.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func caption(_ f: ConstellationFocus, name: String) -> some View {
        let lw = lensWords
        return VStack(alignment: .leading, spacing: 2) {
            Text("\(f.total.formatted()) verses carry \(name)\(lw.isEmpty ? "" : " (\(lw))")")
                .font(.subheadline.weight(.semibold))
            if f.total > 0 {
                Text("\(f.shared.formatted()) also carry another theme · \(f.solo.formatted()) carry \(name) alone")
                    .font(.caption).foregroundStyle(Ink.muted)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// "This hour": the raags whose attributed primary timing claim names the current watch
    /// (fixed clock). Claims, never facts — the caption says "this hour", the Raag Clock says why.
    private func setThisHour(_ on: Bool) async {
        guard on, let corpus = container.corpus else { lens.raags = []; return }
        let clock = await corpus.timingClock()
        let now = Calendar.current.dateComponents([.hour, .minute], from: Date())
        let pahar = Pahar.paharFromMinutes((now.hour ?? 0) * 60 + (now.minute ?? 0))
        let raags = Array(Set(clock.primary.filter { $0.pahar == pahar }.compactMap(\.raagName))).sorted()
        lens.raags = raags
        if raags.isEmpty { noRaagThisHour = true }
    }

    /// sggs://constellation?theme=&with= (deep link, Siri, Spotlight): land on that theme, and open
    /// the pair (or its alone verses) when the link names one.
    private func consumeLink() {
        guard let link = container.router.pendingConstellation else { return }
        container.router.pendingConstellation = nil
        concept = link.theme
        showSky = false
        if link.alone || link.with != nil {
            container.present(.pair(PairRequest(concept: link.theme, with: link.alone ? nil : link.with, lens: lens)))
        }
    }

    /// nil = the verses that carry the theme alone.
    private func open(_ co: String?) {
        Haptics.tap()
        container.present(.pair(PairRequest(concept: concept, with: co, lens: lens)))
    }

    private func load() async {
        guard let corpus = container.corpus else { state = .failed("No database"); return }
        state = .loading
        do {
            let r = try await corpus.constellationFocus(concept: concept, lens: lens)
            // .task(id:) cancels on a switch — never let theme A's late reply overwrite theme B's
            // view, and never swallow a real failure into a spinner.
            if Task.isCancelled { return }
            state = .loaded(r)
        } catch is CancellationError {
        } catch { state = .failed(UserMessage.load(error)) }
    }
}

/// Deterministic radial layout: the centre theme, the alone-halo, and up to nine companions on
/// spokes whose length encodes the PPMI bond (closer = stronger), width the Jaccard overlap, and
/// star size √(verses shared). Colours are the theme groups.
private struct ConstellationMap: View {
    let center: String
    let solo: Int
    let companions: [ConstellationCompanion]
    var onCentre: () -> Void
    var onSelect: (String?) -> Void
    @Environment(\.palette) private var palette

    private func points(in size: CGSize) -> [CGPoint] {
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        let outer = min(size.width, size.height) / 2 - 40
        let inner = min(92, outer * 0.55)
        let lo = companions.map(\.ppmi).min() ?? 0, hi = companions.map(\.ppmi).max() ?? 0
        var out: [CGPoint] = []
        for (i, co) in companions.enumerated() {
            let near = hi > lo ? (co.ppmi - lo) / (hi - lo) : 0.5
            let r = inner + (outer - inner) * CGFloat(1 - near)
            let a = 2 * Double.pi * Double(i) / Double(max(companions.count, 1)) - Double.pi / 2
            out.append(CGPoint(x: c.x + r * CGFloat(cos(a)), y: c.y + r * CGFloat(sin(a))))
        }
        return out
    }

    var body: some View {
        GeometryReader { geo in
            let c = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let pts = points(in: geo.size)
            let maxN = Double(companions.map(\.n).max() ?? 1)
            let maxJ = max(companions.map(\.jaccard).max() ?? 1, 1e-6)
            ZStack {
                ForEach(Array(companions.enumerated()), id: \.element.id) { i, co in
                    Path { p in p.move(to: c); p.addLine(to: pts[i]) }
                        .stroke(ThemeGroup.color(co.co).opacity(0.45), lineWidth: 1 + 5 * CGFloat(co.jaccard / maxJ))
                        .accessibilityHidden(true)
                }
                if solo > 0 {
                    Button { onSelect(nil) } label: {
                        ZStack(alignment: .bottom) {
                            Circle().strokeBorder(Ink.muted, style: StrokeStyle(lineWidth: 1.5, dash: [3, 5]))
                                .frame(width: 104, height: 104)
                            Text("\(solo.formatted()) alone").font(.caption2.weight(.semibold))
                                .foregroundStyle(Ink.muted).offset(y: 16)
                        }
                    }
                    .buttonStyle(.plain)
                    .position(c)
                    .accessibilityLabel("\(solo) verses carry \(ConceptName.display(center)) alone")
                    .accessibilityHint("Opens them")
                }
                ForEach(Array(companions.enumerated()), id: \.element.id) { i, co in
                    Button { onSelect(co.co) } label: {
                        VStack(spacing: 2) {
                            Circle().fill(ThemeGroup.color(co.co))
                                .frame(width: starSize(co.n, maxN), height: starSize(co.n, maxN))
                            Text("\(ConceptName.display(co.co)) · \(co.n.formatted())")
                                .font(.caption2.weight(.semibold)).foregroundStyle(.primary)
                                .lineLimit(1).minimumScaleFactor(0.7)
                                .fixedSize()
                        }
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .position(pts[i])
                    .accessibilityLabel("\(ConceptName.display(co.co)): \(co.n) verses carry both \(ConceptName.display(center)) and \(ConceptName.display(co.co)); together in \(co.shabadCount) shabads")
                }
                Button(action: onCentre) {
                    Text(ConceptName.display(center))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(palette.onAccent)
                        .lineLimit(1).minimumScaleFactor(0.6)
                        .frame(width: 72, height: 72)
                        .background(Circle().fill(palette.accentFill))
                        .overlay(Circle().strokeBorder(palette.accent, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
                .position(c)
                .accessibilityLabel("\(ConceptName.display(center)): about this theme")
            }
        }
    }

    private func starSize(_ n: Int, _ maxN: Double) -> CGFloat {
        26 + CGFloat(Double(max(n, 0)).squareRoot() / max(maxN, 1).squareRoot()) * 34
    }
}

/// The list twin: the same companions, in the same order, plus the alone row.
private struct ConstellationList: View {
    let concept: String
    let focus: ConstellationFocus
    let shown: [ConstellationCompanion]
    var onSelect: (String?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(shown) { co in
                row(title: ConceptName.display(co.co), color: ThemeGroup.color(co.co),
                    detail: "\(co.n.formatted()) verses shared · together in \(co.shabadCount.formatted()) shabads · PPMI \(co.ppmi.formatted(.number.precision(.fractionLength(2))))") {
                    onSelect(co.co)
                }
                Divider()
            }
            if focus.solo > 0 {
                row(title: "\(ConceptName.display(concept)) alone", color: Ink.muted,
                    detail: "\(focus.solo.formatted()) verses carry no other theme") { onSelect(nil) }
            }
        }
    }

    private func row(title: String, color: Color, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                Circle().fill(color).frame(width: 10, height: 10).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                    Text(detail).font(.caption).foregroundStyle(Ink.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary).accessibilityHidden(true)
            }
            .padding(.vertical, Theme.Space.s)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

/// What a pair sheet shows: the verses `concept` shares with `with`, or (nil) carries alone.
struct PairRequest: Identifiable, Hashable {
    let concept: String
    let with: String?
    let lens: ConstellationLens
    var id: String { "\(concept)~\(with ?? "alone")" }
}

/// The verses two themes share, grouped by shabad (raag · voice · Ang), 50 at a time. Each verse
/// says which verified word of each theme it carries — a word match, not an interpretation.
struct PairSheet: View {
    let request: PairRequest
    @Environment(AppContainer.self) private var container
    @Environment(\.dismiss) private var dismiss
    @State private var shabads: [PairShabad] = []
    @State private var total = 0
    @State private var bond: ThemeBond?
    @State private var loaded = 0
    @State private var state: LoadState<Int> = .loading
    @State private var loadingMore = false

    private var title: String {
        let a = ConceptName.display(request.concept)
        return request.with.map { "\(a) ✦ \(ConceptName.display($0))" } ?? "\(a) alone"
    }

    var body: some View {
        NavigationStack {
            LoadStateView(state: state, emptyTitle: "No verses", onRetry: { Task { await loadFirst() } }) { _ in
                List {
                    Section {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(total.formatted()) verses").font(.headline)
                            if let bond {
                                Text("Together in \(bond.shabadCount.formatted()) shabads across the Granth")
                                    .font(.caption).foregroundStyle(Ink.muted)
                            }
                            Text(request.with == nil
                                 ? "Shown because it carries a word of this theme and no other theme's word."
                                 : "Shown because it carries a word of each theme: matched by a shared word, not by meaning.")
                                .font(.caption).foregroundStyle(Ink.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .combine)
                    }
                    .listRowBackground(Ink.base)
                    ForEach(shabads) { sh in
                        Section {
                            ForEach(sh.verses) { v in
                                VStack(alignment: .leading, spacing: 4) {
                                    LineRow(gurmukhi: v.gurmukhi, translit: v.translit,
                                            meta: (v.isRahao ? "ਰਹਾਉ · refrain · " : "") + "Ang \(v.ang)",
                                            lineId: v.id, ang: v.ang, compId: sh.compId, shareContext: title) {
                                        container.present(.shabad(compId: sh.compId, focusLineId: v.id))
                                    }
                                    Text("Carries " + v.terms.joined(separator: " · "))
                                        .font(.caption2).foregroundStyle(Ink.muted)
                                        .accessibilityLabel(Text("Matched words: ") + Text(v.terms.joined(separator: ", ")))
                                }
                                .listRowSeparator(.hidden)
                                .listRowBackground(Ink.base)
                            }
                        } header: {
                            Text(eyebrow(sh)).font(.caption.weight(.semibold))
                        }
                    }
                    if loaded < total {
                        Button {
                            Task { await loadMore() }
                        } label: {
                            Text(loadingMore ? "Loading…" : "Show \(min(50, total - loaded)) more (\(loaded.formatted()) of \(total.formatted()))")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .disabled(loadingMore)
                        .listRowBackground(Ink.base)
                    }
                }
                .listStyle(.plain)
                .inkPlainList()
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
        .task { await loadFirst() }
    }

    private func eyebrow(_ sh: PairShabad) -> String {
        var parts: [String] = []
        if let r = sh.raag { parts.append("Raag " + (container.meta?.raags.first { $0.name == r }?.roman ?? r)) }
        if let a = sh.author { parts.append(a) }
        parts.append("Ang \(sh.ang)")
        return parts.joined(separator: " · ")
    }

    private func page(_ offset: Int) async throws -> PairPage? {
        guard let corpus = container.corpus else { return nil }
        return try await corpus.constellationPair(concept: request.concept, with: request.with,
                                                  lens: request.lens, offset: offset)
    }

    private func loadFirst() async {
        state = .loading
        do {
            guard let p = try await page(0) else { state = .failed("No database"); return }
            shabads = p.shabads; total = p.total; bond = p.bond; loaded = p.verseCount
            state = p.total == 0 ? .empty : .loaded(p.total)
        } catch is CancellationError {
        } catch { state = .failed(UserMessage.load(error)) }
    }

    private func loadMore() async {
        loadingMore = true
        defer { loadingMore = false }
        guard let p = try? await page(loaded) else { return }   // try? flattens the optional
        var merged = shabads
        for sh in p.shabads {      // a shabad cut by the page boundary continues in the same group
            if let last = merged.last, last.compId == sh.compId {
                merged[merged.count - 1] = PairShabad(compId: last.compId, ang: last.ang, raag: last.raag,
                                                      author: last.author, verses: last.verses + sh.verses)
            } else { merged.append(sh) }
        }
        shabads = merged
        loaded += p.verseCount
    }
}
