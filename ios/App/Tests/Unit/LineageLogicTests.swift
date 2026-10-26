import XCTest
import GurbaniSearchKit
import GurbaniDB
@testable import SGGS

/// Lineage's pure logic: the Voice of the day (deterministic, rotating, falling back when a voice
/// has no rahao verse), the "Did you know" facts, River's alive-in-a-year readout and its tap rows.
final class LineageLogicTests: XCTestCase {

    private func verse(_ id: Int) -> VoiceVerse { VoiceVerse(id: id, ang: id, compId: id, gurmukhi: "ਤੁਕ \(id)") }

    // MARK: Voice of the day

    func testSameDaySameVoiceAndVerse() {
        let day = HukamOfTheDay.dayNumber(year: 2026, month: 10, day: 24)
        XCTAssertEqual(VoiceOfTheDayPick.voiceIndex(day: day, count: 29), VoiceOfTheDayPick.voiceIndex(day: day, count: 29))
        let rahao = (1...7).map(verse)
        XCTAssertEqual(VoiceOfTheDayPick.verse(day: day, voiceCount: 29, rahao: rahao, fallback: nil),
                       VoiceOfTheDayPick.verse(day: day, voiceCount: 29, rahao: rahao, fallback: nil))
    }

    /// Across a month every voice comes round, none twice within one rotation.
    func testAMonthRotatesThroughEveryVoice() {
        let start = HukamOfTheDay.dayNumber(year: 2026, month: 10, day: 1)
        let count = 29
        let picks = (0..<count).compactMap { VoiceOfTheDayPick.voiceIndex(day: start + $0, count: count) }
        XCTAssertEqual(Set(picks).count, count, "one rotation shows each voice once")
        XCTAssertEqual(VoiceOfTheDayPick.voiceIndex(day: start + count, count: count), picks[0], "then it starts again")
        // the next rotation moves on to the voice's next rahao verse
        let a = VoiceOfTheDayPick.verseIndex(day: start, voiceCount: count, verseCount: 5)
        let b = VoiceOfTheDayPick.verseIndex(day: start + count, voiceCount: count, verseCount: 5)
        XCTAssertEqual(((a ?? 0) + 1) % 5, b)
    }

    func testNoRahaoFallsBackToTheOpeningVerse() {
        let opening = verse(99)
        XCTAssertEqual(VoiceOfTheDayPick.verse(day: 20_000, voiceCount: 29, rahao: [], fallback: opening), opening)
        XCTAssertNil(VoiceOfTheDayPick.verse(day: 20_000, voiceCount: 29, rahao: [], fallback: nil))
        XCTAssertNil(VoiceOfTheDayPick.voiceIndex(day: 20_000, count: 0), "no voices: no card")
        XCTAssertEqual(VoiceOfTheDayPick.voiceIndex(day: -3, count: 29), 26, "never a negative index")
    }

    // MARK: did you know

    func testFactsAreBuiltOnlyFromWhatTheDBGives() {
        let raag = SignatureRaag(raag: "ਜੈਜਾਵੰਤੀ", roman: "jaijaavantee", author: "Guru Tegh Bahadur Ji (M9)", firstAng: 1352, nVerses: 28)
        let bhatts = (1...11).map { i in
            VoiceSummary(author: "Bhatt \(i)", nVerses: 10, nCompositions: 1, nRaags: 0,
                         firstAng: 1388 + i, lastAng: 1398 + i, angs: AngSet([1388 + i]))
        }
        let name: (String) -> String = { AuthorName($0).english }
        let en = Locale(identifier: "en_US")
        let facts = LineageFacts.build(signatureRaags: [raag], dialogue: nil, bhatts: bhatts, name: name, locale: en)
        XCTAssertEqual(facts.map(\.id), ["raag-ਜੈਜਾਵੰਤੀ", "bhatts"])
        XCTAssertEqual(facts[0].text, "appears in the Granth only in Guru Tegh Bahadur Ji's Bani, from Ang 1352.")
        XCTAssertEqual(facts[0].author, "Guru Tegh Bahadur Ji (M9)")
        XCTAssertEqual(facts[1].text, "11 Bhatts each have Swaiyye in the Granth, Angs 1389–1409.")

        let span = DialogueSpan(count: 17, firstAng: 1364, lastAng: 1384,
                                bhagats: ["Bhagat Kabir Ji", "Baba Sheikh Farid Ji"],
                                gurus: ["Guru Nanak Dev Ji (M1)", "Guru Amar Das Ji (M3)", "Guru Arjan Dev Ji (M5)"])
        let withDialogue = LineageFacts.build(signatureRaags: [], dialogue: span, bhatts: [], name: name, locale: en)
        XCTAssertEqual(withDialogue.map(\.text), [
            "Saloks of Guru Nanak Dev Ji, Guru Amar Das Ji, and Guru Arjan Dev Ji are set beside saloks of Bhagat Kabir Ji and Baba Sheikh Farid Ji, Angs 1364–1384.",
        ])
        XCTAssertTrue(LineageFacts.build(signatureRaags: [], dialogue: nil, bhatts: Array(bhatts.prefix(1)),
                                         name: name, locale: en).isEmpty, "one Bhatt is not a fact about the Bhatts")
    }

