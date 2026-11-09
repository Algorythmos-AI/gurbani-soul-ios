import XCTest
import GurbaniSearchKit
@testable import SGGS

// The Hukamnama from Sri Harmandir Sahib (push): schedule/DST, the registrar state machine, the
// router's strict date check, the range-hash proof + re-locate path, and the shared store.

private func utc(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0) -> Date {
    var c = Calendar(identifier: .gregorian); c.timeZone = .gmt
    return c.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
}

/// Loads a generated fixture (ios/tools/hukamnama_fixture.py) from the test bundle.
private func fixture(_ name: String, _ ext: String) throws -> Data {
    let url = try XCTUnwrap(Bundle(for: HukamnamaScheduleTests.self).url(forResource: name, withExtension: ext),
                            "fixture \(name).\(ext) missing from the test bundle")
    return try Data(contentsOf: url)
}

private func fixtureEntry() throws -> HukamnamaEntry {
    try HukamnamaStore.decoder.decode(HukamnamaEntry.self, from: fixture("hukamnama-entry", "json"))
}

// MARK: - Schedule

final class HukamnamaScheduleTests: XCTestCase {
    private func zone(_ id: String) -> TimeZone { TimeZone(identifier: id)! }

    func testKathmanduHasOneSlotAtQuarterPast() {
        // +05:45, no DST: 07:00 local is 01:15 UTC all year
        let s = HukamnamaSchedule.build(localMinute: 7 * 60, timeZone: zone("Asia/Kathmandu"), from: utc(2026, 11, 9, 12))
        XCTAssertEqual(s.map(\.slotUTCMin), [75])
        XCTAssertEqual(s[0].fromUTC, Int(utc(2026, 11, 9, 12).timeIntervalSince1970))
    }

    func testLondonCoversBothDSTChanges() {
        let s = HukamnamaSchedule.build(localMinute: 7 * 60, timeZone: zone("Europe/London"), from: utc(2026, 11, 9, 12))
        XCTAssertEqual(s.map(\.slotUTCMin), [420, 360, 420])
        // BST starts 2027-03-28: the new slot takes effect one minute after 2027-03-27's 07:00 GMT delivery
        XCTAssertEqual(s[1].fromUTC, Int(utc(2027, 3, 27, 7, 1).timeIntervalSince1970))
        // GMT returns 2027-10-31: effective after 2027-10-30's 07:00 BST (06:00 UTC) delivery
        XCTAssertEqual(s[2].fromUTC, Int(utc(2027, 10, 30, 6, 1).timeIntervalSince1970))
    }

    func testSydneyAndVancouver() {
        // AEDT (+11) → 20:00 UTC the previous day; AEST (+10) from 2027-04-04 → 21:00 UTC
        let syd = HukamnamaSchedule.build(localMinute: 7 * 60, timeZone: zone("Australia/Sydney"), from: utc(2026, 11, 9))
        XCTAssertEqual(syd.map(\.slotUTCMin), [1200, 1260, 1200])
        // PST (−8) → 15:00 UTC; PDT (−7) from 2027-03-14 → 14:00 UTC
        let van = HukamnamaSchedule.build(localMinute: 7 * 60, timeZone: zone("America/Vancouver"), from: utc(2026, 11, 9))
        XCTAssertEqual(van.map(\.slotUTCMin), [900, 840, 900])
    }

    func testEntriesAreOrderedAndInRange() {
        for id in ["Asia/Kolkata", "Asia/Kathmandu", "Europe/London", "Australia/Sydney", "America/Vancouver",
                   "Australia/Lord_Howe", "Pacific/Chatham", "America/St_Johns"] {
            for minute in [0, 150, 7 * 60, 23 * 60 + 59] {
                let s = HukamnamaSchedule.build(localMinute: minute, timeZone: zone(id), from: utc(2026, 11, 9, 3))
                XCTAssertFalse(s.isEmpty, id)
                XCTAssertEqual(s.map(\.fromUTC), s.map(\.fromUTC).sorted(), id)
                XCTAssertTrue(s.allSatisfy { (0..<1440).contains($0.slotUTCMin) }, id)
                XCTAssertLessThanOrEqual(s.count, 5, "\(id) \(minute)")   // a year of DST, never per-day noise
            }
        }
    }

