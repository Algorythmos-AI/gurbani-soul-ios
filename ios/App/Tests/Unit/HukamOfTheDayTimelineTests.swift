import XCTest
import GurbaniDB
import GurbaniSearchKit
@testable import SGGS

/// The Hukam of the day widget's timeline: today's verse at once, each later day's at that day's
/// local midnight (DST included), never a later day early and never an earlier day as today's.
/// And the snapshot that carries two weeks of verses stays well inside the widget's budget.
final class HukamOfTheDayTimelineTests: XCTestCase {

    private let la = TimeZone(identifier: "America/Los_Angeles")!

    private func calendar(_ tz: TimeZone) -> Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = tz; return c
    }

    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int, tz: TimeZone) -> Date {
        calendar(tz).date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    private func day(_ key: String, ang: Int) -> HukamDay {
        HukamDay(date: key, gurmukhi: "ਵਾਕ \(ang)", translit: "vaak \(ang)", ang: ang, compId: ang * 10, lineId: ang * 100)
    }

    private func snapshot(_ days: [HukamDay]?) -> WidgetSnapshot {
        WidgetSnapshot(generatedAt: .now, hukamGurmukhi: "ਪੁਰਾਣਾ", hukamTranslit: "", hukamAng: 1, hukamCompId: 2,
                       paharRaags: [:], hukamDays: days)
    }

    func testTodayAtOnceThenEachLocalMidnight() {
        let now = date(2026, 10, 23, 15, 20, tz: la)
        let snap = snapshot([day("2026-10-23", ang: 1), day("2026-10-24", ang: 2), day("2026-10-25", ang: 3)])
        let s = snap.hukamSchedule(from: now, calendar: calendar(la))
        XCTAssertEqual(s.map(\.day.ang), [1, 2, 3])
        XCTAssertEqual(s[0].date, now, "today's verse shows at once")
        XCTAssertEqual(s[1].date, date(2026, 10, 24, 0, 0, tz: la))
        XCTAssertEqual(s[2].date, date(2026, 10, 25, 0, 0, tz: la))
    }

    func testMidnightFollowsDaylightSaving() {
        // US clocks fall back at 02:00 on 1 November 2026: that day is 25 hours long
        let now = date(2026, 10, 31, 22, 0, tz: la)
        let snap = snapshot([day("2026-10-31", ang: 1), day("2026-11-01", ang: 2), day("2026-11-02", ang: 3)])
        let s = snap.hukamSchedule(from: now, calendar: calendar(la))
        XCTAssertEqual(s.count, 3)
        XCTAssertEqual(s[2].date.timeIntervalSince(s[1].date), 25 * 3600)
    }

    func testPastDaysAreSkippedAndOrderIsByDate() {
        let now = date(2026, 10, 25, 8, 0, tz: la)
        let snap = snapshot([day("2026-10-26", ang: 4), day("2026-10-23", ang: 1),
                             day("2026-10-25", ang: 3), day("2026-10-24", ang: 2)])
        XCTAssertEqual(snap.hukamSchedule(from: now, calendar: calendar(la)).map(\.day.ang), [3, 4])
    }

    func testNoVerseForTodayMeansNoSchedule() {
        // the app has not been opened since the last day it wrote: fall back, never show an old day as today's
        let now = date(2026, 11, 20, 9, 0, tz: la)
        XCTAssertTrue(snapshot([day("2026-10-23", ang: 1)]).hukamSchedule(from: now, calendar: calendar(la)).isEmpty)
        // nor a later day early when today's verse is missing
        let gap = snapshot([day("2026-11-21", ang: 2)])
        XCTAssertTrue(gap.hukamSchedule(from: now, calendar: calendar(la)).isEmpty)
        XCTAssertTrue(snapshot(nil).hukamSchedule(from: now, calendar: calendar(la)).isEmpty)
    }

    func testDayKeysAreTheReadersLocalDate() {
        let instant = Date(timeIntervalSince1970: 1_792_823_400)       // 2026-10-24 06:30 UTC
        XCTAssertEqual(WidgetSnapshot.dayKey(instant, calendar: calendar(la)), "2026-10-23")
        XCTAssertEqual(WidgetSnapshot.dayKey(instant, calendar: calendar(TimeZone(identifier: "Asia/Kolkata")!)), "2026-10-24")
        XCTAssertEqual(WidgetSnapshot.startOfDay(key: "2026-10-24", calendar: calendar(la)), date(2026, 10, 24, 0, 0, tz: la))
        XCTAssertNil(WidgetSnapshot.startOfDay(key: "not a day", calendar: calendar(la)))
        XCTAssertEqual(day("2026-10-23", ang: 13).url, URL(string: "sggs://shabad/130?line=1300"))
    }

    func testSnapshotWithoutDaysStillDecodes() throws {
        let legacy = """
        {"generatedAt":0,"hukamGurmukhi":"x","hukamTranslit":"","hukamAng":1,"hukamCompId":2,"paharRaags":{"4":["maajh"]}}
        """.data(using: .utf8)!
        let snap = try JSONDecoder().decode(WidgetSnapshot.self, from: legacy)
        XCTAssertNil(snap.hukamDays)
        XCTAssertTrue(snap.hukamSchedule(from: .now, calendar: .current).isEmpty)
    }

    /// Two weeks of real verses, drawn the way the app draws them, keep the snapshot far below
    /// the 50 KB the widget extension is promised; each is verbatim from the DB.
    func testTwoWeeksOfRealVersesStayInsideTheBudget() throws {
        guard let path = Bundle.main.url(forResource: "sggs-ios", withExtension: "sqlite")?.path
            ?? Bundle(for: Self.self).url(forResource: "sggs-ios", withExtension: "sqlite")?.path
        else { throw XCTSkip("bundled DB not found in host app") }
        let db = try SQLiteCandidateSource(path: path)
        let cal = calendar(la)
        let start = cal.startOfDay(for: date(2026, 10, 23, 12, 0, tz: la))
        var days: [HukamDay] = []
        for offset in 0..<WidgetSnapshot.hukamDayCount {
            let d = try XCTUnwrap(cal.date(byAdding: .day, value: offset, to: start))
            let unit = try db.hukamUnit(seed: db.hukamOfTheDaySeed(day: HukamOfTheDay.dayNumber(of: d, calendar: cal)))
            let verse = try XCTUnwrap(unit.lines.first(where: { !$0.isHeader }))
            days.append(HukamDay(date: WidgetSnapshot.dayKey(d, calendar: cal), gurmukhi: verse.gurmukhi,
                                 translit: verse.translit, ang: verse.ang, compId: verse.compId, lineId: verse.id))
        }
        XCTAssertEqual(days.count, 14)
        XCTAssertEqual(days.first?.date, "2026-10-23")
        XCTAssertEqual(days.last?.date, "2026-11-05")
        let bytes = try JSONEncoder().encode(snapshot(days)).count
        XCTAssertLessThan(bytes, 25_000, "the snapshot with 14 days is \(bytes) bytes")
        let s = snapshot(days).hukamSchedule(from: date(2026, 10, 23, 12, 0, tz: la), calendar: cal)
        XCTAssertEqual(s.count, 14)
    }
}
