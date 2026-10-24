import SwiftUI

/// Lineage › River: every dated voice as a lifespan on one timeline (c. 1160–1720), pinch to
/// zoom, drag the year scrubber to read who was alive that year (selection haptics), with the
/// Granth's milestones marked. Dates are approximate: a "c." lifespan fades at both ends. At
/// accessibility sizes and under VoiceOver the chart gives way to its list twin.
struct VoiceRiverView: View {
    let voices: [Contributor]
    let onOpen: (Contributor) -> Void

    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @State private var zoom: CGFloat = 1
    @GestureState private var pinch: CGFloat = 1
    @State private var scrubYear: Int?

    static let startYear = 1160
    static let endYear = 1720
    /// Milestones of the Granth itself. Historical claims without a reviewed source yet, so they
    /// wait for the scholar (G3) behind `EditorialGate.aboutCopy`; dates follow the circa rule.
    static let milestones: [(year: Int, label: String, title: String)] = [
        (1604, "1604", "The Adi Granth is compiled"),
        (1706, "c. 1705–06", "The Damdama Sahib Bir adds Guru Tegh Bahadur Ji's Bani"),
        (1708, "1708", "Guruship passes to the Granth"),
    ]
    static var shownMilestones: [(year: Int, label: String, title: String)] {
        EditorialGate.aboutCopy ? milestones : []
    }

    private var dated: [Contributor] {
        voices.filter { $0.born != nil || $0.died != nil }
            .sorted { $0.timelineYear != $1.timelineYear ? $0.timelineYear < $1.timelineYear : $0.displayName < $1.displayName }
    }
    private var undated: [Contributor] { voices.filter { $0.born == nil && $0.died == nil } }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            if typeSize.isAccessibilitySize || voiceOver {
                listTwin
            } else {
                chart
                scrubber
                if !Self.shownMilestones.isEmpty { milestoneLegend }
            }
            Text("Lifespans are approximate. A faded end marks a date scholars give only as \u{201C}c.\u{201D}")
                .font(.caption).foregroundStyle(.secondary)
            if !undated.isEmpty {
                Text("Undated: " + undated.map(\.displayName).joined(separator: ", "))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: chart

    private static let laneHeight: CGFloat = 26
    private static let axisHeight: CGFloat = 22

    private var chart: some View {
        let lanes = dated
        let height = Self.axisHeight + CGFloat(lanes.count) * Self.laneHeight + 8
        return GeometryReader { geo in
            let width = geo.size.width * min(4, max(1, zoom * pinch))
            ScrollView(.horizontal, showsIndicators: false) {
                Canvas { ctx, size in draw(&ctx, size: size, lanes: lanes) }
                    .frame(width: width, height: height)
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        if let lane = Self.lane(atY: location.y), lanes.indices.contains(lane) { onOpen(lanes[lane]) }
                    }
            }
        }
        .frame(height: height)
        .gesture(
            MagnifyGesture()
                .updating($pinch) { value, state, _ in state = value.magnification }
                .onEnded { value in zoom = min(4, max(1, zoom * value.magnification)) }
        )
        .accessibilityHidden(true)   // the list twin is the VoiceOver path
    }

    /// The lifespan row under a tap; nil on the year-label strip above the first row (`Int()`
    /// would truncate a small negative offset to row 0).
    static func lane(atY y: CGFloat) -> Int? {
        guard y >= axisHeight else { return nil }
        return Int(floor((y - axisHeight) / laneHeight))
    }

    private func x(_ year: Double, _ width: CGFloat) -> CGFloat {
        CGFloat((year - Double(Self.startYear)) / Double(Self.endYear - Self.startYear)) * width
    }

