import SwiftUI
import GurbaniPahar

/// The Raag Clock face, drawn once for the app and every widget family (compiled into both
/// targets; no `TimingClock`/DB dependency — the widget links only `GurbaniPahar`).
///
/// Geometry contract (since 1.5.0): ONE 12-hour scale for the ring and the analog face — 12 at
/// the top, 3 right, 6 bottom, 9 left, 30° per hour (`Pahar.faceDegrees`), so every boundary,
/// sunrise/sunset mark and the "now" point sit exactly where the hour hand points at that time.
/// The ring shows the half of the day the hour hand is in (`Pahar.HalfDay`, 12 AM–12 PM or
/// 12 PM–12 AM) with every watch clipped to it, and says which half. From the centre outwards:
///   hollow (the 12-hour face, or the half's name when there is no face) · pahar band
///   `inner…outer` (the watches in this half, raag beads, current-watch glow) · hour ring
///   (12 ticks, a major every 3 h, on the dial's own hours) · labels (the half, then 3 · 6 · 9).
/// Colours are brand tokens only (brand book §3): the current watch is `accentFill` with an
/// `accent` stroke, the hand is `accent`, day watches sit on `accentDeep`, night on `Ink.info`;
/// pahar 7 stays faint on purpose — its silence is content.
struct PaharDialModel: Equatable {
    /// Windows for pahars 1…8 (index 0 = pahar 1), fixed or solar.
    var windows: [Pahar.Window]
    var current: Int
    var minutesNow: Int
    /// Present only when solar mode is live (draws the sunrise/sunset marks).
    var sunrise: Int? = nil
    var sunset: Int? = nil
    /// Primary raag count per pahar → beads along the arc.
    var beads: [Int: Int] = [:]

    /// The half of the day the face shows — the one the hour hand is in.
    var half: Pahar.HalfDay { Pahar.HalfDay(minute: minutesNow) }

    static func fixed(current: Int, minutesNow: Int, beads: [Int: Int] = [:]) -> PaharDialModel {
        PaharDialModel(windows: (1...8).map { Pahar.window($0) }, current: current,
                       minutesNow: minutesNow, beads: beads)
    }

    static func solar(sunrise: Int, sunset: Int, current: Int, minutesNow: Int, beads: [Int: Int] = [:]) -> PaharDialModel {
        PaharDialModel(windows: (1...8).map { Pahar.solarWindow($0, sunrise: sunrise, sunset: sunset) },
                       current: current, minutesNow: minutesNow, sunrise: sunrise, sunset: sunset, beads: beads)
    }
}

enum DialStyle: Equatable {
    /// The app and the large widget: hour ring, numerals, beads, solar marks.
    case full
    /// Small/medium widgets: ticks only, no numerals.
    case compact
    /// Lock-screen accessories and tinted rendering: strokes in `.primary`, no fills.
    case mono
}

/// Radii for one dial size — shared by the renderer, the hit-test and the hollow overlay.
struct DialMetrics {
    let size: CGFloat
    let center: CGPoint
    let outer: CGFloat
    let inner: CGFloat
    let style: DialStyle

    init(size: CGFloat, center: CGPoint? = nil, style: DialStyle) {
        self.size = size
        self.center = center ?? CGPoint(x: size / 2, y: size / 2)
        self.style = style
        let inset: CGFloat = switch style {
        case .full: max(34, size * 0.11)       // room for ticks + numerals (never clipped)
        case .compact: 6
        case .mono: 4
        }
        outer = max(size / 2 - inset, 8)
        inner = outer * (style == .mono ? 0.66 : 0.62)
    }

    /// Diameter available to the hollow readout.
    var hollowWidth: CGFloat { max(inner * 2 - 10, 0) }
    /// Radius of the analog face drawn in the hollow.
    var faceRadius: CGFloat { inner - (style == .full ? 7 : 3) }
    var tickInner: CGFloat { outer + 3 }
    var tickMinor: CGFloat { outer + 7 }
    var tickMajor: CGFloat { outer + 10 }
    var numeralRadius: CGFloat { outer + 19 }

    /// minutes → screen angle on the 12-hour face (12 at the top, clockwise): the hour hand's
    /// angle at that wall-clock minute, so 06:00 and 18:00 both point at the 6.
    static func angle(_ m: Int) -> Angle { angle(Double(m)) }
    static func angle(_ m: Double) -> Angle { .degrees(Pahar.faceDegrees(m) - 90) }

    func point(minute m: Double, radius r: CGFloat) -> CGPoint {
        let a = Self.angle(m).radians
        return CGPoint(x: center.x + CGFloat(cos(a)) * r, y: center.y + CGFloat(sin(a)) * r)
    }

