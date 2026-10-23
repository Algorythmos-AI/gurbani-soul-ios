import SwiftUI
import Charts
import GurbaniSearchKit

/// Insights › Contributors: every voice, in Granth order (where its Bani first appears) by
/// default, or by how much Bani is preserved. Descriptive — never a ranking of merit.
struct ContributorsView: View {
    let authors: [AuthorStat]
    /// author → `authors` row (first/last Ang), for Granth order and each voice's Ang range.
    let rows: [String: AuthorRow]

    enum Order: String, CaseIterable, Identifiable {
        case granth = "Granth order", volume = "Most Bani"
        var id: String { rawValue }
    }
    @State private var order: Order = .granth
    @ScaledMetric(relativeTo: .caption) private var barRow: CGFloat = 22

    private var ordered: [AuthorStat] {
        Self.ordered(authors, by: order, firstAngs: rows.mapValues(\.firstAng))
    }

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
                    VoiceRow(stat: a, row: rows[a.author])
                }
            }
            .inkRow()
        }
        .inkGroupedList()
        .appAnimation(Motion.gentle, value: order)
    }
}

/// One voice: full English name, a Mahala badge for the Gurus, any Gurmukhi suffix in Sant
/// Lipi, inflected counts and where in the Granth its Bani sits. No stylometry: those metrics
/// are computed on the English translation, so they describe the translation, not the voice.
private struct VoiceRow: View {
    let stat: AuthorStat
    let row: AuthorRow?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            AuthorNameLabel(name: AuthorName(stat.author))
            Text(VoiceCopy.summary(lines: stat.nLines, shabads: stat.nShabads, raags: stat.nRaags))
                .font(.caption).foregroundStyle(.secondary)
            if let row {
                Text(row.firstAng == row.lastAng ? "Ang \(String(row.firstAng))"
                                                 : "Angs \(String(row.firstAng))–\(String(row.lastAng))")
                    .font(.caption).foregroundStyle(.secondary)
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
