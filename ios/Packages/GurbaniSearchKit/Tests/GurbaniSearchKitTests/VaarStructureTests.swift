import XCTest
@testable import GurbaniSearchKit

/// `VaarStructure` on hand-made runs: each refusal path, and the label grammar.
final class VaarStructureTests: XCTestCase {

    private func run(_ rows: [(Bool, String)], from base: Int = 100, ang: Int = 1) -> [VaarLine] {
        rows.enumerated().map { VaarLine(id: base + $0.offset, ang: ang, isHeader: $0.element.0, gurmukhi: $0.element.1) }
    }

    private let small: [(Bool, String)] = [
        (true, "ੴ ਸਤਿਗੁਰ ਪ੍ਰਸਾਦਿ ॥"),
        (true, "ਟੇਸਟ ਕੀ ਵਾਰ ਮਹਲਾ ੪"),
        (true, "ਸਲੋਕ ਮਃ ੩ ॥"),
        (false, "ਪਹਿਲੀ ਤੁਕ ॥"),
        (false, "ਦੂਜੀ ਤੁਕ ॥੧॥"),
        (true, "ਮਃ ੧ ॥"),
        (false, "ਤੀਜੀ ਤੁਕ ॥੨॥"),
        (true, "ਪਉੜੀ ॥"),
        (false, "ਪਉੜੀ ਦੀ ਤੁਕ ॥"),
        (false, "ਅੰਤਲੀ ਤੁਕ ॥੧॥"),
        (false, "ਸੁਧੁ ॥"),
    ]

    func testBuildsHeadingUnitsAndVoices() throws {
        let t = try XCTUnwrap(VaarStructure.build(vaarId: 1, pauriAuthor: "Guru Ram Das Ji (M4)",
                                                  lines: run(small), hints: [VaarUnitHint(kind: "salok", firstLineId: 103, author: nil)]))
        XCTAssertEqual(t.heading.map(\.id), [100, 101])
        XCTAssertEqual(t.titleLines.map(\.id), [101])
        XCTAssertNil(t.dhuni)
        XCTAssertEqual(t.units.map(\.kind), [.salok, .salok, .pauri])
        XCTAssertEqual(t.units.map(\.author), ["Guru Amar Das Ji (M3)", "Guru Nanak Dev Ji (M1)", "Guru Ram Das Ji (M4)"])
        XCTAssertEqual(t.units[2].pauriNo, 1)
        XCTAssertEqual(t.units[2].lines.last?.gurmukhi, "ਸੁਧੁ ॥", "a closing rubric stays with its pauri")
        XCTAssertEqual(t.units[0].firstVerse?.id, 103)
        XCTAssertEqual(t.voices.count, 3)
        XCTAssertEqual(t.unitIndex(containing: 106), 1)
        XCTAssertNil(t.unitIndex(containing: 100))
    }

    func testRefusesAPauriThatDoesNotCloseWithItsNumber() {
        var rows = small
        rows[9] = (false, "ਅੰਤਲੀ ਤੁਕ ॥੭॥")
        XCTAssertNil(VaarStructure.build(vaarId: 1, pauriAuthor: nil, lines: run(rows), hints: [VaarUnitHint(kind: "salok", firstLineId: 103, author: nil)]))
    }

    func testRefusesAGapInLineIds() {
        var lines = run(small)
        lines.remove(at: 5)
        XCTAssertNil(VaarStructure.build(vaarId: 1, pauriAuthor: nil, lines: lines, hints: [VaarUnitHint(kind: "salok", firstLineId: 103, author: nil)]))
    }

    func testRefusesAnEmptyUnit() {
        var rows = small
        rows.insert((true, "ਮਃ ੨ ॥"), at: 5)    // two labels back to back: the first has no verse
        XCTAssertNil(VaarStructure.build(vaarId: 1, pauriAuthor: nil, lines: run(rows), hints: [VaarUnitHint(kind: "salok", firstLineId: 103, author: nil)]))
    }

    func testDhuniRubricWithoutHeaderFlagJoinsTheHeading() throws {
        var rows = small
        rows.insert((false, "ਕਿਸੇ ਕੀ ਧੁਨੀ ॥"), at: 2)
        let t = try XCTUnwrap(VaarStructure.build(vaarId: 1, pauriAuthor: nil, lines: run(rows),
                                                  hints: [VaarUnitHint(kind: "salok", firstLineId: 102, author: nil)]))
        XCTAssertEqual(t.dhuni?.id, 102)
        XCTAssertEqual(t.heading.map(\.id), [100, 101, 102])
        XCTAssertEqual(t.units.first?.label?.id, 103)
    }