    func testSpringForwardGapUsesTheNextRealTime() {
        // Sydney 2027-10-03: 02:00 → 03:00. A 02:30 alarm rings at 03:30 AEDT (16:30 UTC) that day.
        let s = HukamnamaSchedule.build(localMinute: 150, timeZone: zone("Australia/Sydney"), from: utc(2027, 9, 1))
        XCTAssertEqual(s.first?.slotUTCMin, 990)   // 02:30 AEST = 16:30 UTC
        XCTAssertEqual(s.dropFirst().first?.slotUTCMin, 930)   // 02:30 AEDT = 15:30 UTC, from the day after the gap
    }

    func testRebuildWindow() {
        let from = utc(2026, 11, 9)
        XCTAssertFalse(HukamnamaSchedule.needsRebuild(builtFrom: from, now: from.addingTimeInterval(300 * 86_400)))
        XCTAssertTrue(HukamnamaSchedule.needsRebuild(builtFrom: from, now: from.addingTimeInterval(306 * 86_400)))
        XCTAssertTrue(HukamnamaSchedule.needsRebuild(builtFrom: from, now: from.addingTimeInterval(-60)))
    }

    func testUsualPublishInstantIsHalfPastFiveIST() {
        XCTAssertEqual(HukamnamaSchedule.usualPublishInstant(now: utc(2026, 11, 9, 12)), utc(2026, 11, 9))
        // 20:00 UTC on 8 Nov is 01:30 on 9 Nov in Amritsar → that morning's 05:30 IST
        XCTAssertEqual(HukamnamaSchedule.usualPublishInstant(now: utc(2026, 11, 8, 20)), utc(2026, 11, 9))
        XCTAssertEqual(HukamnamaSchedule.usualLocalTime(now: utc(2026, 11, 9, 12), timeZone: zone("Australia/Sydney"),
                                                        locale: Locale(identifier: "en_US_POSIX")), "11:00 AM")
    }

    func testAmritsarDate() {
        XCTAssertEqual(AmritsarDate.key(utc(2026, 11, 8, 18, 30)), "2026-11-09")   // IST midnight
        XCTAssertEqual(AmritsarDate.key(utc(2026, 11, 8, 18, 29)), "2026-11-08")
        XCTAssertEqual(AmritsarDate.label("2026-11-09"), "Mon 9 Nov · Amritsar")
        for bad in ["2026-02-30", "2026-13-01", "2026-1-09", "26-11-09", "2026-11-09 ", "2026/11/09", ""] {
            XCTAssertFalse(AmritsarDate.isValidKey(bad), bad)
        }
    }
}

// MARK: - Registrar state machine

/// A settable clock the controller reads (the closure must be Sendable).
private final class TestClock: @unchecked Sendable {
    var now: Date
    init(_ now: Date) { self.now = now }
}

@MainActor
final class HukamnamaPushControllerTests: XCTestCase {
    nonisolated(unsafe) private var defaults: UserDefaults!
    nonisolated(unsafe) private var suiteName = ""
    private let clock = TestClock(utc(2026, 11, 9, 3))
    private let tokenA = String(repeating: "a1", count: 32)
    private let tokenB = String(repeating: "b2", count: 32)

