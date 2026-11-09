import Foundation

// The "Hukamnama · Sri Harmandir Sahib" widget's timeline — pure, so the app's unit tests prove it.
// Every decision is keyed to the AMRITSAR date (`AmritsarDate`), never the reader's local date,
// and the timeline carries its own state changes (Amritsar midnight, 05:30 and 14:00 IST), so a
// widget that WidgetKit never reloads still never presents an old verse as today's — the same
// principle as `HukamTimeline`'s closing entry. Separate from the Hukam of the day (G3 R6).

enum HukamnamaTimeline {
    /// SGPC stamps the Hukamnama 05:30 IST.
    static let publishMinuteIST = 5 * 60 + 30
    /// After 14:00 IST with nothing new, the day is "Delayed" (the card's rule, `HukamnamaHome`).
    static let lateMinuteIST = 14 * 60
    /// How far ahead the timeline lays out its own state changes.
    static let horizon: TimeInterval = 48 * 3600

    enum State: Equatable, Sendable {
        /// Today's (Amritsar) Hukamnama is published.
        case today(HukamnamaEntry)
        /// Before 05:30 IST: yesterday's Hukamnama is still the current one. Shown with its date,
        /// never called today's.
        case current(HukamnamaEntry)
        /// 05:30–14:00 IST with nothing new (or today's is pending): the last one, dimmed and dated.
        case notYet(previous: HukamnamaEntry?)
        /// Held for a check, or past 14:00 IST with nothing new.
        case delayed(previous: HukamnamaEntry?)
        /// No Hukamnama has ever reached this device.
        case empty
    }

    struct Entry: Equatable, Sendable {
        let date: Date
        let state: State
        /// False when the entry's corpus fingerprint differs from this app's: the widget then
        /// shows the Ang and date only, never the verse (the sheet re-proves the range itself).
        let verseShown: Bool
    }

    /// Minutes since Amritsar midnight at `now`.
    static func minuteIST(_ now: Date) -> Int {
        let c = AmritsarDate.calendar.dateComponents([.hour, .minute], from: now)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    /// The Amritsar date key the day before `key`.
    static func previousKey(_ key: String) -> String? {
        guard let d = AmritsarDate.startOfDay(key),
              let p = AmritsarDate.calendar.date(byAdding: .day, value: -1, to: d) else { return nil }
        return AmritsarDate.key(p)
    }

    /// The widget's state at `now`, from the store's entries (any order).
    static func state(entries: [HukamnamaEntry], now: Date) -> State {
        let today = AmritsarDate.key(now)
        let published = entries.filter { $0.status == .published && $0.amritsarDate <= today }
            .sorted { $0.amritsarDate > $1.amritsarDate }
        if let t = published.first, t.amritsarDate == today { return .today(t) }
        let previous = published.first   // strictly before today here
        if entries.isEmpty { return .empty }
        if entries.contains(where: { $0.amritsarDate == today && $0.status == .held }) {
            return .delayed(previous: previous)
        }
        let minute = minuteIST(now)
        if minute < publishMinuteIST, let p = previous, p.amritsarDate == previousKey(today) {
            return .current(p)
        }
        return minute >= lateMinuteIST ? .delayed(previous: previous) : .notYet(previous: previous)
    }

    /// The entry a state shows a verse from, if any.
    static func shown(_ state: State) -> HukamnamaEntry? {
        switch state {
        case .today(let e), .current(let e): return e
        case .notYet(let p), .delayed(let p): return p
        case .empty: return nil
        }
    }

    /// Whether `entry`'s verse may be shown on a device whose corpus fingerprint is `local`.
    /// A missing fingerprint on either side is not a mismatch (the server always sends one;
    /// the app writes its own at launch) — but a present, different one always is.
    static func verseAllowed(_ entry: HukamnamaEntry?, local: String?) -> Bool {
        guard let entry, let verse = entry.openingGurmukhi, !verse.isEmpty else { return false }
        if let remote = entry.scriptureSHA256, let local, remote != local { return false }
        return true
    }

    /// The instants after `now` (within `horizon`) at which the state can change on its own:
    /// Amritsar midnight, 05:30 and 14:00 IST.
    static func boundaries(after now: Date) -> [Date] {
        let cal = AmritsarDate.calendar
        let start = cal.startOfDay(for: now)
        var out: [Date] = []
        for day in 0...3 {
            guard let d = cal.date(byAdding: .day, value: day, to: start) else { continue }
            for minute in [0, publishMinuteIST, lateMinuteIST] {
                let t = d.addingTimeInterval(TimeInterval(minute * 60))
                if t > now && t <= now.addingTimeInterval(horizon) { out.append(t) }
            }
        }
        return out.sorted()
    }

    /// When to ask WidgetKit for a fresh timeline (the widget fetches `/today` then):
    /// - today's is published → 05:35 IST tomorrow;
    /// - before 05:35 IST → 05:35 IST;
    /// - 05:35–09:00 IST → every 20 minutes;
    /// - 09:00–12:00 IST → 12:00 IST;
    /// - after 12:00 IST → 05:35 IST tomorrow.
    /// About 15 reloads on a late morning, within WidgetKit's daily budget.
    static func refresh(now: Date, hasToday: Bool) -> Date {
        let cal = AmritsarDate.calendar
        let midnight = cal.startOfDay(for: now)
        func at(_ minute: Int, dayOffset: Int = 0) -> Date {
            (cal.date(byAdding: .day, value: dayOffset, to: midnight) ?? midnight)
                .addingTimeInterval(TimeInterval(minute * 60))
        }
        let first = publishMinuteIST + 5
        let tomorrow = at(first, dayOffset: 1)
        if hasToday { return tomorrow }
        let minute = minuteIST(now)
        switch minute {
        case ..<first: return at(first)
        case ..<(9 * 60): return min(now.addingTimeInterval(20 * 60), at(9 * 60))
        case ..<(12 * 60): return at(12 * 60)
        default: return tomorrow
        }
    }

    static func build(entries: [HukamnamaEntry], localScripture: String?, now: Date) -> (entries: [Entry], refresh: Date) {
        let dates = [now] + boundaries(after: now)
        let out = dates.map { d -> Entry in
            let s = state(entries: entries, now: d)
            return Entry(date: d, state: s, verseShown: verseAllowed(shown(s), local: localScripture))
        }
        let hasToday: Bool
        if case .today = out[0].state { hasToday = true } else { hasToday = false }
        return (out, refresh(now: now, hasToday: hasToday))
    }

    /// Whether the widget should ask the service for `/today` at `now` (nothing published for
    /// today yet, inside the publishing window). Outside it, the push and the app keep it current.
    static func shouldFetch(entries: [HukamnamaEntry], now: Date) -> Bool {
        if case .today = state(entries: entries, now: now) { return false }
        let minute = minuteIST(now)
        return minute >= publishMinuteIST && minute < lateMinuteIST
    }
}
