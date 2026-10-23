import XCTest
import GurbaniSearchKit
@testable import SGGS

/// Contributors labels: full names with a Mahala badge (never a bare "(M5)"), the Gurmukhi
/// suffix split out for `GurmukhiText` (never inline in English), and inflected counts
/// ("1 shabad", not "1 shabads"; "Outside the raag sections", not "0 raags").
final class AuthorNameTests: XCTestCase {

    func testGuruNameSplitsIntoFullNameAndMahala() {
        let n = AuthorName("Guru Arjan Dev Ji (M5)")
        XCTAssertEqual(n.english, "Guru Arjan Dev Ji")
        XCTAssertEqual(n.mahala, 5)
        XCTAssertEqual(n.badge, "M5")
        XCTAssertNil(n.gurmukhi)
        XCTAssertEqual(n.spoken, "Guru Arjan Dev Ji, Mahala 5")
        XCTAssertEqual(n.compact, "M5")
        XCTAssertEqual(n.raw, "Guru Arjan Dev Ji (M5)", "the stored key is never altered")
    }

    func testBhattGurmukhiSuffixIsSplitOutOfTheEnglishLabel() {
        let n = AuthorName("Bhatt Kalsahar (ਭਟ)")
        XCTAssertEqual(n.english, "Bhatt Kalsahar")
        XCTAssertEqual(n.gurmukhi, "ਭਟ")
        XCTAssertNil(n.mahala)
        XCTAssertNil(n.badge)
        XCTAssertEqual(n.compact, "Bhatt Kalsahar")
        XCTAssertEqual(AuthorName("The Bhatts (ਭਟ)").english, "The Bhatts")
    }

    func testPlainNamesPassThrough() {
        XCTAssertEqual(AuthorName("Bhagat Kabir Ji").english, "Bhagat Kabir Ji")
        XCTAssertEqual(AuthorName("Bhagat Kabir Ji").compact, "Kabir")
        XCTAssertEqual(AuthorName("Satta & Balwand").english, "Satta & Balwand")
        XCTAssertNil(AuthorName("Bhai Mardana").mahala)
        // a non-Mahala, non-Gurmukhi group is part of the name, not peeled
        XCTAssertEqual(AuthorName("Someone (Elder)").english, "Someone (Elder)")
        XCTAssertEqual(AuthorName("").english, "")
    }

    /// Every bundled roster entry renders cleanly: no parenthesis or Gurmukhi left in the
    /// English label, and each Guru's Mahala matches the roster's `seq`.
    func testEveryRosterNameRendersCleanly() throws {
        guard let roster = ContributorsStore.load() ?? ContributorsStore.load(bundle: Bundle(for: Self.self))
        else { throw XCTSkip("contributors.json not bundled") }
        XCTAssertGreaterThanOrEqual(roster.count, 30)
        for c in roster {
            let n = AuthorName(c.name)
            XCTAssertFalse(n.english.contains("("), "\(c.name) leaks a parenthesis")
            XCTAssertFalse(n.english.unicodeScalars.contains { (0x0A00...0x0A7F).contains($0.value) },
                           "\(c.name) leaks Gurmukhi into the English label")
            if c.kind == "guru" { XCTAssertEqual(n.mahala, c.seq, c.name) }
            if c.kind == "bhatt" { XCTAssertEqual(n.gurmukhi, "ਭਟ", c.name) }
        }
    }

    private let en = Locale(identifier: "en_US")
    private func text(_ a: AttributedString) -> String { String(a.characters) }

    func testCountsInflectForZeroOneAndTwo() {
        XCTAssertEqual(text(VoiceCopy.shabads(0, locale: en)), "0 shabads")
        XCTAssertEqual(text(VoiceCopy.shabads(1, locale: en)), "1 shabad")
        XCTAssertEqual(text(VoiceCopy.shabads(2, locale: en)), "2 shabads")
        XCTAssertEqual(text(VoiceCopy.raags(1, locale: en)), "1 raag")
        XCTAssertEqual(text(VoiceCopy.raags(2, locale: en)), "2 raags")
        XCTAssertEqual(text(VoiceCopy.lines(1, locale: en)), "1 line")
        XCTAssertEqual(text(VoiceCopy.lines(2, locale: en)), "2 lines")
    }

    func testNoRaagSaysOutsideTheRaagSections() {
        let bhatt = text(VoiceCopy.summary(lines: 4, shabads: 1, raags: 0, locale: en))
        XCTAssertEqual(bhatt, "4 lines · 1 shabad · Outside the raag sections")
        XCTAssertFalse(bhatt.contains("0 raag"))
        XCTAssertEqual(text(VoiceCopy.summary(lines: 230, shabads: 63, raags: 9, locale: en)),
                       "230 lines · 63 shabads · 9 raags")
    }

    private func stat(_ author: String, _ n: Int) -> AuthorStat {
        AuthorStat(author: author, nLines: n, nShabads: 1, nRaags: 1, mattr100: 0.8, avgWordsLine: 6, isReliable: true)
    }

    /// Default order is the Granth's (first Ang), never volume-first; "Most Bani" is opt-in.
    func testGranthOrderFollowsFirstAngAndVolumeIsOptIn() {
        let authors = [stat("Guru Arjan Dev Ji (M5)", 22955), stat("Guru Nanak Dev Ji (M1)", 10997),
                       stat("Guru Ram Das Ji (M4)", 5905), stat("Bhatt Bhal (ਭਟ)", 4), stat("Unknown", 9)]
        let angs = ["Guru Arjan Dev Ji (M5)": 10, "Guru Nanak Dev Ji (M1)": 8,
                    "Guru Ram Das Ji (M4)": 10, "Bhatt Bhal (ਭਟ)": 1396]
        XCTAssertEqual(ContributorsView.ordered(authors, by: .granth, firstAngs: angs).map(\.author),
                       ["Guru Nanak Dev Ji (M1)", "Guru Arjan Dev Ji (M5)", "Guru Ram Das Ji (M4)",
                        "Bhatt Bhal (ਭਟ)", "Unknown"],
                       "first Ang, ties by volume, unknown Ang last")
        XCTAssertEqual(ContributorsView.ordered(authors, by: .volume, firstAngs: angs).first?.author,
                       "Guru Arjan Dev Ji (M5)")
    }

    /// The chart keys its bars by `compact`: two voices sharing a label would merge into one bar.
    func testCompactLabelsAreDistinctAcrossTheRoster() throws {
        guard let roster = ContributorsStore.load() ?? ContributorsStore.load(bundle: Bundle(for: Self.self))
        else { throw XCTSkip("contributors.json not bundled") }
        let labels = roster.map { AuthorName($0.name).compact }
        XCTAssertEqual(Set(labels).count, labels.count, "duplicate compact labels: \(labels)")
    }
}