    func testUnlabelledVaarSplitsAtHints() throws {
        let rows: [(Bool, String)] = [
            (true, "ਟੇਸਟ ਕੀ ਵਾਰ"), (true, "ੴ ਸਤਿਗੁਰ ਪ੍ਰਸਾਦਿ ॥"),
            (false, "ਇਕ ॥"), (false, "ਦੋ ॥੧॥"), (false, "ਤਿੰਨ ॥"), (false, "ਚਾਰ ॥੨॥"),
        ]
        let hints = [VaarUnitHint(kind: "pauri", firstLineId: 102, author: "Satta & Balwand"),
                     VaarUnitHint(kind: "pauri", firstLineId: 104, author: "Satta & Balwand")]
        let t = try XCTUnwrap(VaarStructure.build(vaarId: 16, pauriAuthor: "Satta & Balwand", lines: run(rows), hints: hints))
        XCTAssertEqual(t.units.map(\.pauriNo), [1, 2])
        XCTAssertEqual(t.units.map { $0.lines.map(\.id) }, [[102, 103], [104, 105]])
    }

    func testVerseBeforeTheFirstLabelIsAUnit() throws {
        // Maru M5: the title carries the first ਡਖਣੇ's label.
        let rows: [(Bool, String)] = [
            (true, "ਟੇਸਟ ਵਾਰ ਮਹਲਾ ੫ ਡਖਣੇ ਮਃ ੫"), (true, "ੴ ਸਤਿਗੁਰ ਪ੍ਰਸਾਦਿ ॥"),
            (false, "ਡਖਣਾ ॥੧॥"), (true, "ਪਉੜੀ ॥"), (false, "ਪਉੜੀ ॥੧॥"),
        ]
        let t = try XCTUnwrap(VaarStructure.build(vaarId: 18, pauriAuthor: "Guru Arjan Dev Ji (M5)", lines: run(rows),
                                                  hints: [VaarUnitHint(kind: "salok", firstLineId: 102, author: "Guru Arjan Dev Ji (M5)")]))
        XCTAssertEqual(t.units.map(\.kind), [.salok, .pauri])
        XCTAssertNil(t.units[0].label)
        XCTAssertEqual(t.units[0].author, "Guru Arjan Dev Ji (M5)")
    }

    func testLabelGrammar() {
        func label(_ s: String, header: Bool = true) -> Bool {
            VaarStructure.isLabel(VaarLine(id: 1, ang: 1, isHeader: header, gurmukhi: s))
        }
        XCTAssertTrue(label("ਸਲੋਕੁ ਮਃ ੧ ॥"))
        XCTAssertTrue(label("ਪਉੜੀ ਨਵੀ ਮਃ ੫ ॥"))
        XCTAssertTrue(label("ਪਵੜੀ ॥", header: false))
        XCTAssertTrue(label("ਮਰਦਾਨਾ ੧ ॥", header: false))
        XCTAssertFalse(label("ਮਃ ੧ ॥੨॥"), "a verse number is never a label")
        XCTAssertFalse(label("ਸਲੋਕ ਪੜਿ ਪੜਿ ਪੰਡਿਤ ਥਕੇ ॥", header: false), "a verse that opens with a label word")
        XCTAssertEqual(VaarStructure.author(ofLabel: "ਸਲੋਕ ਡਖਣੇ ਮਃ ੫ ॥"), "Guru Arjan Dev Ji (M5)")
        XCTAssertEqual(VaarStructure.author(ofLabel: "ਸਲੋਕ ਮਹਲਾ ੨ ॥"), "Guru Angad Dev Ji (M2)")
        XCTAssertEqual(VaarStructure.author(ofLabel: "ਸਲੋਕੁ ਮਰਦਾਨਾ ੧ ॥"), "Bhai Mardana")
        XCTAssertNil(VaarStructure.author(ofLabel: "ਪਉੜੀ ੫ ॥"), "a pauri number is not a Mahalla")
        XCTAssertNil(VaarStructure.author(ofLabel: "ਸਲੋਕ ॥"))
        XCTAssertEqual(VaarStructure.verseNumbers(in: "ਤੁਕ ॥੨੨॥੧॥ ਸੁਧੁ"), [22, 1])
        XCTAssertTrue(VaarStructure.isDhuni("ਲਲਾਂ ਬਹਲੀਮਾ ਕੀ ਧੁਨਿ ਗਾਵਣੀ"))
    }
}
