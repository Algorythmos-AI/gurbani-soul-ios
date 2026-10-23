import SwiftUI

/// The Saroop Ribbon, the Index's map of the whole Granth: all 1,430 Angs as one strip, every
/// bani and raag drawn in proportion to the Angs it fills, so the saroop's shape is visible at
/// once — Gauri's 196 Angs, Jaijavanti's 2, the thirteen opening Angs, the closing saloks and
/// Raagmala. Slide a finger along it: a loupe names
/// the work and the Ang under it (a light tick at each new work), and lifting opens that work.
///
/// Gold pins mark where the Index's major compositions begin; a small ink marker shows the Ang the
/// reader last read. VoiceOver sees ONE adjustable element that steps work by work.
struct SaroopRibbon: View {
    let layout: RibbonLayout
    let raagCount: Int
    /// Angs to pin (the major compositions' first Angs).
    var pins: [Int] = []
    /// The last-read Ang, or nil to hide the marker.
    var hereAng: Int?
    /// Called when a finger lifts (or VoiceOver activates) over a work, with the Ang under it.
    let open: (RibbonLayout.Segment, Int) -> Void

    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Strip position under the finger, in Ang units; nil when not touching. Gesture state, so a
    /// touch the scroll view takes over (or the system cancels) can never leave the loupe stuck.
    @GestureState private var scrubX: Double?
    /// The work VoiceOver's adjustable action is on.
    @State private var focusIndex: Int?

    private let barHeight: CGFloat = 24
    private var stripHeight: CGFloat { barHeight + 14 }
    /// Grows with Dynamic Type so the loupe's Gurmukhi and caption never clip.
    @ScaledMetric(relativeTo: .caption) private var loupeHeight: CGFloat = 52

