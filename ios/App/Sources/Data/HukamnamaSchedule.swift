import Foundation

/// One entry of the "At a time I choose" schedule the device sends: from `fromUTC` (Unix
/// seconds) on, the server delivers at `slotUTCMin` minutes past 00:00 UTC each day. The server
/// uses the last entry whose `fromUTC` has passed. A zone NAME is never sent — only the slots it
/// implies, so DST is covered without telling the server where the reader lives.
struct HukamnamaSlot: Codable, Equatable, Sendable {
    let fromUTC: Int
    let slotUTCMin: Int
    enum CodingKeys: String, CodingKey { case fromUTC = "from_utc", slotUTCMin = "slot_utc_min" }
}

/// Pure schedule math (no clock, no UserDefaults): unit-testable for any zone.
enum HukamnamaSchedule {
    /// How far ahead the schedule reaches.
    static let horizonDays = 365
    /// The app re-sends a fresh schedule once fewer than this many days of it remain.
    static let resendWhenDaysLeft = 60

    /// The 12-month slot schedule for a local wall-clock minute (0..<1440) in `timeZone`,
    /// starting at `from`. A new entry appears only when the UTC minute changes (a DST change, or
    /// a zone whose offset changes); a zone without DST (Kathmandu, +05:45) yields one entry.
    ///
    /// A later entry takes effect one minute after the previous day's delivery, so a change of
    /// offset never fires twice on one local day nor skips a day: it must be live before the next
    /// delivery whether that moves earlier or later in UTC.
    /// A local time that does not exist on a spring-forward day (02:30 in Sydney) is the next
    /// time that does, as the system clock would ring an alarm.
    static func build(localMinute: Int, timeZone: TimeZone, from: Date) -> [HukamnamaSlot] {
        let minute = min(max(localMinute, 0), 24 * 60 - 1)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = .gmt
        let start = cal.startOfDay(for: from)
        var out: [HukamnamaSlot] = []
        var previousFire: Date?
        for day in 0...horizonDays {
            guard let midnight = cal.date(byAdding: .day, value: day, to: start),
                  let fire = cal.nextDate(after: midnight.addingTimeInterval(-1),
                                          matching: DateComponents(hour: minute / 60, minute: minute % 60),
                                          matchingPolicy: .nextTime) else { continue }
            let c = utc.dateComponents([.hour, .minute], from: fire)
            let slot = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            if out.last?.slotUTCMin != slot {
                let effective: Int
                if out.isEmpty {
                    effective = Int(from.timeIntervalSince1970.rounded(.down) / 60) * 60
                } else {
                    effective = Int((previousFire ?? fire).timeIntervalSince1970) + 60
                }
                out.append(HukamnamaSlot(fromUTC: effective, slotUTCMin: slot))
            }
            previousFire = fire
        }
        return out
    }

    /// When the schedule built `from` should be rebuilt: it runs out within `resendWhenDaysLeft`.
    static func needsRebuild(builtFrom: Date, now: Date) -> Bool {
        now < builtFrom || now.timeIntervalSince(builtFrom) > Double(horizonDays - resendWhenDaysLeft) * 86_400
    }

    /// SGPC stamps the Hukamnama 05:30 AM (IST). The instant of 05:30 IST on the Amritsar date of
    /// `now` — what "Usually around … your time" is computed from, on the device.
    static func usualPublishInstant(now: Date) -> Date {
        let cal = AmritsarDate.calendar
        let day = cal.startOfDay(for: now)
        return cal.date(byAdding: .minute, value: 5 * 60 + 30, to: day) ?? day
    }

    /// "11:00 am" in the reader's zone and locale style.
    static func usualLocalTime(now: Date, timeZone: TimeZone = .current, locale: Locale = .current) -> String {
        let f = DateFormatter()
        f.locale = locale
        f.timeZone = timeZone
        f.dateStyle = .none
        f.timeStyle = .short
        return f.string(from: usualPublishInstant(now: now))
    }
}
