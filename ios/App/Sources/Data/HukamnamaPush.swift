import Foundation
import CryptoKit
#if canImport(UIKit)
import UIKit
#endif
#if canImport(UserNotifications)
import UserNotifications
#endif

// The Hukamnama from Sri Harmandir Sahib: opt-in remote push. Everything here goes through two
// seams so no test ever touches APNs or the network:
//   PushRegistering   — the OS permission + APNs token (SystemPushRegistrar / FakePushRegistrar)
//   HukamnamaServing  — the service's device + read API (HukamnamaHTTPService / FakeHukamnamaService)
// State: WANTED (the reader's toggle, stored) and EFFECTIVE (authorized, registered and
// acknowledged by the server). The controller keeps the server in step on every launch and
// foreground, so a lost server table heals itself within one foreground.

/// Build-time facts from Info.plist (project.yml settings, per configuration).
enum HukamnamaConfig {
    private static func plist(_ key: String) -> String? {
        (Bundle.main.object(forInfoDictionaryKey: key) as? String).flatMap { $0.isEmpty || $0.hasPrefix("$(") ? nil : $0 }
    }
    /// The feature ships dark in Release until its review gates are signed (G3, G4, H-src).
    static var enabled: Bool { plist("HukamnamaEnabled") == "YES" }
    static var apiBase: URL? {
        plist("HukamnamaAPIBase").flatMap(URL.init(string:)).flatMap { $0.scheme == "https" ? $0 : nil }
    }
    /// "development" (Xcode-installed Debug builds: sandbox tokens) or "production" (TestFlight
    /// and App Store builds) — the APNs environment this binary's tokens belong to.
    static var apsEnvironment: String { plist("HukamnamaAPSEnvironment") == "production" ? "production" : "development" }
    /// The bundled corpus fingerprint (sggs-ios.manifest.json `scripture_sha256`).
    static let scriptureSHA256: String? = {
        guard let url = Bundle.main.url(forResource: "sggs-ios.manifest", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sha = obj["scripture_sha256"] as? String, HukamnamaEntry.isHex64(sha) else { return nil }
        return sha
    }()
}

/// How the reader wants it. Wire values are the server's `mode`.
enum HukamnamaMode: String, Codable, Sendable, CaseIterable {
    /// "As soon as it's published" — one broadcast the moment the shabad resolves.
    case asap
    /// "At a time I choose" — the device's DST slot schedule.
    case scheduled
}

/// The PUT body. Small on purpose: no zone name, no locale, no identifiers.
struct HukamnamaDeviceBody: Codable, Equatable, Sendable {
    var env: String
    var mode: HukamnamaMode
    var schedule: [HukamnamaSlot]?
    var scriptureSHA256: String?
    /// The previous token when the OS rotated it; the server deletes it in the same transaction.
    var replaces: String?
    enum CodingKeys: String, CodingKey {
        case env, mode, schedule, scriptureSHA256 = "scripture_sha256", replaces
    }

    static let encoder: JSONEncoder = { let e = JSONEncoder(); e.outputFormatting = [.sortedKeys]; return e }()

    /// APNs token shape the server accepts: lowercase hex, 64–200 characters.
    static func isValidToken(_ t: String) -> Bool {
        (64...200).contains(t.utf8.count) && t.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    /// What decides "did anything change since the last acknowledgement": the token plus every
    /// field except `replaces` (a one-off instruction, not state).
    func digest(token: String) -> String {
        var b = self
        b.replaces = nil
        let data = (try? Self.encoder.encode(b)) ?? Data()
        return SHA256.hash(data: Data(token.utf8) + data).map { String(format: "%02x", $0) }.joined()
    }
}

enum HukamnamaServiceError: Error, Equatable {
    case offline, rejected(Int), malformed
    /// The server refused this device for good (a 4xx other than 429): retrying the same body
    /// will not help. 429 and 5xx are "try again later", like offline.
    var isPermanentRejection: Bool {
        if case .rejected(let code) = self { return (400..<500).contains(code) && code != 429 }
        return false
    }
}

/// What the PUT /v1/devices answer says about today's delivery for this device. Decoded
/// tolerantly: every field is optional and an unknown value is ignored (never an error).
struct HukamnamaDeviceStatus: Equatable, Sendable {
    enum Delivery: String, Sendable { case sent, due, notToday = "not_today" }
    enum Reason: String, Sendable { case registeredAfterPublish = "registered_after_publish", slotPassed = "slot_passed" }

