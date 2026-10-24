import SwiftUI
import Charts
import GurbaniSearchKit

/// Insights › Contributors: every voice, in Granth order (where its Bani first appears) by
/// default, or by how much Bani is preserved. Descriptive — never a ranking of merit.
struct ContributorsView: View {
    @Environment(AppContainer.self) private var container
    let authors: [AuthorStat]
    /// author → `authors` row (first/last Ang), for Granth order and each voice's Ang range.
    let rows: [String: AuthorRow]
    /// Voices of the Granth (ribbon); nil only if the read failed.
    var atlas: VoicesAtlas? = nil

    @State private var grouping: DotFieldLayout.Grouping = .voice
    @State private var selected: String?
    private let roster = Self.rosterIndex
    /// Voices with a cited place in the bundled roster (roster v2), read once.
    private static let mapVoices = MapVoice.loadBundled()
    /// The bundled roster by name, read once (it never changes at runtime).
    private static let rosterIndex: [String: Contributor] =
        Dictionary((ContributorsStore.load() ?? []).map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })

    enum Order: String, CaseIterable, Identifiable {
        case granth = "Granth order", volume = "Most Bani"
        var id: String { rawValue }
    }
    @State private var order: Order = .granth

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

    /// The dot field is always laid out in Granth order, whatever order the list below uses,
    /// so a dot keeps its place while the reader re-sorts the list.
    private var granthOrdered: [AuthorStat] {
        Self.ordered(authors, by: .granth, firstAngs: rows.mapValues(\.firstAng))
    }

    private var legend: some View {
        HStack(spacing: Theme.Space.m) {
            ForEach(VoiceKind.allCases, id: \.self) { k in
                HStack(spacing: 4) {
                    Circle().fill(k.color).frame(width: 8, height: 8)
                    Text(k.legend).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    Text("\(String(authors.count)) voices · one Granth")
                        .font(Brand.heading(.title3)).accessibilityAddTraits(.isHeader)
                    Picker("Group", selection: $grouping) {
                        ForEach(DotFieldLayout.Grouping.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("voicesGrouping")
                    VoicesDotField(voices: granthOrdered.map { ($0.author, $0.nLines) }, roster: roster,
                                   grouping: grouping, selected: $selected)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Every verse line of the Granth as dots, one dot for about \(DotFieldLayout.linesPerDot) lines, coloured by tradition")
                        .accessibilityChartDescriptor(ContributorsChartDescriptor(authors: ordered, order: order))
                        .accessibilityIdentifier("voicesDotField")
                    legend
                    if let selected, let stat = authors.first(where: { $0.author == selected }) {
                        HStack {
                            AuthorNameLabel(name: AuthorName(selected))
                            Spacer()
                            Text(VoiceCopy.lines(stat.nLines)).font(.caption).foregroundStyle(.secondary)
                        }
                        .transition(.opacity)
                    }
                }
                .padding(.vertical, Theme.Space.xs)
            } footer: {
                Text("One dot ≈ \(DotFieldLayout.linesPerDot) verse lines; every voice keeps at least one. Size shows how much Bani is preserved here — never importance.")
            }
            .inkRow()
            if VoicesFeatures.mapEnabled, !Self.mapVoices.isEmpty {
                Section {
                    VoicesMap(voices: Self.mapVoices, selected: $selected)
                } header: {
                    Text("From Multan to Banaras")
                }
                .inkRow()
            }
            if let atlas {
                Section {
                    GranthRibbon(model: RibbonModel(atlas: atlas, roster: roster), selected: selected) { ang in
                        container.router.openAng(ang)
                    }
                } header: {
                    Text("Where each voice sings")
                } footer: {
                    Text("Verse lines in every ten Angs, stacked by tradition. Tap a dot above or a voice below to follow one voice through the Granth.")
                }
                .inkRow()
            }
            Section {
                ForEach(ordered) { a in
                    Button {
                        MotionGate.run(Motion.gentle) { selected = (selected == a.author) ? nil : a.author }
                    } label: {
                        VoiceRow(stat: a, row: rows[a.author], isSelected: selected == a.author)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(atlas == nil ? "" : "Shows where this voice sings in the Granth ribbon")
                }
            } header: {
                HStack {
                    Text("Voices")
                    Spacer()
                    Picker("Order", selection: $order) {
                        ForEach(Order.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("contributorsOrder")
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
    var isSelected = false

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
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .overlay(alignment: .leading) {
            if isSelected {
                Capsule().fill(Brand.primary).frame(width: 3).offset(x: -Theme.Space.s)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
