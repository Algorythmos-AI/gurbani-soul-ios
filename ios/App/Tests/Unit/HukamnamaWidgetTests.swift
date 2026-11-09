import XCTest
import SwiftUI
import WidgetKit
@testable import SGGS

// The "Hukamnama · Sri Harmandir Sahib" widget: its pure timeline (keyed to the Amritsar date)
// and its face in every family. The verse is the corpus-generated fixture
// (Tests/Fixtures/hukamnama-entry.json, ios/tools/hukamnama_fixture.py), never hand-typed.

private func fixtureEntry() throws -> HukamnamaEntry {
    let url = try XCTUnwrap(Bundle(for: HukamnamaTimelineTests.self).url(forResource: "hukamnama-entry", withExtension: "json"),
                            "fixture hukamnama-entry.json missing from the test bundle")
    return try HukamnamaStore.decoder.decode(HukamnamaEntry.self, from: Data(contentsOf: url))
}

/// `key` at `hour:minute` in Amritsar.
private func ist(_ key: String, _ hour: Int, _ minute: Int = 0) -> Date {
    AmritsarDate.startOfDay(key)!.addingTimeInterval(TimeInterval(hour * 3600 + minute * 60))
}

private func entry(_ base: HukamnamaEntry, date: String, status: HukamnamaEntry.Status = .published) -> HukamnamaEntry {
    var e = base
    e.amritsarDate = date
    e.status = status
    return e
}

final class HukamnamaTimelineTests: XCTestCase {
    private let today = "2026-11-09", yesterday = "2026-11-08"

    func testTodaysPublishedIsToday() throws {
        let t = entry(try fixtureEntry(), date: today)
        XCTAssertEqual(HukamnamaTimeline.state(entries: [t], now: ist(today, 6)), .today(t))
        XCTAssertEqual(HukamnamaTimeline.state(entries: [t], now: ist(today, 23, 59)), .today(t))
    }

    func testBeforePublishYesterdaysIsCurrentNotToday() throws {
        let y = entry(try fixtureEntry(), date: yesterday)
        XCTAssertEqual(HukamnamaTimeline.state(entries: [y], now: ist(today, 3)), .current(y))
        XCTAssertEqual(HukamnamaTimeline.state(entries: [y], now: ist(today, 5, 29)), .current(y))
        XCTAssertEqual(HukamnamaTimeline.state(entries: [y], now: ist(today, 5, 30)), .notYet(previous: y))
    }

    func testOlderThanYesterdayIsNeverCurrent() throws {
        let old = entry(try fixtureEntry(), date: "2026-11-06")
        XCTAssertEqual(HukamnamaTimeline.state(entries: [old], now: ist(today, 3)), .notYet(previous: old))
    }

    func testDelayedAfterTwoPmOrWhenHeld() throws {
        let y = entry(try fixtureEntry(), date: yesterday)
        XCTAssertEqual(HukamnamaTimeline.state(entries: [y], now: ist(today, 13, 59)), .notYet(previous: y))
        XCTAssertEqual(HukamnamaTimeline.state(entries: [y], now: ist(today, 14)), .delayed(previous: y))
        let held = HukamnamaEntry(amritsarDate: today, status: .held)
        XCTAssertEqual(HukamnamaTimeline.state(entries: [y, held], now: ist(today, 6)), .delayed(previous: y))
        let pending = HukamnamaEntry(amritsarDate: today, status: .pending)
        XCTAssertEqual(HukamnamaTimeline.state(entries: [y, pending], now: ist(today, 6)), .notYet(previous: y))
    }

    func testEmptyStore() {
        XCTAssertEqual(HukamnamaTimeline.state(entries: [], now: ist(today, 9)), .empty)
        XCTAssertNil(HukamnamaTimeline.shown(.empty))
    }

    func testAFutureDateIsNeverShownAsToday() throws {
        // a skewed or hostile entry for tomorrow must not be presented today
        let tomorrow = entry(try fixtureEntry(), date: "2026-11-10")
        XCTAssertEqual(HukamnamaTimeline.state(entries: [tomorrow], now: ist(today, 9)), .notYet(previous: nil))
    }