    var amritsarDate: String?
    var status: HukamnamaEntry.Status?
    var delivery: Delivery?
    var sentAt: Date?
    var reason: Reason?
    var nextSlotAt: Date?

    init(amritsarDate: String? = nil, status: HukamnamaEntry.Status? = nil, delivery: Delivery? = nil,
         sentAt: Date? = nil, reason: Reason? = nil, nextSlotAt: Date? = nil) {
        self.amritsarDate = amritsarDate; self.status = status; self.delivery = delivery
        self.sentAt = sentAt; self.reason = reason; self.nextSlotAt = nextSlotAt
    }

    /// Nil when the body is not a JSON object or carries none of the fields (`{"ok":true}`).
    static func decode(_ data: Data) -> HukamnamaDeviceStatus? {
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        var s = HukamnamaDeviceStatus()
        if let t = obj["today"] as? [String: Any] {
            s.amritsarDate = (t["amritsar_date"] as? String).flatMap { AmritsarDate.isValidKey($0) ? $0 : nil }
            s.status = (t["status"] as? String).flatMap(HukamnamaEntry.Status.init(rawValue:))
            s.delivery = (t["delivery"] as? String).flatMap(Delivery.init(rawValue:))
            s.sentAt = date(t["sent_at"])
            s.reason = (t["reason"] as? String).flatMap(Reason.init(rawValue:))
        }
        s.nextSlotAt = date(obj["next_slot_at"])
        return s == HukamnamaDeviceStatus() ? nil : s
    }

