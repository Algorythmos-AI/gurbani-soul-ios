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
        // PST (−8) → 15:00 UTC; PDT (−7) from 2027-03-14 → 14:00 UTC. (Los Angeles, not Vancouver:
        // newer tz data puts British Columbia on permanent UTC−7, so its answer depends on the OS.)
        let la = HukamnamaSchedule.build(localMinute: 7 * 60, timeZone: zone("America/Los_Angeles"), from: utc(2026, 11, 9))
        XCTAssertEqual(la.map(\.slotUTCMin), [900, 840, 900])
    }

    func testEntriesAreOrderedAndInRange() {
        for id in ["Asia/Kolkata", "Asia/Kathmandu", "Europe/London", "Australia/Sydney", "America/Vancouver", "America/Los_Angeles",
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
                                                        locale: Locale(identifier: "en_US_POSIX"))
                           .replacingOccurrences(of: "\u{202F}", with: " "), "11:00 AM")   // ICU's narrow no-break space
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

    private static let thisInstall = "install-this-phone"

    private func make(_ registrar: FakePushRegistrar, _ service: FakeHukamnamaService,
                      install: String = thisInstall) -> HukamnamaPushController {
        let c = clock
        return HukamnamaPushController(registrar: registrar, service: service, defaults: defaults,
                                       env: "development", scriptureSHA256: String(repeating: "0", count: 64),
                                       now: { c.now }, zone: { TimeZone(identifier: "Australia/Sydney")! },
                                       installID: install)
    }

    /// Polls (real time, up to 3 s) until `condition` holds — the fake service runs on its own actor.
    private func waitUntil(_ what: String, _ condition: () async -> Bool) async {
        for _ in 0..<600 {
            if await condition() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("timed out waiting for \(what)")
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

    // MARK: serial queue (the turn-off race)

    func testTurnOffWhileARefreshPutIsInFlightDeletesAfterIt() async {
        let reg = FakePushRegistrar(token: tokenA), svc = FakeHukamnamaService()
        let c = make(reg, svc)
        _ = await c.setEnabled(true)
        clock.now = clock.now.addingTimeInterval(25 * 3600)   // the next refresh re-acknowledges
        await svc.hold()
        let refreshing = Task { await c.refresh() }
        await waitUntil("the refresh PUT to start") { await svc.parkedCount == 1 }
        let off = Task { await c.setEnabled(false) }
        await waitUntil("the toggle to take effect") { !c.wanted }
        XCTAssertFalse(c.wanted, "off takes effect before anything is awaited")
        try? await Task.sleep(for: .milliseconds(50))
        let parked = await svc.parkedCount, startedWhileHeld = await svc.started
        XCTAssertEqual(parked, 1, "the DELETE waits for the PUT in flight")
        XCTAssertFalse(startedWhileHeld.contains("DELETE \(tokenA)"))
        await svc.resume()
        await refreshing.value
        let settled = await off.value
        XCTAssertFalse(settled); XCTAssertFalse(c.wanted); XCTAssertFalse(c.effective)
        let started = await svc.started, rows = await svc.rows
        XCTAssertEqual(Array(started.suffix(2)), ["PUT \(tokenA)", "DELETE \(tokenA)"], "the DELETE goes after the PUT")
        XCTAssertNil(rows[tokenA], "the late PUT left no row behind")
        XCTAssertNil(c.ack); XCTAssertEqual(c.deleteQueue, [])
        await c.refresh()
        let puts = await svc.puts.count
        XCTAssertEqual(puts, 2, "nothing re-registers once off")
    }

    func testQueuedDeleteNeverRacesTheFreshPutForTheSameToken() async {
        let reg = FakePushRegistrar(token: tokenA), svc = FakeHukamnamaService()
        let c = make(reg, svc)
        _ = await c.setEnabled(true)
        await svc.setOffline(true)
        _ = await c.setEnabled(false)
        XCTAssertEqual(c.deleteQueue, [tokenA])
        await svc.setOffline(false)
        await svc.hold()
        let refreshing = Task { await c.refresh() }          // flushes the queued DELETE
        await waitUntil("the queued DELETE to start") { await svc.parkedCount == 1 }
        let on = Task { await c.setEnabled(true) }           // the same token, PUT again
        try? await Task.sleep(for: .milliseconds(50))
        let startedWhileHeld = await svc.started
        XCTAssertEqual(startedWhileHeld.last, "DELETE \(tokenA)", "the PUT waits for the DELETE in flight")
        await svc.resume()
        await refreshing.value
        let settled = await on.value
        XCTAssertTrue(settled); XCTAssertTrue(c.effective)
        let started = await svc.started, rows = await svc.rows
        XCTAssertEqual(Array(started.suffix(2)), ["DELETE \(tokenA)", "PUT \(tokenA)"])
        XCTAssertNotNil(rows[tokenA], "the fresh registration survives")
        XCTAssertEqual(c.ack?.token, tokenA); XCTAssertEqual(c.deleteQueue, [])
    }

    func testRefreshWhileNotWantedDeletesALeftoverAck() async {
        let reg = FakePushRegistrar(token: tokenA), svc = FakeHukamnamaService()
        let c = make(reg, svc)
        c.ack = .init(token: tokenA, digest: "x", at: clock.now, install: Self.thisInstall)
        await c.refresh()
        let deletes = await svc.deletes
        XCTAssertEqual(deletes, [tokenA]); XCTAssertNil(c.ack); XCTAssertFalse(c.effective)
    }

    func testRefreshesAskedForTogetherShareOneRun() async {
        let reg = FakePushRegistrar(token: tokenA), svc = FakeHukamnamaService()
        let c = make(reg, svc)
        _ = await c.setEnabled(true)
        clock.now = clock.now.addingTimeInterval(25 * 3600)
        await svc.hold()
        let first = Task { await c.refresh() }
        await waitUntil("the first refresh PUT") { await svc.parkedCount == 1 }
        let second = Task { await c.refresh() }, third = Task { await c.refresh() }
        try? await Task.sleep(for: .milliseconds(20))
        await svc.resume()
        await first.value; await second.value; await third.value
        let puts = await svc.puts.count
        XCTAssertEqual(puts, 2, "the queued refreshes joined into one, which found nothing to send")
    }

    // MARK: server answers

    func testPermanentRejectionOnReackStopsClaimingDelivery() async {
        let reg = FakePushRegistrar(token: tokenA), svc = FakeHukamnamaService()
        let c = make(reg, svc)
        _ = await c.setEnabled(true)
        await svc.set(rejectPuts: 400)
        clock.now = clock.now.addingTimeInterval(25 * 3600)
        await c.refresh()
        XCTAssertFalse(c.effective, "a 4xx is not 'offline'")
        XCTAssertTrue(c.wanted, "the reader's wish is kept")
        XCTAssertEqual(c.message, HukamnamaPushController.refused)
        XCTAssertFalse(c.changePending)
    }

    func testTooManyRequestsIsTreatedLikeOffline() async {
        let reg = FakePushRegistrar(token: tokenA), svc = FakeHukamnamaService()
        let c = make(reg, svc)
        _ = await c.setEnabled(true)
        await svc.set(rejectPuts: 429)
        clock.now = clock.now.addingTimeInterval(25 * 3600)
        await c.refresh()
        XCTAssertTrue(c.effective, "still registered; retried later"); XCTAssertNil(c.message)
        await svc.set(rejectPuts: 503)
        await c.refresh()
        XCTAssertTrue(c.effective); XCTAssertNil(c.message)
        await svc.set(rejectPuts: nil)
        await c.refresh()
        let puts = await svc.puts.count
        XCTAssertEqual(puts, 2, "the re-ack went through once the server recovered")
    }

    func testRejectionErrorClassification() {
        XCTAssertTrue(HukamnamaServiceError.rejected(400).isPermanentRejection)
        XCTAssertTrue(HukamnamaServiceError.rejected(410).isPermanentRejection)
        XCTAssertFalse(HukamnamaServiceError.rejected(429).isPermanentRejection)
        XCTAssertFalse(HukamnamaServiceError.rejected(500).isPermanentRejection)
        XCTAssertFalse(HukamnamaServiceError.offline.isPermanentRejection)
    }

    func testDeliveryStatusFromThePutIsKeptAndClearedOnOff() async {
        let reg = FakePushRegistrar(token: tokenA), svc = FakeHukamnamaService()
        let status = HukamnamaDeviceStatus(amritsarDate: AmritsarDate.key(clock.now), status: .published, delivery: .sent,
                                           sentAt: clock.now, reason: nil, nextSlotAt: nil)
        await svc.set(nextStatus: status)
        let c = make(reg, svc)
        _ = await c.setEnabled(true)
        XCTAssertEqual(c.deliveryStatus, status); XCTAssertEqual(c.deliveryStatusAt, clock.now)
        // an older server's bare {"ok":true} keeps the last answer
        await svc.set(nextStatus: nil)
        c.setMode(.scheduled)
        await c.refresh()
        XCTAssertEqual(c.deliveryStatus, status)
        _ = await c.setEnabled(false)
        XCTAssertNil(c.deliveryStatus)
    }

    func testAChangeMadeOfflineIsPendingUntilItReachesTheServer() async {
        let reg = FakePushRegistrar(token: tokenA), svc = FakeHukamnamaService()
        let c = make(reg, svc)
        _ = await c.setEnabled(true)
        await svc.setOffline(true)
        c.setMode(.scheduled)
        await c.refresh()
        XCTAssertTrue(c.changePending); XCTAssertTrue(c.effective, "the old registration still stands")
        XCTAssertEqual(HukamnamaDeliveryCopy.line(status: nil, receivedAt: nil, mode: c.mode, settingsChangedAt: c.settingsChangedAt,
                                                  changePending: c.changePending, now: clock.now),
                       HukamnamaDeliveryCopy.willUpdate)
        await svc.setOffline(false)
        await c.refresh()
        XCTAssertFalse(c.changePending)
        let last = await svc.puts.last
        XCTAssertEqual(last?.body.mode, .scheduled)
    }

    // MARK: permission + restored backups

    func testDeniedNoteClearsOnceSettingsAllowNotificationsAgain() async {
        let reg = FakePushRegistrar(status: .notDetermined, grants: false), svc = FakeHukamnamaService()
        let c = make(reg, svc)
        _ = await c.setEnabled(true)
        XCTAssertTrue(c.denied); XCTAssertFalse(c.wanted)
        await reg.set(status: .authorized)      // the reader allowed notifications in Settings
        await c.refresh()
        XCTAssertFalse(c.denied, "the Settings note goes even though the toggle is off")
    }

    func testRestoredBackupAsksForTheToggleAgainAndKeepsTheOldPhonesRow() async {
        // UserDefaults came over from the old phone: wanted, and the old phone's acknowledgement
        defaults.set(true, forKey: HukamnamaPushController.wantedKey)
        let reg = FakePushRegistrar(status: .notDetermined, token: tokenA), svc = FakeHukamnamaService()
        let c = make(reg, svc)
        c.ack = .init(token: tokenB, digest: "old", at: clock.now, install: "install-old-phone")
        await c.refresh()
        XCTAssertFalse(c.wanted); XCTAssertFalse(c.effective); XCTAssertFalse(c.denied)
        XCTAssertEqual(c.message, HukamnamaPushController.turnOnAgain)
        XCTAssertNil(c.ack)
        let prompts = await reg.promptCount, deletes = await svc.deletes, puts = await svc.puts.count
        XCTAssertEqual(prompts, 0, "only the toggle prompts"); XCTAssertEqual(deletes, [], "the old phone's row is not ours to delete")
        XCTAssertEqual(puts, 0)
        let on = await c.setEnabled(true)
        XCTAssertTrue(on)
        let put = await svc.puts.last
        XCTAssertEqual(put?.token, tokenA); XCTAssertNil(put?.body.replaces, "never replaces the old phone's token")
    }

    func testAnotherInstallsAckIsNeverSentAsReplaces() async {
        // restored, and permission already granted on the new phone (e.g. through Nitnem reminders)
        defaults.set(true, forKey: HukamnamaPushController.wantedKey)
        let reg = FakePushRegistrar(token: tokenA), svc = FakeHukamnamaService()
        let c = make(reg, svc)
        c.ack = .init(token: tokenB, digest: "old", at: clock.now, install: "install-old-phone")
        await c.refresh()
        let put = await svc.puts.last, deletes = await svc.deletes
        XCTAssertEqual(put?.token, tokenA); XCTAssertNil(put?.body.replaces)
        XCTAssertEqual(deletes, []); XCTAssertEqual(c.ack?.install, Self.thisInstall)
    }

    func testAnAckFromBeforeTheInstallMarkerIsStillOurs() async {
        defaults.set(true, forKey: HukamnamaPushController.wantedKey)
        let reg = FakePushRegistrar(token: tokenB), svc = FakeHukamnamaService()
        let c = make(reg, svc)
        c.ack = .init(token: tokenA, digest: "old", at: clock.now, install: nil)
        await c.refresh()
        let put = await svc.puts.last
        XCTAssertEqual(put?.body.replaces, tokenA, "a same-phone token rotation still replaces")
    }

    func testInstallMarkerIsStableAndExcludedFromBackup() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("install-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let first = HukamnamaInstall.id(directory: dir)
        XCTAssertFalse(first.isEmpty)
        XCTAssertEqual(HukamnamaInstall.id(directory: dir), first)
        let values = try dir.appendingPathComponent(HukamnamaInstall.filename).resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(values.isExcludedFromBackup, true)
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
        // a foreground arrival is seen (banner + sound) unless its own sheet is already open
        XCTAssertEqual(NotificationRouter.presentationOptions(threadIdentifier: "hukamnama", sheetShowingSameDate: false),
                       [.banner, .list, .sound])
        XCTAssertEqual(NotificationRouter.presentationOptions(threadIdentifier: "hukamnama", sheetShowingSameDate: true), [.list])
        XCTAssertEqual(NotificationRouter.presentationOptions(threadIdentifier: "", sheetShowingSameDate: false), [])
        XCTAssertEqual(NotificationRouter.presentationOptions(threadIdentifier: "", sheetShowingSameDate: true), [])
    }

    func testNotificationDateForTheSameSheetCheck() {
        let e = HukamnamaEntry(amritsarDate: "2026-11-09", status: .published)
        XCTAssertEqual(NotificationRouter.hukamnamaDate(entry: e, userInfo: [:]), "2026-11-09")
        XCTAssertEqual(NotificationRouter.hukamnamaDate(entry: nil, userInfo: ["amritsar_date": "2026-11-08"]), "2026-11-08")
        XCTAssertEqual(NotificationRouter.hukamnamaDate(entry: nil, userInfo: ["url": "sggs://hukamnama/2026-11-07"], now: now), "2026-11-07")
        XCTAssertNil(NotificationRouter.hukamnamaDate(entry: nil, userInfo: ["url": "sggs://hukamnama/2026-11-31"], now: now))
        XCTAssertNil(NotificationRouter.hukamnamaDate(entry: nil, userInfo: ["amritsar_date": "today"]))
        XCTAssertNil(NotificationRouter.hukamnamaDate(entry: nil, userInfo: [:]))
    }
}

// MARK: - Delivery status (PUT answer) + its one-line copy

final class HukamnamaDeliveryStatusTests: XCTestCase {
    private let tz = TimeZone(identifier: "Australia/Sydney")!
    private let locale = Locale(identifier: "en_US")
    private func time(_ d: Date) -> String {
        d.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, timeZone: tz))
    }

    func testDecodesTheFullAnswer() throws {
        let json = #"{"ok":true,"today":{"amritsar_date":"2026-11-11","status":"published","delivery":"sent","sent_at":"2026-11-11T02:54:18Z","reason":null},"next_slot_at":"2026-11-12T03:13:00Z"}"#
        let s = try XCTUnwrap(HukamnamaDeviceStatus.decode(Data(json.utf8)))
        XCTAssertEqual(s.amritsarDate, "2026-11-11"); XCTAssertEqual(s.status, .published)
        XCTAssertEqual(s.delivery, .sent); XCTAssertNil(s.reason)
        XCTAssertEqual(s.sentAt, utc(2026, 11, 11, 2, 54).addingTimeInterval(18))
        XCTAssertEqual(s.nextSlotAt, utc(2026, 11, 12, 3, 13))
    }

    func testOldServersAndOddAnswersAreTolerated() {
        XCTAssertNil(HukamnamaDeviceStatus.decode(Data(#"{"ok":true}"#.utf8)), "an older server: nothing to say")
        XCTAssertNil(HukamnamaDeviceStatus.decode(Data("".utf8)))
        XCTAssertNil(HukamnamaDeviceStatus.decode(Data("[1,2]".utf8)))
        let odd = #"{"ok":true,"today":{"amritsar_date":"2026-11-31","status":"lost","delivery":"teleported","sent_at":"yesterday","reason":"moon","extra":1},"next_slot_at":"2026-11-12T03:13:00.250Z","future":{}}"#
        let s = HukamnamaDeviceStatus.decode(Data(odd.utf8))
        XCTAssertNil(s?.amritsarDate); XCTAssertNil(s?.status); XCTAssertNil(s?.delivery)
        XCTAssertNil(s?.sentAt); XCTAssertNil(s?.reason)
        XCTAssertEqual(s?.nextSlotAt?.timeIntervalSince1970 ?? 0,
                       utc(2026, 11, 12, 3, 13).timeIntervalSince1970 + 0.25, accuracy: 0.001,
                       "unknown values are ignored, fractional seconds read")
        let types = #"{"today":{"amritsar_date":20261111,"delivery":["sent"]},"next_slot_at":5}"#
        XCTAssertNil(HukamnamaDeviceStatus.decode(Data(types.utf8)))
    }

    private func line(_ s: HukamnamaDeviceStatus?, mode: HukamnamaMode = .scheduled, changed: Date? = nil,
                      pending: Bool = false, now: Date, receivedAt: Date? = nil) -> String? {
        HukamnamaDeliveryCopy.line(status: s, receivedAt: receivedAt ?? now, mode: mode, settingsChangedAt: changed,
                                   changePending: pending, now: now, locale: locale, timeZone: tz)
    }

    func testEveryLine() {
        let now = utc(2026, 11, 11, 4)            // 09:30 in Amritsar, 15:00 in Sydney
        let today = AmritsarDate.key(now)
        let sent = utc(2026, 11, 11, 2, 54), next = utc(2026, 11, 12, 3, 13), laterToday = utc(2026, 11, 11, 6)

        let delivered = HukamnamaDeviceStatus(amritsarDate: today, status: .published, delivery: .sent, sentAt: sent)
        XCTAssertEqual(line(delivered, now: now), "Today's Hukamnama was delivered at \(time(sent)).")
        XCTAssertEqual(line(delivered, changed: sent.addingTimeInterval(-60), now: now),
                       "Today's Hukamnama was delivered at \(time(sent)).", "a change before delivery says nothing more")
        XCTAssertEqual(line(delivered, changed: sent.addingTimeInterval(60), now: now),
                       "Today's Hukamnama was delivered at \(time(sent)). Your new time starts tomorrow.")

        XCTAssertEqual(line(.init(amritsarDate: today, delivery: .notToday, reason: .registeredAfterPublish), now: now),
                       "Today's Hukamnama is already out — open it from the Nitnem page. Notifications start tomorrow.")
        XCTAssertEqual(line(.init(amritsarDate: today, delivery: .notToday, reason: .slotPassed, nextSlotAt: next), now: now),
                       "Your time has passed for today. Notifications start tomorrow at \(time(next)).")
        XCTAssertNil(line(.init(amritsarDate: today, delivery: .notToday), now: now), "no reason: nothing guessed")

        XCTAssertEqual(line(.init(amritsarDate: today, status: .pending, delivery: .due, nextSlotAt: laterToday), now: now),
                       "Today's arrives at \(time(laterToday)).")
        XCTAssertNil(line(.init(amritsarDate: today, delivery: .due, nextSlotAt: now.addingTimeInterval(-60)), now: now),
                     "a slot already past is not promised")
        XCTAssertEqual(line(.init(amritsarDate: today, status: .pending, delivery: .due), mode: .asap, now: now),
                       "Today's arrives as soon as it's published.")
        XCTAssertNil(line(.init(amritsarDate: today, status: .published, delivery: .due), mode: .asap, now: now))

        XCTAssertEqual(line(delivered, pending: true, now: now), "Will update when you're online.")
        XCTAssertNil(line(nil, now: now))
    }

    func testOnlyTodaysAnswerIsShown() {
        let now = utc(2026, 11, 11, 4)
        let yesterday = HukamnamaDeviceStatus(amritsarDate: "2026-11-10", status: .published, delivery: .sent, sentAt: utc(2026, 11, 10, 2))
        XCTAssertNil(line(yesterday, now: now))
        var undated = yesterday; undated.amritsarDate = nil
        XCTAssertNil(line(undated, now: now, receivedAt: utc(2026, 11, 10, 3)), "an undated answer from yesterday")
        XCTAssertNotNil(line(undated, now: now, receivedAt: utc(2026, 11, 11, 1)))
    }

    @MainActor func testCopyNeverCarriesGurmukhi() {
        let gurmukhi = UnicodeScalar(0x0A00)!...UnicodeScalar(0x0A7F)!
        let now = utc(2026, 11, 11, 4), today = AmritsarDate.key(now)
        let all = [HukamnamaDeliveryCopy.lateNote, HukamnamaDeliveryCopy.willUpdate, HukamnamaPushController.refused,
                   HukamnamaPushController.turnOnAgain,
                   line(.init(amritsarDate: today, delivery: .sent, sentAt: now), now: now) ?? "",
                   line(.init(amritsarDate: today, delivery: .notToday, reason: .registeredAfterPublish), now: now) ?? ""]
        for text in all { XCTAssertFalse(text.unicodeScalars.contains { gurmukhi.contains($0) }, text) }
    }
}

// MARK: - The sheet's entry choice (store, then the service)

@MainActor
final class HukamnamaHomePickTests: XCTestCase {
    nonisolated(unsafe) private var dir: URL!
    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("hukamnama-home-\(UUID().uuidString)")
    }
    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    private var storeURL: URL { dir.appendingPathComponent(HukamnamaStore.filename) }
    private func published(_ date: String, hash: Character = "a") -> HukamnamaEntry {
        HukamnamaEntry(amritsarDate: date, status: .published, ang: 1, firstLineId: 1, lastLineId: 2,
                       rangeSHA256: String(repeating: hash, count: 64))
    }
    private let now = Date()
    private var today: String { AmritsarDate.key(now) }
    private var yesterday: String { AmritsarDate.key(now.addingTimeInterval(-86_400)) }

    func testAMissingDateIsNotFoundNotOffline() async {
        let svc = FakeHukamnamaService()
        let home = HukamnamaHome(service: svc, storeURL: storeURL)
        let r = await home.fetch(date: "2026-01-05")
        XCTAssertEqual(r, .notFound)
        let pick = await home.pick(date: "2026-01-05", now: now)
        XCTAssertEqual(pick, .notFound)
        await svc.setOffline(true)
        let offline = await home.pick(date: "2026-01-05", now: now)
        XCTAssertEqual(offline, .offline)
    }

    func testTheLatestFetchesTodayBeforeShowingAnOlderOne() async {
        HukamnamaStore.merge([published(yesterday)], url: storeURL)
        let svc = FakeHukamnamaService(entries: [published(yesterday), published(today, hash: "b")])
        let home = HukamnamaHome(service: svc, storeURL: storeURL)
        let pick = await home.pick(date: nil, now: now)
        XCTAssertEqual(pick, .entry(published(today, hash: "b")), "today's, not the stored yesterday")
        let fetches = await svc.fetches
        XCTAssertEqual(fetches, [nil])
        // and once today's is stored, no read at all
        _ = await home.pick(date: nil, now: now)
        let again = await svc.fetches.count
        XCTAssertEqual(again, 1)
    }

    func testTheLatestFallsBackToTheStoredOneOffline() async {
        HukamnamaStore.merge([published(yesterday)], url: storeURL)
        let svc = FakeHukamnamaService()
        await svc.setOffline(true)
        let home = HukamnamaHome(service: svc, storeURL: storeURL)
        let pick = await home.pick(date: nil, now: now)
        XCTAssertEqual(pick, .entry(published(yesterday)))
        let empty = HukamnamaHome(service: svc, storeURL: dir.appendingPathComponent("none.json"))
        let nothing = await empty.pick(date: nil, now: now)
        XCTAssertEqual(nothing, .offline)
    }

    func testRevisionChangesWhenTheEntryArrives() {
        let home = HukamnamaHome(service: nil, storeURL: storeURL)
        let before = home.revision(date: today, now: now)
        home.ingest(HukamnamaEntry(amritsarDate: today, status: .pending))
        let pending = home.revision(date: today, now: now)
        home.ingest(published(today))
        let after = home.revision(date: today, now: now)
        XCTAssertNotEqual(before, pending); XCTAssertNotEqual(pending, after)
        XCTAssertEqual(home.revision(date: nil, now: now), after, "the latest sheet keys on today's entry")
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
        // …and its refrain
        var withRahao = entry(day(9)); withRahao.rahaoGurmukhi = ["line one ॥", "line two ॥ ਰਹਾਉ ॥"]
        m = HukamnamaStore.merged(existing: [withRahao], incoming: [entry(day(9))])
        XCTAssertEqual(m.first?.rahaoGurmukhi, withRahao.rahaoGurmukhi)
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
        XCTAssertFalse(api.rahaoLines.isEmpty, "the fixture carries its ਰਹਾਉ")
        XCTAssertEqual(pushed.rahaoLines, api.rahaoLines, "push and read API carry the same refrain")
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
        // a malformed refrain is dropped whole (never shown in part); the entry itself stays
        let line = api.rahaoLines[0]
        let bad: [Any] = [[String](), [line, line, line, line], [""], ["\(line)\n\(line)"],
                          [String(repeating: "ਕ", count: 400)], line, 7]
        for v in bad {
            var badRahao = info; badRahao["rahao_gurmukhi"] = v
            let e = try XCTUnwrap(HukamnamaEntry(pushUserInfo: badRahao), "\(v)")
            XCTAssertEqual(e.rahaoLines, [], "\(v)")
        }
        var noRahao = info; noRahao.removeValue(forKey: "rahao_gurmukhi")
        XCTAssertEqual(try XCTUnwrap(HukamnamaEntry(pushUserInfo: noRahao)).rahaoLines, [], "an older server sends none")
        // malformed fields → not a Hukamnama entry at all
        for (k, v) in [("range_sha256", "nothex"), ("amritsar_date", "2026-11-31"), ("first_line_id", "x")] as [(String, Any)] {
            var bad = info; bad[k] = v
            XCTAssertNil(HukamnamaEntry(pushUserInfo: bad), k)
        }
    }
}
