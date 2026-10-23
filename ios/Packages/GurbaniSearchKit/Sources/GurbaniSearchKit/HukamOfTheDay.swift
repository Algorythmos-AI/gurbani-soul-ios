import Foundation

/// The Hukam of the day: one verse for a whole calendar day, drawn the way the app's Hukam draw
/// is (every verse line of the Granth equally likely, then expanded to its structural unit by
/// `hukamUnit(seed:)`), but seeded by the date instead of the clock. The same date always gives
/// the same verse on the same corpus, on every device and in every time zone; the reader's
/// local midnight is what moves it to the next one.
///
/// Pure arithmetic, so the widget timeline and the tests can rely on it without a database.
/// This is not the Darbar Sahib Hukamnama and the copy that shows it must never say so.
public enum HukamOfTheDay {

    /// Days since 1970-01-01 for a civil (proleptic Gregorian) date, with no time zone involved:
    /// the reader's local calendar date in, one integer out. Howard Hinnant's days_from_civil.
    public static func dayNumber(year: Int, month: Int, day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400                                        // [0, 399]
        let mp = (month + 9) % 12                                      // March = 0
        let doy = (153 * mp + 2) / 5 + day - 1                         // [0, 365]
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy                // [0, 146096]
        return era * 146_097 + doe - 719_468
    }

    /// The day number of `date` as the reader's calendar sees it.
    public static func dayNumber(of date: Date, calendar: Calendar = .current) -> Int {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return dayNumber(year: c.year ?? 1970, month: c.month ?? 1, day: c.day ?? 1)
    }

    /// Which verse line (0-based, in reading order among the non-header lines) a day draws,
    /// out of `count`. SplitMix64 of the day number: consecutive days land far apart.
    public static func lineIndex(day: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return Int(splitMix64(UInt64(bitPattern: Int64(day)) ^ salt) % UInt64(count))
    }

    /// "HUKAM" in ASCII: keeps this draw independent of any other SplitMix64 use of a day number.
    static let salt: UInt64 = 0x48_55_4B_41_4D

    static func splitMix64(_ seed: UInt64) -> UInt64 {
        var z = seed &+ 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
