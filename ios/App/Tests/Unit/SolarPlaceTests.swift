import XCTest
import GurbaniPahar
@testable import SGGS

/// The travel notice's rule (`SolarPlace`): a saved solar place clearly off this phone's time zone
/// is named, never shown silently — and a place on its own zone's clock never is. Found
/// 2026-10-26: a Sydney fix on a London phone read "2nd pahar of night" at 1:30 PM.
final class SolarPlaceTests: XCTestCase {

    private let london = TimeZone(identifier: "Europe/London")!

    private let sydneyPlace = (lat: -33.87, lon: 151.21)
    private let londonPlace = (lat: 51.51, lon: -0.13)
    private let amritsar = (lat: 31.63, lon: 74.87)

    private func utc(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    private func away(_ p: (lat: Double, lon: Double), _ zone: String, _ date: Date) -> Bool {
        SolarPlace.isAway(lon: p.lon, tz: TimeZone(identifier: zone)!, at: date)
    }

    // MARK: the reported case

    func testLondonPhoneWithSydneyPlaceIsAway() {
        let at = utc(2026, 10, 26, 13, 30)                       // 1:30 PM in London (GMT)
        XCTAssertTrue(SolarPlace.isAway(lon: sydneyPlace.lon, tz: london, at: at))
        XCTAssertEqual(SolarPlace.leadHours(lon: sydneyPlace.lon, tz: london, at: at), 10.08, accuracy: 0.01)
        XCTAssertEqual(SolarPlace.leadPhrase(SolarPlace.leadHours(lon: sydneyPlace.lon, tz: london, at: at)),
                       "about 10 hours ahead of")
    }

    func testLondonPhoneWithLondonPlaceIsNotAway() {
        for at in [utc(2026, 1, 15, 12, 0), utc(2026, 7, 15, 12, 0), utc(2026, 10, 26, 13, 30)] {
            XCTAssertFalse(SolarPlace.isAway(lon: londonPlace.lon, tz: london, at: at))
        }
    }

    /// The other direction, and a near neighbour on the same clock.
    func testSydneyPhoneWithLondonPlaceIsAwayButNotWithItsOwn() {
        let at = utc(2026, 10, 26, 2, 30)
        XCTAssertTrue(away(londonPlace, "Australia/Sydney", at))
        XCTAssertEqual(SolarPlace.leadPhrase(SolarPlace.leadHours(lon: londonPlace.lon,
                                                                  tz: TimeZone(identifier: "Australia/Sydney")!, at: at)),
                       "about 10 hours behind")
        XCTAssertFalse(away(sydneyPlace, "Australia/Sydney", at))
        XCTAssertFalse(away((-37.81, 144.96), "Australia/Sydney", at), "Melbourne shares Sydney's clock")
    }

    // MARK: half-hour zones

    func testHalfHourAndQuarterHourZones() {
        let at = utc(2026, 10, 26, 8, 0)
        XCTAssertFalse(away(amritsar, "Asia/Kolkata", at), "Amritsar on IST (+5:30)")
        XCTAssertTrue(away(sydneyPlace, "Asia/Kolkata", at))
        XCTAssertTrue(away(londonPlace, "Asia/Kolkata", at))
        XCTAssertEqual(SolarPlace.leadHours(lon: londonPlace.lon, tz: TimeZone(identifier: "Asia/Kolkata")!, at: at),
                       -5.51, accuracy: 0.01)
        XCTAssertFalse(away((27.72, 85.32), "Asia/Kathmandu", at), "Kathmandu on +5:45")
        // Adelaide: +9:30 standard, +10:30 in its summer — its own place stays quiet in both
        let adelaide = (lat: -34.93, lon: 138.60)
        XCTAssertFalse(away(adelaide, "Australia/Adelaide", utc(2026, 1, 15, 2, 0)))
        XCTAssertFalse(away(adelaide, "Australia/Adelaide", utc(2026, 7, 15, 2, 0)))
        XCTAssertTrue(away(londonPlace, "Australia/Adelaide", utc(2026, 1, 15, 2, 0)))
    }

    // MARK: DST edges

    /// Daylight saving moves clocks, not the sky: the lead is the same either side of a change,
    /// so the notice can never appear or vanish at 1 AM on a DST night.
    func testDaylightSavingEdgesNeverFlipTheAnswer() {
        let edges: [(String, Date, Date)] = [
            ("Europe/London", utc(2026, 3, 29, 0, 59), utc(2026, 3, 29, 1, 1)),       // BST starts
            ("Europe/London", utc(2026, 10, 25, 0, 59), utc(2026, 10, 25, 1, 1)),     // BST ends
            ("Australia/Sydney", utc(2026, 10, 3, 15, 59), utc(2026, 10, 3, 16, 1)),  // AEDT starts
            ("Australia/Sydney", utc(2026, 4, 4, 15, 59), utc(2026, 4, 4, 16, 1)),    // AEDT ends
            ("Australia/Adelaide", utc(2026, 10, 3, 16, 29), utc(2026, 10, 3, 16, 31)),
        ]
        for (zone, before, after) in edges {
            let tz = TimeZone(identifier: zone)!
            XCTAssertNotEqual(tz.secondsFromGMT(for: before), tz.secondsFromGMT(for: after), "\(zone): not a DST edge")
            for place in [sydneyPlace, londonPlace, amritsar] {
                XCTAssertEqual(SolarPlace.leadHours(lon: place.lon, tz: tz, at: before),
                               SolarPlace.leadHours(lon: place.lon, tz: tz, at: after), accuracy: 1e-9,
                               "\(zone) \(place): the lead moved with the clock")
            }
        }
        XCTAssertFalse(away(londonPlace, "Europe/London", utc(2026, 3, 29, 1, 1)))
        XCTAssertTrue(away(sydneyPlace, "Europe/London", utc(2026, 3, 29, 1, 1)))
        XCTAssertFalse(away(sydneyPlace, "Australia/Sydney", utc(2026, 10, 3, 16, 1)))
    }

    /// Lisbon's longitude on Madrid's summer clock is 2.6 h off the wall clock but 1.6 h off
    /// Madrid's standard time: the same country's zone stays quiet in summer, as in winter.
    func testSummerTimeAloneNeverTriggersTheNotice() {
        let galicia = (lat: 42.88, lon: -8.54)                      // Santiago de Compostela, CET
        XCTAssertFalse(away(galicia, "Europe/Madrid", utc(2026, 7, 15, 12, 0)))
        XCTAssertFalse(away(galicia, "Europe/Madrid", utc(2026, 1, 15, 12, 0)))
        XCTAssertFalse(away((34.05, -118.24), "America/Los_Angeles", utc(2026, 7, 15, 19, 0)))
        XCTAssertTrue(away((34.05, -118.24), "America/New_York", utc(2026, 7, 15, 19, 0)), "LA's sky on a New York phone")
    }

    // MARK: the date line

    func testZonesAcrossTheDateLineWrap() {
        let at = utc(2026, 10, 26, 0, 0)
        XCTAssertFalse(away((1.87, -157.40), "Pacific/Kiritimati", at), "UTC+14 at 157° W")
        XCTAssertFalse(away((-13.83, -171.76), "Pacific/Apia", at), "UTC+13 at 172° W")
        XCTAssertFalse(away((-36.85, 174.76), "Pacific/Auckland", at))
        XCTAssertTrue(away(londonPlace, "Pacific/Auckland", at))
    }

    // MARK: labels

    func testLabels() {
        XCTAssertEqual(SolarPlace.label(lat: -33.87, lon: 151.21), "33.87° S, 151.21° E")
        XCTAssertEqual(SolarPlace.label(lat: -33.87, lon: 151.21, short: true), "33.9°S 151.2°E")
        XCTAssertEqual(SolarPlace.label(lat: 51.51, lon: -0.13), "51.51° N, 0.13° W")
        XCTAssertEqual(SolarPlace.spokenLabel(lat: -33.87, lon: 151.21), "33.87 degrees south, 151.21 degrees east")
        XCTAssertEqual(SolarPlace.leadPhrase(-1.2), "about 1 hour behind")
    }

    // MARK: the widget

    /// Raag Now names the place only in solar mode, only while the mismatch holds.
    func testWidgetNamesTheSkyOnlyWhenAway() {
        let at = utc(2026, 10, 26, 13, 30)
        let sydneySolar = RaagClockConfig(solar: true, lat: sydneyPlace.lat, lon: sydneyPlace.lon)
        XCTAssertEqual(RaagNowTimeline.entry(at: at, config: sydneySolar, snapshot: nil, tz: london).skyPlace,
                       "33.9°S 151.2°E")
        let londonSolar = RaagClockConfig(solar: true, lat: londonPlace.lat, lon: londonPlace.lon)
        XCTAssertNil(RaagNowTimeline.entry(at: at, config: londonSolar, snapshot: nil, tz: london).skyPlace)
        // fixed mode is unaffected: the stored place plays no part in it
        let sydneyFixed = RaagClockConfig(solar: false, lat: sydneyPlace.lat, lon: sydneyPlace.lon)
        let fixed = RaagNowTimeline.entry(at: at, config: sydneyFixed, snapshot: nil, tz: london)
        XCTAssertNil(fixed.skyPlace)
        XCTAssertFalse(fixed.solar)
        // a polar fallback shows the fixed clock, so there is no other sky to name
        let polar = RaagClockConfig(solar: true, lat: 78.22, lon: 150)
        let winter = RaagNowTimeline.entry(at: utc(2026, 12, 21, 12, 0), config: polar, snapshot: nil, tz: london)
        XCTAssertFalse(winter.solar)
        XCTAssertNil(winter.skyPlace)
    }

    // MARK: "Keep this place"

    /// Keeping is a flag on the stored place, never a second copy of it: a new place asks again,
    /// the same fix again keeps the choice. Restores whatever the device held.
    func testKeptPlaceClearsOnlyWhenThePlaceChanges() {
        let suite = SharedDefaults.suite
        let coords = suite.string(forKey: SharedDefaults.solarCoordsKey)
        let kept = suite.object(forKey: SharedDefaults.solarPlaceKeptKey)
        defer {
            if let coords { suite.set(coords, forKey: SharedDefaults.solarCoordsKey) }
            else { suite.removeObject(forKey: SharedDefaults.solarCoordsKey) }
            if let kept { suite.set(kept, forKey: SharedDefaults.solarPlaceKeptKey) }
            else { suite.removeObject(forKey: SharedDefaults.solarPlaceKeptKey) }
        }
        SharedDefaults.storeSolarCoords(lat: -33.87, lon: 151.21)
        SharedDefaults.solarPlaceKept = true
        SharedDefaults.storeSolarCoords(lat: -33.8701, lon: 151.2099)   // the same place, rounded
        XCTAssertTrue(SharedDefaults.solarPlaceKept, "a fresh fix of the same place keeps the choice")
        SharedDefaults.storeSolarCoords(lat: 51.51, lon: -0.13)
        XCTAssertFalse(SharedDefaults.solarPlaceKept, "a new place is a new decision")
        XCTAssertNil(suite.object(forKey: SharedDefaults.solarPlaceKeptKey))
    }
}