    /// Inverse of the geometry for taps: a point inside the pahar band → minute-of-day within
    /// the half the face shows.
    func minute(at pt: CGPoint, half: Pahar.HalfDay) -> Int? {
        let dx = pt.x - center.x, dy = pt.y - center.y
        let r = sqrt(dx * dx + dy * dy)
        guard r >= inner * 0.8, r <= outer + 12 else { return nil }
        var deg = atan2(Double(dy), Double(dx)) * 180 / .pi + 90       // 0° = 12 o'clock
        deg = (deg.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        return half.start + Int(deg / 360 * 720) % 720
    }
}

struct PaharDialRenderer: View {
    let model: PaharDialModel
    var style: DialStyle = .full
    var palette: AccentPalette = .brandDefault
    /// The ring's labels (`PaharFormat.dialNumerals(half:)`): the half's name at the 12, then
    /// the 3 · 6 · 9 hours of that half; ignored unless `style == .full`.
    var numerals: [(minute: Int, label: String)] = []
    /// Tinted/vibrant widget rendering: everything becomes `.primary` strokes.
    var monochrome = false
    /// Draw the classic 12-hour analog face (numerals 1–12; the caller adds `ClockHandsLayer`)
    /// in the hollow, so the modern clock and the eight Sikhi watches read on one face. Off for
    /// `.mono`. With a face, its hour hand is the one "now" mark; without one the ring draws a
    /// needle at the same angle instead.
    var analogFace = true
    /// The date shown by the face's day/date complication (nil hides it).
    var faceDate: Date? = nil
    /// The zone `faceDate` is read in (a widget entry's own, so its date matches its ring).
    var faceTimeZone: TimeZone = .current

    private var mono: Bool { monochrome || style == .mono }

    var body: some View {
        Canvas(rendersAsynchronously: false) { ctx, size in
            let m = DialMetrics(size: min(size.width, size.height),
                                center: CGPoint(x: size.width / 2, y: size.height / 2), style: style)
            drawHourRing(&ctx, m)
            drawWatches(&ctx, m)
            drawSolarMarks(&ctx, m)
            drawNumerals(&ctx, m)
            if hasFace(m) { drawAnalogFace(&ctx, m) } else { drawHalfName(&ctx, m); drawHand(&ctx, m) }
        }
    }

    /// True when the hollow holds the 12-hour face — then the caller's hour hand marks now.
    private func hasFace(_ m: DialMetrics) -> Bool {
        analogFace && style != .mono && FaceMetrics(dial: m).drawsFace
    }

    /// Without a face (Explore's preview) the hollow names the half the ring shows.
    private func drawHalfName(_ ctx: inout GraphicsContext, _ m: DialMetrics) {
        guard style != .mono, m.inner > 18 else { return }
        let t = Text(PaharFormat.halfName(model.half))
            .font(.system(size: max(9, min(15, m.inner * 0.42)), weight: .semibold, design: .rounded))
            .foregroundStyle(Color.secondary)
        ctx.draw(ctx.resolve(t), at: m.center, anchor: .center)
    }

    // MARK: the 12-hour face (static part — the hands live in `ClockHandsLayer`)