    private static func date(_ value: Any?) -> Date? {
        guard let text = value as? String else { return nil }
        let f = ISO8601DateFormatter()
        if let d = f.date(from: text) { return d }
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: text)
    }
}

protocol HukamnamaServing: Sendable {
    /// PUT. Returns what the server says about today's delivery for this device, when it says
    /// anything (an older server answers just `{"ok":true}` → nil).
    func register(token: String, body: HukamnamaDeviceBody) async throws -> HukamnamaDeviceStatus?
    func unregister(token: String) async throws
    /// nil `date` = today (Amritsar); a nil result means the service has no such date (404).
    func fetch(date: String?) async throws -> HukamnamaEntry?
}

/// The in-memory service used under `SGGS_UITEST` and by unit tests: records every call.
actor FakeHukamnamaService: HukamnamaServing {
    struct Put: Equatable, Sendable { let token: String; let body: HukamnamaDeviceBody }
    private(set) var puts: [Put] = []
    private(set) var deletes: [String] = []
    private(set) var fetches: [String?] = []
    /// Registered tokens → their last body (what the server's table would hold).
    private(set) var rows: [String: HukamnamaDeviceBody] = [:]
    var offline = false
    private var entries: [String: HukamnamaEntry]
    init(entries: [HukamnamaEntry] = []) {
        var m: [String: HukamnamaEntry] = [:]
        for e in entries { m[e.amritsarDate] = e }
        self.entries = m
    }
    func setOffline(_ v: Bool) { offline = v }
    func setEntry(_ e: HukamnamaEntry) { entries[e.amritsarDate] = e }
    func dropAllRows() { rows = [:] }

    /// What the next successful PUT answers (nil = an older server's bare `{"ok":true}`).
    var nextStatus: HukamnamaDeviceStatus?
    /// A status code every PUT is refused with (nil = accepted).
    var rejectPuts: Int?
    func set(nextStatus: HukamnamaDeviceStatus?) { self.nextStatus = nextStatus }
    func set(rejectPuts: Int?) { self.rejectPuts = rejectPuts }

    /// Test gate: while set, every PUT / DELETE parks here (after it is recorded as started) until
    /// `resume()`, so a test can interleave the controller's operations deterministically.
    private var holding = false
    private var parked: [CheckedContinuation<Void, Never>] = []
    private(set) var started: [String] = []
    func hold() { holding = true }
    func resume() { holding = false; let p = parked; parked = []; for c in p { c.resume() } }
    var parkedCount: Int { parked.count }
    private func gate(_ what: String) async {
        started.append(what)
        guard holding else { return }
        await withCheckedContinuation { parked.append($0) }
    }

    func register(token: String, body: HukamnamaDeviceBody) async throws -> HukamnamaDeviceStatus? {
        await gate("PUT \(token)")
        guard !offline else { throw HukamnamaServiceError.offline }
        if let code = rejectPuts { throw HukamnamaServiceError.rejected(code) }
        puts.append(Put(token: token, body: body))
        if let old = body.replaces { rows[old] = nil }
        rows[token] = body
        return nextStatus
    }
    func unregister(token: String) async throws {
        await gate("DELETE \(token)")
        guard !offline else { throw HukamnamaServiceError.offline }
        deletes.append(token)
        rows[token] = nil
    }
    func fetch(date: String?) async throws -> HukamnamaEntry? {
        fetches.append(date)
        guard !offline else { throw HukamnamaServiceError.offline }
        if let date { return entries[date] }
        return entries[AmritsarDate.key(Date())] ?? entries.values.sorted { $0.amritsarDate > $1.amritsarDate }.first
    }
}

enum PushRegistrationError: Error, Equatable { case timedOut, failed }

/// The slice of the OS the controller needs: notification permission + the APNs token.
protocol PushRegistering: Sendable {
    func authorizationStatus() async -> NitnemAuthStatus
    /// False when the reader turned every alert style off for the app (lock screen, Notification
    /// Center and banners) — as good as denied for this feature.
    func alertsEnabled() async -> Bool
    func requestAuthorization() async -> Bool
    /// Registers with APNs and returns the device token (lowercase hex). Waits up to 10 s.
    func registerForToken() async throws -> String
}

/// Hands the app delegate's APNs callbacks to whoever is waiting for a token. A token that
/// arrives before anyone asked (registration at launch, the toggle not yet saved) is kept, so a
/// later wait that times out still gets it.
@MainActor
final class PushTokenBroker {
    static let shared = PushTokenBroker()
    private(set) var lastToken: String?
    private var waiters: [UUID: CheckedContinuation<String, Error>] = [:]
    /// The call that asks the OS for a token (UIApplication in the app; a closure in tests).
    var trigger: @MainActor () -> Void = {}

    static func hex(_ token: Data) -> String { token.map { String(format: "%02x", $0) }.joined() }

    func requestToken(timeout: Duration = .seconds(10)) async throws -> String {
        let id = UUID()
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
            waiters[id] = cont
            trigger()
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: timeout)
                guard let self, let c = self.waiters.removeValue(forKey: id) else { return }
                if let t = self.lastToken { c.resume(returning: t) } else { c.resume(throwing: PushRegistrationError.timedOut) }
            }
        }
    }

    func deliver(token: Data) { deliver(hex: Self.hex(token)) }

    func deliver(hex: String) {
        lastToken = hex
        let ws = waiters
        waiters = [:]
        for c in ws.values { c.resume(returning: hex) }
    }

    func deliverFailure() {
        let ws = waiters
        waiters = [:]
        for c in ws.values { c.resume(throwing: PushRegistrationError.failed) }
    }
}

#if canImport(UserNotifications) && canImport(UIKit)
/// The real registrar: UNUserNotificationCenter for permission, UIApplication for the token
/// (delivered back through `SGGSAppDelegate` → `PushTokenBroker`).
struct SystemPushRegistrar: PushRegistering {
    private var center: UNUserNotificationCenter { .current() }