    func testTheDayTurnsOnAmritsarTimeNotLocalTime() throws {
        // 20:00 in Vancouver on 8 Nov (UTC−8) is 09:30 on 9 Nov in Amritsar.
        let t = entry(try fixtureEntry(), date: today)
        var c = DateComponents(); c.year = 2026; c.month = 11; c.day = 8; c.hour = 20; c.minute = 0
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "America/Vancouver")!
        let vancouverEvening = try XCTUnwrap(cal.date(from: c))
        XCTAssertEqual(AmritsarDate.key(vancouverEvening), today)
        XCTAssertEqual(HukamnamaTimeline.state(entries: [t], now: vancouverEvening), .today(t))
    }

    /// The closing-entry rule: with no reload at all, yesterday's verse is never shown as today's.
    func testTimelineCarriesItsOwnStateChanges() throws {
        let t = entry(try fixtureEntry(), date: today)
        let built = HukamnamaTimeline.build(entries: [t], localScripture: t.scriptureSHA256, now: ist(today, 20))
        XCTAssertEqual(built.entries.first?.state, .today(t))
        let dates = built.entries.map(\.date)
        XCTAssertEqual(dates, dates.sorted())
        XCTAssertTrue(dates.contains(ist("2026-11-10", 0)), "no entry at Amritsar midnight")
        XCTAssertTrue(dates.contains(ist("2026-11-10", 5, 30)), "no entry at 05:30 IST")
        XCTAssertTrue(dates.contains(ist("2026-11-10", 14)), "no entry at 14:00 IST")
        for e in built.entries where e.date >= ist("2026-11-10", 0) {
            if case .today = e.state { XCTFail("9 Nov's Hukamnama presented as today's at \(e.date)") }
        }
        let afterMidnight = try XCTUnwrap(built.entries.first { $0.date == ist("2026-11-10", 0) })
        XCTAssertEqual(afterMidnight.state, .current(t))
        let afterPublish = try XCTUnwrap(built.entries.first { $0.date == ist("2026-11-10", 5, 30) })
        XCTAssertEqual(afterPublish.state, .notYet(previous: t))
    }

    func testRefreshSchedule() {
        let next0535 = ist("2026-11-10", 5, 35)
        XCTAssertEqual(HukamnamaTimeline.refresh(now: ist(today, 7), hasToday: true), next0535)
        XCTAssertEqual(HukamnamaTimeline.refresh(now: ist(today, 2), hasToday: false), ist(today, 5, 35))
        XCTAssertEqual(HukamnamaTimeline.refresh(now: ist(today, 6), hasToday: false), ist(today, 6, 20))
        XCTAssertEqual(HukamnamaTimeline.refresh(now: ist(today, 8, 50), hasToday: false), ist(today, 9))
        XCTAssertEqual(HukamnamaTimeline.refresh(now: ist(today, 10), hasToday: false), ist(today, 12))
        XCTAssertEqual(HukamnamaTimeline.refresh(now: ist(today, 13), hasToday: false), next0535)
        // about 15 reloads on a late morning, inside WidgetKit's budget
        var now = ist(today, 0, 1), n = 0
        while now < next0535 { now = HukamnamaTimeline.refresh(now: now, hasToday: false); n += 1 }
        XCTAssertLessThanOrEqual(n, 16)
    }

    func testFetchOnlyInsideTheWindowAndOnlyUntilPublished() throws {
        let y = entry(try fixtureEntry(), date: yesterday), t = entry(try fixtureEntry(), date: today)
        XCTAssertFalse(HukamnamaTimeline.shouldFetch(entries: [y], now: ist(today, 4)))
        XCTAssertTrue(HukamnamaTimeline.shouldFetch(entries: [y], now: ist(today, 6)))
        XCTAssertTrue(HukamnamaTimeline.shouldFetch(entries: [], now: ist(today, 6)))
        XCTAssertFalse(HukamnamaTimeline.shouldFetch(entries: [y, t], now: ist(today, 6)))
        XCTAssertFalse(HukamnamaTimeline.shouldFetch(entries: [y], now: ist(today, 15)))
    }

    func testVerseOnlyWithAMatchingFingerprint() throws {
        let t = try fixtureEntry()
        XCTAssertTrue(HukamnamaTimeline.verseAllowed(t, local: t.scriptureSHA256))
        XCTAssertTrue(HukamnamaTimeline.verseAllowed(t, local: nil))
        XCTAssertFalse(HukamnamaTimeline.verseAllowed(t, local: String(repeating: "0", count: 64)))
        var noVerse = t; noVerse.openingGurmukhi = nil
        XCTAssertFalse(HukamnamaTimeline.verseAllowed(noVerse, local: t.scriptureSHA256))
        XCTAssertFalse(HukamnamaTimeline.verseAllowed(nil, local: nil))
        let built = HukamnamaTimeline.build(entries: [entry(t, date: today)],
                                            localScripture: String(repeating: "0", count: 64), now: ist(today, 9))
        XCTAssertEqual(built.entries.first?.verseShown, false)
    }
}

/// Renders `HukamnamaWidgetView` — the real widget face, which lives in Shared/ — in every family
/// and state, light and dark, through `ImageRenderer`; writes PNGs to `SGGS_WIDGET_SNAPSHOT_DIR`
/// for review; and gates the citation (never truncated, up to AX2) like HukamWidgetRenderTests.
@MainActor
final class HukamnamaWidgetRenderTests: XCTestCase {
    private let families: [(WidgetFamily, CGSize, String)] = [
        (.systemSmall, CGSize(width: 158, height: 158), "small"),
        (.systemMedium, CGSize(width: 338, height: 158), "medium"),
        (.systemLarge, CGSize(width: 338, height: 354), "large"),
        (.accessoryCircular, CGSize(width: 72, height: 72), "circular"),
        (.accessoryRectangular, CGSize(width: 172, height: 76), "rectangular"),
        (.accessoryInline, CGSize(width: 260, height: 24), "inline"),
    ]
    private let inset: CGFloat = 14

