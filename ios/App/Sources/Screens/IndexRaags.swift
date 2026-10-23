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

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.palette) private var palette

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
                movement(title: "The \(String(map.raags.count)) raags", symbol: "music.note", span: map.raagSpan,
                         caption: "In the order of the saroop. The bar shows where each raag sits.") {
                    LazyVGrid(columns: columns, spacing: Theme.Space.m) {
                        ForEach(map.raags) { r in raagCard(r) }
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
                                   @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(alignment: .firstTextBaseline) {
                SectionEyebrow(text: title, symbol: symbol)
                Spacer(minLength: Theme.Space.s)
                if let span {
                    Text(span.angLabel).font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            Text(caption).font(.footnote).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            content()
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
                    Text("\((r.firstAng...r.lastAng).angLabel) · \(String(r.nShabads)) shabads")
                        .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                        .fixedSize(horizontal: false, vertical: true)
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
