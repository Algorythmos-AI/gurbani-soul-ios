import SwiftUI
import GurbaniSearchKit

/// A voice's presence across the Granth's 1,430 Angs: one tick for every column of the strip
/// that holds at least one Ang carrying their verses. The mini form sits on a Lineage card; the
/// full form on the Voice page is tappable (a tick opens the nearest Ang that carries their Bani)
/// and, for VoiceOver, adjustable through those Angs. Drawn in one `Canvas` pass.
struct AngBarcode: View {
    let angs: AngSet
    let color: Color
    var height: CGFloat = 8
    /// A hairline where the raag sections end (Ang 1353) — the Voice page shows it.
    var marksRaagEnd = false
    /// Opens an Ang. Nil makes the strip decorative (the card's text carries the numbers).
    var onOpen: ((Int) -> Void)? = nil

    @State private var focusAng: Int?

    static let raagSectionsEnd = 1353

    var body: some View {
        GeometryReader { geo in
            Canvas { ctx, size in
                let track = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: min(3, size.height / 2))
                ctx.fill(track, with: .color(Ink.raised))
                let columns = max(1, Int(size.width / 1.5))
                let w = size.width / CGFloat(columns)
                for i in 0..<columns {
                    let lo = Int(Double(i) * Double(AngSet.angCount) / Double(columns)) + 1
                    let hi = Int(Double(i + 1) * Double(AngSet.angCount) / Double(columns))
                    if angs.intersects(lo...max(lo, hi)) {
                        ctx.fill(Path(CGRect(x: CGFloat(i) * w, y: 0, width: max(1, w * 0.8), height: size.height)),
                                 with: .color(color))
                    }
                }
                if marksRaagEnd {
                    let x = size.width * CGFloat(Self.raagSectionsEnd - 1) / CGFloat(AngSet.angCount)
                    ctx.fill(Path(CGRect(x: x, y: -2, width: 1, height: size.height + 4)), with: .color(.secondary.opacity(0.6)))
                }
                if let focusAng {
                    let x = size.width * CGFloat(focusAng - 1) / CGFloat(AngSet.angCount)
                    ctx.stroke(Path(CGRect(x: x - 2, y: -1, width: 4, height: size.height + 2)), with: .color(.primary), lineWidth: 1)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { location in
                guard let onOpen, geo.size.width > 0 else { return }
                let ang = Int((location.x / geo.size.width) * CGFloat(AngSet.angCount)) + 1
                if let target = angs.nearest(to: min(max(1, ang), AngSet.angCount)) { onOpen(target) }
            }
        }
        .frame(height: height)
        // A decorative strip (no `onOpen`, e.g. on a Lineage card) must not take touches: its tap
        // gesture swallowed taps meant for the card's Button, so a tap on the strip opened nothing.
        .allowsHitTesting(onOpen != nil)
        .modifier(BarcodeAccessibility(angs: angs, onOpen: onOpen, focusAng: $focusAng))
    }
}

/// VoiceOver: a decorative strip is hidden; an interactive one reads the span and steps through
/// the Angs that carry the voice (swipe up/down), opening the current one on double-tap.
private struct BarcodeAccessibility: ViewModifier {
    let angs: AngSet
    let onOpen: ((Int) -> Void)?
    @Binding var focusAng: Int?

    func body(content: Content) -> some View {
        if let onOpen {
            let list = angs.angs
            content
                .accessibilityElement()
                .accessibilityLabel("Their Bani across the Granth")
                .accessibilityValue(focusAng.map { "Ang \(String($0))" }
                    ?? "on \(list.count) of \(GranthAngs.count.formatted()) Angs, from Ang \(String(list.first ?? 0)) to Ang \(String(list.last ?? 0))")
                .accessibilityHint("Swipe up or down to move through those Angs; double-tap to open one.")
                .accessibilityAddTraits(.isButton)
                .accessibilityAdjustableAction { direction in
                    guard !list.isEmpty else { return }
                    let i = focusAng.flatMap { list.firstIndex(of: $0) }
                    switch direction {
                    case .increment: focusAng = list[min(list.count - 1, (i ?? -1) + 1)]
                    case .decrement: focusAng = list[max(0, (i ?? 1) - 1)]
                    @unknown default: break
                    }
                }
                .accessibilityAction { if let a = focusAng ?? list.first { onOpen(a) } }
        } else {
            content.accessibilityHidden(true)
        }
    }
}

/// The round medallion for a voice: the Mahala in Gurmukhi for a Guru ("ਮ: ੯"), else the first
/// letter of the Gurmukhi name (Latin initial until roster v2 brings it). Gurmukhi stays in ink,
/// in Sant Lipi; the ring carries the tradition colour. Decorative — the name beside it is read.
struct VoiceMedallionView: View {
    let contributor: Contributor
    var diameter: CGFloat = 36

    var body: some View {
        let m = VoiceMedallion.of(contributor)
        let k = contributor.kindColor
        Group {
            if m.isGurmukhi {
                Text(m.text)
                    .font(Brand.gurmukhi(diameter * (m.text.count > 2 ? 0.3 : 0.48)))
                    .foregroundStyle(.primary)
            } else {
                Text(m.text)
                    .font(.system(size: diameter * 0.42, weight: .semibold))
                    .foregroundStyle(.primary)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .padding(diameter * 0.12)
        .frame(width: diameter, height: diameter)
        .background(Circle().fill(k.opacity(0.16)))
        .overlay(Circle().strokeBorder(k.opacity(0.55), lineWidth: 1.5))
        .accessibilityHidden(true)
    }
}