    override func setUp() {
        suiteName = "hukamnama-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }
    override func tearDown() { defaults.removePersistentDomain(forName: suiteName) }

    private func make(_ registrar: FakePushRegistrar, _ service: FakeHukamnamaService) -> HukamnamaPushController {
        let c = clock
        return HukamnamaPushController(registrar: registrar, service: service, defaults: defaults,
                                       env: "development", scriptureSHA256: String(repeating: "0", count: 64),
                                       now: { c.now }, zone: { TimeZone(identifier: "Australia/Sydney")! })
    }

    func testTurningOnRegistersOnce() async {
        let reg = FakePushRegistrar(token: tokenA), svc = FakeHukamnamaService()
        let c = make(reg, svc)
        let on = await c.setEnabled(true)
        XCTAssertTrue(on); XCTAssertTrue(c.wanted); XCTAssertTrue(c.effective)
        let puts = await svc.puts
        XCTAssertEqual(puts.count, 1)
        XCTAssertEqual(puts.first?.token, tokenA)
        XCTAssertEqual(puts.first?.body.env, "development")
        XCTAssertEqual(puts.first?.body.mode, .asap)
        XCTAssertNil(puts.first?.body.schedule, "asap sends no schedule")
        XCTAssertNil(puts.first?.body.replaces)
        // a foreground with nothing changed sends nothing
        await c.refresh()
        let after = await svc.puts.count
        XCTAssertEqual(after, 1)
    }

    func testPromptOnlyFromTheToggleAndDenialSnapsBack() async {
        let reg = FakePushRegistrar(status: .notDetermined, grants: false), svc = FakeHukamnamaService()
        let c = make(reg, svc)
        await c.refresh()   // wanted is off: a foreground never prompts
        let before = await reg.promptCount
        XCTAssertEqual(before, 0)
        let on = await c.setEnabled(true)
        XCTAssertFalse(on); XCTAssertFalse(c.wanted); XCTAssertTrue(c.denied)
        let prompts = await reg.promptCount, puts = await svc.puts.count
        XCTAssertEqual(prompts, 1); XCTAssertEqual(puts, 0)
    }

    func testRegistrationFailureLeavesNothingHalfRegistered() async {
        let reg = FakePushRegistrar(token: tokenA), svc = FakeHukamnamaService()
        await reg.set(fails: true)
        let c = make(reg, svc)
        let on = await c.setEnabled(true)
        XCTAssertFalse(on); XCTAssertFalse(c.wanted)
        XCTAssertEqual(c.message, HukamnamaPushController.couldNotTurnOn)
        let puts = await svc.puts.count
        XCTAssertEqual(puts, 0)
    }

    func testServerUnreachableOnEnableSnapsBackAndQueuesCleanup() async {
        let reg = FakePushRegistrar(token: tokenA), svc = FakeHukamnamaService()
        await svc.setOffline(true)
        let c = make(reg, svc)
        let on = await c.setEnabled(true)
        XCTAssertFalse(on); XCTAssertFalse(c.wanted)
        XCTAssertEqual(c.message, HukamnamaPushController.couldNotTurnOn)
        XCTAssertEqual(c.deleteQueue, [tokenA], "a PUT whose answer was lost must not leave a row behind")
        await svc.setOffline(false)
        await c.refresh()
        let deletes = await svc.deletes
        XCTAssertEqual(deletes, [tokenA]); XCTAssertEqual(c.deleteQueue, [])
    }

    func testReacknowledgesAfter24HoursAndHealsALostTable() async {
        let reg = FakePushRegistrar(token: tokenA), svc = FakeHukamnamaService()
        let c = make(reg, svc)
        _ = await c.setEnabled(true)
        await svc.dropAllRows()                      // the server lost its table
        clock.now = clock.now.addingTimeInterval(23 * 3600)
        await c.refresh()
        var count = await svc.puts.count
        XCTAssertEqual(count, 1, "within 24 h and unchanged: no PUT")
        clock.now = clock.now.addingTimeInterval(2 * 3600)
        await c.refresh()
        count = await svc.puts.count
        XCTAssertEqual(count, 2, "after 24 h: re-acknowledged")
        let rows = await svc.rows
        XCTAssertNotNil(rows[tokenA], "the row is back after one foreground")
    }

    func testTokenRotationSendsReplaces() async {
        let reg = FakePushRegistrar(token: tokenA), svc = FakeHukamnamaService()
        let c = make(reg, svc)
        _ = await c.setEnabled(true)
        await reg.set(token: tokenB)
        await c.refresh()
        let puts = await svc.puts, rows = await svc.rows
        XCTAssertEqual(puts.count, 2)
        XCTAssertEqual(puts.last?.token, tokenB)
        XCTAssertEqual(puts.last?.body.replaces, tokenA)
        XCTAssertNil(rows[tokenA]); XCTAssertNotNil(rows[tokenB])
        XCTAssertEqual(c.ack?.token, tokenB)
    }

    func testDeniedInSettingsDeletesThenRestores() async {
        let reg = FakePushRegistrar(token: tokenA), svc = FakeHukamnamaService()
        let c = make(reg, svc)
        _ = await c.setEnabled(true)
        await reg.set(status: .denied)
        await c.refresh()
        let deletes = await svc.deletes
        XCTAssertEqual(deletes, [tokenA])
        XCTAssertTrue(c.wanted, "the reader still wants it"); XCTAssertFalse(c.effective); XCTAssertTrue(c.denied)
        XCTAssertNil(c.ack)
        await reg.set(status: .authorized)
        await c.refresh()
        let rows = await svc.rows
        XCTAssertNotNil(rows[tokenA], "permission back → PUT again")
        XCTAssertTrue(c.effective); XCTAssertFalse(c.denied)
    }

    func testAlertsOffCountsAsDenied() async {
        let reg = FakePushRegistrar(token: tokenA), svc = FakeHukamnamaService()
        let c = make(reg, svc)
        _ = await c.setEnabled(true)
        await reg.set(alerts: false)
        await c.refresh()
        let rows = await svc.rows
        XCTAssertNil(rows[tokenA]); XCTAssertTrue(c.denied)
    }

    func testTurningOffOfflineQueuesTheDelete() async {
        let reg = FakePushRegistrar(token: tokenA), svc = FakeHukamnamaService()
        let c = make(reg, svc)
        _ = await c.setEnabled(true)
        await svc.setOffline(true)
        let on = await c.setEnabled(false)
        XCTAssertFalse(on); XCTAssertFalse(c.wanted)
        XCTAssertEqual(c.deleteQueue, [tokenA])
        await c.refresh()   // still offline: kept
        XCTAssertEqual(c.deleteQueue, [tokenA])
        await svc.setOffline(false)
        await c.refresh()   // a later launch
        XCTAssertEqual(c.deleteQueue, [])
        let rows = await svc.rows
        XCTAssertNil(rows[tokenA])
    }

    func testScheduledModeSendsAStableSchedule() async {
        let reg = FakePushRegistrar(token: tokenA), svc = FakeHukamnamaService()
        let c = make(reg, svc)
        _ = await c.setEnabled(true)
        c.setMode(.scheduled)
        c.setMinute(6 * 60 + 30)
        let first = c.currentBody(replaces: nil)
        XCTAssertEqual(first.mode, .scheduled)
        XCTAssertEqual(first.schedule?.count, 3, "Sydney: two DST changes in a year")
        clock.now = clock.now.addingTimeInterval(3 * 86_400)
        XCTAssertEqual(c.currentBody(replaces: nil), first, "the schedule is anchored: no PUT just because a day passed")
        // the body (with a 200-char token in the URL, not the body) stays small
        let data = try? HukamnamaDeviceBody.encoder.encode(HukamnamaDeviceBody(
            env: "production", mode: .scheduled, schedule: first.schedule, scriptureSHA256: first.scriptureSHA256,
            replaces: String(repeating: "f", count: 200)))
        XCTAssertLessThan(data?.count ?? .max, 1024)
    }

    func testDigestIgnoresReplaces() {
        let b = HukamnamaDeviceBody(env: "production", mode: .asap, schedule: nil, scriptureSHA256: nil, replaces: nil)
        var r = b; r.replaces = tokenA
        XCTAssertEqual(b.digest(token: tokenB), r.digest(token: tokenB))
        XCTAssertNotEqual(b.digest(token: tokenA), b.digest(token: tokenB))
    }

    func testTokenShape() {
        XCTAssertTrue(HukamnamaDeviceBody.isValidToken(tokenA))
        XCTAssertFalse(HukamnamaDeviceBody.isValidToken(String(repeating: "A", count: 64)), "uppercase")
        XCTAssertFalse(HukamnamaDeviceBody.isValidToken(String(repeating: "a", count: 63)))
        XCTAssertFalse(HukamnamaDeviceBody.isValidToken(String(repeating: "a", count: 201)))
    }

    // The broker: a token that arrived before the toggle was saved is used; a late one resolves the wait.
    func testBrokerTokenBeforeAndAfterTheWait() async throws {
        let broker = PushTokenBroker()
        broker.deliver(hex: tokenA)
        let early = try await broker.requestToken(timeout: .milliseconds(50))
        XCTAssertEqual(early, tokenA, "a token delivered before the wait is used once the wait times out")

        let fresh = PushTokenBroker()
        fresh.trigger = { [weak fresh] in
            Task { @MainActor in fresh?.deliver(token: Data([0xde, 0xad, 0xbe, 0xef])) }
        }
        let late = try await fresh.requestToken(timeout: .seconds(5))
        XCTAssertEqual(late, "deadbeef")

        let failing = PushTokenBroker()
        failing.trigger = { [weak failing] in Task { @MainActor in failing?.deliverFailure() } }
        do { _ = try await failing.requestToken(timeout: .seconds(5)); XCTFail("expected a failure") }
        catch { XCTAssertEqual(error as? PushRegistrationError, .failed) }

        let silent = PushTokenBroker()
        do { _ = try await silent.requestToken(timeout: .milliseconds(50)); XCTFail("expected a timeout") }
        catch { XCTAssertEqual(error as? PushRegistrationError, .timedOut) }
    }
}

// MARK: - Router + notification routing

@MainActor
final class HukamnamaRouterTests: XCTestCase {
    private let now = utc(2026, 11, 9, 3)