    private var scrubSegment: RibbonLayout.Segment? { scrubX.flatMap { layout.segment(at: $0) } }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(alignment: .firstTextBaseline) {
                SectionEyebrow(text: "The saroop", symbol: "book.pages")
                Spacer(minLength: Theme.Space.s)
                Text("\(GranthMap.totalAngs.formatted()) Angs")
                    .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
            }
            GeometryReader { geo in
                let w = geo.size.width
                VStack(spacing: 4) {
                    loupe(width: w)
                        .frame(height: loupeHeight)
                    // Only the strip takes the finger: the loupe and hint above it are not targets.
                    strip(width: w)
                        .frame(height: stripHeight)   // pins above, here-marker below
                        .contentShape(Rectangle())
                        .gesture(scrub(width: w))
                        .sensoryFeedback(.selection, trigger: scrubSegment?.id)
                }
            }
            .frame(height: loupeHeight + 4 + stripHeight)
            legend
        }
        .padding(Theme.Space.l)
        .background(Ink.card, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(Ink.hairline))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Map of the Granth")
        .accessibilityValue(spokenValue)
        .accessibilityHint("Swipe up or down to move through the Granth, raag by raag. Double-tap to open.")
        .accessibilityAdjustableAction { dir in
            let i = currentFocus
            switch dir {
            case .increment: focusIndex = max(0, min(i + 1, layout.segments.count - 1))
            case .decrement: focusIndex = max(i - 1, 0)
            @unknown default: break
            }
        }
        .accessibilityAction {
            guard layout.segments.indices.contains(currentFocus) else { return }
            let s = layout.segments[currentFocus]
            open(s, s.firstAng)
        }
        .accessibilityIdentifier("index_ribbon")
    }

    // MARK: scrubbing

    /// Slide to look, lift to open. A mostly-vertical drag is a page scroll, not a scrub (no loupe,
    /// nothing opens), and lifting well off the strip cancels.
    private func scrub(width w: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($scrubX) { g, state, _ in
                guard w > 0, Self.isScrub(g.translation) else { state = nil; return }
                state = min(max(Double(g.location.x / w) * layout.length, 0), layout.length)
            }
            .onEnded { g in
                guard w > 0, Self.isScrub(g.translation),
                      Self.liftsOnStrip(y: g.location.y, height: stripHeight) else { return }
                let x = min(max(Double(g.location.x / w) * layout.length, 0), layout.length)
                if let s = layout.segment(at: x) { open(s, s.ang(at: x)) }
            }
    }

    /// Horizontal enough to be a scrub: vertical travel within 24 pt, or less than the horizontal.
    static func isScrub(_ t: CGSize) -> Bool { abs(t.height) <= max(24, abs(t.width)) }

    /// The finger lifted on, or close to, the strip (32 pt of slack above and below).
    static func liftsOnStrip(y: CGFloat, height: CGFloat) -> Bool { y >= -32 && y <= height + 32 }

    // MARK: VoiceOver

    /// Starts on the work holding the last-read Ang, else the first raag.
    private var currentFocus: Int {
        if let focusIndex, layout.segments.indices.contains(focusIndex) { return focusIndex }
        if let a = hereAng, let i = layout.segments.firstIndex(where: { ($0.firstAng...$0.lastAng).contains(a) }) { return i }
        return layout.segments.firstIndex { $0.movement == .raags } ?? 0
    }

    private var spokenValue: String {
        guard layout.segments.indices.contains(currentFocus) else { return "" }
        let s = layout.segments[currentFocus]
        var v = RibbonLayout.spokenLabel(s, raagCount: raagCount)
        if let a = hereAng, (s.firstAng...s.lastAng).contains(a) { v += ". You last read Ang \(String(a)) here" }
        return v
    }

    // MARK: drawing

    private func strip(width w: CGFloat) -> some View {
        let active = scrubSegment?.id
        return Canvas { ctx, size in
            guard layout.length > 0 else { return }
            let scale = size.width / CGFloat(layout.length)
            let barY: CGFloat = 7
            let bar = CGRect(x: 0, y: barY, width: size.width, height: barHeight)
            let clip = Path(roundedRect: bar, cornerRadius: 6)
            ctx.drawLayer { layer in
                layer.clip(to: clip)
                var raagIndex = 0
                for s in layout.segments {
                    let r = CGRect(x: CGFloat(s.x0) * scale, y: barY,
                                   width: max(CGFloat(s.width) * scale, 0.5), height: barHeight)
                    let fill: Color
                    if s.id == active {
                        fill = palette.accent
                    } else if s.movement == .raags {
                        fill = palette.accent.opacity(raagIndex.isMultiple(of: 2) ? 0.42 : 0.24)
                        raagIndex += 1
                    } else {
                        fill = Color.primary.opacity(0.30)
                    }
                    layer.fill(Path(r), with: .color(fill))
                    // a hairline between works, where there is room to see it
                    if r.width > 2 {
                        layer.fill(Path(CGRect(x: r.maxX - 0.5, y: barY, width: 0.5, height: barHeight)),
                                   with: .color(Ink.card))
                    }
                }
            }
            ctx.stroke(clip, with: .color(Ink.hairline), lineWidth: 0.5)
            // pins: where the major compositions begin
            for a in pins {
                guard let x = layout.x(forAng: a) else { continue }
                let cx = CGFloat(x) * scale
                ctx.fill(Path(ellipseIn: CGRect(x: cx - 2.5, y: 0, width: 5, height: 5)), with: .color(palette.accent))
            }
            // the last-read Ang
            if let a = hereAng, let x = layout.x(forAng: a) {
                let cx = CGFloat(x) * scale
                var tri = Path()
                tri.move(to: CGPoint(x: cx, y: barY + barHeight + 1))
                tri.addLine(to: CGPoint(x: cx - 4, y: barY + barHeight + 7))
                tri.addLine(to: CGPoint(x: cx + 4, y: barY + barHeight + 7))
                tri.closeSubpath()
                ctx.fill(tri, with: .color(.primary))
            }
            // the finger
            if let x = scrubX {
                let cx = CGFloat(x) * scale
                ctx.fill(Path(CGRect(x: cx - 1, y: barY - 3, width: 2, height: barHeight + 6)), with: .color(.primary))
            }
        }
        .frame(width: w)
        .accessibilityHidden(true)
    }

    /// The loupe: what is under the finger. At rest, a hint (and the last-read Ang, if any).
    private func loupe(width w: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            if let x = scrubX, let s = scrubSegment {
                let ang = s.ang(at: x)
                let bubbleW = min(w, 220)
                let cx = CGFloat(x / max(layout.length, 1)) * w
                let left = min(max(cx - bubbleW / 2, 0), w - bubbleW)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                        GurmukhiText(verbatim: s.name, size: 17).lineLimit(1)
                        Spacer(minLength: 0)
                        Text("Ang \(String(ang))").font(.caption.weight(.semibold)).monospacedDigit()
                    }
                    Text(s.english ?? (s.movement == .raags ? "Raag" : " "))
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                .padding(.horizontal, Theme.Space.m).padding(.vertical, 6)
                .frame(width: bubbleW, alignment: .leading)
                .background(Ink.raised, in: RoundedRectangle(cornerRadius: Theme.Radius.chip))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.chip).strokeBorder(palette.accent, lineWidth: 1))
                .offset(x: left)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96, anchor: .bottom)))
            } else {
                HStack(spacing: Theme.Space.xs) {
                    Image(systemName: "hand.draw").font(.caption)
                    Text(hereAng.map { "Slide along the Granth · you last read Ang \(String($0))" }
                         ?? "Slide along the Granth to find any raag or bani")
                        .font(.caption)
                        .lineLimit(2)
                }
                .foregroundStyle(.secondary)
                .frame(width: w, height: loupeHeight, alignment: .bottomLeading)
                .transition(.opacity)
            }
        }
        .frame(width: w, height: loupeHeight, alignment: .bottomLeading)
        .animation(reduceMotion ? nil : Motion.gentle, value: scrubX == nil)
    }

    private var legend: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Theme.Space.m) { legendItems }
            VStack(alignment: .leading, spacing: 4) { legendItems }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder private var legendItems: some View {
        swatch(palette.accent.opacity(0.42), "The \(String(raagCount)) raags")
        swatch(Color.primary.opacity(0.30), "Banis before and after")
        if !pins.isEmpty {
            HStack(spacing: 4) {
                Circle().fill(palette.accent).frame(width: 5, height: 5)
                Text("Compositions").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }

    private func swatch(_ c: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(c).frame(width: 12, height: 8)
            Text(label).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
    }
}
