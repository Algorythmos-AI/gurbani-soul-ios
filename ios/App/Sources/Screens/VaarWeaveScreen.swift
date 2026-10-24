import SwiftUI
import GurbaniSearchKit

/// One Vaar as a weave: the pauris form a numbered spine, and the saloks that lead into each
/// pauri hang beside it in their own voice's colour. Every node shows its opening line verbatim;
/// tapping one opens the whole salok or pauri. Structure is read from the print (`VaarText`).
struct VaarWeaveScreen: View {
    let vaarId: Int
    @Environment(AppContainer.self) private var container
    @Environment(\.palette) private var palette
    @State private var summary: VaarSummary?
    @State private var text: VaarText?
    @State private var loaded = false
    @State private var hasTiming = false
    @State private var openUnit: VaarTextUnit?

    var body: some View {
        Group {
            if let text, let summary {
                weave(summary, text)
            } else if loaded, let summary {
                unreadable(summary)
            } else if loaded {
                ContentUnavailableView("Vaar not found", systemImage: "list.number")
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Ink.canvas.ignoresSafeArea())
        .navigationTitle(summary?.roman.map { "Vaar · \($0.capitalized)" } ?? "Vaar")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $openUnit) { unit in
            if let text, let summary { VaarUnitSheet(summary: summary, text: text, unit: unit) }
        }
        .task {
            guard !loaded, let corpus = container.corpus else { return }
            let s = await corpus.vaars().first { $0.vaarId == vaarId }
            let t = await corpus.vaarText(id: vaarId)
            if let raag = s?.raag, container.corpus?.capabilities.hasTiming == true {
                hasTiming = !(await corpus.timingRaag(name: raag).claims.isEmpty)
            }
            summary = s; text = t; loaded = true
        }
    }

    // MARK: layout

    private func weave(_ s: VaarSummary, _ t: VaarText) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Theme.Space.m) {
                header(s, t)
                actions(t)
                SectionEyebrow(text: "The weave · in reading order", symbol: "point.3.connected.trianglepath.dotted")
                    .padding(.top, Theme.Space.s)
                    .accessibilityIdentifier("vaar.weave")
                let groups = Self.groups(t)
                ForEach(groups) { g in
                    WeaveGroupRow(group: g, isLast: g.id == groups.last?.id) { openUnit = $0 }
                }
                if hasTiming, let raag = s.raag {
                    Button { container.router.openClock(raag: raag) } label: {
                        HStack {
                            Image(systemName: "clock")
                            Text("Raag ").font(.subheadline) + Text(raag).font(Brand.gurmukhi(17)) + Text(" in the Raag Clock").font(.subheadline)
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }
                        .padding(Theme.Space.l)
                        .background(Ink.card, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
                        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(Ink.hairline))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, Theme.Space.s)
                }
            }
            .padding(.horizontal, Theme.Space.l)
            .padding(.bottom, Theme.Space.xl)
        }
    }

    private func header(_ s: VaarSummary, _ t: VaarText) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                SectionEyebrow(text: [s.roman?.capitalized, "Vaar"].compactMap { $0 }.joined(separator: " · "))
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    ForEach(t.heading) { line in
                        GurmukhiText(verbatim: line.gurmukhi,
                                     size: VaarStructure.isInvocation(line.gurmukhi) ? 17 : 21,
                                     weight: VaarStructure.isInvocation(line.gurmukhi) ? .regular : .medium)
                    }
                }
                Text("Sri Guru Granth Sahib Ji · \(angSpan(t.firstAng, t.lastAng))")
                    .font(.footnote).foregroundStyle(.secondary)
                VoiceStrip(text: t, height: 20)
                VoiceLegend(text: t)
            }
        }
        .padding(.top, Theme.Space.s)
    }

    private func actions(_ t: VaarText) -> some View {
        HStack(spacing: Theme.Space.s) {
            Button { read(t, from: t.units.first) } label: {
                Label("Read the Vaar", systemImage: "book")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Capsule().fill(palette.accentFill))
                    .overlay(Capsule().strokeBorder(palette.accent))
                    .foregroundStyle(palette.onAccent)
            }
            .accessibilityIdentifier("vaar.read")
            Button { read(t, from: t.pauris.first) } label: {
                Label("Pauris only", systemImage: "list.number")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Capsule().fill(Ink.raised))
                    .overlay(Capsule().strokeBorder(Ink.hairline))
            }
            .accessibilityIdentifier("vaar.pauris")
        }
        .buttonStyle(.plain)
    }

    private func read(_ t: VaarText, from unit: VaarTextUnit?) {
        guard let line = unit?.firstVerse else { return }
        container.router.openAng(line.ang, lineId: line.id)
    }

    /// The Vaar's tables are present but its printed structure could not be proven: say so and
    /// keep the reader one tap away rather than guessing.
    private func unreadable(_ s: VaarSummary) -> some View {
        ContentUnavailableView {
            Label("This Vaar opens in the Reader", systemImage: "book")
        } description: {
            Text("Its layout could not be read from this edition, so it is shown as printed, Ang by Ang.")
        } actions: {
            Button("Open Ang \(s.firstAng)") { container.router.openAng(s.firstAng) }
                .buttonStyle(.borderedProminent)
        }
    }

    // MARK: grouping

    /// A pauri with the saloks printed before it (the last group may be saloks with no pauri).
    struct WeaveGroup: Identifiable {
        let saloks: [VaarTextUnit]
        let pauri: VaarTextUnit?
        var id: Int { pauri?.index ?? saloks.first?.index ?? 0 }
    }

    static func groups(_ t: VaarText) -> [WeaveGroup] {
        var out: [WeaveGroup] = []
        var pending: [VaarTextUnit] = []
        for u in t.units {
            if u.kind == .pauri { out.append(WeaveGroup(saloks: pending, pauri: u)); pending = [] }
            else { pending.append(u) }
        }
        if !pending.isEmpty { out.append(WeaveGroup(saloks: pending, pauri: nil)) }
        return out
    }
}

