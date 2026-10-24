import SwiftUI
import GurbaniSearchKit

/// A Vaar read straight through, as printed — or only its pauris, the ballad's spine. "Pauris
/// only" hides rows; it never alters or reorders a line. The position is kept per Vaar
/// (`VaarProgressStore`) and the reader resumes there unless opened at a specific line.
struct VaarReaderScreen: View {
    let vaarId: Int
    var paurisOnly = false
    var startLineId: Int? = nil

    @Environment(AppContainer.self) private var container
    @Environment(\.palette) private var palette
    @Environment(\.scenePhase) private var scenePhase
    @State private var summary: VaarSummary?
    @State private var text: VaarText?
    @State private var loaded = false
    @State private var onlyPauris = false
    @State private var positionId: Int?
    @State private var landed = false
    @State private var readSinceLanding = false
    @State private var finished = false
    @State private var endVisible = false
    /// Position changes until this moment come from the app (landing, a jump, a step, the view
    /// toggle), not the reader's own scrolling: they are saved, but never count as reading.
    @State private var programmaticUntil = Date.distantPast
    @State private var saveTask: Task<Void, Never>?

    var body: some View {
        Group {
            if let text, let summary {
                reader(summary, text)
            } else if loaded {
                ContentUnavailableView {
                    Label("This Vaar opens in the Reader", systemImage: "book")
                } description: {
                    Text("Its layout could not be read from this edition.")
                } actions: {
                    if let s = summary { Button("Open Ang \(s.firstAng)") { container.router.openAng(s.firstAng) } }
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Ink.paper.ignoresSafeArea())
        .navigationTitle(summary?.roman.map { "\($0.capitalized) Ki Vaar" } ?? "Vaar")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .onChange(of: positionId) { _, id in positionChanged(id) }
        .onChange(of: scenePhase) { _, phase in if phase != .active { flushSave() } }
        .onDisappear { flushSave() }
    }

    // MARK: rows

    /// Row ids: corpus line ids for lines (the scroll position IS the reading position), negative
    /// ids for the chrome rows so they can never collide with a line.
    static let headingRowId = -1
    static let endRowId = -3
    static func unitRowId(_ index: Int) -> Int { -(index + 10) }
    /// The unit index a chrome row id names, nil for the heading / end rows and for line ids.
    static func unitIndex(fromRowId id: Int) -> Int? { id <= -10 && id > angMarkBase ? -id - 10 : nil }
    /// "Ang N" marker rows: each Ang is marked at most once (reading order is monotonic).
    static let angMarkBase = -1_000_000
    static func angMarkRowId(_ ang: Int) -> Int { angMarkBase - ang }
    static func ang(fromRowId id: Int) -> Int? { id < angMarkBase ? angMarkBase - id : nil }

    private func units(_ t: VaarText) -> [VaarTextUnit] { onlyPauris ? t.pauris : t.units }

    private func reader(_ s: VaarSummary, _ t: VaarText) -> some View {
        let shown = units(t)
        return ScrollView {
            LazyVStack(alignment: .center, spacing: Theme.Space.s) {
                heading(t).id(Self.headingRowId)
                ForEach(Array(shown.enumerated()), id: \.element.id) { k, u in
                    if k > 0, shown[k - 1].lastAng != u.firstAng { angMark(u.firstAng).id(Self.angMarkRowId(u.firstAng)) }
                    unitHead(u).id(Self.unitRowId(u.index))
                    ForEach(Array(u.verse.enumerated()), id: \.element.id) { k, line in
                        if k > 0, line.ang != u.verse[k - 1].ang { angMark(line.ang).id(Self.angMarkRowId(line.ang)) }
                        LineRow(gurmukhi: line.gurmukhi, translit: line.translit, meta: "",
                                lineId: line.id, ang: line.ang, compId: line.compId, centred: true)
                            .id(line.id)
                    }
                }
                ending(s, t).padding(.top, Theme.Space.xl).id(Self.endRowId)
            }
            .scrollTargetLayout()
            .padding()
            .readingColumn()
        }
        .scrollPosition(id: $positionId, anchor: .top)
        .contentMargins(.bottom, 96, for: .scrollContent)
        .safeAreaInset(edge: .bottom) { bar(t) }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Show", selection: $onlyPauris) {
                        Label("The whole Vaar", systemImage: "text.justify").tag(false)
                        Label("Show pauris only", systemImage: "list.number").tag(true)
                    }
                    Section("Go to pauri") {
                        ForEach(t.pauris) { p in
                            Button("Pauri \(p.pauriNo ?? 0) · Ang \(p.firstAng)") { jump(to: p) }
                        }
                    }
                } label: { Image(systemName: "list.bullet.indent") }
                .accessibilityLabel("Vaar options")
                .accessibilityIdentifier("vaarReader.menu")
            }
        }
        .onChange(of: onlyPauris) { _, _ in
            // keep the place: land on the pauri the reader was in
            markProgrammatic()
            if let p = currentGroup(t) { positionId = Self.unitRowId(p.index) }
        }
    }

    private func heading(_ t: VaarText) -> some View {
        VStack(spacing: Theme.Space.s) {
            ForEach(t.heading) { line in
                GurmukhiText(verbatim: line.gurmukhi,
                             size: VaarStructure.isInvocation(line.gurmukhi) ? 19 : 23,
                             weight: VaarStructure.isInvocation(line.gurmukhi) ? .regular : .medium)
                    .multilineTextAlignment(.center)
            }
            Text("Sri Guru Granth Sahib Ji · \(angSpan(t.firstAng, t.lastAng))")
                .font(.footnote).foregroundStyle(.secondary)
            if onlyPauris {
                Text("Pauris only — the saloks are hidden, not removed.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Space.l)
    }

    /// The printed label (verbatim) with the unit's voice; a pauri also shows its number.
    private func unitHead(_ u: VaarTextUnit) -> some View {
        HStack(spacing: Theme.Space.s) {
            Circle().fill(VoiceInk.color(for: u.author)).frame(width: 8, height: 8)
            if let label = u.label {
                GurmukhiText(verbatim: label.gurmukhi, size: 16)
            } else {
                Text(u.kind == .pauri ? "Pauri" : "Salok").font(.subheadline).foregroundStyle(.secondary)
            }
            if let n = u.pauriNo {
                Text("\(n)").font(.caption.weight(.bold)).monospacedDigit()
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Capsule().fill(palette.accentFill))
                    .overlay(Capsule().strokeBorder(palette.accent))
                    .foregroundStyle(palette.onAccent)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, u.kind == .pauri ? Theme.Space.l : Theme.Space.m)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel((u.kind == .pauri ? "Pauri \(u.pauriNo ?? 0)" : "Salok") + (u.author.map { ", \($0)" } ?? ""))
        .accessibilityAddTraits(.isHeader)
    }

    private func angMark(_ ang: Int) -> some View {
        Text("Ang \(ang)").font(.caption2.weight(.medium)).foregroundStyle(.tertiary).monospacedDigit()
            .frame(maxWidth: .infinity)
            .padding(.vertical, 2)
            .accessibilityLabel("Ang \(ang) begins")
    }

    private func ending(_ s: VaarSummary, _ t: VaarText) -> some View {
        VStack(spacing: Theme.Space.m) {
            CompletionSeal(sealed: finished, size: 52)
            Text(finished ? "Vaar complete" : "End of the Vaar").font(Brand.heading(.headline))
            Text("Sri Guru Granth Sahib Ji · \(angSpan(t.firstAng, t.lastAng))")
                .font(.footnote).foregroundStyle(.secondary)
            if let next = nextVaarId {
                Button {
                    // the next Vaar with its own weave underneath, never a stack of readers
                    container.router.explorePath = NavigationPath(
                        [Route.vaars, Route.vaar(next), Route.vaarReader(id: next, paurisOnly: onlyPauris, line: nil)])
                } label: {
                    Label("Next Vaar", systemImage: "arrow.right")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, Theme.Space.xl).frame(minHeight: 44)
                        .background(Capsule().fill(palette.accentFill))
                        .overlay(Capsule().strokeBorder(palette.accent))
                        .foregroundStyle(palette.onAccent)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("vaarReader.next")
            }
        }
        .frame(maxWidth: .infinity)
        .onAppear { endVisible = true; if readSinceLanding && userDriven { complete(t) } }
        .onDisappear { endVisible = false }
    }

    /// "Pauri 12 of 27 · Ang 145" with previous / next pauri.
    private func bar(_ t: VaarText) -> some View {
        let group = currentGroup(t)
        let ang = currentAng(t)
        return HStack(spacing: Theme.Space.m) {
            Button { step(t, by: -1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                .disabled((group?.pauriNo ?? 1) <= 1)
                .accessibilityLabel("Previous pauri")
            VStack(spacing: 1) {
                Text(group.map { "Pauri \($0.pauriNo ?? 0) of \(t.nPauris)" } ?? "Heading")
                    .font(.subheadline.weight(.semibold)).monospacedDigit()
                Text("Ang \(ang)").font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            .frame(minWidth: 140)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("vaarReader.position")
            Button { step(t, by: 1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                .disabled((group?.pauriNo ?? 0) >= t.nPauris)
                .accessibilityLabel("Next pauri")
        }
        .padding(.horizontal, Theme.Space.s)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Ink.hairline))
        .padding(.bottom, Theme.Space.s)
    }

    // MARK: position

    private var nextVaarId: Int? {
        guard let order = container.vaarOrder, let i = order.firstIndex(of: vaarId), i + 1 < order.count else { return nil }
        return order[i + 1]
    }

    /// The unit the top of the screen is in.
    private func currentUnit(_ t: VaarText) -> VaarTextUnit? {
        guard let id = positionId else { return nil }
        if id == Self.headingRowId { return nil }
        if id == Self.endRowId { return t.units.last }
        if let ang = Self.ang(fromRowId: id) { return units(t).first { u in u.lines.contains { $0.ang == ang } } }
        if id < 0 { return Self.unitIndex(fromRowId: id).flatMap { t.units.indices.contains($0) ? t.units[$0] : nil } }
        return t.unitIndex(containing: id).map { t.units[$0] }
    }

    /// The pauri whose group the reader is in — saloks lead into the pauri after them.
    private func currentGroup(_ t: VaarText) -> VaarTextUnit? {
        guard let u = currentUnit(t) else { return nil }
        return t.units[u.index...].first { $0.kind == .pauri } ?? t.pauris.last
    }

    private func currentAng(_ t: VaarText) -> Int {
        guard let id = positionId, id > 0 else { return currentUnit(t)?.firstAng ?? t.firstAng }
        return t.units.lazy.flatMap(\.lines).first { $0.id == id }?.ang ?? t.firstAng
    }

    private func jump(to unit: VaarTextUnit) {
        markProgrammatic()
        MotionGate.run(Motion.gentle) { positionId = Self.unitRowId(unit.index) }
    }

    private func markProgrammatic() { programmaticUntil = Date().addingTimeInterval(1.0) }
    private var userDriven: Bool { Date() >= programmaticUntil }

    private func step(_ t: VaarText, by delta: Int) {
        let n = (currentGroup(t)?.pauriNo ?? 0) + delta
        guard let target = t.pauris.first(where: { $0.pauriNo == n }) else { return }
        // a whole-Vaar step lands on the group's first salok, so the saloks are read too
        let start = onlyPauris ? target : (VaarWeaveScreen.groups(t).first { $0.pauri?.index == target.index }?.saloks.first ?? target)
        jump(to: start)
    }

    private func positionChanged(_ id: Int?) {
        // once finished in this session the position stays where the seal was earned
        guard landed, !finished, let text, let id else { return }
        if userDriven {
            readSinceLanding = true
            if endVisible { complete(text); return }
        }
        let lineId = id > 0 ? id : (currentUnit(text)?.verse.first?.id ?? text.units.first?.verse.first?.id)
        guard let lineId else { return }
        let pauri = currentGroup(text)?.pauriNo
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            container.vaarProgress.setPosition(vaarId, lineId: lineId, pauriNo: pauri, nPauris: text.nPauris)
        }
    }

    private func flushSave() {
        guard let text, landed, !finished, let id = positionId, id != Self.headingRowId else { return }
        saveTask?.cancel()
        let lineId = id > 0 ? id : (currentUnit(text)?.verse.first?.id ?? 0)
        guard lineId > 0 else { return }
        container.vaarProgress.setPosition(vaarId, lineId: lineId, pauriNo: currentGroup(text)?.pauriNo, nPauris: text.nPauris)
    }

    private func complete(_ t: VaarText) {
        guard !finished else { return }
        saveTask?.cancel()
        if let last = t.units.last?.verse.last {
            container.vaarProgress.setPosition(vaarId, lineId: last.id, pauriNo: t.nPauris, nPauris: t.nPauris)
        }
        container.vaarProgress.markComplete(vaarId)
        MotionGate.run(Motion.spring) { finished = true }
        Haptics.success()
    }

    /// Where the reader opens: an explicit line, else the saved position (unless the Vaar was
    /// finished since), else the heading (nil). A line outside this Vaar is ignored. In the
    /// pauris-only view a salok line lands on the pauri it leads into; a label line lands on its
    /// unit's row. Pure, so the precedence is unit-tested.
    static func landing(in t: VaarText, startLineId: Int?, saved: VaarPosition?, paurisOnly: Bool) -> Int? {
        let resumable = saved.flatMap { p in (p.completedAt.map { $0 < p.lastReadAt } ?? true) ? p.lineId : nil }
        let wanted = [startLineId, resumable].compactMap { $0 }.first { t.unitIndex(containing: $0) != nil }
        guard let want = wanted, let idx = t.unitIndex(containing: want) else { return nil }
        let unit = t.units[idx]
        if paurisOnly && unit.kind != .pauri {
            return t.units[idx...].first { $0.kind == .pauri }.map { unitRowId($0.index) }
        }
        return unit.verse.contains { $0.id == want } ? want : unitRowId(unit.index)
    }

    private func load() async {
        guard !loaded, let corpus = container.corpus else { return }
        onlyPauris = paurisOnly
        let s = await corpus.vaars().first { $0.vaarId == vaarId }
        let t = await corpus.vaarText(id: vaarId)
        summary = s; text = t; loaded = true
        if container.vaarOrder == nil { container.vaarOrder = await corpus.vaars().map(\.vaarId) }
        guard let t else { return }
        positionId = Self.landing(in: t, startLineId: startLineId,
                                  saved: container.vaarProgress.position(for: vaarId), paurisOnly: onlyPauris)
        markProgrammatic()
        try? await Task.sleep(for: .milliseconds(400))   // let the landing settle before tracking
        landed = true
    }
}
