import SwiftUI

/// Where each Vaar sits in the Granth (VaarSpanRibbon — distinct from the Voices GranthRibbon): a 1–1430 axis with one mark per Vaar over its Ang span,
/// coloured by the Vaar's pauri voice. Tap or drag to pick a Vaar (a selection tick per change);
/// VoiceOver adjusts through them in order.
struct VaarSpanRibbon: View {
    struct Mark: Identifiable, Equatable {
        let id: Int
        let firstAng: Int
        let lastAng: Int
        let author: String?
        let label: String
    }

    let marks: [Mark]
    @Binding var selected: Int?
    static let angs = 1...1430

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Ink.hairline).frame(height: 2)
                    ForEach(marks) { m in
                        let r = Self.span(m, width: w)
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(VoiceInk.color(for: m.author))
                            .frame(width: r.width, height: m.id == selected ? 22 : 14)
                            .offset(x: r.minX)
                            .opacity(selected == nil || m.id == selected ? 1 : 0.45)
                    }
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                    if let hit = Self.nearest(to: g.location.x, width: w, in: marks), hit != selected {
                        selected = hit
                    }
                })
            }
            .frame(height: 26)
            HStack {
                Text("Ang 1"); Spacer(); Text("Ang 1430")
            }
            .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
        }
        .sensoryFeedback(.selection, trigger: selected)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Where the Vaars sit in the Granth")
        .accessibilityValue(selected.flatMap { id in marks.first { $0.id == id } }.map(\.label) ?? "None selected")
        .accessibilityAdjustableAction { dir in
            let ids = marks.map(\.id)
            let at = selected.flatMap { ids.firstIndex(of: $0) }
            switch dir {
            case .increment: selected = ids[min((at ?? -1) + 1, ids.count - 1)]
            case .decrement: selected = ids[max((at ?? ids.count) - 1, 0)]
            @unknown default: break
            }
        }
    }

    /// The mark's x-extent on a `width`-wide axis; at least 3 pt so a one-Ang Vaar stays visible.
    static func span(_ m: Mark, width: CGFloat) -> CGRect {
        let n = CGFloat(angs.count - 1)
        let x0 = CGFloat(m.firstAng - angs.lowerBound) / n * width
        let x1 = CGFloat(m.lastAng - angs.lowerBound) / n * width
        let w = max(x1 - x0, 3)
        return CGRect(x: min(x0, width - w), y: 0, width: w, height: 1)
    }

    /// The mark nearest an x position (inside a span wins; otherwise the closest edge).
    static func nearest(to x: CGFloat, width: CGFloat, in marks: [Mark]) -> Int? {
        marks.min { a, b in
            func d(_ m: Mark) -> CGFloat {
                let r = span(m, width: width)
                return x < r.minX ? r.minX - x : (x > r.maxX ? x - r.maxX : 0)
            }
            return d(a) < d(b)
        }?.id
    }
}