/// Each voice once, with how many saloks/pauris it carries in this Vaar.
private struct VoiceLegend: View {
    let text: VaarText
    var body: some View {
        let rows = text.voices.map { v in
            (v, text.units.filter { $0.author == v && $0.kind == .pauri }.count,
             text.units.filter { $0.author == v && $0.kind == .salok }.count)
        }
        VStack(alignment: .leading, spacing: 6) {
            ForEach(rows, id: \.0) { v, p, s in
                HStack(spacing: Theme.Space.s) {
                    Circle().fill(VoiceInk.color(for: v)).frame(width: 9, height: 9)
                    Text(v).font(.caption)
                    Spacer(minLength: Theme.Space.s)
                    Text([p > 0 ? "\(p) pauri\(p == 1 ? "" : "s")" : nil, s > 0 ? "\(s) salok\(s == 1 ? "" : "s")" : nil]
                            .compactMap { $0 }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// One step of the spine: the saloks as leaves, then the pauri node.
private struct WeaveGroupRow: View {
    let group: VaarWeaveScreen.WeaveGroup
    let isLast: Bool
    let open: (VaarTextUnit) -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.m) {
            rail
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                ForEach(group.saloks) { u in node(u) }
                if let p = group.pauri { node(p) }
            }
        }
    }

    /// The spine: a hairline with the gold pauri number at this group's pauri.
    private var rail: some View {
        VStack(spacing: 0) {
            if let n = group.pauri?.pauriNo {
                Text("\(n)")
                    .font(.caption.weight(.bold)).monospacedDigit()
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(palette.accentFill))
                    .overlay(Circle().strokeBorder(palette.accent))
                    .foregroundStyle(palette.onAccent)
                    .accessibilityHidden(true)
            }
            Rectangle().fill(isLast ? Color.clear : Ink.hairline).frame(width: 2).frame(maxHeight: .infinity)
        }
        .frame(width: 30)
    }

    private func node(_ u: VaarTextUnit) -> some View {
        Button { open(u) } label: {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                HStack(spacing: 6) {
                    Circle().fill(VoiceInk.color(for: u.author)).frame(width: 8, height: 8)
                    if let label = u.label {
                        GurmukhiText(verbatim: label.gurmukhi, size: 14)
                    } else {
                        Text(u.kind == .pauri ? "Pauri" : "Salok").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: Theme.Space.xs)
                    Text("Ang \(u.firstAng)").font(.caption2).foregroundStyle(.tertiary).monospacedDigit()
                }
                if let first = u.firstVerse {
                    GurmukhiText(verbatim: first.gurmukhi, size: u.kind == .pauri ? 18 : 16)
                }
            }
            .padding(Theme.Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(u.kind == .pauri ? AnyShapeStyle(palette.accent.opacity(0.08)) : AnyShapeStyle(Ink.card),
                        in: RoundedRectangle(cornerRadius: Theme.Radius.card))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card)
                .strokeBorder(u.kind == .pauri ? palette.accent.opacity(0.45) : Ink.hairline))
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.a11y(u))
        .accessibilityHint("Opens the whole \(u.kind == .pauri ? "pauri" : "salok")")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("vaar.unit.\(u.index)")
    }

    static func a11y(_ u: VaarTextUnit) -> Text {
        let head = u.kind == .pauri ? "Pauri \(u.pauriNo ?? 0)" : "Salok"
        var verse = AttributedString(u.firstVerse?.gurmukhi ?? "")
        verse.languageIdentifier = "pa"
        return Text("\(head)\(u.author.map { ", \($0)" } ?? ""), Ang \(u.firstAng). ") + Text(verse)
    }
}

/// The whole salok or pauri, verbatim, every line with the standard copy / share / save actions.
struct VaarUnitSheet: View {
    let summary: VaarSummary
    let text: VaarText
    let unit: VaarTextUnit
    @Environment(\.dismiss) private var dismiss
    @Environment(AppContainer.self) private var container

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    HStack(spacing: Theme.Space.s) {
                        Circle().fill(VoiceInk.color(for: unit.author)).frame(width: 10, height: 10)
                        Text(unit.author ?? (unit.kind == .pauri ? "Pauri" : "Salok"))
                            .font(.subheadline.weight(.medium))
                    }
                    if let label = unit.label {
                        GurmukhiText(verbatim: label.gurmukhi, size: 17)
                    }
                    ForEach(unit.verse) { line in
                        LineRow(gurmukhi: line.gurmukhi, translit: line.translit, meta: "",
                                lineId: line.id, ang: line.ang, compId: line.compId)
                    }
                    Text("Sri Guru Granth Sahib Ji · \(angSpan(unit.firstAng, unit.lastAng))")
                        .font(.footnote).foregroundStyle(.secondary)
                        .padding(.top, Theme.Space.s)
                }
                .padding(Theme.Space.l)
            }
            .background(Ink.base.ignoresSafeArea())
            .navigationTitle(unit.kind == .pauri ? "Pauri \(unit.pauriNo ?? 0)" : "Salok")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        dismiss()
                        if let line = unit.firstVerse { container.router.openAng(line.ang, lineId: line.id) }
                    } label: { Label("Read from here", systemImage: "book") }
                    .accessibilityIdentifier("vaar.readFromHere")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
