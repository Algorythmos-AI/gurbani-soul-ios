import SwiftUI
import GurbaniSearchKit

/// One theme as a chapter of the Granth: its Gurmukhi headword and full description, its word
/// family (tap a form to narrow everything below), the Rahao lines that carry it, the shabads
/// steeped in it, where it falls in reading order and which raags and voices carry it at a higher
/// rate, the themes it most distinctively appears with, and every verse. All counts are real rows;
/// nothing is ranked as better or more important.
struct ThemeChapterScreen: View {
    let concept: String
    @Environment(AppContainer.self) private var container
    @Environment(\.palette) private var palette
    @State private var base: ThemeBase?
    @State private var detail: ThemeDetail?
    @State private var failed: String?
    @State private var term: String?
    @State private var bin: Int?
    @State private var showAllSteeped = false
    @State private var notFound = false

    private var name: String { ConceptName.display(concept) }

    var body: some View {
        Group {
            if let base {
                content(base)
            } else if notFound {
                EmptyStateView(title: "No such theme", message: "There is no theme called “\(concept)”.",
                               actionTitle: "See all themes") { container.router.explorePath = NavigationPath([Route.themes]) }
            } else if let failed {
                EmptyStateView(title: "Something went wrong", message: failed, isError: true,
                               actionTitle: "Try again") { Task { await loadBase() } }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Ink.canvas)
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let base {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: ThemeShare.text(base.row)) { Image(systemName: "square.and.arrow.up") }
                        .accessibilityLabel("Share this theme")
                }
            }
        }
        .task { await loadBase() }
        .task(id: term) { await loadDetail() }
        .onChange(of: term) { _, _ in showAllSteeped = false; bin = nil }
    }

    private var filter: ThemeFilter { ThemeFilter(term: term) }

    private func content(_ b: ThemeBase) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                header(b)
                if b.words.count > 1 { wordFamily(b) }
                if let d = detail, d.term == term {
                    if !d.heart.isEmpty { heartLines(d) }
                    if !d.steeped.isEmpty { steeped(d) }
                } else {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 120)
                }
                whereItLives(b)
                if !b.companions.isEmpty { companions(b) }
                allVerses(b)
            }
            .padding(Theme.Space.l)
            .readingColumn()
        }
    }

    // MARK: sections

    private func header(_ b: ThemeBase) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            if let g = ThemeGroup.of(concept) {
                HStack(spacing: 6) {
                    Circle().fill(g.color).frame(width: 10, height: 10).accessibilityHidden(true)
                    Text(g.title).font(.caption.weight(.semibold)).foregroundStyle(Ink.muted)
                }
            }
            if let head = b.row.headword {
                GurmukhiText(verbatim: head, size: 40, weight: .regular).foregroundStyle(.primary)
                    .accessibilityIdentifier("themes.page.headword")
            }
            Text(name).font(Brand.heading(.title2)).accessibilityAddTraits(.isHeader)
            Text("\(b.row.nVerses.formatted()) verses in \(b.row.nShabads.formatted()) shabads · \(b.row.nRahao.formatted()) in Rahao lines")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(palette.accentText)
            if !b.row.description.isEmpty {
                MixedScriptText(text: b.row.description).font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func wordFamily(_ b: ThemeBase) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            SectionEyebrow(text: "The word family")
            if EditorialGate.aboutCopy {            // explanatory copy waits for the scholar review (G3)
                Text("The forms of its words as they appear in the text. Tap one to narrow this page to it.")
                    .font(.caption).foregroundStyle(Ink.muted)
            }
            let cols = [GridItem(.adaptive(minimum: 96), spacing: Theme.Space.s, alignment: .leading)]
            LazyVGrid(columns: cols, alignment: .leading, spacing: Theme.Space.s) {
                ForEach(b.words) { w in
                    let on = term == w.term
                    Button {
                        Haptics.tap()
                        term = on ? nil : w.term
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            GurmukhiText(verbatim: w.term, size: 19)
                            Text(w.n.formatted()).font(.caption.monospacedDigit()).foregroundStyle(Ink.muted)
                        }
                        .padding(.horizontal, Theme.Space.s).padding(.vertical, 4)
                        .background(on ? Ink.raised : Ink.card, in: RoundedRectangle(cornerRadius: Theme.Radius.chip))
                        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.chip)
                            .strokeBorder(on ? ThemeGroup.color(concept) : Ink.hairline, lineWidth: on ? 1.5 : 1))
                        .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
                    .accessibilityIdentifier("themes.word")
                }
            }
            if let term {
                HStack {
                    Text("Showing only verses with").font(.caption).foregroundStyle(Ink.muted)
                    GurmukhiText(verbatim: term, size: 15)
                    Spacer()
                    Button("Show every form") { Haptics.tap(); self.term = nil }
                        .font(.caption.weight(.semibold)).foregroundStyle(palette.accentText)
                }
            }
        }
    }

    private func heartLines(_ d: ThemeDetail) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            SectionEyebrow(text: "Heart-lines")
            if EditorialGate.aboutCopy {            // explanatory copy waits for the scholar review (G3)
                Text("Explanation: Rahao (pause) is the line a shabad returns to; it is traditionally read as the shabad's central thought. These Rahao lines carry \(name).")
                    .font(.caption).foregroundStyle(Ink.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(d.heart.prefix(4)) { g in
                verseCard(g.lines, compId: g.compId)
            }
            if d.heartTotal > d.heart.prefix(4).reduce(0, { $0 + $1.lines.count }) {
                NavigationLink(value: Route.themeVerses(concept, ThemeFilter(term: term, lens: ConstellationLens(rahaoOnly: true)))) {
                    seeAll("See all \(d.heartTotal.formatted()) Rahao lines")
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func steeped(_ d: ThemeDetail) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            SectionEyebrow(text: "Shabads where it fills half the verses")
            Text("Shabads of \(SteepedShabad.minLines) or more verses where at least half carry \(name), in reading order.")
                .font(.caption).foregroundStyle(Ink.muted)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(d.steeped.prefix(showAllSteeped ? d.steeped.count : 5)) { s in
                Button {
                    Haptics.tap()
                    container.present(.shabad(compId: s.compId, focusLineId: s.firstLineId))
                } label: {
                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        GurmukhiText(verbatim: s.firstVerse, size: 19).foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                        Text(steepedMeta(s)).font(.caption).foregroundStyle(Ink.muted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Theme.Space.m)
                    .background(Ink.card, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(Ink.hairline))
                }
                .buttonStyle(.pressableCard)
                .accessibilityHint("Opens the shabad")
            }
            if d.steeped.count > 5 && !showAllSteeped {
                Button { Haptics.tap(); showAllSteeped = true } label: {
                    seeAll("Show all \(d.steeped.count) shabads")
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func steepedMeta(_ s: SteepedShabad) -> String {
        var bits = ["\(s.n) of \(s.total) verses", "Ang \(s.ang)"]
        if let r = s.raag { bits.append(raagName(r)) }
        if let a = s.author { bits.append(a.replacingOccurrences(of: " Ji", with: "")) }
        return bits.joined(separator: " · ")
    }

    private func whereItLives(_ b: ThemeBase) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            SectionEyebrow(text: "Where it lives")
            // the strip follows the word filter, so the count it shows is the list it opens
            let bins = term == nil ? b.row.angBins : (detail?.term == term ? detail?.bins : nil) ?? b.row.angBins
            AngStrip(concept: concept, bins: bins, selected: bin) { bin = $0 }
            if let bin, bins.indices.contains(bin) {
                let r = ConstellationFocus.angRange(bin: bin)
                if bins[bin] > 0 {
                    NavigationLink(value: Route.themeVerses(concept, ThemeFilter(term: term, lens: ConstellationLens(angMin: r.lowerBound, angMax: r.upperBound)))) {
                        seeAll("See the \(bins[bin].formatted()) \(bins[bin] == 1 ? "verse" : "verses") in Angs \(r.lowerBound)–\(r.upperBound)")
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("No verse in Angs \(r.lowerBound)–\(r.upperBound) carries it\(term == nil ? "" : " in this form").")
                        .font(.caption).foregroundStyle(Ink.muted)
                }
            }
            if let card = b.card {
                if !card.raags.isEmpty {
                    concentration("Raags that carry it at a higher rate", card.raags.prefix(4).map { ($0, raagName($0.entityId)) })
                }
                if !card.authors.isEmpty {
                    concentration("Voices that carry it at a higher rate",
                                  card.authors.prefix(4).map { ($0, $0.entityId.replacingOccurrences(of: " Ji", with: "")) })
                }
                if EditorialGate.aboutCopy {        // explanatory copy waits for the scholar review (G3)
                    Text("A rate is the share of that raag's or voice's tagged verses that carry \(name), beside its share across the whole Granth; shown only where the sample is large enough to be reliable.")
                        .font(.caption2).foregroundStyle(Ink.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func concentration(_ title: String, _ rows: [(ThemeConcentration, String)]) -> some View {
        let pct = { (v: Double) in (v * 100).formatted(.number.precision(.fractionLength(1))) + "%" }
        return VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text(title).font(.subheadline.weight(.semibold))
            ForEach(rows, id: \.0.id) { x, label in
                HStack(alignment: .firstTextBaseline) {
                    Text(label).font(.subheadline)
                    Spacer()
                    Text("\(pct(x.entityRate)) vs \(pct(x.corpusRate))")
                        .font(.caption.monospacedDigit()).foregroundStyle(Ink.muted)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func companions(_ b: ThemeBase) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            SectionEyebrow(text: "Often appears with")
            Text("The themes that share shabads with \(name) more than their size alone would predict.")
                .font(.caption).foregroundStyle(Ink.muted)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(b.companions) { c in
                HStack {
                    NavigationLink(value: Route.theme(c.co)) {
                        HStack(spacing: Theme.Space.s) {
                            Circle().fill(ThemeGroup.color(c.co)).frame(width: 10, height: 10).accessibilityHidden(true)
                            Text(ConceptName.display(c.co)).font(.body.weight(.medium)).foregroundStyle(.primary)
                            Text("\(c.n.formatted()) shared verses").font(.caption.monospacedDigit()).foregroundStyle(Ink.muted)
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Button {
                        Haptics.tap()
                        container.router.openConstellation(ConstellationLink(theme: concept, with: c.co, alone: false))
                    } label: {
                        Image(systemName: "sparkles").foregroundStyle(palette.accentText)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open \(name) and \(ConceptName.display(c.co)) in the Constellation")
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func allVerses(_ b: ThemeBase) -> some View {
        // never a stale number: the filtered total once loaded, else the word's own count
        let n: Int = {
            guard let term else { return b.row.nVerses }
            if detail?.term == term, let t = detail?.total { return t }
            return b.words.first { $0.term == term }?.n ?? b.row.nVerses
        }()
        return NavigationLink(value: Route.themeVerses(concept, filter)) {
            HStack {
                Text(term == nil ? "All \(n.formatted()) verses" : "All \(n.formatted()) verses with this form")
                    .font(.headline)
                Spacer()
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).accessibilityHidden(true)
            }
            .foregroundStyle(palette.onAccent)
            .padding(Theme.Space.l)
            .background(palette.accentFill, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(palette.accent))
        }
        .buttonStyle(.pressableCard)
        .accessibilityIdentifier("themes.page.all")
    }

    private func verseCard(_ lines: [SearchLine], compId: Int) -> some View {
        Button {
            Haptics.tap()
            container.present(.shabad(compId: compId, focusLineId: lines.first?.id))
        } label: {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                ForEach(lines, id: \.id) { l in
                    GurmukhiText(verbatim: l.gurmukhi, size: 20).foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                }
                if let first = lines.first {
                    Text(verseMeta(first)).font(.caption).foregroundStyle(Ink.muted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Space.m)
            .background(Ink.card, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(Ink.hairline))
        }
        .buttonStyle(.pressableCard)
        .accessibilityHint("Opens the shabad")
    }

    private func verseMeta(_ l: SearchLine) -> String {
        var bits = ["Ang \(l.ang)"]
        if let r = l.raag { bits.append(raagName(r)) }
        if let a = l.author { bits.append(a.replacingOccurrences(of: " Ji", with: "")) }
        return bits.joined(separator: " · ")
    }

    private func seeAll(_ title: String) -> some View {
        HStack {
            Text(title).font(.subheadline.weight(.semibold))
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).accessibilityHidden(true)
        }
        .foregroundStyle(palette.accentText)
        .padding(.vertical, Theme.Space.xs)
        .contentShape(Rectangle())
    }

    private func raagName(_ gurmukhi: String) -> String {
        "Raag " + (container.meta?.raags.first { $0.name == gurmukhi }?.roman ?? gurmukhi)
    }

    // MARK: data

    private func loadBase() async {
        guard let corpus = container.corpus else { failed = "No database"; return }
        failed = nil
        do {
            guard let row = try await corpus.themeIndex().first(where: { $0.concept == concept }) else {
                notFound = true
                return
            }
            let words = try await corpus.themeWords(concept)
            let card = try? await corpus.themeCard(concept: concept)
            let focus = try? await corpus.constellationFocus(concept: concept)
            let companions = ThemePageModel.companions(focus?.companions ?? [], limit: 5)
            base = ThemeBase(row: row, words: words, card: card ?? nil, companions: companions)
        } catch is CancellationError {
        } catch { failed = UserMessage.load(error) }
    }

    private func loadDetail() async {
        guard let corpus = container.corpus else { return }
        let asked = term
        if let d = detail, d.term == asked, d.total != nil { return }     // coming back: keep it
        do {
            let f = ThemeFilter(term: asked)
            let heart = try await corpus.themePage(concept, filter: ThemeFilter(term: asked, lens: ConstellationLens(rahaoOnly: true)), limit: 24)
            let steeped = try await corpus.themeSteeped(concept, filter: f)
            let total = try await corpus.themeCount(concept, filter: f)
            let bins = try await corpus.themeAngBins(concept, filter: f)
            try Task.checkCancellation()
            guard asked == term else { return }
            detail = ThemeDetail(term: asked, heart: ThemePageModel.groups(heart.lines), heartTotal: heart.total,
                                 steeped: steeped, total: total, bins: bins)
        } catch is CancellationError {
        } catch {
            guard asked == term else { return }                     // a newer word owns the page
            detail = ThemeDetail(term: asked, heart: [], heartTotal: 0, steeped: [], total: nil, bins: nil)
        }
    }
}

struct ThemeBase: Equatable {
    let row: ThemeIndexRow
    let words: [ThemeWord]
    let card: ThemeCard?
    let companions: [ConstellationCompanion]
}

struct ThemeDetail: Equatable {
    let term: String?
    let heart: [ThemeFeed.Group]
    let heartTotal: Int
    let steeped: [SteepedShabad]
    /// nil when the counts could not be read (the page then falls back to the known counts).
    let total: Int?
    let bins: [Int]?
}

enum ThemePageModel {
    /// Companions that actually share verses, most distinctive (PPMI) first; ties by name.
    static func companions(_ all: [ConstellationCompanion], limit: Int) -> [ConstellationCompanion] {
        Array(all.filter { $0.n > 0 && $0.ppmi > 0 }
            .sorted { $0.ppmi != $1.ppmi ? $0.ppmi > $1.ppmi : $0.co < $1.co }
            .prefix(limit))
    }

    /// Consecutive verses of one shabad, together (the same rule as the verse list).
    static func groups(_ lines: [SearchLine]) -> [ThemeFeed.Group] {
        var feed = ThemeFeed()
        feed.lines = lines
        return feed.groups
    }
}

/// Description text with any Gurmukhi run set in Sant Lipi (the rest in the system face), so
/// the words the description quotes read in the same face as the scripture.
struct MixedScriptText: View {
    let text: String
    @Environment(\.font) private var font

    var body: some View {
        Text(Self.attributed(text))
    }

    static func isGurmukhi(_ s: Unicode.Scalar) -> Bool { (0x0A00...0x0A7F).contains(s.value) }

    static func runs(_ text: String) -> [(String, Bool)] {
        var out: [(String, Bool)] = []
        var cur = "", curG: Bool?
        for ch in text {
            let g: Bool
            if ch.unicodeScalars.contains(where: isGurmukhi) { g = true }
            else if ch == " " || ch == "/" { g = curG ?? false }          // a space or slash inside a Gurmukhi phrase stays in it
            else { g = false }
            if curG == nil || g == curG { cur.append(ch); curG = g }
            else { out.append((cur, curG!)); cur = String(ch); curG = g }
        }
        if let curG, !cur.isEmpty { out.append((cur, curG)) }
        return out
    }

    static func attributed(_ text: String) -> AttributedString {
        var out = AttributedString()
        for (s, g) in runs(text) {
            var a = AttributedString(s)
            if g { a.font = Brand.gurmukhi(17, relativeTo: .callout) }
            out += a
        }
        return out
    }
}
