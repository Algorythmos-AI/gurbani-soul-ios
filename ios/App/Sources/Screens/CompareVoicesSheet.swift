import SwiftUI
import GurbaniSearchKit

/// ⇄ Compare two voices (Lineage v2 §2c): where each sings across the 1,430 Angs (two barcodes),
/// theme emphasis as diverging bars (one voice to each side of a shared label), the raags they
/// share, and whether their lifetimes overlap. Counts are the canonical ones (`lines`, headers
/// excluded). Descriptive only — never a ranking of voices or of scripture.
struct CompareVoicesSheet: View {
    let a: Contributor
    let b: Contributor
    let summaryA: VoiceSummary?
    let summaryB: VoiceSummary?

    @Environment(AppContainer.self) private var container
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var pa: AuthorProfile?
    @State private var pb: AuthorProfile?
    @State private var raagsA: [RaagShare] = []
    @State private var raagsB: [RaagShare] = []
    @State private var loaded = false

    /// Fill colours only; every label stays in ink.
    private let colorA = Theme.accent
    private let colorB = Ink.info

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.xl) {
                    legend
                    angsSection
                    if loaded {
                        themesSection
                        raagsSection
                    } else {
                        ProgressView().frame(maxWidth: .infinity)
                    }
                    lifetimesSection
                    countsGrid
                    Text("Descriptive only — never a ranking of voices or of scripture.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding()
            }
            .navigationTitle("Compare")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .task {
            guard !loaded, let corpus = container.corpus else { return }
            if container.meta == nil { await container.loadMeta() }
            pa = await corpus.authorProfile(a.name, full: true)
            pb = await corpus.authorProfile(b.name, full: true)
            raagsA = await corpus.authorRaags(a.name)
            raagsB = await corpus.authorRaags(b.name)
            loaded = true
        }
    }

    // MARK: legend

    private var legend: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            legendRow(a, colorA)
            legendRow(b, colorB)
        }
    }

    private func legendRow(_ c: Contributor, _ color: Color) -> some View {
        HStack(spacing: Theme.Space.s) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 14, height: 14)
                .accessibilityHidden(true)
            Text(c.displayName).font(.headline)
            if let g = c.gurmukhi { GurmukhiText(verbatim: g, size: 17) }
        }
    }

    // MARK: Angs

    @ViewBuilder private var angsSection: some View {
        if let sa = summaryA, let sb = summaryB {
            let shared = sa.angs.angs.filter(sb.angs.contains).count
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                SectionEyebrow(text: "Across the Granth")
                AngBarcode(angs: sa.angs, color: colorA, height: 14, marksRaagEnd: true)
                AngBarcode(angs: sb.angs, color: colorB, height: 14, marksRaagEnd: true)
                Text(shared == 0 ? "They share no Ang."
                     : "Both appear on \(shared.formatted()) \(shared == 1 ? "Ang" : "Angs").")
                    .font(.callout)
                Text("\(a.displayName): Angs \(sa.firstAng)–\(sa.lastAng). \(b.displayName): Angs \(sb.firstAng)–\(sb.lastAng).")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: themes — diverging bars

    /// Up to 10 themes, by the two voices' combined lift.
    private var axes: [String] {
        var combined: [String: Double] = [:]
        for ax in pa?.fingerprint ?? [] { combined[ax.concept, default: 0] += ax.lift }
        for ax in pb?.fingerprint ?? [] { combined[ax.concept, default: 0] += ax.lift }
        return combined.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.prefix(10).map(\.key)
    }

    private func lift(_ p: AuthorProfile?, _ concept: String) -> Double {
        p?.fingerprint.first { $0.concept == concept }?.lift ?? 0
    }

    private var descriptions: [String: String] {
        Dictionary((container.meta?.concepts ?? []).map { ($0.concept, $0.description) }, uniquingKeysWith: { x, _ in x })
    }

    @ViewBuilder private var themesSection: some View {
        let axes = self.axes
        if !axes.isEmpty {
            let maxLift = max(axes.map { max(lift(pa, $0), lift(pb, $0)) }.max() ?? 1, 0.001)
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                SectionEyebrow(text: "Theme emphasis")
                Text("How much more (or less) each voice dwells on a theme than the Granth as a whole (lift; 1× = the Granth's own rate).")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(axes, id: \.self) { concept in
                    let label = ConceptName.label(concept, description: descriptions[concept])
                    let la = lift(pa, concept), lb = lift(pb, concept)
                    Group {
                        if typeSize.isAccessibilitySize {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(label).font(.subheadline.weight(.semibold))
                                barRow(a.displayName, la, maxLift, colorA)
                                barRow(b.displayName, lb, maxLift, colorB)
                            }
                        } else {
                            HStack(spacing: Theme.Space.s) {
                                bar(la, maxLift, colorA, leading: false)
                                Text(label).font(.caption).multilineTextAlignment(.center)
                                    .frame(width: 118)
                                bar(lb, maxLift, colorB, leading: true)
                            }
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(label): \(a.displayName) \(String(format: "%.1f", la)) times, \(b.displayName) \(String(format: "%.1f", lb)) times")
                }
            }
        }
    }

    /// One side of the diverging chart: grows away from the centre label.
    private func bar(_ value: Double, _ maxLift: Double, _ color: Color, leading: Bool) -> some View {
        GeometryReader { geo in
            let w = max(2, geo.size.width * CGFloat(value / maxLift))
            HStack(spacing: 4) {
                if !leading { Spacer(minLength: 0) }
                if !leading { Text(String(format: "%.1f×", value)).font(.caption2).monospacedDigit().foregroundStyle(.secondary) }
                Capsule().fill(color).frame(width: min(w, max(2, geo.size.width - 34)), height: 10)
                if leading { Text(String(format: "%.1f×", value)).font(.caption2).monospacedDigit().foregroundStyle(.secondary) }
                if leading { Spacer(minLength: 0) }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: 22)
    }

    private func barRow(_ name: String, _ value: Double, _ maxLift: Double, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(name) · \(String(format: "%.1f×", value))").font(.caption)
            GeometryReader { geo in
                Capsule().fill(color).frame(width: max(2, geo.size.width * CGFloat(value / maxLift)), height: 10)
            }
            .frame(height: 10)
        }
    }

    // MARK: raags

    @ViewBuilder private var raagsSection: some View {
        let shared = raagsA.filter { r in raagsB.contains { $0.raag == r.raag } }
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            SectionEyebrow(text: "Raags in common")
            if shared.isEmpty {
                Text(raagsA.isEmpty || raagsB.isEmpty
                     ? "At least one of them sings only outside the raag sections."
                     : "They share no raag.")
                    .font(.callout)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96))], alignment: .leading, spacing: Theme.Space.s) {
                    ForEach(shared) { r in
                        GurmukhiText(verbatim: r.raag, size: 19)
                            .padding(.horizontal, Theme.Space.s).padding(.vertical, 4)
                            .background(Capsule().fill(Ink.raised))
                            .overlay(Capsule().strokeBorder(Ink.hairline))
                    }
                }
                Text("\(shared.count) of \(a.displayName)'s \(raagsA.count) and \(b.displayName)'s \(raagsB.count) raags.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: lifetimes

    static func overlap(_ a: Contributor, _ b: Contributor) -> ClosedRange<Int>? {
        guard let ab = a.born, let ad = a.died, let bb = b.born, let bd = b.died else { return nil }
        let lo = max(ab, bb), hi = min(ad, bd)
        return lo <= hi ? lo...hi : nil
    }

    @ViewBuilder private var lifetimesSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            SectionEyebrow(text: "Lifetimes")
            if a.born == nil || a.died == nil || b.born == nil || b.died == nil {
                Text("Dates for at least one of them are not known closely enough to compare.").font(.callout)
            } else if let o = Self.overlap(a, b) {
                Text("By approximate dates their lifetimes overlap, c. \(String(o.lowerBound))–\(String(o.upperBound)) (about \(o.upperBound - o.lowerBound) years) — an overlap, not a record of meeting.")
                    .font(.callout)
            } else {
                Text("By approximate dates their lifetimes do not overlap.").font(.callout)
            }
            Text([a.lifespan.map { "\(a.displayName): \($0)" }, b.lifespan.map { "\(b.displayName): \($0)" }]
                    .compactMap { $0 }.joined(separator: " · "))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: counts

    private var countsGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: Theme.Space.m, verticalSpacing: Theme.Space.xs) {
            GridRow {
                Text("").font(.caption)
                Text(a.displayName).font(.caption.weight(.semibold))
                Text(b.displayName).font(.caption.weight(.semibold))
            }
            countRow("Verses", summaryA?.nVerses, summaryB?.nVerses)
            countRow("Compositions", summaryA?.nCompositions, summaryB?.nCompositions)
            GridRow {
                Text("Raags").font(.caption)
                raagCell(summaryA)
                raagCell(summaryB)
            }
        }
    }

    private func countRow(_ label: String, _ va: Int?, _ vb: Int?) -> some View {
        GridRow {
            Text(label).font(.caption)
            Text(va.map { $0.formatted() } ?? "—").font(.caption).monospacedDigit()
            Text(vb.map { $0.formatted() } ?? "—").font(.caption).monospacedDigit()
        }
    }

    @ViewBuilder private func raagCell(_ s: VoiceSummary?) -> some View {
        if let s, s.nRaags == 0 {
            Text(VoiceCopy.outsideRaags).font(.caption)
        } else {
            Text(s.map { $0.nRaags.formatted() } ?? "—").font(.caption).monospacedDigit()
        }
    }
}
