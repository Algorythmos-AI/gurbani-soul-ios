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
