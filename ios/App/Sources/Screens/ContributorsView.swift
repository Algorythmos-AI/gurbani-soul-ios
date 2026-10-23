import SwiftUI
import Charts
import GurbaniSearchKit

/// Insights › Contributors: every voice, in Granth order (where its Bani first appears) by
/// default, or by how much Bani is preserved. Descriptive — never a ranking of merit.
struct ContributorsView: View {
    let authors: [AuthorStat]
    /// author → first Ang (`authors.first_ang`), for Granth order.
    let firstAngs: [String: Int]

    enum Order: String, CaseIterable, Identifiable {
        case granth = "Granth order", volume = "Most Bani"
        var id: String { rawValue }
    }
    @State private var order: Order = .granth
    @State private var showVocabularyInfo = false
    @ScaledMetric(relativeTo: .caption) private var barRow: CGFloat = 22

    private var ordered: [AuthorStat] { Self.ordered(authors, by: order, firstAngs: firstAngs) }

    /// Granth order = first Ang, then volume, then name (stable for voices sharing an Ang).
    /// A voice with no known first Ang sorts last rather than disappearing.
    static func ordered(_ authors: [AuthorStat], by order: Order, firstAngs: [String: Int]) -> [AuthorStat] {
        authors.sorted { a, b in
            let byVolume = a.nLines != b.nLines ? a.nLines > b.nLines : a.author < b.author
            guard order == .granth else { return byVolume }
            let fa = firstAngs[a.author] ?? .max, fb = firstAngs[b.author] ?? .max
            return fa != fb ? fa < fb : byVolume
        }
    }

    var body: some View {
        List {
            Section {
                Picker("Order", selection: $order) {
                    ForEach(Order.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("contributorsOrder")
                Chart(ordered) { a in
                    BarMark(x: .value("Lines", a.nLines),
                            y: .value("Voice", AuthorName(a.author).compact))
                        .foregroundStyle(AccentPalette.soul.accentFill)   // brand gold, as fill only
                }
                .chartXAxisLabel("Lines")
                .chartYScale(domain: ordered.map { AuthorName($0.author).compact })
                .frame(height: CGFloat(max(ordered.count, 1)) * barRow)
                .accessibilityChartDescriptor(ContributorsChartDescriptor(authors: ordered, order: order))
            } footer: {
                Text(order == .granth
                     ? "Lines preserved in the Granth, per voice, in the order their Bani first appears. Descriptive — never a ranking of merit."
                     : "Lines preserved in the Granth, per voice, most first. Volume reflects what is preserved here — never importance.")
            }
            .inkRow()
            Section("Voices") {
                ForEach(ordered) { a in
                    VoiceRow(stat: a, firstAng: firstAngs[a.author]) { showVocabularyInfo = true }
                }
            }
            .inkRow()
        }
        .inkGroupedList()
        .appAnimation(Motion.gentle, value: order)
        .sheet(isPresented: $showVocabularyInfo) { VocabularyRangeInfo() }
    }
}

/// One voice: full English name, a Mahala badge for the Gurus, any Gurmukhi suffix in Sant
/// Lipi, inflected counts, and Vocabulary range only where the sample is large enough.
private struct VoiceRow: View {
    let stat: AuthorStat
    let firstAng: Int?
    let onInfo: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            AuthorNameLabel(name: AuthorName(stat.author))
            Text(VoiceCopy.summary(lines: stat.nLines, shabads: stat.nShabads, raags: stat.nRaags))
                .font(.caption).foregroundStyle(.secondary)
            if let firstAng {
                Text("First appears at Ang \(String(firstAng))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if stat.isReliable {
                HStack(spacing: Theme.Space.xs) {
                    Text("\(VoiceCopy.vocabularyRange) \(stat.mattr100, format: .number.precision(.fractionLength(2)))")
                        .font(.caption).foregroundStyle(.secondary)
                    Button(action: onInfo) {
                        Image(systemName: "info.circle").font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("About vocabulary range")
                }
            } else {
                Text(VoiceCopy.tooFewLines).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

/// "Guru Arjan Dev Ji [M5]" / "Bhatt Kalsahar ਭਟ": the English name, the Mahala badge, and
/// the Gurmukhi suffix through `GurmukhiText` — never inline in the English string.
struct AuthorNameLabel: View {
    let name: AuthorName
    var font: Font = .subheadline.weight(.medium)
    var gurmukhiSize: CGFloat = 17

    var body: some View {
        // Stacks instead of truncating at large Dynamic Type sizes.
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) { parts }
            VStack(alignment: .leading, spacing: 2) { parts }
        }
    }

    @ViewBuilder private var parts: some View {
        Text(name.english).font(font)
            .accessibilityLabel(name.spoken)
        if let badge = name.badge {
            Text(badge)
                .font(.caption2.weight(.bold)).monospacedDigit()
                .padding(.horizontal, 6).padding(.vertical, 1)
                .background(Capsule().fill(AccentPalette.soul.accentFill.opacity(0.22)))
                .overlay(Capsule().strokeBorder(AccentPalette.soul.accent.opacity(0.5)))
                .foregroundStyle(.primary)
                .accessibilityHidden(true)   // `spoken` already says "Mahala 5"
        }
        if let g = name.gurmukhi {
            GurmukhiText(verbatim: g, size: gurmukhiSize).foregroundStyle(.secondary)
        }
    }
}

/// The ⓘ sheet behind "Vocabulary range": one plain explanation of MATTR-100.
struct VocabularyRangeInfo: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    Text(VoiceCopy.vocabularyExplainer).font(.body)
                    Text("Shown only where a voice has enough lines for the measure to be fair; otherwise it reads “\(VoiceCopy.tooFewLines)”.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .background(Ink.base.ignoresSafeArea())
            .navigationTitle(VoiceCopy.vocabularyRange)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Audio Graphs / VoiceOver summary of the Contributors bar chart.
private struct ContributorsChartDescriptor: AXChartDescriptorRepresentable {
    let authors: [AuthorStat]
    let order: ContributorsView.Order

    func makeChartDescriptor() -> AXChartDescriptor {
        let names = authors.map { AuthorName($0.author).spoken }
        let maxLines = Double(max(authors.map(\.nLines).max() ?? 1, 1))
        let x = AXCategoricalDataAxisDescriptor(title: "Voice", categoryOrder: names)
        let y = AXNumericDataAxisDescriptor(title: "Lines", range: 0...maxLines, gridlinePositions: []) {
            "\(Int($0)) lines"
        }
        let series = AXDataSeriesDescriptor(
            name: "Lines preserved", isContinuous: false,
            dataPoints: authors.map { AXDataPoint(x: AuthorName($0.author).spoken, y: Double($0.nLines)) })
        return AXChartDescriptor(
            title: "Lines preserved per voice",
            summary: order == .granth
                ? "Each voice in the order its Bani first appears in the Granth. Descriptive, never a ranking."
                : "Each voice by how much of its Bani is preserved. Descriptive, never a ranking.",
            xAxis: x, yAxis: y, additionalAxes: [], series: [series])
    }
}
