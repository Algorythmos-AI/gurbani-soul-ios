import XCTest
@testable import SGGS

/// The Explore hub's placement rules: today's Feature turns over by day among the eligible
/// destinations, and the rest pack into full rows, each destination exactly once.
final class ExploreLayoutTests: XCTestCase {

    private func shape(_ rows: [[ExploreCell]]) -> [[String]] {
        rows.map { $0.map { "\($0.destination.rawValue):\($0.span)" } }
    }

    func testEveryDestinationHasOneUniqueTitle() {
        let titles = ExploreDestination.allCases.map(\.title)
        XCTAssertEqual(Set(titles).count, titles.count)
        // The UI tests tap these exact titles.
        XCTAssertEqual(titles, ["Index", "Themes", "Lineage", "Vaars", "Constellation", "Insights", "Raag Clock"])
    }

    func testFeatureTurnsOverByDayAndCoversEveryEligibleDestination() {
        let eligible = ExploreLayout.eligible(vaarsAvailable: true)
        let picks = (0..<eligible.count).compactMap { ExploreLayout.feature(day: 1000 + $0, eligible: eligible) }
        XCTAssertEqual(Set(picks), Set(eligible), "consecutive days visit every eligible destination")
        XCTAssertEqual(ExploreLayout.feature(day: 1000, eligible: eligible),
                       ExploreLayout.feature(day: 1000 + eligible.count, eligible: eligible), "same day key, same Feature")
        XCTAssertNotNil(ExploreLayout.feature(day: -3, eligible: eligible), "a negative day key never traps")
        XCTAssertNil(ExploreLayout.feature(day: 5, eligible: []))
    }

    func testPinWinsOnlyWhenEligible() {
        let eligible = ExploreLayout.eligible(vaarsAvailable: true)
        XCTAssertEqual(ExploreLayout.feature(day: 0, eligible: eligible, pinned: .vaars), .vaars)
        let noVaars = ExploreLayout.eligible(vaarsAvailable: false)
        XCTAssertFalse(noVaars.contains(.vaars))
        XCTAssertNotEqual(ExploreLayout.feature(day: 0, eligible: noVaars, pinned: .vaars), .vaars)
    }

    func testEveryWidthFillsEveryRowWithEachDestinationOnce() {
        for columns in [2, 3] {
            for featured in ExploreDestination.allCases {
                let rest = ExploreDestination.allCases.filter { $0 != featured }
                let rows = ExploreLayout.pack(rest, columns: columns)
                XCTAssertEqual(rows.flatMap { $0 }.map(\.destination).sorted { $0.rawValue < $1.rawValue },
                               rest.sorted { $0.rawValue < $1.rawValue }, "\(featured) leads, \(columns) columns")
                for row in rows {
                    XCTAssertEqual(row.map(\.span).reduce(0, +), columns, "row not full: \(shape(rows))")
                }
            }
        }
    }

    func testSquaresPairUpBeforeStandingAlone() {
        // The Index leads: Constellation reaches past Insights to pair with the Raag Clock.
        let rows = ExploreLayout.pack(ExploreDestination.allCases.filter { $0 != .index }, columns: 2)
        XCTAssertEqual(shape(rows), [["themes:1", "lineage:1"], ["vaars:2"], ["constellation:1", "clock:1"], ["insights:2"]])
        // The Clock leads: no square is left to pair with Constellation, so it grows wide.
        let clockLeads = ExploreLayout.pack(ExploreDestination.allCases.filter { $0 != .clock }, columns: 2)
        XCTAssertEqual(shape(clockLeads),
                       [["index:2"], ["themes:1", "lineage:1"], ["vaars:2"], ["constellation:2"], ["insights:2"]])
        // Three columns.
        let wide = ExploreLayout.pack(ExploreDestination.allCases.filter { $0 != .index }, columns: 3)
        XCTAssertEqual(shape(wide), [["themes:1", "lineage:1", "constellation:1"], ["vaars:2", "clock:1"], ["insights:3"]])
    }

    func testOneColumnIsOneCardPerRow() {
        let rows = ExploreLayout.pack(ExploreDestination.allCases, columns: 1)
        XCTAssertEqual(rows.count, ExploreDestination.allCases.count)
        XCTAssertTrue(rows.allSatisfy { $0.count == 1 && $0[0].span == 1 })
    }
}
