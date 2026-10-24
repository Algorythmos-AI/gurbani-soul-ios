import SwiftUI
import GurbaniSearchKit

/// The Index's Raags tab, in the Granth's own order: the banis before the raags, the 31 raags
/// as fingerprint cards (where each sits in the saroop, how much of it it fills, its shabads and
/// its traditional hour), then the banis after the raags. Every figure comes from `GranthMap`.
struct IndexRaagsTab: View {
    let map: GranthMap
    /// Raag name → its cited primary pahars (empty when this DB carries no timing layer).
    let pahars: [String: [Int]]
    /// Opens a raag. The caller decides where (the Raag page, or the Reader at its first Ang).
    let openRaag: (RaagRow) -> Void
    let openSection: (SectionRow) -> Void
    /// Opens the Raag Clock (the "In this hour" strip's way in).
    var openClock: () -> Void = {}

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.palette) private var palette
    /// saroop | length | hour — survives leaving the Index.
    @SceneStorage("index_raag_sort") private var sort = "saroop"

    private var columns: [GridItem] {
        let n = dynamicTypeSize.isAccessibilitySize ? 1 : 2
        return Array(repeating: GridItem(.flexible(), spacing: Theme.Space.m, alignment: .top), count: n)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            if !map.opening.isEmpty {
                movement(title: "Before the raags", symbol: "sunrise", span: map.openingSpan,
                         caption: "The banis that open the Granth.") {
                    sectionList(map.opening, id: "index_opening")
                }
            }
            if !map.raags.isEmpty {
                if !pahars.isEmpty { thisHour }
                movement(title: "The \(String(map.raags.count)) raags", symbol: "music.note", span: map.raagSpan,
                         caption: sortCaption, trailing: AnyView(sortMenu)) {
                    LazyVGrid(columns: columns, spacing: Theme.Space.m) {
                        ForEach(sortedRaags) { r in raagCard(r) }
                    }
                }
            }
            if !map.closing.isEmpty {
                movement(title: "After the raags", symbol: "text.book.closed", span: map.closingSpan,
                         caption: "Saloks, savaiye and the closing banis.") {
                    sectionList(map.closing, id: "index_closing")
                }
            }
        }
    }

    // MARK: movements

    private func movement<C: View>(title: String, symbol: String, span: ClosedRange<Int>?, caption: String,
                                   trailing: AnyView? = nil,
                                   @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(alignment: .firstTextBaseline) {
                SectionEyebrow(text: title, symbol: symbol)
                Spacer(minLength: Theme.Space.s)
                if let span {
                    Text(span.angLabel).font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                }
                if let trailing { trailing }
            }
            Text(caption).font(.footnote).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            content()
        }
    }

    // MARK: order

    private var sortedRaags: [RaagRow] {
        switch sort {
        case "length":
            return map.raags.sorted { ($0.lastAng - $0.firstAng, -$0.seq) > ($1.lastAng - $1.firstAng, -$1.seq) }
        case "hour" where !pahars.isEmpty:
            // Pahar 1 (from sunrise) through 8; raags with no cited hour keep saroop order after.
            return map.raags.sorted { (pahars[$0.name]?.first ?? 99, $0.seq) < (pahars[$1.name]?.first ?? 99, $1.seq) }
        default:
            return map.raags
        }
    }

    private var sortCaption: String {
        switch sort {
        case "length": return "Longest first. The bar shows where each raag sits."
        case "hour" where !pahars.isEmpty: return "By the hour tradition gives each raag, from sunrise. Raags with no cited hour follow."
        default: return "In the order of the saroop. The bar shows where each raag sits."
        }
    }

    private var sortMenu: some View {
        Menu {
            Picker("Order", selection: $sort) {
                Label("Saroop order", systemImage: "book.pages").tag("saroop")
                Label("Length", systemImage: "ruler").tag("length")
                if !pahars.isEmpty { Label("Hour of the day", systemImage: "clock").tag("hour") }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down.circle")
                .font(.body)
                .frame(minWidth: 44, minHeight: 28)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Order the raags")
        .accessibilityIdentifier("index_raagSort")
    }

    // MARK: in this hour

    /// The raags tradition gives the CURRENT pahar — reckoned exactly as the Raag Clock and its
    /// widget reckon it (`RaagNowTimeline`, solar when the reader chose it), so they never disagree.
    private var thisHour: some View {
        TimelineView(.everyMinute) { ctx in
            let p = RaagNowTimeline.entry(at: ctx.date, config: RaagClockConfig.current(snapshot: nil), snapshot: nil).pahar
            let now = map.raags.filter { pahars[$0.name]?.contains(p) ?? false }
            if !now.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    HStack(alignment: .firstTextBaseline) {
                        SectionEyebrow(text: "In this hour", symbol: p <= 4 ? "sun.max" : "moon.stars")
                        Spacer(minLength: Theme.Space.s)
                        Button("Raag Clock", action: openClock)
                            .font(.caption.weight(.medium))
                            .accessibilityIdentifier("index_openClock")
                    }
                    Text("The \(Pahar.label(p)) — the raags tradition gives this watch. Tradition, not scripture.")
                        .font(.footnote).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Theme.Space.s) {
                            ForEach(now) { r in
                                Button { openRaag(r) } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        GurmukhiText(verbatim: r.name, size: 18)
                                        if let en = GranthNames.raag(r.name, roman: r.roman) {
                                            Text(en).font(.caption2.weight(.medium)).foregroundStyle(palette.accentText)
                                        }
                                    }
                                    .padding(.horizontal, Theme.Space.m).padding(.vertical, Theme.Space.s)
                                    .background(Ink.card, in: RoundedRectangle(cornerRadius: Theme.Radius.chip))
                                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.chip).strokeBorder(palette.accent.opacity(0.6)))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Raag \(GranthNames.raag(r.name, roman: r.roman) ?? r.name)")
                                .accessibilityIdentifier("index_hour_\(GranthNames.slug(forRaag: r.name, roman: r.roman))")
                            }
                        }
                    }
                }
                .accessibilityElement(children: .contain)
            }
        }
    }

    // MARK: raag card

    private func raagCard(_ r: RaagRow) -> some View {
        let english = GranthNames.raag(r.name, roman: r.roman)
        let hours = pahars[r.name] ?? []
        return Button { openRaag(r) } label: {
            Card {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    HStack(alignment: .top) {
                        GurmukhiText(verbatim: r.name, size: 20)
                        Spacer(minLength: Theme.Space.xs)
                        if let p = hours.first {
                            Image(systemName: p <= 4 ? "sun.max" : "moon.stars")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if let english {
                        Text(english).font(.footnote.weight(.medium)).italic()
                            .foregroundStyle(palette.accentText)
                    }
                    AngSliceBar(first: r.firstAng, last: r.lastAng)
                        .padding(.vertical, 2)
                    // Two fixed lines, so every card in a row is the same height.
                    VStack(alignment: .leading, spacing: 1) {
                        Text((r.firstAng...r.lastAng).angLabel)
                        Text("\(String(r.nShabads)) shabads")
                    }
                    .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.85)
                }
            }
        }
        .buttonStyle(.pressableCard)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(raagLabel(r, english: english, hours: hours))
        .accessibilityHint("Opens the raag")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("raag_\(GranthNames.slug(forRaag: r.name, roman: r.roman))")
    }

    private func raagLabel(_ r: RaagRow, english: String?, hours: [Int]) -> String {
        var parts = ["Raag \(english ?? r.name)", "raag \(String(r.seq)) of \(String(map.raags.count))",
                     (r.firstAng...r.lastAng).angLabel, "\(String(r.nShabads)) shabads"]
        if let p = hours.first { parts.append("traditionally sung in the \(Pahar.label(p))") }
        return parts.joined(separator: ", ")
    }

    // MARK: sections

    private func sectionList(_ rows: [SectionRow], id: String) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { i, s in
                Button { openSection(s) } label: { sectionRow(s) }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(GranthNames.section(s.name, firstAng: s.firstAng, lastAng: s.lastAng) ?? s.name), \((s.firstAng...s.lastAng).angLabel)")
                    .accessibilityAddTraits(.isButton)
                if i < rows.count - 1 { Divider().padding(.leading, Theme.Space.l) }
            }
        }
        .background(Ink.card, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(Ink.hairline))
        .accessibilityIdentifier(id)
    }

    private func sectionRow(_ s: SectionRow) -> some View {
        HStack(spacing: Theme.Space.m) {
            VStack(alignment: .leading, spacing: 2) {
                GurmukhiText(verbatim: s.name, size: 18)
                if let en = GranthNames.section(s.name, firstAng: s.firstAng, lastAng: s.lastAng) {
                    Text(en).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: Theme.Space.s)
            Text((s.firstAng...s.lastAng).angLabel)
                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.vertical, Theme.Space.m)
        .contentShape(Rectangle())
    }
}