    // MARK: River

    private func voices() throws -> [Contributor] {
        let json = #"""
        {"contributors": [
          {"name": "Guru Nanak Dev Ji (M1)", "roman": "Guru Nanak Dev Ji", "kind": "guru", "seq": 1, "born": 1469, "died": 1539,
           "circa": false, "era": "15th–16th century", "region": "Punjab", "tradition": "Sikh", "blurb": "b"},
          {"name": "Bhagat Jaidev Ji", "roman": "Jaidev", "kind": "bhagat", "born": 1170, "died": 1245,
           "circa": true, "era": "12th–13th century", "region": "Bengal", "tradition": "Vaishnava", "blurb": "b"},
          {"name": "Bhagat Beni Ji", "roman": "Beni", "kind": "bhagat", "circa": true,
           "era": "", "region": "", "tradition": "", "blurb": "b"}
        ]}
        """#
        return try XCTUnwrap(ContributorsStore.decode(Data(json.utf8)))
    }

    func testAliveInAYearAndTheReadout() throws {
        let v = try voices()
        XCTAssertEqual(LifespanLogic.alive(v, year: 1500).map(\.name), ["Guru Nanak Dev Ji (M1)"])
        XCTAssertEqual(LifespanLogic.alive(v, year: 1200).map(\.name), ["Bhagat Jaidev Ji"])
        XCTAssertTrue(LifespanLogic.alive(v, year: 1400).isEmpty)
        XCTAssertNil(LifespanLogic.bounds(v[2]), "an undated voice is never placed in time")
        XCTAssertEqual(LifespanLogic.readout(year: nil, voices: v), "Drag along the years to see who was alive.")
        XCTAssertEqual(LifespanLogic.readout(year: 1500, voices: v), "c. 1500: Guru Nanak Dev Ji")
        XCTAssertEqual(LifespanLogic.readout(year: 1400, voices: v), "c. 1400: none of these voices by the dates given")
    }

    /// A tap on the year-label strip above the first lifespan opens nothing (it used to open row 0).
    @MainActor
    func testRiverTapRows() {
        XCTAssertNil(VoiceRiverView.lane(atY: 0))
        XCTAssertNil(VoiceRiverView.lane(atY: 21))
        XCTAssertEqual(VoiceRiverView.lane(atY: 22), 0)
        XCTAssertEqual(VoiceRiverView.lane(atY: 22 + 26 * 3 + 1), 3)
    }

    @MainActor
    func testMilestonesWaitForTheScholar() {
        XCTAssertEqual(VoiceRiverView.milestones.first { $0.year == 1706 }?.label, "c. 1705–06")
        XCTAssertEqual(VoiceRiverView.shownMilestones.isEmpty, !EditorialGate.aboutCopy)
    }

    // MARK: Compare

    @MainActor
    func testCompareOverlapAndSharedAngs() throws {
        let v = try voices()
        let m1 = v[0], jaidev = v[1], beni = v[2]
        XCTAssertNil(CompareVoicesSheet.overlap(m1, jaidev), "disjoint lifetimes")
        XCTAssertNil(CompareVoicesSheet.overlap(m1, beni), "no dates, no overlap claimed")
        XCTAssertEqual(CompareVoicesSheet.overlap(m1, m1), 1469...1539)
        XCTAssertEqual(CompareVoicesSheet.overlapDuration(1500...1500), "about a year")
        XCTAssertEqual(CompareVoicesSheet.overlapDuration(1500...1501), "about a year")
        XCTAssertEqual(CompareVoicesSheet.overlapDuration(1469...1504), "about 35 years")
        XCTAssertEqual(CompareVoicesSheet.sharedAngs(AngSet([1, 2, 1430]), AngSet([2, 3, 1430])), 2)
        XCTAssertEqual(CompareVoicesSheet.sharedAngs(AngSet([1]), AngSet([2])), 0)
        XCTAssertEqual(CompareVoicesSheet.liftText(nil), "—", "a missing theme is not a measured zero")
        XCTAssertEqual(CompareVoicesSheet.liftText(1.63), "1.6×")
    }

    // MARK: one voice count

    /// Every roster voice is counted; one with no tagged lines is under review, not dropped.
    func testEveryRosterVoiceIsCounted() throws {
        let roster = try voices()   // M1, Jaidev, Beni
        let today = LineageCount.split(roster, withBani: ["Guru Nanak Dev Ji (M1)", "Bhagat Jaidev Ji"])
        XCTAssertEqual(today.voices.map(\.name), roster.map(\.name), "the count is the roster's")
        XCTAssertEqual(today.underReview.map(\.name), ["Bhagat Beni Ji"])
        XCTAssertEqual(today.tagged, 2)
        let all = LineageCount.split(roster, withBani: Set(roster.map(\.name)))
        XCTAssertEqual(all.voices.count, 3); XCTAssertTrue(all.underReview.isEmpty)
        XCTAssertNil(LineageCount.taggedNote(all), "no note when every voice has tagged lines")
        let unread = LineageCount.split(roster, withBani: [])
        XCTAssertEqual(unread.voices.count, 3, "before the DB is read, the roster shows as is")
        XCTAssertTrue(unread.underReview.isEmpty, "nothing is under review before the DB is read")
        let extra = LineageCount.split(roster, withBani: ["Guru Nanak Dev Ji (M1)", "Bhatt Kalh"])
        XCTAssertEqual(extra.voices.map(\.name).last, "Bhatt Kalh", "a DB voice the roster lacks is still counted")
        XCTAssertEqual(extra.voices.count, 4)
    }

    func testReviewLineAndNoteCiteTheAng() throws {
        let json = #"""
        {"contributors": [{"name": "Bhagat Surdas Ji", "roman": "Surdas", "display": "Bhagat Surdas Ji", "kind": "bhagat",
          "circa": true, "era": "16th century", "region": "", "tradition": "", "blurb": "b",
          "attribution_note": "The corpus files his single line (Ang 1253, ਛਾਡਿ) under Namdev."},
          {"name": "Bhagat Beni Ji", "roman": "Beni", "kind": "bhagat", "circa": true,
           "era": "", "region": "", "tradition": "", "blurb": "b"}]}
        """#
        let roster = try XCTUnwrap(ContributorsStore.decode(Data(json.utf8)))
        XCTAssertEqual(roster[0].reviewAng, 1253)
        XCTAssertNil(roster[1].reviewAng)
        XCTAssertEqual(LineageCount.reviewLine(roster[0]), "Ang 1253 · attribution under scholarly review")
        XCTAssertEqual(LineageCount.reviewLine(roster[1]), "Attribution under scholarly review")
        let split = LineageCount.split(roster, withBani: ["Guru Nanak Dev Ji (M1)"])
        XCTAssertEqual(LineageCount.taggedNote(split, locale: Locale(identifier: "en_US")),
                       "Figures count the lines tagged to each voice. Bhagat Surdas Ji (Ang 1253) and Bhagat Beni Ji: attribution under scholarly review.")
        XCTAssertNil(Contributor.firstAng(in: "Ang 9999"), "an Ang outside 1–1430 is not a citation")
        XCTAssertNil(Contributor.firstAng(in: "Angs 12"))
    }
}
