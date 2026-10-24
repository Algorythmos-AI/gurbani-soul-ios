import XCTest
import GurbaniSearchKit
@testable import SGGS

/// The Index's two promises about time and place: "Continue reading" only offers a position that
/// really resumes, and "In this hour" names the same pahar the Raag Clock shows.
@MainActor
final class IndexContinueAndHourTests: XCTestCase {

    private func summary(_ key: String, nLines: Int = 100) -> BaniSummary {
        BaniSummary(key: key, variant: "", isDefault: true, titleGm: "ਗ", titleEn: key, category: .popular,
                    orderNo: 100, nLines: nLines, nGroups: 1, hasExtra: false, estimatedMinutes: 10,
                    descriptionEn: nil, sourceLabel: "x")
    }
    private func line(_ seq: Int, lineId: Int) -> BaniLine {
        BaniLine(seq: seq, lineGroup: 1, gurmukhi: "x", translit: "", isHeader: false,
                 isRahao: false, markers: [], citation: .sggs(ang: 1, lineId: lineId, compId: 1))
    }

    /// A saved position whose anchor a corpus update removed opens at the top, so the card must
    /// not offer it — even though the stored `lastSeq` still gives a fraction above zero.
    func testContinueSkipsAPositionThatNoLongerResumes() {
        let store = NitnemProgressStore(url: FileManager.default.temporaryDirectory
            .appendingPathComponent("np-\(UUID().uuidString).json"))
        let lines = (1...50).map { line($0, lineId: 1000 + $0) }
        store.setPosition("stale", seq: 40, anchor: 999_999, nLines: 100)   // anchor gone, count changed
        store.setPosition("good", seq: 20, anchor: 1020, nLines: 50)
        store.setPosition("top", seq: 1, anchor: 1001, nLines: 50)          // lastSeq ≤ 1 never resumes
        let offered = [summary("stale", nLines: 50), summary("good", nLines: 50), summary("top", nLines: 50)]
        let resumes: (String) -> Bool = { store.resumeSeq(for: $0, lines: lines) != nil }
        XCTAssertFalse(resumes("stale")); XCTAssertTrue(resumes("good")); XCTAssertFalse(resumes("top"))
        let target = ContinueReading.target(
            offered: offered, isCompleted: { store.isCompleted($0) },
            fraction: { store.fraction(for: $0.id, total: $0.nLines) }, resumes: resumes,
            lastReadAt: { store.progress(for: $0)?.lastReadAt })
        XCTAssertEqual(target?.key, "good")
        XCTAssertNil(ContinueReading.target(offered: [summary("stale", nLines: 50)],
                                            isCompleted: { _ in false }, fraction: { _ in 0.8 },
                                            resumes: resumes, lastReadAt: { _ in Date() }),
                     "a stale position alone never makes a card")
    }

    /// "In this hour" reckons through `RaagNowTimeline` (the widget's math); the Raag Clock
    /// reckons the same instant as `Pahar.paharSolar` over `PaharFormat.usableSun(sunTimes)`,
    /// else `Pahar.paharFromMinutes`. Both must agree for every hour, fixed and solar.
    func testInThisHourMatchesTheRaagClock() {
        let tz = TimeZone(identifier: "Asia/Kolkata")!
        var cal = Calendar(identifier: .gregorian); cal.timeZone = tz
        let day = cal.date(from: DateComponents(year: 2026, month: 10, day: 24))!
        let places: [(lat: Double, lon: Double)?] = [nil, (31.63, 74.87), (51.5, -0.13), (-33.87, 151.21)]
        for place in places {
            for solar in [false, true] {
                let config = RaagClockConfig(solar: solar, lat: place?.lat, lon: place?.lon)
                for minute in stride(from: 0, to: 1440, by: 17) {
                    let date = cal.date(byAdding: .minute, value: minute, to: day)!
                    let index = RaagNowTimeline.entry(at: date, config: config, snapshot: nil, tz: tz).pahar
                    // the Raag Clock's own formula (ClockScreen.currentPahar)
                    let m = PaharFormat.minutesOfDay(date, tz: tz)
                    let sun = solar ? place.flatMap { PaharFormat.usableSun(PaharFormat.sunTimes(on: date, lat: $0.lat, lon: $0.lon, tz: tz)) } : nil
                    let clock = sun.map { Pahar.paharSolar(m, sunrise: $0.sunrise, sunset: $0.sunset) } ?? Pahar.paharFromMinutes(m)
                    XCTAssertEqual(index, clock, "solar=\(solar) place=\(String(describing: place)) minute=\(minute)")
                }
            }
        }
    }
}
