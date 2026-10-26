import XCTest
import GurbaniDB
import GurbaniSearchKit
import GurbaniPahar
@testable import SGGS

/// Explore's live previews on the SHIPPED DB: the Theme Feature quotes its verse byte for byte as
/// the corpus stores it, the sky is the Sky screen's own layout, and the Clock card states the
/// watch the widgets state.
@MainActor
final class ExploreLiveTests: XCTestCase {

    private func corpus() throws -> CorpusActor {
        do { return try CorpusActor() } catch { throw XCTSkip("bundled DB not found in host app") }
    }

    func testThemeVerseIsTheCorpusLineByteForByte() async throws {
        let actor = try corpus()
        let day = HukamOfTheDay.dayNumber(year: 2026, month: 10, day: 26)
        let live = ExploreLive()
        await live.load(corpus: actor, day: day)
        let today = try XCTUnwrap(live.themeToday, "no theme of the day")
        let direct = try await actor.themeOfTheDay(day: day)
        let expected = try XCTUnwrap(direct)
        XCTAssertEqual(today, expected)
        // The line on its own Ang, as the reader shows it.
        let page = try await actor.ang(today.line.ang)
        let stored = try XCTUnwrap(page.lines.first { $0.id == today.line.id }, "verse not on its Ang")
        XCTAssertEqual(Array(today.line.gurmukhi.utf8), Array(stored.gurmukhi.utf8), "the quoted verse must be verbatim")
        let bins = try await actor.themeAngBins(today.concept)
        XCTAssertEqual(live.themeBins, bins)
    }

    func testSkyIsTheSkyScreensLayout() async throws {
        let actor = try corpus()
        let live = ExploreLive()
        await live.load(corpus: actor, day: 1)
        let sky = try XCTUnwrap(live.sky)
        let graph = try await actor.constellationSky(minPPMI: 0)
        XCTAssertEqual(sky.concepts, graph.nodes.map(\.concept))
        XCTAssertEqual(sky.points.count, graph.nodes.count)
        XCTAssertTrue(sky.points.allSatisfy { (0...1).contains($0.x) && (0...1).contains($0.y) })
        XCTAssertEqual(sky.drawn.count, graph.edges.filter { $0.ppmi >= 0.7 }.count, "only the Sky screen's drawn pairs")
        let again = await ExploreSky.make(graph)
        XCTAssertEqual(again, sky, "the layout is seeded: the same sky every time")
    }

    func testSecondLoadSameDayReadsNothingNew() async throws {
        let actor = try corpus()
        let live = ExploreLive()
        await live.load(corpus: actor, day: 7)
        let first = live.themeToday
        await live.load(corpus: actor, day: 7)
        XCTAssertEqual(live.themeToday, first)
        await live.load(corpus: actor, day: 8)
        XCTAssertNotEqual(live.themeToday?.concept, first?.concept, "a new day turns the theme over")
    }

    /// The hub left open across midnight: a load still in flight for yesterday never publishes
    /// over today's (Codex review on #90).
    func testANewerDayWinsOverALoadInFlight() async throws {
        let actor = try corpus()
        let live = ExploreLive()
        // Yesterday's load starts first and is still waiting when today's is asked for.
        let yesterday = Task { await live.load(corpus: actor, day: 20) }
        try await Task.sleep(for: .milliseconds(50))
        await live.load(corpus: actor, day: 21)
        await yesterday.value
        let expected = try await actor.themeOfTheDay(day: 21)
        XCTAssertEqual(live.themeToday, expected, "yesterday's theme published over today's")
        await live.load(corpus: actor, day: 21)
        XCTAssertEqual(live.themeToday, expected)
    }

