import XCTest
@testable import GurbaniSearchKit

/// The Hukam of the day's date maths: a civil date maps to one day number with no time zone in
/// play, and a day number maps to one verse line. Expected values were computed independently
/// (Python `date` arithmetic and a reference SplitMix64).
final class HukamOfTheDayTests: XCTestCase {

    func testDayNumberIsDaysSinceTheEpoch() {
        XCTAssertEqual(HukamOfTheDay.dayNumber(year: 1970, month: 1, day: 1), 0)
        XCTAssertEqual(HukamOfTheDay.dayNumber(year: 1969, month: 12, day: 31), -1)
        XCTAssertEqual(HukamOfTheDay.dayNumber(year: 2000, month: 3, day: 1), 11_017)
        XCTAssertEqual(HukamOfTheDay.dayNumber(year: 2024, month: 2, day: 29), 19_782)   // leap day
        XCTAssertEqual(HukamOfTheDay.dayNumber(year: 2026, month: 10, day: 23), 20_749)
        XCTAssertEqual(HukamOfTheDay.dayNumber(year: 2100, month: 2, day: 28), 47_540)   // 2100 is not a leap year
    }

    func testTheLocalCalendarDateDecidesTheDay() throws {
        // 23:30 in Los Angeles and noon the next day in Kolkata are the same instant, but
        // each reader's own date decides their Hukam.
        let instant = Date(timeIntervalSince1970: 1_792_823_400)       // 2026-10-24 06:30 UTC
        var la = Calendar(identifier: .gregorian); la.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        var kol = Calendar(identifier: .gregorian); kol.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Kolkata"))
        XCTAssertEqual(HukamOfTheDay.dayNumber(of: instant, calendar: la), 20_749)     // still the 23rd
        XCTAssertEqual(HukamOfTheDay.dayNumber(of: instant, calendar: kol), 20_750)    // already the 24th
    }

    func testLineIndexIsPinnedAndInRange() {
        XCTAssertEqual(HukamOfTheDay.lineIndex(day: 0, count: 1000), 170)
        XCTAssertEqual(HukamOfTheDay.lineIndex(day: 20_749, count: 1000), 140)
        XCTAssertEqual(HukamOfTheDay.lineIndex(day: 20_750, count: 1000), 298)
        XCTAssertEqual(HukamOfTheDay.lineIndex(day: 5, count: 0), 0)
        for day in -400...400 {
            let i = HukamOfTheDay.lineIndex(day: day, count: 53_000)
            XCTAssertTrue((0..<53_000).contains(i))
            XCTAssertEqual(i, HukamOfTheDay.lineIndex(day: day, count: 53_000), "the same day must draw the same line")
        }
    }

    func testDaysSpreadAcrossTheGranth() {
        // ten years of days over 100 buckets: every bucket is reached, none dominates
        var buckets = [Int](repeating: 0, count: 100)
        for day in 20_000..<23_650 { buckets[HukamOfTheDay.lineIndex(day: day, count: 100)] += 1 }
        XCTAssertGreaterThan(buckets.min() ?? 0, 10)
        XCTAssertLessThan(buckets.max() ?? .max, 70)
        // and a week never repeats a verse line
        let week = (20_749..<20_756).map { HukamOfTheDay.lineIndex(day: $0, count: 53_000) }
        XCTAssertEqual(Set(week).count, 7)
    }
}