    func authorizationStatus() async -> NitnemAuthStatus {
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .ephemeral: return .authorized
        case .provisional: return .provisional
        case .denied: return .denied
        default: return .notDetermined
        }
    }

    func alertsEnabled() async -> Bool {
        let s = await center.notificationSettings()
        return s.alertSetting == .enabled || s.lockScreenSetting == .enabled || s.notificationCenterSetting == .enabled
    }

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func registerForToken() async throws -> String {
        try await MainActor.run {
            let broker = PushTokenBroker.shared
            broker.trigger = { UIApplication.shared.registerForRemoteNotifications() }
            return broker
        }.requestToken()
    }
}
#endif

/// An in-memory registrar used under `SGGS_UITEST` and by unit tests (no prompt, no APNs).
actor FakePushRegistrar: PushRegistering {
    var status: NitnemAuthStatus
    var alerts = true
    var grants: Bool
    var token: String
    var fails = false
    private(set) var promptCount = 0
    private(set) var registerCount = 0
    init(status: NitnemAuthStatus = .authorized, grants: Bool = true,
         token: String = String(repeating: "ab", count: 32)) {
        self.status = status; self.grants = grants; self.token = token
    }
    func set(status: NitnemAuthStatus) { self.status = status }
    func set(alerts: Bool) { self.alerts = alerts }
    func set(token: String) { self.token = token }
    func set(fails: Bool) { self.fails = fails }

    func authorizationStatus() async -> NitnemAuthStatus { status }
    func alertsEnabled() async -> Bool { alerts }
    func requestAuthorization() async -> Bool {
        promptCount += 1
        status = grants ? .authorized : .denied
        return grants
    }
    func registerForToken() async throws -> String {
        registerCount += 1
        if fails { throw PushRegistrationError.failed }
        return token
    }
}

/// A random marker for THIS install on THIS device, kept in a file excluded from backups (so a
/// restored backup or a new phone gets a fresh one). The controller stamps it on every
/// acknowledgement: an acknowledgement carrying another marker came over from another phone and
/// is never sent as `replaces` (that would delete the other phone's registration) nor deleted.
/// Nothing here leaves the device. Empty when the file cannot be written ("unknown": trusted).
enum HukamnamaInstall {
    static let filename = "hukamnama-install-id"

    static func id(directory: URL? = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first) -> String {
        guard let directory else { return "" }
        var url = directory.appendingPathComponent(filename)
        if let s = try? String(contentsOf: url, encoding: .utf8), !s.isEmpty { return s }
        let s = UUID().uuidString
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data(s.utf8).write(to: url, options: .atomic)
            var v = URLResourceValues()
            v.isExcludedFromBackup = true
            try url.setResourceValues(v)
        } catch { return "" }
        return s
    }
}

/// The wanted/effective state machine for the Hukamnama push.
///
/// Every operation (the toggle, a refresh, a debounced settings sync) runs on ONE serial queue:
/// at most one PUT or DELETE is in flight, in the order the reader asked for them, so a late PUT
/// can never land after the DELETE that was meant to follow it. `wanted` is re-read after every
/// await; when it went false meanwhile, the acknowledged row is deleted, never left behind.
@MainActor @Observable
final class HukamnamaPushController {
    // Stored preferences (UserDefaults; the UI-test vault resets them).
    static let wantedKey = "sggs_hukamnama_wanted"
    static let modeKey = "sggs_hukamnama_mode"
    static let minuteKey = "sggs_hukamnama_minute"
    static let ackKey = "sggs_hukamnama_ack"
    static let deleteQueueKey = "sggs_hukamnama_delete_queue"
    static let anchorKey = "sggs_hukamnama_schedule_anchor"
    static let changedAtKey = "sggs_hukamnama_settings_changed_at"
    static let storedKeys = [wantedKey, modeKey, minuteKey, ackKey, deleteQueueKey, anchorKey, changedAtKey]
    /// "At a time I choose" defaults to 07:00 local.
    static let defaultMinute = 7 * 60
    /// A PUT is re-sent at least this often, even when nothing changed (self-heals a lost table).
    static let reackInterval: TimeInterval = 24 * 3600

