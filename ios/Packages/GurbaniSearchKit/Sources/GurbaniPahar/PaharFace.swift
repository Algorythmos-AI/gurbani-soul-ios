import Foundation

/// Where the eight watches sit on an ordinary 12-hour clock face — the ONE scale the Raag Clock
/// ring and its analog face share (owner decision, 2026-10-27: the pahar ring must never read
/// against the clock people already know).
///
/// The face is 12 at the top, 3 right, 6 bottom, 9 left: 30° per hour, the same angle the hour
/// hand points at. A 12-hour face can show only half a day, so the ring shows the half the hour
/// hand is in — 12 AM–12 PM or 12 PM–12 AM — with every watch clipped to it.
///
/// Presentation geometry only: not part of the pahar.js contract (`Pahar` stays the byte-parity
/// port). Integer minutes-since-midnight in, degrees clockwise from 12 o'clock out.
extension Pahar {

    /// The half of the day a 12-hour face is showing.
    public enum HalfDay: Sendable, Equatable {
        /// 00:00–12:00 (12 AM to 12 PM).
        case am
        /// 12:00–24:00 (12 PM to 12 AM).
        case pm

        /// The half containing minute-of-day `m` (wraps like the rest of `Pahar`). Noon is PM,
        /// midnight is AM — the instant the hour hand passes 12 the face turns to the next half.
        public init(minute m: Int) {
            self = ((m % 1440) + 1440) % 1440 < 720 ? .am : .pm
        }

        /// First minute of the half (0 or 720).
        public var start: Int { self == .am ? 0 : 720 }
        /// One past the last minute (720 or 1440).
        public var end: Int { start + 720 }
    }

    /// A clipped stretch of a watch inside one half: `half.start ≤ start < end ≤ half.end`.
    /// Unlike `Window` it never wraps, so `end` can be 720 or 1440.
    public struct Span: Sendable, Equatable {
        public let start: Int
        public let end: Int
        public init(start: Int, end: Int) { self.start = start; self.end = end }
        public var minutes: Int { end - start }
    }

    /// Degrees clockwise from 12 o'clock on a 12-hour face — exactly the hour hand's angle at
    /// that wall-clock minute (06:00 and 18:00 are both 180°; 08:18 is 249°). Result in [0, 360).
    public static func faceDegrees(_ m: Double) -> Double {
        let r = m.truncatingRemainder(dividingBy: 720)
        return (r < 0 ? r + 720 : r) / 720 * 360
    }

    public static func faceDegrees(_ m: Int) -> Double { faceDegrees(Double(m)) }

    /// The part(s) of a watch that fall inside `half`. A watch that crosses noon or midnight is
    /// cut there; one that wraps past midnight may leave a piece at both ends of the AM half
    /// (impossible for real pahars, which are under 12 h, but handled). A zero-length window is
    /// empty. Pieces come back in clock order.
    public static func clip(_ w: Window, to half: HalfDay) -> [Span] {
        func wrap(_ m: Int) -> Int { ((m % 1440) + 1440) % 1440 }
        let s = wrap(w.start), e0 = wrap(w.end)
        if s == e0 { return [] }
        let e = e0 < s ? e0 + 1440 : e0           // [s, e) with s < e ≤ s + 1440
        var out: [Span] = []
        for shift in [-1440, 0] {                 // the wrapped tail lands in tomorrow's AM half
            let a = max(s + shift, half.start), b = min(e + shift, half.end)
            if a < b { out.append(Span(start: a, end: b)) }
        }
        return out.sorted { $0.start < $1.start }
    }

    /// True when minute-of-day `m` lies in `half` (for sunrise/sunset marks).
    public static func isIn(_ m: Int, half: HalfDay) -> Bool { HalfDay(minute: m) == half }
}
