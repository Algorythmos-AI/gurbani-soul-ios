import SwiftUI
import GurbaniSearchKit

/// The Granth as a ribbon: 1,430 Angs in 143 columns of ten, each column stacked by tradition
/// (verse lines). Choose a voice and everything else dims to show where that voice sings —
/// Kabir across the raags and again in his saloks, the Bhatts only in the Swaiyye. Scrub with a
/// finger; the loupe names the Angs and who sings there, and opens them in the Reader on tap.
struct RibbonModel: Equatable {
    struct Column: Equatable {
        /// verse lines per tradition, in VoiceKind.allCases order
        let byKind: [Int]
        let total: Int
        /// (voice, lines) most first
        let voices: [(String, Int)]
        static func == (a: Column, b: Column) -> Bool {
            a.byKind == b.byKind && a.voices.map(\.0) == b.voices.map(\.0) && a.voices.map(\.1) == b.voices.map(\.1)
        }
    }
    let columns: [Column]
    let peak: Int

    init(atlas: VoicesAtlas, roster: [String: Contributor]) {
        var cols: [Column] = []
        for b in 0..<VoicesAtlas.bucketCount {
            var byKind = Array(repeating: 0, count: VoiceKind.allCases.count)
            var voices: [(String, Int)] = []
            for (author, row) in atlas.histogram where row[b] > 0 {
                let k = VoiceKind.of(author, roster: roster)
                byKind[VoiceKind.allCases.firstIndex(of: k)!] += row[b]
                voices.append((author, row[b]))
            }
            voices.sort { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0 < $1.0 }
            cols.append(Column(byKind: byKind, total: byKind.reduce(0, +), voices: voices))
        }
        columns = cols
        peak = max(cols.map(\.total).max() ?? 1, 1)
    }

    static func describe(_ b: Int, column c: Column, selected: String?) -> String {
        let r = VoicesAtlas.angs(inBucket: b)
        let where_ = "Angs \(r.lowerBound) to \(r.upperBound)"
        if let selected {
            let n = c.voices.first(where: { $0.0 == selected })?.1 ?? 0
            return n == 0 ? "\(where_): \(AuthorName(selected).spoken) does not sing here"
                          : "\(where_): \(AuthorName(selected).spoken), \(n) lines"
        }
        let top = c.voices.prefix(3).map { "\(AuthorName($0.0).spoken) \($0.1)" }.joined(separator: ", ")
        return "\(where_): \(c.total) lines. \(top)"
    }
}

struct GranthRibbon: View {
    let model: RibbonModel
    let selected: String?
    var onOpenAng: (Int) -> Void

    @State private var scrub: Int?
    @State private var focus: Int = 0          // VoiceOver's adjustable position
    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 96

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            loupe
            GeometryReader { geo in
                Canvas { ctx, size in draw(ctx, size) }
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { v in scrub = bucket(at: v.location.x, width: geo.size.width) })
                    .sensoryFeedback(.selection, trigger: scrub)
            }
            .frame(height: height)
            axis
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Granth ribbon, 1,430 Angs in groups of ten")
        .accessibilityValue(RibbonModel.describe(focus, column: model.columns[focus], selected: selected))
        .accessibilityAdjustableAction { dir in
            switch dir {
            case .increment: focus = min(focus + 1, VoicesAtlas.bucketCount - 1)
            case .decrement: focus = max(focus - 1, 0)
            @unknown default: break
            }
        }
        .accessibilityAction(named: "Open in Reader") { onOpenAng(VoicesAtlas.angs(inBucket: focus).lowerBound) }
        .accessibilityIdentifier("granthRibbon")
    }

    private func bucket(at x: CGFloat, width: CGFloat) -> Int {
        guard width > 0 else { return 0 }
        return min(max(Int(x / width * CGFloat(VoicesAtlas.bucketCount)), 0), VoicesAtlas.bucketCount - 1)
    }

    private func draw(_ ctx: GraphicsContext, _ size: CGSize) {
        let n = CGFloat(VoicesAtlas.bucketCount)
        let w = size.width / n
        let bar = max(w - 0.6, 0.6)
        for (b, c) in model.columns.enumerated() {
            let x = CGFloat(b) * w
            var y = size.height
            let mine = selected.flatMap { s in c.voices.first(where: { $0.0 == s })?.1 } ?? 0
            for (k, kind) in VoiceKind.allCases.enumerated() where c.byKind[k] > 0 {
                let h = size.height * CGFloat(c.byKind[k]) / CGFloat(model.peak)
                y -= h
                ctx.fill(Path(CGRect(x: x, y: y, width: bar, height: h)),
                         with: .color(kind.color.opacity(selected == nil ? (scrub == nil || scrub == b ? 1 : 0.55) : 0.16)))
            }
            if mine > 0 {
                let h = max(size.height * CGFloat(mine) / CGFloat(model.peak), 1.5)
                ctx.fill(Path(CGRect(x: x, y: size.height - h, width: bar, height: h)),
                         with: .color(Brand.primary))   // accent, not the fill-only brand gold
            }
            if scrub == b {
                ctx.stroke(Path(CGRect(x: x - 0.5, y: 0, width: bar + 1, height: size.height)),
                           with: .color(Brand.primary), lineWidth: 1)
            }
        }
    }

    @ViewBuilder private var loupe: some View {
        let b = scrub ?? 0
        let c = model.columns[b]
        HStack(alignment: .firstTextBaseline) {
            if scrub == nil {
                Text(selected == nil ? "Touch and slide along the Granth"
                                     : "Where \(AuthorName(selected!).english) sings")
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                let r = VoicesAtlas.angs(inBucket: b)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Angs \(String(r.lowerBound))–\(String(r.upperBound))").font(.footnote.weight(.semibold))
                    Text(c.voices.prefix(3).map { "\(AuthorName($0.0).compact) \($0.1)" }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: Theme.Space.s)
                Button("Open Ang \(String(r.lowerBound))") { onOpenAng(r.lowerBound) }
                    .font(.footnote.weight(.semibold))
                    .accessibilityIdentifier("ribbonOpenAng")
            }
        }
        .frame(minHeight: 36, alignment: .leading)
        .animation(nil, value: scrub)
    }

    private var axis: some View {
        HStack {
            Text("Ang 1"); Spacer(); Text("Ang 715"); Spacer(); Text("Ang 1430")
        }
        .font(.caption2).monospacedDigit().foregroundStyle(.secondary)
        .accessibilityHidden(true)
    }
}