    static let couldNotTurnOn = "Couldn't turn on. Try again."
    /// The server refused this device (a 4xx other than 429) on a re-acknowledgement.
    static let refused = "The Hukamnama couldn't be set up for this device. Turn it off and on again."
    /// Restored from a backup / moved to a new phone: the wish came along, the permission didn't.
    static var turnOnAgain: String {
        #if canImport(UIKit)
        let device = UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
        #else
        let device = "iPhone"
        #endif
        return "Turn it on again on this \(device)."
    }

    /// What the server last acknowledged for this device. `install` = `HukamnamaInstall.id()` of
    /// the install that wrote it (nil in acknowledgements written before it existed: trusted).
    struct Ack: Codable, Equatable, Sendable {
        let token: String; let digest: String; let at: Date
        var install: String?
    }
    /// The start the current schedule was built from (kept so the body is stable day to day).
    struct Anchor: Codable, Equatable, Sendable { let from: Date; let zone: String; let minute: Int }

    private let registrar: PushRegistering
    private let service: HukamnamaServing?
    private let defaults: UserDefaults
    private let env: String
    private let scriptureSHA256: String?
    private let now: @Sendable () -> Date
    private let zone: @Sendable () -> TimeZone
    private let installID: String

    private(set) var wanted: Bool
    private(set) var effective = false
    private(set) var mode: HukamnamaMode
    private(set) var minute: Int
    /// Notifications are off for the app in iOS Settings while the reader wants this.
    private(set) var denied = false
    /// A plain sentence for the row under the toggle (nil = nothing to say).
    private(set) var message: String?
    /// The toggle is waiting on the OS or the server.
    private(set) var busy = false
    /// What the last PUT's answer said about today's delivery, and when it arrived.
    private(set) var deliveryStatus: HukamnamaDeviceStatus?
    private(set) var deliveryStatusAt: Date?
    /// A mode/time change has not reached the server yet (offline or a busy server); retried on
    /// the next refresh.
    private(set) var changePending = false
    private var pendingSync: Task<Void, Never>?

    // the serial queue
    private var tail: Task<Void, Never>?
    private var queuedRefresh: Task<Void, Never>?
    private var generation = 0
    private var busyCount = 0

    init(registrar: PushRegistering, service: HukamnamaServing?, defaults: UserDefaults = .standard,
         env: String = HukamnamaConfig.apsEnvironment, scriptureSHA256: String? = HukamnamaConfig.scriptureSHA256,
         now: @escaping @Sendable () -> Date = { Date() },
         zone: @escaping @Sendable () -> TimeZone = { TimeZone.autoupdatingCurrent },
         installID: String = HukamnamaInstall.id()) {
        self.registrar = registrar
        self.service = service
        self.defaults = defaults
        self.env = env
        self.scriptureSHA256 = scriptureSHA256
        self.now = now
        self.zone = zone
        self.installID = installID
        self.wanted = defaults.bool(forKey: Self.wantedKey)
        self.mode = defaults.string(forKey: Self.modeKey).flatMap(HukamnamaMode.init(rawValue:)) ?? .asap
        let m = defaults.object(forKey: Self.minuteKey) as? Int ?? Self.defaultMinute
        self.minute = (0..<(24 * 60)).contains(m) ? m : Self.defaultMinute
    }

    // MARK: stored state