    func testStrictTargets() {
        XCTAssertEqual(Router.hukamnamaTarget(URL(string: "sggs://hukamnama")!, now: now), .latest)
        XCTAssertEqual(Router.hukamnamaTarget(URL(string: "sggs://hukamnama/")!, now: now), .latest)
        XCTAssertEqual(Router.hukamnamaTarget(URL(string: "sggs://hukamnama/2026-11-09")!, now: now), .date("2026-11-09"))
        XCTAssertEqual(Router.hukamnamaTarget(URL(string: "sggs://hukamnama/2025-10-06")!, now: now), .date("2025-10-06"))
        for bad in ["sggs://hukamnama/2026-11-9", "sggs://hukamnama/2026-02-30", "sggs://hukamnama/2026-13-01",
                    "sggs://hukamnama/26-11-09", "sggs://hukamnama/2026-11-09x", "sggs://hukamnama/2026-11-09/more",
                    "sggs://hukamnama/today", "sggs://hukamnama/2028-01-01", "sggs://hukamnama/2025-09-01",
                    "sggs://hukam/2026-11-09", "https://hukamnama/2026-11-09", "sggs://hukamnama/%32026-11-09",
                    "sggs://user@hukamnama/2026-11-09", "sggs://hukamnama:80/2026-11-09"] {
            XCTAssertNil(Router.hukamnamaTarget(URL(string: bad)!, now: now), bad)
        }
    }

