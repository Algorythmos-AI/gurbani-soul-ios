import SwiftUI
import GurbaniSearchKit

/// The Granth as a gathering: every verse line as a share of a dot (1 dot ≈ `linesPerDot`
/// lines), coloured by tradition, regrouped by voice, tradition or century. Every voice keeps
/// at least one dot, so Bhatt Bhal's four lines are visible, not rounded away. Descriptive —
/// dots read as a sangat, not a leaderboard.
struct DotFieldLayout: Equatable {
    enum Grouping: String, CaseIterable, Identifiable {
        case voice = "Voices", tradition = "Traditions", century = "Centuries"
        var id: String { rawValue }
    }

    struct Dot: Equatable {
        let voice: String
        let kind: VoiceKind
    }
    struct Label: Equatable {
        let text: String
        let origin: CGPoint
    }

    static let linesPerDot = 50

    /// One entry per dot, in a stable order (voices in Granth order), so dot i is the same dot
    /// in every grouping and can morph from one position to the next.
    let dots: [Dot]
    let positions: [CGPoint]
    let labels: [Label]
    let size: CGSize

    static func dotCount(lines: Int) -> Int { max(1, Int((Double(lines) / Double(linesPerDot)).rounded())) }

    /// - voices: (author, verse lines) in Granth order.
    static func make(voices: [(author: String, lines: Int)], roster: [String: Contributor],
                     grouping: Grouping, width: CGFloat, dot: CGFloat = 6, gap: CGFloat = 2.5,
                     labelHeight: CGFloat = 22) -> DotFieldLayout {
        var dots: [Dot] = []
        for v in voices {
            let k = VoiceKind.of(v.author, roster: roster)
            dots += Array(repeating: Dot(voice: v.author, kind: k), count: dotCount(lines: v.lines))
        }
        let pitch = dot + gap
        let cols = max(1, Int((width + gap) / pitch))
        var positions = Array(repeating: CGPoint.zero, count: dots.count)
        var labels: [Label] = []
        var y: CGFloat = 0

        // groups of dot indices, each in Granth order
        var groups: [(title: String?, indices: [Int])] = []
        switch grouping {
        case .voice:
            groups = [(nil, Array(dots.indices))]
        case .tradition:
            for k in VoiceKind.allCases {
                let idx = dots.indices.filter { dots[$0].kind == k }
                if !idx.isEmpty { groups.append((k.title, idx)) }
            }
        case .century:
            let byVoice = Dictionary(grouping: dots.indices) { VoiceKind.century(dots[$0].voice, roster: roster) }
            let keys = byVoice.keys.sorted { ($0 ?? .max) < ($1 ?? .max) }
            groups = keys.map { (VoiceKind.centuryTitle($0), byVoice[$0]!.sorted()) }
        }

        for g in groups {
            if let title = g.title {
                labels.append(Label(text: title, origin: CGPoint(x: 0, y: y)))
                y += labelHeight
            }
            var col = 0, row = 0
            var prevVoice: String?
            for i in g.indices {
                // in the single-group (voices) view, a one-dot pause separates each voice
                if grouping == .voice, let p = prevVoice, p != dots[i].voice, col > 0 {
                    col += 1
                    if col >= cols { col = 0; row += 1 }
                }
                if col >= cols { col = 0; row += 1 }
                positions[i] = CGPoint(x: CGFloat(col) * pitch + dot / 2, y: y + CGFloat(row) * pitch + dot / 2)
                prevVoice = dots[i].voice
                col += 1
            }
            y += CGFloat(row + 1) * pitch + (g.title == nil ? 0 : gap * 4)
        }
        return DotFieldLayout(dots: dots, positions: positions, labels: labels, size: CGSize(width: width, height: y))
    }

    /// The voice under a point, if any dot is within reach.
    func voice(at p: CGPoint, reach: CGFloat = 10) -> String? {
        var best: (d: CGFloat, i: Int)?
        for (i, q) in positions.enumerated() {
            let d = hypot(q.x - p.x, q.y - p.y)
            if d <= reach, d < (best?.d ?? .infinity) { best = (d, i) }
        }
        return best.map { dots[$0.i].voice }
    }
}

/// Draws a `DotFieldLayout`, morphing every dot from its previous position to the current one.
struct VoicesDotField: View {
    let voices: [(author: String, lines: Int)]
    let roster: [String: Contributor]
    let grouping: DotFieldLayout.Grouping
    @Binding var selected: String?

    @State private var width: CGFloat = 0
    @State private var from: [CGPoint] = []
    @State private var progress: Double = 1
    @State private var shown: DotFieldLayout?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var layout: DotFieldLayout? {
        width > 0 ? DotFieldLayout.make(voices: voices, roster: roster, grouping: grouping, width: width) : nil
    }

    var body: some View {
        let current = layout
        ZStack(alignment: .topLeading) {
            if let current {
                DotCanvas(layout: current, from: from.count == current.positions.count ? from : current.positions,
                          progress: progress, selected: selected)
                    .frame(height: current.size.height)
                    .contentShape(Rectangle())
                    .onTapGesture { p in
                        let v = current.voice(at: p)
                        MotionGate.run(Motion.gentle) { selected = (v == selected) ? nil : v }
                        if v != nil { Haptics.tap() }
                    }
                ForEach(Array(current.labels.enumerated()), id: \.offset) { _, l in
                    Text(l.text).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        .offset(x: l.origin.x, y: l.origin.y)
                        .allowsHitTesting(false)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .onChange(of: grouping) { _, _ in morph() }
        .onChange(of: width) { _, _ in from = []; progress = 1; shown = layout }
        .onAppear { shown = layout }
    }

    private func morph() {
        guard let old = shown ?? layout else { shown = layout; return }
        // start from wherever each dot is drawn right now (mid-flight morphs stay continuous)
        let now = zip(from.count == old.positions.count ? from : old.positions, old.positions)
            .map { a, b in CGPoint(x: a.x + (b.x - a.x) * progress, y: a.y + (b.y - a.y) * progress) }
        shown = layout
        guard !reduceMotion, now.count == layout?.positions.count else { from = []; progress = 1; return }
        from = now
        progress = 0
        MotionGate.run(Motion.spring) { progress = 1 }
    }
}

private struct DotCanvas: View, @MainActor Animatable {   // SwiftUI animates on the main actor
    let layout: DotFieldLayout
    let from: [CGPoint]
    var progress: Double
    let selected: String?

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        Canvas { ctx, _ in
            let r: CGFloat = 3
            for (i, d) in layout.dots.enumerated() {
                let a = from[i], b = layout.positions[i]
                let p = CGPoint(x: a.x + (b.x - a.x) * progress, y: a.y + (b.y - a.y) * progress)
                let dim = selected != nil && selected != d.voice
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)),
                         with: .color(d.kind.color.opacity(dim ? 0.18 : 1)))
            }
        }
        .accessibilityHidden(true)   // the parent carries the summary + chart descriptor
    }
}