    var ack: Ack? {
        get { defaults.data(forKey: Self.ackKey).flatMap { try? JSONDecoder().decode(Ack.self, from: $0) } }
        set { defaults.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: Self.ackKey) }
    }
    var deleteQueue: [String] {
        get { defaults.stringArray(forKey: Self.deleteQueueKey) ?? [] }
        set { defaults.set(newValue.isEmpty ? nil : Array(Set(newValue)).sorted(), forKey: Self.deleteQueueKey) }
    }
    private var anchor: Anchor? {
        get { defaults.data(forKey: Self.anchorKey).flatMap { try? JSONDecoder().decode(Anchor.self, from: $0) } }
        set { defaults.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: Self.anchorKey) }
    }
    /// When the reader last changed the mode or the time.
    private(set) var settingsChangedAt: Date? {
        get { defaults.object(forKey: Self.changedAtKey) as? Date }
        set { defaults.set(newValue, forKey: Self.changedAtKey) }
    }
    private func setWanted(_ v: Bool) { wanted = v; defaults.set(v, forKey: Self.wantedKey) }

    /// An acknowledgement written by another install (a restored backup, a new phone) is not this
    /// device's registration: forget it without a DELETE and never send it as `replaces`.
    private func dropForeignAck() {
        guard let a = ack, let install = a.install, !installID.isEmpty, install != installID else { return }
        ack = nil
    }

    // MARK: the serial queue

    /// Runs `op` after every operation queued before it (one at a time, in call order).
    private func enqueue<T: Sendable>(_ op: @escaping @MainActor @Sendable () async -> T) -> Task<T, Never> {
        let previous = tail
        let task = Task { @MainActor in
            await previous?.value
            return await op()
        }
        tail = Task { @MainActor in _ = await task.value }
        return task
    }

    // MARK: reader actions

    /// The toggle. Returns the value it should settle on. The permission prompt is shown only
    /// from here. Turning ON needs permission, a token and the server's acknowledgement — any
    /// failure snaps it back with nothing half registered. Turning OFF takes effect at once
    /// (`wanted` = false before anything is awaited) and sends the DELETE after whatever is in
    /// flight (queued when offline, retried on later launches).
    @discardableResult
    func setEnabled(_ on: Bool) async -> Bool {
        generation += 1
        let gen = generation
        message = nil
        if !on {
            setWanted(false)
            effective = false
            denied = false
            deliveryStatus = nil
            changePending = false
        }
        busyCount += 1
        busy = true
        defer { busyCount -= 1; busy = busyCount > 0 }
        return await enqueue { [self] in on ? await self.turnOn(gen) : await self.turnOff() }.value
    }

    private func turnOff() async -> Bool {
        await removeLeftoverRegistration()
        return false
    }

    private func turnOn(_ gen: Int) async -> Bool {
        // a later toggle superseded this one: leave everything to it
        func superseded() -> Bool { gen != generation }
        dropForeignAck()
        var status = await registrar.authorizationStatus()
        if superseded() { return wanted }
        if status == .notDetermined || status == .provisional {
            status = await registrar.requestAuthorization() ? .authorized : .denied
            if superseded() { return wanted }
        }
        guard status != .denied else {
            denied = true
            setWanted(false)
            return false
        }
        denied = false
        let token: String
        do { token = try await registrar.registerForToken() } catch {
            if superseded() { return wanted }
            message = Self.couldNotTurnOn
            setWanted(false)
            return false
        }
        if superseded() { return wanted }
        setWanted(true)
        if await sync(token: token, force: true) { return true }
        // A PUT that succeeded after a turn-off is recorded in `ack`; the queued turn-off deletes
        // it. A failed PUT may have landed with its answer lost: make sure no row is left behind.
        if ack?.token != token { await delete(token) }
        if superseded() || !wanted { return wanted }
        setWanted(false)
        message = Self.couldNotTurnOn
        return false
    }

    func setMode(_ m: HukamnamaMode) {
        mode = m
        defaults.set(m.rawValue, forKey: Self.modeKey)
        settingsChangedAt = now()
        scheduleSync()
    }

    func setMinute(_ m: Int) {
        guard (0..<(24 * 60)).contains(m) else { return }
        minute = m
        defaults.set(m, forKey: Self.minuteKey)
        settingsChangedAt = now()
        scheduleSync()
    }

    /// Debounced: a DatePicker scrub or a burst of time-zone notifications sends one PUT.
    func scheduleSync(after delay: Duration = .milliseconds(800)) {
        pendingSync?.cancel()
        pendingSync = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }

    // MARK: keeping the server in step

    /// Launch, foreground and time-zone change. Idempotent: a PUT only when something changed or
    /// the last acknowledgement is older than 24 h. A refresh asked for while one is already
    /// waiting in the queue joins it instead of queueing another.
    func refresh() async {
        if let queued = queuedRefresh { await queued.value; return }
        let task = enqueue { [self] in
            self.queuedRefresh = nil
            await self.performRefresh()
        }
        queuedRefresh = task
        await task.value
    }

    private func performRefresh() async {
        dropForeignAck()
        await flushDeleteQueue()
        let status = await registrar.authorizationStatus()
        // permission came back in Settings: the "turned off in Settings" note goes, wanted or not
        if status != .denied { denied = false }
        guard wanted else { effective = false; await removeLeftoverRegistration(); return }
        if status == .notDetermined {
            // restored from a backup or moved to a new phone: the wish came along, the permission
            // did not. Only the toggle may prompt, so ask the reader to turn it on again here.
            setWanted(false)
            effective = false
            deliveryStatus = nil
            message = Self.turnOnAgain
            await removeLeftoverRegistration()
            return
        }
        let alerts = await registrar.alertsEnabled()
        guard wanted else { effective = false; await removeLeftoverRegistration(); return }
        guard status != .denied, alerts else {
            // the reader still wants it; iOS won't show it. Remove the row until permission returns.
            denied = true
            effective = false
            if let token = ack?.token { ack = nil; await delete(token) }
            return
        }
        denied = false
        guard let token = try? await registrar.registerForToken() else { return }
        guard wanted else { effective = false; await removeLeftoverRegistration(); return }
        _ = await sync(token: token, force: false)
        if !wanted { await removeLeftoverRegistration() }
    }

    /// Not wanted (any more): delete whatever row this install still has acknowledged.
    private func removeLeftoverRegistration() async {
        dropForeignAck()
        guard !wanted, let token = ack?.token else { return }
        ack = nil
        await delete(token)
    }

    /// The body the server should hold right now.
    func currentBody(replaces: String?) -> HukamnamaDeviceBody {
        HukamnamaDeviceBody(env: env, mode: mode, schedule: mode == .scheduled ? currentSchedule() : nil,
                            scriptureSHA256: scriptureSHA256, replaces: replaces)
    }

    private func currentSchedule() -> [HukamnamaSlot] {
        let t = now(), z = zone()
        if let a = anchor, a.zone == z.identifier, a.minute == minute,
           !HukamnamaSchedule.needsRebuild(builtFrom: a.from, now: t) {
            return HukamnamaSchedule.build(localMinute: minute, timeZone: z, from: a.from)
        }
        anchor = Anchor(from: t, zone: z.identifier, minute: minute)
        return HukamnamaSchedule.build(localMinute: minute, timeZone: z, from: t)
    }

    /// One PUT (or none, when the server already holds exactly this). Only ever called from an
    /// operation on the serial queue.
    @discardableResult
    private func sync(token: String, force: Bool) async -> Bool {
        guard let service, HukamnamaDeviceBody.isValidToken(token) else { effective = false; return false }
        dropForeignAck()
        let previous = ack
        let replaces = previous.flatMap { $0.token != token ? $0.token : nil }
        let body = currentBody(replaces: replaces)
        let digest = body.digest(token: token)
        if !force, let previous, previous.token == token, previous.digest == digest,
           now().timeIntervalSince(previous.at) < Self.reackInterval {
            effective = true
            changePending = false
            return true
        }
        do {
            let status = try await service.register(token: token, body: body)
            // the server holds this row now, wanted or not: record it so a turn-off deletes it
            ack = Ack(token: token, digest: digest, at: now(), install: installID.isEmpty ? nil : installID)
            deleteQueue = deleteQueue.filter { $0 != token && $0 != replaces }
            changePending = false
            if let status { deliveryStatus = status; deliveryStatusAt = now() }
            guard wanted else { effective = false; return false }
            effective = true
            return true
        } catch let error as HukamnamaServiceError where error.isPermanentRejection {
            // 4xx (not 429): retrying the same body will not help. Not delivering; say so.
            effective = false
            if !force { message = Self.refused }
            return false
        } catch {
            // offline, 429 or 5xx: the previous registration (if any) still stands; retry later
            effective = wanted && previous?.token == token && !force
            if !force, previous?.digest != digest { changePending = true }
            return false
        }
    }

    private func delete(_ token: String) async {
        guard let service else { return }
        do { try await service.unregister(token: token) } catch { deleteQueue = deleteQueue + [token] }
    }

    /// Retry DELETEs that failed offline. A queued token that is the CURRENT registration (the
    /// reader turned it back on) is never deleted.
    private func flushDeleteQueue() async {
        guard let service else { return }
        var left: [String] = []
        for token in deleteQueue where token != ack?.token {
            do { try await service.unregister(token: token) } catch { left.append(token) }
        }
        // no PUT can have run meanwhile (the queue is serial), so this overwrites nothing newer
        deleteQueue = left
    }

    #if DEBUG
    /// A one-line state for UI tests (shown only under SGGS_UITEST).
    var debugSummary: String {
        "wanted=\(wanted) effective=\(effective) mode=\(mode.rawValue) denied=\(denied)"
    }
    #endif
}