    func testPresentationIdCarriesTheDate() {
        XCTAssertEqual(Presentation.hukamnama(date: "2026-11-09").id, "hukamnama-2026-11-09")
        XCTAssertEqual(Presentation.hukamnama(date: nil).id, "hukamnama-latest")
        XCTAssertNotEqual(Presentation.hukamnama(date: nil).id, Presentation.hukamOfTheDay.id)
        XCTAssertNil(Presentation.hukamnama(date: nil).composition, "never the shabad/Hukam sheet")
    }

    func testNotificationRouting() {
        let good: [AnyHashable: Any] = ["url": "sggs://hukamnama/2026-11-09"]
        XCTAssertEqual(NotificationRouter.openURL(threadIdentifier: "hukamnama", userInfo: good, now: now)?.absoluteString,
                       "sggs://hukamnama/2026-11-09")
        for bad in ["sggs://hukamnama/2026-11-31", "sggs://ang/1", "javascript:alert(1)", ""] {
            XCTAssertEqual(NotificationRouter.openURL(threadIdentifier: "hukamnama", userInfo: ["url": bad], now: now)?.absoluteString,
                           "sggs://hukamnama", bad)
        }
        XCTAssertEqual(NotificationRouter.openURL(threadIdentifier: "hukamnama", userInfo: [:], now: now)?.absoluteString,
                       "sggs://hukamnama")
        // reminders keep their behaviour
        XCTAssertEqual(NotificationRouter.openURL(threadIdentifier: "", userInfo: [:], now: now)?.absoluteString, "sggs://nitnem")
        XCTAssertEqual(NotificationRouter.presentationOptions(threadIdentifier: "hukamnama"), [.list])
        XCTAssertEqual(NotificationRouter.presentationOptions(threadIdentifier: ""), [])
    }
}

// MARK: - Range proof against the app's own corpus

/// A line source that serves the real corpus with a deliberate fault, to prove the sheet refuses.
private struct FaultyLineSource: HukamnamaLineSource {
    let corpus: CorpusActor
    var shiftIds = 0                       // pretend the DB's ids moved
    var corruptLineId: Int? = nil          // serve one line with altered text
    func lines(from first: Int, to last: Int) async throws -> [ReaderLine] {
        let rows = try await corpus.lines(from: first + shiftIds, to: last + shiftIds)
        return rows.map { l in
            guard l.id == corruptLineId else { return l }
            return ReaderLine(id: l.id, ang: l.ang, raag: l.raag, section: l.section, author: l.author,
                              compType: l.compType, compId: l.compId, lineNo: l.lineNo, isRahao: l.isRahao,
                              isHeader: l.isHeader, gurmukhi: l.gurmukhi + "x", translit: l.translit, markers: l.markers)
        }
    }
    func angLines(_ n: Int) async throws -> [ReaderLine] { try await lines(from: 1, to: 0) + corpus.angLines(n) }
}

final class HukamnamaLocatorTests: XCTestCase {
    func testFixtureHashMatchesTheCorpus() async throws {
        // range_sha256 was computed in Python (ios/tools/hukamnama_fixture.py); Swift must agree
        let corpus = try CorpusActor()
        let e = try fixtureEntry()
        let lines = try await corpus.lines(from: e.firstLineId!, to: e.lastLineId!)
        XCTAssertEqual(HukamnamaLocator.rangeSHA256(lines.map(\.gurmukhi)), e.rangeSHA256)
        XCTAssertEqual(lines.first(where: { !$0.isHeader })?.gurmukhi, e.openingGurmukhi)
        XCTAssertEqual(e.scriptureSHA256, HukamnamaConfig.scriptureSHA256, "fixture built from this corpus")
        let r = await HukamnamaLocator.resolve(e, source: corpus)
        XCTAssertEqual(r, .verified(lines))
    }

