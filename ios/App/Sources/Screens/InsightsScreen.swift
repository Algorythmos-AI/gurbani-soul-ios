import SwiftUI
import Charts
import GurbaniSearchKit

@MainActor @Observable
final class InsightsModel {
    var authors: [AuthorStat] = []
    var raags: [RaagStat] = []
    var loaded = false
    private let corpus: CorpusActor?
    init(corpus: CorpusActor?) { self.corpus = corpus }
    func load() async {
        guard !loaded else { return }
        guard let corpus else { loaded = true; return }   // no DB → show empty, never an endless spinner
        authors = (try? await corpus.authorAnalytics()) ?? []
        raags = (try? await corpus.raagAnalytics()) ?? []
        loaded = true
    }
}

struct InsightsScreen: View {
    @Environment(AppContainer.self) private var container
    @State private var model: InsightsModel?
    @State private var tab = 0
    @State private var authorRows: [String: AuthorRow] = [:]

    private static let views: [(id: Int, label: String)] = [
        (0, "Contributors"), (1, "Raags"), (2, "Network"), (3, "Resonance"), (4, "Flow"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            // 5 views don't fit a segmented control — same pill pattern as Search modes
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Space.s) {
                    ForEach(Self.views, id: \.id) { v in
                        ModePill(title: v.label, isSelected: tab == v.id,
                                 accessibilityID: "insights_\(v.label)") { tab = v.id }
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical, Theme.Space.s)

            if let model, model.loaded {
                switch tab {
                case 0: ContributorsView(authors: model.authors, rows: authorRows)
                case 1: RaagsView(raags: model.raags)
                case 2: ThemeNetworkSection()
                case 3: ResonanceSection()
                default: ProgressionSection()
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Ink.base.ignoresSafeArea())
        .navigationTitle("Insights")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if model == nil { model = InsightsModel(corpus: container.corpus) }
            await model?.load()
            // first/last Ang per voice (authors) — Granth order and each voice's Ang range
            if container.meta == nil { await container.loadMeta() }
            authorRows = Dictionary((container.meta?.authors ?? []).map { ($0.name, $0) },
                                    uniquingKeysWith: { a, _ in a })
        }
    }
}

private struct RaagsView: View {
    let raags: [RaagStat]
    var body: some View {
        List {
            Section {
                Chart(raags.prefix(14)) { r in
                    BarMark(x: .value("Lines", r.nLines), y: .value("Raag", r.raag))
                        .foregroundStyle(Brand.gold.gradient)
                }
                .chartXAxisLabel("Lines")
                .frame(height: 340)
                .accessibilityLabel("Lines per raag")
            } footer: {
                Text("How much of the Granth sits in each raag (musical measure).")
            }
            .inkRow()
            Section("Detail") {
                ForEach(raags) { r in
                    VStack(alignment: .leading, spacing: 2) {
                        GurmukhiText(verbatim: r.raag, size: 18)
                        Text("\(r.nLines) lines · \(r.nShabads) shabads · \(r.nAuthors) authors")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .inkRow()
        }
        .inkGroupedList()
    }
}
