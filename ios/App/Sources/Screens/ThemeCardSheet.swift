import SwiftUI
import GurbaniSearchKit

/// The theme card (web parity: the Constellation centre): the theme's description, the verified
/// Gurmukhi words that tag it, its counts, and where it concentrates — the raags and voices whose
/// rate of this theme is above the Granth's, shown only where the sample is reliable, each with
/// the base rate beside it. Descriptive, never a ranking.
struct ThemeCardSheet: View {
    let concept: String
    @Environment(AppContainer.self) private var container
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    @State private var state: LoadState<ThemeCard> = .loading

    var body: some View {
        NavigationStack {
            LoadStateView(state: state, emptyTitle: "Unknown theme", onRetry: { Task { await load() } }) { card in
                List {
                    Section {
                        VStack(alignment: .leading, spacing: Theme.Space.s) {
                            if let g = ThemeGroup.of(concept) {
                                HStack(spacing: 6) {
                                    Circle().fill(g.color).frame(width: 10, height: 10).accessibilityHidden(true)
                                    Text(g.title).font(.caption.weight(.semibold)).foregroundStyle(Ink.muted)
                                }
                            }
                            Text("\(card.nVerses.formatted()) verses in \(card.nShabads.formatted()) shabads · \(card.nRahao.formatted()) refrains")
                                .font(.subheadline.weight(.semibold))
                            if !card.description.isEmpty {
                                Text(card.description).font(.callout)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                    Section("The Gurmukhi words that tag it") {
                        FlowTerms(terms: card.terms)
                    }
                    if !card.raags.isEmpty {
                        Section("Concentrates in") {
                            ForEach(card.raags) { row($0, name: raagName($0.entityId)) }
                        }
                    }
                    if !card.authors.isEmpty {
                        Section("Voiced most by") {
                            ForEach(card.authors) { row($0, name: $0.entityId.replacingOccurrences(of: " Ji", with: "")) }
                        }
                    }
                    Section {
                        NavigationLink("See all \(card.nVerses.formatted()) verses") {
                            ThemeResultsScreen(concept: concept)
                        }
                    } footer: {
                        Text("A verse carries this theme when it contains one of these words. Rates appear only where the sample is large enough to be reliable.")
                    }
                }
            }
            .navigationTitle(ConceptName.display(concept))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
        .task { await load() }
    }

    private func raagName(_ gurmukhi: String) -> String {
        "Raag " + (container.meta?.raags.first { $0.name == gurmukhi }?.roman ?? gurmukhi)
    }

    private func row(_ x: ThemeConcentration, name: String) -> some View {
        let pct = { (v: Double) in (v * 100).formatted(.number.precision(.fractionLength(1))) + "%" }
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(name).font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(x.lift.formatted(.number.precision(.fractionLength(2))))×")
                    .font(.subheadline.monospacedDigit()).foregroundStyle(palette.accentText)
            }
            Text("\(pct(x.entityRate)) of its tagged verses, against \(pct(x.corpusRate)) across the Granth · \(x.nTagged.formatted()) verses")
                .font(.caption).foregroundStyle(Ink.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private func load() async {
        guard let corpus = container.corpus else { state = .failed("No database"); return }
        state = .loading
        do {
            if let c = try await corpus.themeCard(concept: concept) { state = .loaded(c) } else { state = .empty }
        } catch is CancellationError {
        } catch { state = .failed(UserMessage.load(error)) }
    }
}

/// The theme's Gurmukhi words, verbatim, in ink, wrapping as chips.
private struct FlowTerms: View {
    let terms: [String]
    var body: some View {
        let rows = [GridItem(.adaptive(minimum: 72), spacing: Theme.Space.s, alignment: .leading)]
        LazyVGrid(columns: rows, alignment: .leading, spacing: Theme.Space.s) {
            ForEach(terms, id: \.self) { t in
                GurmukhiText(verbatim: t, size: 19)
                    .padding(.horizontal, Theme.Space.s).padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: Theme.Radius.chip).fill(Ink.raised))
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Where the theme falls in reading order: 15 bins of 100 Angs. Tapping a bin narrows the lens to
/// those Angs; tapping it again clears it.
struct AngStrip: View {
    let concept: String
    let bins: [Int]
    let selected: Int?
    var onSelect: (Int?) -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        let maxN = max(bins.max() ?? 1, 1)
        VStack(alignment: .leading, spacing: 4) {
            Text("Where \(ConceptName.display(concept)) falls in reading order")
                .font(.caption.weight(.semibold))
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(Array(bins.enumerated()), id: \.offset) { i, n in
                    let range = ConstellationFocus.angRange(bin: i)
                    Button {
                        Haptics.tap()
                        onSelect(selected == i ? nil : i)
                    } label: {
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(palette.accent.opacity(selected == nil || selected == i ? 0.9 : 0.35))
                                .frame(height: 6 + 46 * CGFloat(n) / CGFloat(maxN))
                        }
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Angs \(range.lowerBound) to \(range.upperBound): \(n) verses")
                    .accessibilityAddTraits(selected == i ? .isSelected : [])
                }
            }
            HStack {
                Text("Ang 1"); Spacer(); Text("1430")
            }
            .font(.caption2).foregroundStyle(Ink.muted)
            .accessibilityHidden(true)
        }
    }
}
