import SwiftUI
import GurbaniSearchKit

/// The whole sky: all 54 themes at once (web parity /constellation?view=sky). A deterministic
/// ForceLayout (SplitMix64 seed, fixed iterations, settled off-main before the first frame) pulls
/// every pair together by its PPMI, so a theme with no strong bond still sits by its nearest
/// themes; only the pairs at PPMI ≥ 0.7 are drawn. Star size = √verses, colour = theological
/// group. Pinch to zoom, drag to pan, tap a star to focus it. The list twin carries the same
/// themes for VoiceOver, Switch Control and large type. Descriptive only.
struct ConstellationSkyScreen: View {
    let current: String
    var onFocus: (String) -> Void
    @Environment(AppContainer.self) private var container
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var sky: SkyModel?
    @State private var failed: String?
    @State private var asList = false
    @State private var appeared = false
    @State private var scale: CGFloat = 1
    @State private var settledScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var settledOffset: CGSize = .zero

    struct SkyModel: Sendable {
        let nodes: [SkyNode]
        let points: [CGPoint]          // unit square
        let drawn: [(Int, Int, Double, Double)]   // i, j, ppmi, jaccard (PPMI ≥ 0.7)
    }

    private var showList: Bool { asList || typeSize.isAccessibilitySize }

    var body: some View {
        Group {
            if let sky {
                if showList { list(sky) } else { map(sky) }
            } else if let failed {
                EmptyStateView(title: "Something went wrong", message: failed, isError: true,
                               actionTitle: "Try again") { Task { await load() } }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Ink.clockFace.ignoresSafeArea())   // the night sky (the Raag dial's surface)
        .navigationTitle("The whole sky")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(showList ? "Map" : "List") { asList.toggle() }
                    .disabled(typeSize.isAccessibilitySize)
                    .accessibilityLabel(showList ? "View as map" : "View as list")
            }
        }
        .task { await load() }
    }

    // MARK: map

    private func map(_ sky: SkyModel) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text("All \(sky.nodes.count) themes. Lines join themes that share shabads more than chance (PPMI 0.7 or more). Tap a star to focus it.")
                .font(.caption).foregroundStyle(Ink.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Theme.Space.l)
            GeometryReader { geo in
                let size = geo.size
                let maxN = Double(sky.nodes.map(\.n).max() ?? 1)
                ZStack {
                    Canvas { ctx, sz in
                        for (i, j, ppmi, jaccard) in sky.drawn {
                            var path = Path()
                            path.move(to: at(sky.points[i], sz)); path.addLine(to: at(sky.points[j], sz))
                            ctx.stroke(path, with: .color(Ink.muted.opacity(0.10 + 0.5 * min(1, jaccard / 0.5))),
                                       lineWidth: 0.5 + 2.5 * CGFloat(min(1, (ppmi - 0.7) / 2.9)))
                        }
                    }
                    .accessibilityHidden(true)
                    ForEach(Array(sky.nodes.enumerated()), id: \.element.id) { i, node in
                        let r = 4 + 13 * CGFloat((Double(node.n) / maxN).squareRoot())
                        Button {
                            Haptics.tap()
                            onFocus(node.concept)
                        } label: {
                            VStack(spacing: 1) {
                                Circle().fill(ThemeGroup.color(node.concept))
                                    .frame(width: 2 * r, height: 2 * r)
                                    .overlay(Circle().strokeBorder(node.concept == current ? Color.primary : Color.clear, lineWidth: 2))
                                Text(ConceptName.display(node.concept))
                                    .font(.system(size: 9, weight: .semibold)).foregroundStyle(.primary)
                                    .lineLimit(1).fixedSize()
                            }
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .position(at(sky.points[i], size))
                        .accessibilityLabel("\(ConceptName.display(node.concept)): \(node.n) verses")
                        .accessibilityHint("Focus this theme")
                    }
                }
                .scaleEffect(scale)
                .offset(offset)
                .gesture(
                    MagnifyGesture()
                        .onChanged { v in scale = min(4, max(0.8, settledScale * v.magnification)) }
                        .onEnded { _ in settledScale = scale }
                        .simultaneously(with: DragGesture(minimumDistance: 8)
                            .onChanged { v in
                                offset = CGSize(width: settledOffset.width + v.translation.width,
                                                height: settledOffset.height + v.translation.height)
                            }
                            .onEnded { _ in settledOffset = offset })
                )
                .clipped()
            }
            legend
        }
        .opacity(appeared ? 1 : 0)
        .appAnimation(Motion.gentle, value: appeared)
        .onAppear { appeared = true }
    }

    private func at(_ p: CGPoint, _ size: CGSize) -> CGPoint {
        let pad: CGFloat = 30
        return CGPoint(x: pad + p.x * (size.width - 2 * pad), y: pad + p.y * (size.height - 2 * pad))
    }

    private var legend: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Space.m) {
                ForEach(ThemeGroup.all) { g in
                    HStack(spacing: 4) {
                        Circle().fill(g.color).frame(width: 10, height: 10).accessibilityHidden(true)
                        Text(g.title).font(.caption2).foregroundStyle(.primary)
                    }
                }
            }
            .padding(.horizontal, Theme.Space.l)
            .padding(.bottom, Theme.Space.s)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Theme groups: " + ThemeGroup.all.map(\.title).joined(separator: ", "))
    }

    // MARK: list twin

    private func list(_ sky: SkyModel) -> some View {
        let counts = Dictionary(uniqueKeysWithValues: sky.nodes.map { ($0.concept, $0.n) })
        let placed = Set(ThemeGroup.all.flatMap(\.keys))
        let leftover = sky.nodes.filter { !placed.contains($0.concept) }.map(\.concept)
        return List {
            ForEach(ThemeGroup.all) { g in
                Section(g.title) {
                    ForEach(g.keys.filter { counts[$0] != nil }, id: \.self) { k in listRow(k, counts[k] ?? 0) }
                }
            }
            if !leftover.isEmpty {
                Section("More Themes") { ForEach(leftover, id: \.self) { k in listRow(k, counts[k] ?? 0) } }
            }
        }
    }

    private func listRow(_ concept: String, _ n: Int) -> some View {
        Button {
            onFocus(concept)
        } label: {
            HStack {
                Circle().fill(ThemeGroup.color(concept)).frame(width: 10, height: 10).accessibilityHidden(true)
                Text(ConceptName.display(concept)).foregroundStyle(.primary)
                Spacer()
                Text("\(n.formatted()) verses").font(.caption).foregroundStyle(Ink.muted)
            }
        }
        .accessibilityLabel("\(ConceptName.display(concept)), \(n) verses")
        .accessibilityHint("Focus this theme")
    }

    // MARK: load

    private func load() async {
        guard let corpus = container.corpus else { failed = "No database"; return }
        failed = nil
        do {
            let all = try await corpus.constellationSky(minPPMI: 0)     // every pair: the layout's springs
            let nodes = all.nodes
            let index = Dictionary(uniqueKeysWithValues: nodes.enumerated().map { ($1.concept, $0) })
            let maxP = max(all.edges.map(\.ppmi).max() ?? 1, 1e-6)
            let springs = all.edges.compactMap { e -> (Int, Int, Double)? in
                guard e.ppmi > 0, let i = index[e.source], let j = index[e.target] else { return nil }
                return (i, j, 3 * e.ppmi / maxP)
            }
            let drawn = all.edges.compactMap { e -> (Int, Int, Double, Double)? in
                guard e.ppmi >= 0.7, let i = index[e.source], let j = index[e.target] else { return nil }
                return (i, j, e.ppmi, e.jaccard)
            }
            let count = nodes.count
            let points = await Task.detached(priority: .userInitiated) {
                ForceLayout.layout(nodeCount: count, edges: springs, iterations: 300, seed: 54)
            }.value
            if Task.isCancelled { return }
            sky = SkyModel(nodes: nodes, points: points, drawn: drawn)
        } catch is CancellationError {
        } catch { failed = UserMessage.load(error) }
    }
}
