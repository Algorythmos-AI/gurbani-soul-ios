import XCTest
@testable import GurbaniDB
@testable import GurbaniSearchKit

/// The Hukam of the day on the shipped iOS DB: a day always draws the same seed, the seed
/// expands to a unit with a verse to show, and consecutive days move through the Granth.
final class HukamOfTheDayDBTests: XCTestCase {

    private func source() throws -> SQLiteCandidateSource {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<12 {
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent("contract/_meta.json").path) { break }
            dir = dir.deletingLastPathComponent()
        }
        let dbPath = dir.appendingPathComponent("ios/Resources/sggs-ios.sqlite").path
        guard FileManager.default.fileExists(atPath: dbPath) else {
            throw XCTSkip("ios/Resources/sggs-ios.sqlite missing — run pipeline/build_ios_db.py")
        }
        return try SQLiteCandidateSource(path: dbPath)
    }

    func testEachDayDrawsOneVerseItCanShow() throws {
        let db = try source()
        let today = HukamOfTheDay.dayNumber(year: 2026, month: 10, day: 23)
        var seeds: [Int] = []
        for day in today..<(today + 14) {
            let seed = try db.hukamOfTheDaySeed(day: day)
            XCTAssertEqual(seed, try db.hukamOfTheDaySeed(day: day), "day \(day) must always draw the same seed")
            let unit = try db.hukamUnit(seed: seed)
            let verse = try XCTUnwrap(unit.lines.first(where: { !$0.isHeader }), "day \(day): unit \(seed) has no verse")
            XCTAssertFalse(verse.gurmukhi.isEmpty, "day \(day): empty verse")
            XCTAssertTrue((1...1430).contains(verse.ang), "day \(day): Ang \(verse.ang) out of range")
            XCTAssertTrue(unit.compIds.contains(verse.compId), "day \(day): the shown verse is outside its unit")
            seeds.append(seed)
        }
        // two days can land in the same long composition, but a fortnight moves through the Granth
        XCTAssertGreaterThanOrEqual(Set(seeds).count, 12, "14 days drew only \(Set(seeds).count) distinct seeds")
    }
}