/// The one-line delivery note under the Hukamnama mode/time rows (Reminders). Pure, so every
/// branch is unit-tested. Display strings only — never Gurmukhi or scripture text.
enum HukamnamaDeliveryCopy {
    /// Always under the time picker ("At a time I choose").
    static let lateNote = "If it isn't published by then, it arrives as soon as it is."
    static let willUpdate = "Will update when you're online."
    static let alreadyOut = "Today's Hukamnama is already out — open it from the Nitnem page. Notifications start tomorrow."
    static let arrivesWhenPublished = "Today's arrives as soon as it's published."

    static func line(status: HukamnamaDeviceStatus?, receivedAt: Date?, mode: HukamnamaMode,
                     settingsChangedAt: Date?, changePending: Bool, now: Date,
                     locale: Locale = .autoupdatingCurrent, timeZone: TimeZone = .autoupdatingCurrent) -> String? {
        if changePending { return willUpdate }
        guard let status, let delivery = status.delivery else { return nil }
        // only today's answer: yesterday's "delivered at" would be wrong this morning
        let today = AmritsarDate.key(now)
        if let d = status.amritsarDate {
            guard d == today else { return nil }
        } else if receivedAt.map(AmritsarDate.key) != today {
            return nil
        }
        func time(_ d: Date) -> String {
            d.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, timeZone: timeZone))
        }
        switch delivery {
        case .sent:
            guard let sent = status.sentAt else { return "Today's Hukamnama was delivered." }
            let first = "Today's Hukamnama was delivered at \(time(sent))."
            if let changed = settingsChangedAt, changed > sent { return first + " Your new time starts tomorrow." }
            return first
        case .notToday:
            switch status.reason {
            case .registeredAfterPublish: return alreadyOut
            case .slotPassed:
                guard let next = status.nextSlotAt else { return "Your time has passed for today. Notifications start tomorrow." }
                return "Your time has passed for today. Notifications start tomorrow at \(time(next))."
            case nil: return nil
            }
        case .due:
            switch mode {
            case .scheduled:
                guard let next = status.nextSlotAt, next > now else { return nil }
                return "Today's arrives at \(time(next))."
            case .asap:
                return status.status == .pending ? arrivesWhenPublished : nil
            }
        }
    }
}