    private func states() throws -> [(String, HukamnamaTimeline.Entry)] {
        let t = try fixtureEntry()
        let now = ist(t.amritsarDate, 9)
        return [
            ("today", .init(date: now, state: .today(t), verseShown: true)),
            ("notyet", .init(date: now, state: .notYet(previous: t), verseShown: true)),
            ("delayed", .init(date: now, state: .delayed(previous: nil), verseShown: false)),
            ("mismatch", .init(date: now, state: .today(t), verseShown: false)),
            ("empty", .init(date: now, state: .empty, verseShown: false)),
        ]
    }

    private func face(_ e: HukamnamaTimeline.Entry, family: WidgetFamily, size: CGSize, dark: Bool,
                      typeSize: DynamicTypeSize = .large) -> some View {
        let accessory = [.accessoryCircular, .accessoryRectangular, .accessoryInline].contains(family)
        return ZStack {
            if accessory { Color.black } else { PaperGround() }
            HukamnamaWidgetView(entry: e, family: family).padding(accessory ? 4 : inset)
        }
        .frame(width: size.width, height: size.height)
        .environment(\.colorScheme, accessory || dark ? .dark : .light)
        .environment(\.dynamicTypeSize, typeSize)
    }

    func testRendersEveryFamilyAndState() throws {
        let out = ProcessInfo.processInfo.environment["SGGS_WIDGET_SNAPSHOT_DIR"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("sggs-widget-snapshots")
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        for (stateName, e) in try states() {
            for (family, size, name) in families {
                for dark in [false, true] {
                    let r = ImageRenderer(content: face(e, family: family, size: size, dark: dark))
                    r.scale = 3
                    let img = try XCTUnwrap(r.uiImage, "hukamnama \(name) \(stateName) failed to render")
                    XCTAssertGreaterThan(img.size.width, 0)
                    if let png = img.pngData() {
                        try png.write(to: out.appendingPathComponent("hukamnama-\(name)-\(stateName)-\(dark ? "dark" : "light").png"))
                    }
                }
            }
        }
    }

    func testCopyNeverCallsItTheHukamOfTheDay() {
        // G3 R6, both ways round
        for s in [HukamnamaWidgetView.name, HukamnamaWidgetView.emptyText,
                  HukamnamaWidgetView.notYetText, HukamnamaWidgetView.delayedText] {
            XCTAssertFalse(s.localizedCaseInsensitiveContains("of the day"), s)
        }
        XCTAssertEqual(HukamnamaWidgetView.name, "Hukamnama · Sri Harmandir Sahib")
    }

    /// "Sri Guru Granth Sahib Ji · Ang N" reads in full on every Home Screen family, at every type
    /// size up to AX2 (it clamps at xxxLarge), for a 3- and a 4-digit Ang.
    func testCitationIsNeverTruncated() throws {
        var e = try fixtureEntry()
        for ang in [673, 1429] {
            e.ang = ang
            let entry = HukamnamaTimeline.Entry(date: .now, state: .today(e), verseShown: true)
            for (family, size, name) in families.prefix(3) {
                for typeSize in [DynamicTypeSize.large, .xxxLarge, .accessibility1, .accessibility2] {
                    let label = "hukamnama \(name) Ang \(ang) \(typeSize)"
                    let probe = FrameProbe()
                    let host = UIHostingController(rootView:
                        face(entry, family: family, size: size, dark: false, typeSize: typeSize)
                            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { probe.root = $0 }
                            .onPreferenceChange(CitationFrameKey.self) { probe.citation = $0 })
                    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 600, height: 800))
                    window.rootViewController = host
                    window.isHidden = false
                    host.view.layoutIfNeeded()
                    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
                    window.isHidden = true
                    let cite = probe.citation, root = probe.root
                    XCTAssertFalse(cite.isNull || root.isNull, "\(label): no citation frame reported")
                    if cite.isNull || root.isNull { continue }
                    let content = root.insetBy(dx: inset - 0.5, dy: inset - 0.5)
                    XCTAssertTrue(content.contains(cite), "\(label): citation \(cite) clipped outside \(content)")
                    let needed = UIHostingController(rootView:
                        Text(Citation.displayText(ang: ang)).font(WidgetType.serif(12))
                            .environment(\.dynamicTypeSize, min(typeSize, .xxxLarge)))
                        .sizeThatFits(in: CGSize(width: cite.width + 0.5, height: .greatestFiniteMagnitude))
                    XCTAssertLessThanOrEqual(needed.height, cite.height + 1,
                                             "\(label): citation truncated — needs \(needed.height)pt, got \(cite.height)pt")
                }
            }
        }
    }
}

private final class FrameProbe: @unchecked Sendable {
    var root: CGRect = .null
    var citation: CGRect = .null
}