    func testMovedIdsTakeTheRelocatePath() async throws {
        let corpus = try CorpusActor()
        var e = try fixtureEntry()
        let truth = try await corpus.lines(from: e.firstLineId!, to: e.lastLineId!)
        e.firstLineId! += 3; e.lastLineId! += 3   // the server's ids are off by three
        let r = await HukamnamaLocator.resolve(e, source: corpus)
        XCTAssertEqual(r, .relocated(truth), "found again by Ang + opening verse, proven by the hash")
    }

    func testMismatchedTextIsNeverShown() async throws {
        let corpus = try CorpusActor()
        let e = try fixtureEntry()
        let r = await HukamnamaLocator.resolve(e, source: FaultyLineSource(corpus: corpus, corruptLineId: e.firstLineId! + 2))
        XCTAssertEqual(r, .needsUpdate(ang: e.ang))
        var wrongHash = e
        wrongHash.rangeSHA256 = String(repeating: "0", count: 64)
        let r2 = await HukamnamaLocator.resolve(wrongHash, source: corpus)
        XCTAssertEqual(r2, .needsUpdate(ang: e.ang))
        var noOpening = e
        noOpening.firstLineId! += 1; noOpening.lastLineId! += 1; noOpening.openingGurmukhi = nil
        let r3 = await HukamnamaLocator.resolve(noOpening, source: corpus)
        XCTAssertEqual(r3, .needsUpdate(ang: e.ang), "no opening verse: nothing to re-locate by")
    }

    func testUnlocatableEntries() throws {
        var e = try fixtureEntry()
        XCTAssertTrue(e.isLocatable)
        e.lastLineId = e.firstLineId! + HukamnamaEntry.maxRangeLines
        XCTAssertFalse(e.isLocatable, "an absurd span is refused, never queried")
        e = try fixtureEntry(); e.status = .pending
        XCTAssertFalse(e.isLocatable)
        e = try fixtureEntry(); e.rangeSHA256 = "ABC"
        XCTAssertFalse(e.isLocatable)
    }
}

// MARK: - Shared store + push payload

final class HukamnamaStoreTests: XCTestCase {
    private var dir: URL!
    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("hukamnama-\(UUID().uuidString)")
    }
    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    private func entry(_ date: String, _ status: HukamnamaEntry.Status = .published, hash: String = String(repeating: "a", count: 64),
                       opening: String? = nil) -> HukamnamaEntry {
        Self.entry(date, status, hash: hash, opening: opening)
    }
    private static func entry(_ date: String, _ status: HukamnamaEntry.Status = .published, hash: String = String(repeating: "a", count: 64),
                              opening: String? = nil) -> HukamnamaEntry {
        HukamnamaEntry(amritsarDate: date, status: status, ang: 1, firstLineId: 1, lastLineId: 2,
                       openingGurmukhi: opening, rangeSHA256: status == .published ? hash : nil)
    }
    private func day(_ i: Int) -> String { Self.day(i) }
    private static func day(_ i: Int) -> String { String(format: "2026-11-%02d", i) }

