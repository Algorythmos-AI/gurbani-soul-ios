import SwiftUI
import GurbaniSearchKit

/// The Hukamnama from Sri Harmandir Sahib, Amritsar, for one Amritsar date (nil = the latest).
/// SGPC's page only LOCATED the shabad; every line here comes from the app's own corpus and is
/// shown only after its range hashes to the server's `range_sha256` (`HukamnamaLocator`). When
/// nothing proves out, the sheet says "Update Gurbani Soul" with the Ang only — never a line.
/// Not the Hukam of the day (G3 R6): its own sheet, title and wording.
struct HukamnamaSheet: View {
    let date: String?
    @Environment(AppContainer.self) private var container
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette

    enum Phase: Equatable {
        case loading
        case lines(HukamnamaEntry, [ReaderLine])
        case notYet(date: String)
        case held(date: String)
        case needsUpdate(ang: Int?)
        case offline
        case notFound
    }
    @State private var phase: Phase = .loading

    static let title = "Hukamnama · Sri Harmandir Sahib, Amritsar"
    static let footer = "Located by Ang from SGPC (sgpc.net). Text from Sri Guru Granth Sahib Ji."

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Hukamnama")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
        .accessibilityIdentifier("hukamnamaSheet")
        // the entry's revision is in the id: an open sheet reloads when the Hukamnama arrives
        .task(id: "\(date ?? "latest")-\(container.integrity?.ok == true)-\(container.hukamnama.revision(date: date))") {
            await load()
        }
    }

    @ViewBuilder private var content: some View {
        switch phase {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .lines(let entry, let lines):
            reader(entry: entry, lines: lines)
        case .notYet(let d):
            message(title: "Not yet published",
                    body: "\(AmritsarDate.label(d) ?? d). Usually around \(HukamnamaSchedule.usualLocalTime(now: Date())) your time.",
                    id: "hukamnamaNotYet")
        case .held(let d):
            message(title: "Delayed today",
                    body: "\(AmritsarDate.label(d) ?? d). It will appear here once it has been checked.",
                    id: "hukamnamaHeld")
        case .needsUpdate(let ang):
            message(title: "Update Gurbani Soul to read this Hukamnama",
                    body: ang.map { HukamnamaEntry.citation(ang: $0) } ?? "",
                    id: "hukamnamaNeedsUpdate")
        case .offline:
            message(title: "Connect to the internet",
                    body: "The Hukamnama is found online each morning. Its text then comes from Sri Guru Granth Sahib Ji in this app.",
                    id: "hukamnamaOffline", retry: true)
        case .notFound:
            message(title: "No Hukamnama for this date", body: date.flatMap(AmritsarDate.label) ?? "", id: "hukamnamaNotFound")
        }
    }

    private func reader(entry: HukamnamaEntry, lines: [ReaderLine]) -> some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    SectionEyebrow(text: Self.title)
                        .accessibilityIdentifier("hukamnamaHeader")
                    if let label = AmritsarDate.label(entry.amritsarDate) {
                        Text(label).font(.subheadline).foregroundStyle(.secondary)
                    }
                    if let ang = (lines.first(where: { !$0.isHeader }) ?? lines.first)?.ang {
                        Text(HukamnamaEntry.citation(ang: ang)).font(.caption).foregroundStyle(.secondary)
                            .accessibilityIdentifier("hukamnamaCitation")
                    }
                }
                .padding(.vertical, Theme.Space.xs)
                .listRowSeparator(.hidden)
            }
            Section {
                ForEach(lines, id: \.id) { line in
                    if VerseTypography.rendersAsHeading(line.gurmukhi, flaggedHeader: line.isHeader) {
                        VerseHeading(verbatim: line.gurmukhi, translit: line.translit)
                            .padding(.vertical, 4)
                            .listRowSeparator(.hidden)
                    } else {
                        // the same row as every reader: saroop, Sant Lipi, size, Copy (verbatim), Share
                        LineRow(gurmukhi: line.gurmukhi, translit: line.translit,
                                meta: line.isRahao ? "ਰਹਾਉ · refrain" : "", en: line.en,
                                inSpan: line.enSpan != nil, lineId: line.id, ang: line.ang, compId: line.compId)
                            .listRowSeparator(.hidden)
                    }
                }
            } footer: {
                Text(Self.footer).font(.footnote).accessibilityIdentifier("hukamnamaFooter")
            }
        }
        .listStyle(.plain)
        .safeAreaInset(edge: .bottom) {
            if let first = lines.first(where: { !$0.isHeader }) ?? lines.first {
                Button {
                    container.router.openAng(first.ang, lineId: first.id)
                    dismiss()
                } label: {
                    Label("Open Ang \(String(first.ang)) in Reader", systemImage: "book")
                        .font(.body.weight(.medium))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, Theme.Space.m)
                .background(Capsule().fill(Ink.card))
                .overlay(Capsule().strokeBorder(Ink.hairline))
                .padding(.horizontal, Theme.Space.l)
                .frame(maxWidth: 520).frame(maxWidth: .infinity)
                .padding(.bottom, Theme.Space.xs)
            }
        }
    }

    private func message(title: String, body: String, id: String, retry: Bool = false) -> some View {
        VStack(spacing: Theme.Space.m) {
            SectionEyebrow(text: Self.title)
            Text(title).font(.headline).multilineTextAlignment(.center)
            if !body.isEmpty {
                Text(body).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            if retry {
                Button("Try again") { Task { await load() } }.buttonStyle(.bordered)
            }
        }
        .padding(Theme.Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(id)
    }

    /// Store first (the NSE wrote it at delivery), then the service. Lines only after the proof.
    private func load() async {
        // scripture is never shown before the launch integrity check passes
        guard container.integrity?.ok == true, let corpus = container.corpus else { phase = .loading; return }
        phase = .loading
        let entry: HukamnamaEntry
        let pick = await container.hukamnama.pick(date: date)
        guard !Task.isCancelled else { return }   // the entry changed meanwhile: the new task loads it
        switch pick {
        case .entry(let e): entry = e
        case .notFound: phase = .notFound; return
        case .offline: phase = .offline; return
        }
        switch entry.status {
        case .pending: phase = .notYet(date: entry.amritsarDate); return
        case .held: phase = .held(date: entry.amritsarDate); return
        case .published: break
        }
        let resolved = await HukamnamaLocator.resolve(entry, source: corpus)
        guard !Task.isCancelled else { return }
        switch resolved {
        case .verified(let lines), .relocated(let lines): phase = .lines(entry, lines)
        case .needsUpdate(let ang): phase = .needsUpdate(ang: ang)
        }
    }
}
