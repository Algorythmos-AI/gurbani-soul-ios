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
/// The dot field's morph, driven by a clock the view owns (not SwiftUI's animatable data, which
/// a parent cannot read): the displayed position of every dot is computable at any instant, so
/// regrouping again mid-flight starts from where the dots are actually drawn.
enum DotMorph {
    static let duration: TimeInterval = 0.45

    /// Eased progress (smoothstep) of a morph that began at `start`; 1 when none is running.
    static func progress(start: Date?, now: Date, duration: TimeInterval = duration) -> Double {
        guard let start, duration > 0 else { return 1 }
        let t = min(max(now.timeIntervalSince(start) / duration, 0), 1)
        return t * t * (3 - 2 * t)
    }

    /// Positions part-way from `from` to `to`; `to` when the two do not describe the same dots.
    static func interpolate(_ from: [CGPoint], _ to: [CGPoint], _ p: Double) -> [CGPoint] {
        guard from.count == to.count, p < 1 else { return to }
        return zip(from, to).map { a, b in CGPoint(x: a.x + (b.x - a.x) * p, y: a.y + (b.y - a.y) * p) }
    }
}

struct VoicesDotField: View {
    let voices: [(author: String, lines: Int)]
    let roster: [String: Contributor]
    let grouping: DotFieldLayout.Grouping
    @Binding var selected: String?

    @State private var width: CGFloat = 0
    /// Where the running morph started from (displayed positions at that instant).
    @State private var from: [CGPoint] = []
    @State private var morphStart: Date?
    @State private var shown: DotFieldLayout?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var layout: DotFieldLayout? {
        width > 0 ? DotFieldLayout.make(voices: voices, roster: roster, grouping: grouping, width: width) : nil
    }

    var body: some View {
        let current = layout
        ZStack(alignment: .topLeading) {
            if let current {
                TimelineView(.animation(paused: morphStart == nil)) { tl in
                    let p = DotMorph.progress(start: morphStart, now: tl.date)
                    DotCanvas(layout: current,
                              positions: DotMorph.interpolate(from, current.positions, p),
                              selected: selected)
                }
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
        .onChange(of: width) { _, _ in from = []; morphStart = nil; shown = layout }
        .onAppear { shown = layout }
    }

    private func morph() {
        let now = Date()
        guard let old = shown, let next = layout else { shown = layout; return }
        // the positions on screen right now — mid-flight included
        let displayed = DotMorph.interpolate(from, old.positions, DotMorph.progress(start: morphStart, now: now))
        shown = next
        guard !reduceMotion, displayed.count == next.positions.count else { from = []; morphStart = nil; return }
        from = displayed
        morphStart = now
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(DotMorph.duration))
            if morphStart == now { morphStart = nil; from = [] }   // settle, unless a newer morph began
        }
    }
}

private struct DotCanvas: View {
    let layout: DotFieldLayout
    let positions: [CGPoint]
    let selected: String?

    var body: some View {
        Canvas { ctx, _ in
            let r: CGFloat = 3
            for (i, d) in layout.dots.enumerated() where i < positions.count {
                let p = positions[i]
                let dim = selected != nil && selected != d.voice
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)),
                         with: .color(d.kind.color.opacity(dim ? 0.18 : 1)))
            }
        }
        .accessibilityHidden(true)   // the parent carries the summary + chart descriptor
    }
}