    private func draw(_ ctx: inout GraphicsContext, size: CGSize, lanes: [Contributor]) {
        let w = size.width
        // century grid + labels
        for year in stride(from: 1200, through: 1700, by: 100) {
            let gx = x(Double(year), w)
            ctx.fill(Path(CGRect(x: gx, y: Self.axisHeight - 4, width: 0.5, height: size.height)), with: .color(Ink.hairline))
            ctx.draw(Text(String(year)).font(.caption2).foregroundStyle(.secondary),
                     at: CGPoint(x: gx, y: 8), anchor: .center)
        }
        // milestones: dashed lines
        for m in Self.shownMilestones {
            var p = Path()
            let mx = x(Double(m.year), w)
            p.move(to: CGPoint(x: mx, y: Self.axisHeight - 4)); p.addLine(to: CGPoint(x: mx, y: size.height))
            ctx.stroke(p, with: .color(.secondary.opacity(0.7)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        }
        // lifespans
        for (i, c) in lanes.enumerated() {
            let y = Self.axisHeight + CGFloat(i) * Self.laneHeight
            guard let span = LifespanLogic.bounds(c) else { continue }
            let born = Double(span.lowerBound), died = Double(span.upperBound)
            let x0 = x(born, w), x1 = max(x0 + 3, x(died, w))
            let rect = CGRect(x: x0, y: y + 6, width: x1 - x0, height: Self.laneHeight - 14)
            let alive = scrubYear.map { Double($0) >= born && Double($0) <= died } ?? true
            let color = c.kindColor.opacity(alive ? 1 : 0.28)
            let fades = c.circa || c.born == nil || c.died == nil
            let shading: GraphicsContext.Shading = fades
                ? .linearGradient(Gradient(stops: [.init(color: color.opacity(0.15), location: 0),
                                                   .init(color: color, location: 0.22),
                                                   .init(color: color, location: 0.78),
                                                   .init(color: color.opacity(0.15), location: 1)]),
                                  startPoint: CGPoint(x: rect.minX, y: 0), endPoint: CGPoint(x: rect.maxX, y: 0))
                : .color(color)
            ctx.fill(Path(roundedRect: rect, cornerRadius: rect.height / 2), with: shading)
            let label = Text(c.displayName).font(.caption2).foregroundStyle(alive ? .primary : .secondary)
            if x1 + 120 < w {
                ctx.draw(label, at: CGPoint(x: x1 + 5, y: rect.midY), anchor: .leading)
            } else {
                ctx.draw(label, at: CGPoint(x: x0 - 5, y: rect.midY), anchor: .trailing)
            }
        }
        // the scrub line
        if let scrubYear {
            let sx = x(Double(scrubYear), w)
            ctx.fill(Path(CGRect(x: sx - 0.75, y: Self.axisHeight - 6, width: 1.5, height: size.height)), with: .color(.primary))
        }
    }

    // MARK: scrubber

    private var scrubber: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Ink.raised).frame(height: 6)
                    if let scrubYear {
                        Circle().fill(Color.primary)
                            .frame(width: 18, height: 18)
                            .offset(x: x(Double(scrubYear), geo.size.width) - 9)
                    }
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                    let f = min(1, max(0, v.location.x / max(1, geo.size.width)))
                    scrubYear = Self.startYear + Int((f * Double(Self.endYear - Self.startYear)).rounded())
                })
            }
            .frame(height: 28)
            .sensoryFeedback(.selection, trigger: scrubYear.map { $0 / 10 })   // a tick per decade
            .accessibilityElement()
            .accessibilityLabel("Year")
            .accessibilityValue(scrubYear.map(String.init) ?? "none")
            .accessibilityAdjustableAction { d in
                let y = scrubYear ?? 1500
                scrubYear = min(Self.endYear, max(Self.startYear, y + (d == .increment ? 10 : -10)))
            }
            Text(readout).font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(nil, value: scrubYear)
        }
    }

    private var readout: String { LifespanLogic.readout(year: scrubYear, voices: dated) }

    private var milestoneLegend: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Self.shownMilestones, id: \.year) { m in
                Label { Text("\(m.label) · \(m.title)") } icon: {
                    Image(systemName: "line.diagonal").rotationEffect(.degrees(45))
                }
                .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: list twin

    private var listTwin: some View {
        // Voices and milestones in one chronological list.
        enum Row: Identifiable {
            case voice(Contributor)
            case milestone(Int, String, String)
            var id: String {
                switch self { case .voice(let c): return c.name; case .milestone(let y, _, _): return "m\(y)" }
            }
            var year: Int {
                switch self { case .voice(let c): return c.timelineYear; case .milestone(let y, _, _): return y }
            }
        }
        let rows = (dated.map(Row.voice) + Self.shownMilestones.map { Row.milestone($0.year, $0.label, $0.title) })
            .sorted { $0.year < $1.year }
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(rows) { row in
                switch row {
                case .voice(let c):
                    Button { onOpen(c) } label: {
                        HStack(alignment: .firstTextBaseline) {
                            Text(c.displayName).font(.body)
                            Spacer(minLength: Theme.Space.s)
                            Text(c.lifespan ?? "").font(.callout).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, Theme.Space.s)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityHint("Opens their page")
                case .milestone(_, let label, let title):
                    Label("\(label) · \(title)", systemImage: "flag")
                        .font(.callout.weight(.semibold))
                        .padding(.vertical, Theme.Space.s)
                }
                Divider()
            }
        }
    }
}
