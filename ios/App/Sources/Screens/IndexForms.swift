import SwiftUI
import GurbaniSearchKit

/// The poetic forms the Granth's printed headings name (Barah Maha, Pahare, Thitti, Sadd, …), in
/// the order the saroop first meets each. Built only from `shabd_poetic_genre`; every row shows
/// the verbatim heading it was read from. What a form MEANS is not stated here: that is
/// interpretation, and it waits for scholarly review.
enum PoeticFormGroups {

    /// One place a form appears. Consecutive continuation headings of one run (the twenty
    /// "ਡਖਣੇ ਮਃ ੫" labels inside Maru Vaar Mahalla 5) collapse into the run that opens them.
    struct Entry: Equatable, Identifiable {
        let first: PoeticFormEntry
        let lastAng: Int
        let headings: Int
        var id: Int { first.compId }
    }

    struct Group: Equatable, Identifiable {
        let genre: String
        let entries: [Entry]
        var id: String { genre }
    }

    /// A heading that names its author (ਮਹਲਾ / ਮਹਲੇ / a Bhagat or Bhatt name) opens a new entry;
    /// a bare continuation label ("ਡਖਣੇ ਮਃ ੫ ॥") within an Ang of the previous one in the same
    /// raag continues it.
    static func isContinuation(_ e: PoeticFormEntry, after prev: PoeticFormEntry) -> Bool {
        guard e.genre == prev.genre, e.raag == prev.raag, e.firstAng - prev.firstAng <= 1 else { return false }
        let label = e.sourceLabel ?? ""
        return !(label.contains("ਮਹਲਾ") || label.contains("ਮਹਲੇ") || label.contains("ਕਬੀਰ")
                 || label.contains("ਭਗਤ") || label.contains("ਭਟ"))
    }

    static func groups(_ all: [PoeticFormEntry]) -> [Group] {
        var order: [String] = []
        var byGenre: [String: [Entry]] = [:]
        for e in all.sorted(by: { ($0.firstAng, $0.compId) < ($1.firstAng, $1.compId) }) {
            if byGenre[e.genre] == nil { order.append(e.genre) }
            var list = byGenre[e.genre, default: []]
            // Compare with where the open run has reached, so a long run of labels chains on.
            if let run = list.last, isContinuation(e, after: PoeticFormEntry(
                genre: run.first.genre, compId: run.first.compId, firstAng: run.lastAng,
                raag: run.first.raag, raagRoman: run.first.raagRoman, sourceLabel: nil)) {
                list[list.count - 1] = Entry(first: run.first, lastAng: max(run.lastAng, e.firstAng),
                                             headings: run.headings + 1)
            } else {
                list.append(Entry(first: e, lastAng: e.firstAng, headings: 1))
            }
            byGenre[e.genre] = list
        }
        return order.map { Group(genre: $0, entries: byGenre[$0] ?? []) }
    }
}

/// The Forms tab.
struct IndexFormsTab: View {
    let forms: [PoeticFormEntry]
    /// False while the read is in flight: show progress, never a false "none".
    var loaded = true
    let openComposition: (Int) -> Void

    @Environment(\.palette) private var palette

    var body: some View {
        let groups = PoeticFormGroups.groups(forms)
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                SectionEyebrow(text: "Forms the headings name", symbol: "text.word.spacing")
                if !groups.isEmpty {
                    Text("\(String(groups.count)) forms, in the order the Granth first meets them. Each row is the printed heading it was read from.")
                        .font(.footnote).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !loaded {
                ProgressView().frame(maxWidth: .infinity).padding(.top, Theme.Space.xl)
            } else if groups.isEmpty {
                ContentUnavailableView("Forms not in this build", systemImage: "text.word.spacing")
            }
            ForEach(groups) { g in group(g) }
        }
        // A container element keeps its rows' own identifiers; an identifier on a bare stack
        // is pushed down onto every row and would hide theirs from UI tests and automation.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("index_forms_list")
    }

    private func group(_ g: PoeticFormGroups.Group) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(alignment: .firstTextBaseline) {
                Text(PoeticForms.genre(g.genre)).font(Brand.heading(.headline))
                Spacer(minLength: Theme.Space.s)
                Text(g.entries.count == 1 ? "1 place" : "\(String(g.entries.count)) places")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                ForEach(Array(g.entries.enumerated()), id: \.element.id) { i, e in
                    Button { openComposition(e.first.compId) } label: { row(e) }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(PoeticForms.genre(g.genre)), \(place(e))")
                        .accessibilityHint("Opens the composition")
                        .accessibilityAddTraits(.isButton)
                        .accessibilityIdentifier("form_\(g.genre)_\(String(e.first.firstAng))")
                    if i < g.entries.count - 1 { Divider().padding(.leading, Theme.Space.l) }
                }
            }
            .background(Ink.card, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(Ink.hairline))
        }
    }

    private func row(_ e: PoeticFormGroups.Entry) -> some View {
        HStack(spacing: Theme.Space.m) {
            VStack(alignment: .leading, spacing: 3) {
                if let label = e.first.sourceLabel { GurmukhiText(verbatim: label, size: 17) }
                Text(place(e)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Theme.Space.s)
            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, Theme.Space.l).padding(.vertical, Theme.Space.m)
        .contentShape(Rectangle())
    }

    /// "Raag Majh · Ang 133", "After the raags · Ang 1360", "Raag Maru · Angs 1094–1102 · 21 headings".
    private func place(_ e: PoeticFormGroups.Entry) -> String {
        let raag = e.first.raag.map { r in GranthNames.raag(r, roman: e.first.raagRoman).map { "Raag \($0)" } ?? r }
            ?? "After the raags"
        var parts = [raag, (e.first.firstAng...e.lastAng).angLabel]
        if e.headings > 1 { parts.append("\(String(e.headings)) headings") }
        return parts.joined(separator: " · ")
    }
}