    /// The Apple-clean face in the hollow: a quiet surface, 60 rim ticks with bold hour bars,
    /// thin SF numerals 1–12 and a small day/date complication. No hands here — they are a
    /// separate layer so the app can sweep the seconds without redrawing the ring.
    private func drawAnalogFace(_ ctx: inout GraphicsContext, _ m: DialMetrics) {
        let f = FaceMetrics(dial: m)
        guard f.drawsFace else { return }
        let r = f.r, c = f.center
        let face = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        ctx.fill(face, with: .color(FaceMetrics.faceColor))
        ctx.stroke(face, with: .color(Ink.hairline), lineWidth: 1)
        // rim ticks: 60 minutes, the 12 hours as bold rounded bars
        for i in 0..<60 {
            let hourTick = i % 5 == 0
            if !hourTick && !f.showsMinuteTicks { continue }
            if (f.quartersOnly || f.handsOnly) && i % 15 != 0 { continue }
            let a = Double(i) / 60 * 2 * .pi - .pi / 2
            var t = Path()
            t.move(to: f.point(angle: a, radius: r - 2.5))
            t.addLine(to: f.point(angle: a, radius: r - (hourTick ? max(6, r * 0.085) : max(4, r * 0.05))))
            ctx.stroke(t, with: .color(Color.primary.opacity(hourTick ? 0.95 : 0.35)),
                       style: StrokeStyle(lineWidth: hourTick ? max(1.5, r * 0.028) : 0.75, lineCap: .round))
        }
        // numerals: thin and airy (SF), quarters only on a tiny face
        if !f.handsOnly {
            let weight: Font.Weight = r >= 110 ? .light : .regular
            for h in 1...12 where !f.quartersOnly || h % 3 == 0 {
                let a = Double(h) / 12 * 2 * .pi - .pi / 2
                let t = Text("\(h)").font(.system(size: f.numeralSize, weight: weight))
                    .monospacedDigit().foregroundStyle(Color.primary)
                ctx.draw(ctx.resolve(t), at: f.point(angle: a, radius: f.numeralRadius), anchor: .center)
            }
        }
        // day/date complication between the hub and the "3"
        if f.showsDate, let faceDate {
            let (weekday, day) = PaharFormat.weekdayDay(faceDate, tz: faceTimeZone)
            let size = max(9, r * 0.105)
            let t = Text(weekday + " ").font(.system(size: size, weight: .medium)).foregroundStyle(Color.secondary)
                + Text(day).font(.system(size: size, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(mono ? Color.primary : palette.accentText)
            ctx.draw(ctx.resolve(t), at: CGPoint(x: c.x + r * 0.40, y: c.y), anchor: .center)
        }
    }

    // MARK: layers

    /// The band between two minutes of one half. The sweep is the span's own length (720 min =
    /// 360°), never an end angle, so a span ending on the 12 (noon or midnight) closes cleanly.
    private func wedge(_ s: Pahar.Span, _ m: DialMetrics) -> Path {
        let a0 = DialMetrics.angle(s.start)
        let a1 = Angle.degrees(a0.degrees + Double(s.minutes) / 2)
        return Path { p in
            p.addArc(center: m.center, radius: m.outer, startAngle: a0, endAngle: a1, clockwise: false)
            p.addArc(center: m.center, radius: m.inner, startAngle: a1, endAngle: a0, clockwise: true)
            p.closeSubpath()
        }
    }

    private func drawWatches(_ ctx: inout GraphicsContext, _ m: DialMetrics) {
        guard model.windows.count == 8 else { return }
        let half = model.half
        for p in 1...8 {
            let w = model.windows[p - 1]
            let spans = Pahar.clip(w, to: half)
            guard !spans.isEmpty else { continue }      // this watch lies in the other half
            var path = Path()
            for s in spans { path.addPath(wedge(s, m)) }
            let start = w.start, end = w.end <= w.start ? w.end + 1440 : w.end
            let isCurrent = p == model.current
            let day = p <= 4
            if mono {
                ctx.fill(path, with: .color(.primary.opacity(isCurrent ? 0.55 : (p == 7 ? 0.06 : 0.16))))
                ctx.stroke(path, with: .color(.primary.opacity(isCurrent ? 0.95 : 0.35)), lineWidth: isCurrent ? 1.5 : 0.5)
            } else {
                let base: Color = day ? palette.accentDeep : Ink.info
                var fill = base.opacity(day ? 0.42 : 0.30)
                if p == 7 { fill = base.opacity(0.14) }
                if isCurrent { fill = palette.accentFill.opacity(0.92) }
                ctx.fill(path, with: .color(fill))
                // hairline between watches so the face reads as eight distinct wedges
                ctx.stroke(path, with: .color(Ink.hairline), lineWidth: 0.5)
                if isCurrent { ctx.stroke(path, with: .color(palette.accent), lineWidth: 2) }
            }
            // raag beads along the arc's middle radius, spaced over the WHOLE watch; a watch cut
            // at noon or midnight shows only the beads that fall in this half
            let n = min(model.beads[p] ?? 0, 8)
            if n > 0 {
                let midR = (m.outer + m.inner) / 2
                let span = Double(end - start)
                let r: CGFloat = style == .full ? 2.6 : 1.8
                for i in 0..<n {
                    let t = (Double(i) + 1) / (Double(n) + 1)
                    let bm = Double(start) + span * t
                    guard Pahar.isIn(Int(bm.rounded(.down)) % 1440, half: half) else { continue }
                    let pt = m.point(minute: bm, radius: midR)
                    let bead = Path(ellipseIn: CGRect(x: pt.x - r, y: pt.y - r, width: r * 2, height: r * 2))
                    let c: Color = mono ? .primary : (isCurrent ? palette.onAccent : .white)
                    ctx.fill(bead, with: .color(c.opacity(isCurrent ? 0.95 : 0.85)))
                }
            }
        }
    }

    /// Twelve hour ticks on the dial's own hours; the 12 · 3 · 6 · 9 are major. An hour that
    /// carries a label gives its tick up to the label (they collided at the 3 and the 9).
    private func drawHourRing(_ ctx: inout GraphicsContext, _ m: DialMetrics) {
        guard style != .mono else { return }
        let labelled = Set(drawsLabels(m) ? numerals.map { Int(Pahar.faceDegrees($0.minute).rounded()) / 30 } : [])
        for h in 0..<12 where !labelled.contains(h) {
            let major = h % 3 == 0
            let a = m.point(minute: Double(h * 60), radius: m.tickInner)
            let b = m.point(minute: Double(h * 60), radius: major ? m.tickMajor : m.tickMinor)
            var tick = Path(); tick.move(to: a); tick.addLine(to: b)
            let c: Color = mono ? .primary.opacity(major ? 0.8 : 0.35)
                                : (major ? palette.accent : Ink.hairline)
            ctx.stroke(tick, with: .color(c), style: StrokeStyle(lineWidth: major ? 2 : 1, lineCap: .round))
        }
    }

    private func drawsLabels(_ m: DialMetrics) -> Bool { style == .full && m.inner > 40 }

    /// Each label sits on its hour's angle with its inner edge just outside the band — measured,
    /// so "9 AM" at the side clears the band and the canvas edge alike.
    private func drawNumerals(_ ctx: inout GraphicsContext, _ m: DialMetrics) {
        guard drawsLabels(m) else { return }
        for n in numerals {
            // the label on the 12 names the half (AM / PM) and reads first; the hours recede
            let top = n.minute % 720 == 0
            let text = Text(n.label).font(.system(size: top ? 11 : 10, weight: top ? .bold : .semibold, design: .rounded))
                .monospacedDigit().foregroundStyle(mono || top ? Color.primary : Color.secondary)
            let resolved = ctx.resolve(text)
            let size = resolved.measure(in: CGSize(width: 200, height: 60))
            let a = DialMetrics.angle(n.minute).radians
            let r = m.tickInner + 2 + abs(CGFloat(cos(a))) * size.width / 2 + abs(CGFloat(sin(a))) * size.height / 2
            ctx.draw(resolved, at: m.point(minute: Double(n.minute), radius: r), anchor: .center)
        }
    }

    /// Sunrise/sunset badges sit INSIDE the band on the day/night seam (never on the hour
    /// ring, where they would collide with the labels) — only the one in this half.
    private func drawSolarMarks(_ ctx: inout GraphicsContext, _ m: DialMetrics) {
        guard style != .compact, let sr = model.sunrise, let ss = model.sunset else { return }
        let r: CGFloat = style == .full ? 8 : 5.5
        for (minute, symbol) in [(sr, "sunrise.fill"), (ss, "sunset.fill")] where Pahar.isIn(minute, half: model.half) {
            let pt = m.point(minute: Double(minute), radius: (m.outer + m.inner) / 2)
            let badge = Path(ellipseIn: CGRect(x: pt.x - r, y: pt.y - r, width: r * 2, height: r * 2))
            if mono {
                ctx.fill(badge, with: .color(.primary.opacity(0.9)))
            } else {
                ctx.fill(badge, with: .color(Ink.card))
                ctx.stroke(badge, with: .color(palette.accent), lineWidth: 1)
            }
            let glyph = Text(Image(systemName: symbol)).font(.system(size: style == .full ? 8 : 6, weight: .bold))
                .foregroundStyle(mono ? Color.black : palette.accent)
            ctx.draw(ctx.resolve(glyph), at: pt, anchor: .center)
        }
    }

    /// The "now" pointer for a ring with no face (Explore, lock screen) — at the hour hand's
    /// angle, in the pahar band only. A pip at the inner edge marks where it starts. With a
    /// face, the hour hand is the one "now" mark and this is not drawn.
    private func drawHand(_ ctx: inout GraphicsContext, _ m: DialMetrics) {
        let now = Double(model.minutesNow)
        let tip = m.point(minute: now, radius: m.outer + (style == .full ? 4 : 2))
        let root = m.point(minute: now, radius: m.inner - (style == .full ? 5 : 3))
        var hand = Path(); hand.move(to: root); hand.addLine(to: tip)
        let c: Color = mono ? .primary : palette.accent
        // a soft halo under the hand so it stays legible over the gold current wedge
        if !mono {
            ctx.stroke(hand, with: .color(Ink.canvas.opacity(0.9)),
                       style: StrokeStyle(lineWidth: style == .full ? 6 : 4, lineCap: .round))
        }
        ctx.stroke(hand, with: .color(c), style: StrokeStyle(lineWidth: style == .full ? 2.5 : 1.8, lineCap: .round))
        let pip: CGFloat = style == .full ? 4 : 2.5
        ctx.fill(Path(ellipseIn: CGRect(x: root.x - pip, y: root.y - pip, width: pip * 2, height: pip * 2)),
                 with: .color(c))
    }
}