    /// A night watch that crosses midnight, read at 01:35: the window runs PM → AM on the reader's
    /// clock (device review of #90 asked for this pin).
    func testNightWatchAcrossMidnightReadsPMtoAM() throws {
        let london = try XCTUnwrap(TimeZone(identifier: "Europe/London"))
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = london
        let at = try XCTUnwrap(cal.date(from: DateComponents(year: 2026, month: 10, day: 26, hour: 1, minute: 35)))
        let us = Locale(identifier: "en_US")

        let solar = RaagClockConfig(solar: true, lat: 51.51, lon: -0.13)
        let entry = RaagNowTimeline.entry(at: at, config: solar, snapshot: nil, tz: london)
        let clock = ExploreClockNow(entry: entry, locale: us, tz: london)
        XCTAssertEqual(clock.label, "3rd pahar of night")
        XCTAssertEqual(clock.window, "11:45 PM–3:13 AM")

        let fixed = RaagNowTimeline.entry(at: at, config: RaagClockConfig(solar: false), snapshot: nil, tz: london)
        XCTAssertEqual(ExploreClockNow(entry: fixed, locale: us, tz: london).window, "12–3 AM")
        XCTAssertEqual(PaharFormat.window(Pahar.window(6), on: at, locale: us, tz: london), "9 PM–12 AM")
    }

    /// Solar watches follow the STORED location's sky, shown on the reader's own clock. A location
    /// half a world from the device's zone (Sydney coordinates on a London clock) therefore puts a
    /// night watch in London's daytime — the device capture on #90 ("2nd pahar of night ·
    /// 10:58 AM–1:39 PM" at a pinned 13:30) is this case, not a formatting error.
    func testStoredLocationFarFromTheClocksZone() throws {
        let london = try XCTUnwrap(TimeZone(identifier: "Europe/London"))
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = london
        let at = try XCTUnwrap(cal.date(from: DateComponents(year: 2026, month: 10, day: 26, hour: 13, minute: 30)))
        let sydney = RaagClockConfig(solar: true, lat: -33.87, lon: 151.21)
        let clock = ExploreClockNow(entry: RaagNowTimeline.entry(at: at, config: sydney, snapshot: nil, tz: london),
                                    locale: Locale(identifier: "en_US"), tz: london)
        XCTAssertEqual(clock.label, "2nd pahar of night")
        XCTAssertTrue(clock.window.hasPrefix("10:58 AM–1:"), clock.window)
        XCTAssertTrue(clock.window.hasSuffix(" PM"), clock.window)
        // ...and the card says so: never another place's sky without naming it
        XCTAssertEqual(clock.skyPlace, "33.9°S 151.2°E")
        XCTAssertTrue(clock.caption.hasSuffix(" · sky over 33.9°S 151.2°E"), clock.caption)
        XCTAssertTrue(clock.spoken.contains("Sky over 33.9°S 151.2°E, not this phone's time zone"), clock.spoken)
        // a place on the phone's own clock adds nothing
        let home = ExploreClockNow(entry: RaagNowTimeline.entry(at: at, config: RaagClockConfig(solar: true, lat: 51.51, lon: -0.13),
                                                                 snapshot: nil, tz: london),
                                   locale: Locale(identifier: "en_US"), tz: london)
        XCTAssertNil(home.skyPlace)
        XCTAssertFalse(home.caption.contains("sky over"))
    }

    func testClockStatesTheWidgetsWatch() throws {
        let noon = try XCTUnwrap(Calendar.current.date(bySettingHour: 13, minute: 30, second: 0, of: Date()))
        let entry = RaagNowTimeline.entry(at: noon, config: RaagClockConfig(solar: false), snapshot: nil)
        let clock = ExploreClockNow(entry: entry, locale: Locale(identifier: "en_US"))
        XCTAssertEqual(clock.pahar, Pahar.paharFromMinutes(13 * 60 + 30))
        XCTAssertEqual(clock.label, Pahar.label(clock.pahar))
        XCTAssertTrue(clock.caption.hasPrefix(clock.label + " · "))
        XCTAssertFalse(clock.spoken.contains("–"), "VoiceOver reads 'to', not a dash")
        XCTAssertFalse(clock.hasSnapshot, "no raag table yet: the card claims no raags")
        XCTAssertEqual(clock.raagCount, 0)
    }
}