    func testMergeRules() {
        var m = HukamnamaStore.merged(existing: [], incoming: (1...9).map { entry(day($0)) })
        XCTAssertEqual(m.map(\.amritsarDate), (3...9).reversed().map(day), "the newest 7 dates, newest first")
        // a later pending read never downgrades a published day
        m = HukamnamaStore.merged(existing: m, incoming: [entry(day(9), .pending)])
        XCTAssertEqual(m.first?.status, .published)
        // a correction (a different range) replaces the first
        let corrected = String(repeating: "b", count: 64)
        m = HukamnamaStore.merged(existing: m, incoming: [entry(day(9), hash: corrected)])
        XCTAssertEqual(m.first?.rangeSHA256, corrected)
        // the same range from a push (no opening field) keeps the stored opening
        m = HukamnamaStore.merged(existing: [entry(day(9), opening: "verse")], incoming: [entry(day(9))])
        XCTAssertEqual(m.first?.openingGurmukhi, "verse")
        // pending → published upgrades; malformed dates are dropped
        m = HukamnamaStore.merged(existing: [entry(day(9), .pending)], incoming: [entry(day(9)), entry("2026-11-31")])
        XCTAssertEqual(m.map(\.status), [.published])
    }

    func testFileRoundTripKeepsSeparateFromTheWidgetSnapshot() {
        let url = dir.appendingPathComponent(HukamnamaStore.filename)
        XCTAssertNotEqual(HukamnamaStore.filename, WidgetStore.filename)
        HukamnamaStore.merge([entry(day(8))], url: url)
        HukamnamaStore.merge([entry(day(9), .pending)], url: url)
        XCTAssertEqual(HukamnamaStore.load(url: url).map(\.amritsarDate), [day(9), day(8)])
        XCTAssertEqual(HukamnamaStore.latestPublished(url: url)?.amritsarDate, day(8))
    }

    func testConcurrentWritersNeverLoseAnUpdate() {
        // the app and the NSE write the same file; every coordinated merge must survive
        for round in 0..<10 {
            let url = dir.appendingPathComponent("round-\(round).json")
            DispatchQueue.concurrentPerform(iterations: HukamnamaStore.keep) { i in
                HukamnamaStore.merge([Self.entry(Self.day(i + 1))], url: url)
            }
            XCTAssertEqual(Set(HukamnamaStore.load(url: url).map(\.amritsarDate)),
                           Set((1...HukamnamaStore.keep).map(day)), "round \(round)")
        }
    }

    func testPushPayloadFixture() throws {
        let obj = try JSONSerialization.jsonObject(with: fixture("hukamnama", "apns")) as? [String: Any]
        let info = try XCTUnwrap(obj)
        let pushed = try XCTUnwrap(HukamnamaEntry(pushUserInfo: info))
        let api = try fixtureEntry()
        XCTAssertEqual(pushed.amritsarDate, api.amritsarDate)
        XCTAssertEqual(pushed.rangeSHA256, api.rangeSHA256)
        XCTAssertEqual(pushed.firstLineId, api.firstLineId); XCTAssertEqual(pushed.lastLineId, api.lastLineId)
        XCTAssertEqual(pushed.openingGurmukhi, api.openingGurmukhi, "the verse is the body minus our exact citation line")
        XCTAssertEqual(pushed.url?.absoluteString, info["url"] as? String)
        let aps = try XCTUnwrap(info["aps"] as? [String: Any])
        XCTAssertEqual(aps["thread-id"] as? String, NotificationRouter.hukamnamaThread)
        XCTAssertEqual(aps["interruption-level"] as? String, "active", "never time-sensitive")
        XCTAssertEqual((aps["alert"] as? [String: Any])?["subtitle"] as? String, AmritsarDate.label(api.amritsarDate))

        // a body whose last line is not our citation yields no opening (nothing is guessed)
        var odd = info
        var a = aps; var alert = (aps["alert"] as? [String: Any]) ?? [:]
        alert["body"] = "\(api.openingGurmukhi ?? "")\nAng \(api.ang ?? 0)"
        a["alert"] = alert; odd["aps"] = a
        XCTAssertNil(HukamnamaEntry(pushUserInfo: odd)?.openingGurmukhi)
        // malformed fields → not a Hukamnama entry at all
        for (k, v) in [("range_sha256", "nothex"), ("amritsar_date", "2026-11-31"), ("first_line_id", "x")] as [(String, Any)] {
            var bad = info; bad[k] = v
            XCTAssertNil(HukamnamaEntry(pushUserInfo: bad), k)
        }
    }
}
