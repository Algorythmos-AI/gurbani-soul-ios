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

enum HukamnamaServiceError: Error, Equatable { case offline, rejected(Int), malformed }

protocol HukamnamaServing: Sendable {
    func register(token: String, body: HukamnamaDeviceBody) async throws
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

    func register(token: String, body: HukamnamaDeviceBody) async throws {
        guard !offline else { throw HukamnamaServiceError.offline }
        puts.append(Put(token: token, body: body))
        if let old = body.replaces { rows[old] = nil }
        rows[token] = body
    }
    func unregister(token: String) async throws {
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

/// The wanted/effective state machine for the Hukamnama push.
@MainActor @Observable
final class HukamnamaPushController {
    // Stored preferences (UserDefaults; the UI-test vault resets them).
    static let wantedKey = "sggs_hukamnama_wanted"
    static let modeKey = "sggs_hukamnama_mode"
    static let minuteKey = "sggs_hukamnama_minute"
    static let ackKey = "sggs_hukamnama_ack"
    static let deleteQueueKey = "sggs_hukamnama_delete_queue"
    static let anchorKey = "sggs_hukamnama_schedule_anchor"
    static let storedKeys = [wantedKey, modeKey, minuteKey, ackKey, deleteQueueKey, anchorKey]
    /// "At a time I choose" defaults to 07:00 local.
    static let defaultMinute = 7 * 60
    /// A PUT is re-sent at least this often, even when nothing changed (self-heals a lost table).
    static let reackInterval: TimeInterval = 24 * 3600

    static let couldNotTurnOn = "Couldn't turn on. Try again."

    /// What the server last acknowledged for this device.
    struct Ack: Codable, Equatable, Sendable { let token: String; let digest: String; let at: Date }
    /// The start the current schedule was built from (kept so the body is stable day to day).
    struct Anchor: Codable, Equatable, Sendable { let from: Date; let zone: String; let minute: Int }

    private let registrar: PushRegistering
    private let service: HukamnamaServing?
    private let defaults: UserDefaults
    private let env: String
    private let scriptureSHA256: String?
    private let now: @Sendable () -> Date
    private let zone: @Sendable () -> TimeZone

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
    private var pendingSync: Task<Void, Never>?

    init(registrar: PushRegistering, service: HukamnamaServing?, defaults: UserDefaults = .standard,
         env: String = HukamnamaConfig.apsEnvironment, scriptureSHA256: String? = HukamnamaConfig.scriptureSHA256,
         now: @escaping @Sendable () -> Date = { Date() },
         zone: @escaping @Sendable () -> TimeZone = { TimeZone.current }) {
        self.registrar = registrar
        self.service = service
        self.defaults = defaults
        self.env = env
        self.scriptureSHA256 = scriptureSHA256
        self.now = now
        self.zone = zone
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
    private func setWanted(_ v: Bool) { wanted = v; defaults.set(v, forKey: Self.wantedKey) }

    // MARK: reader actions

    /// The toggle. Returns the value it should settle on. The permission prompt is shown only
    /// from here. Turning ON needs permission, a token and the server's acknowledgement — any
    /// failure snaps it back with nothing half registered. Turning OFF sends the DELETE before it
    /// confirms (queued when offline, retried on later launches).
    @discardableResult
    func setEnabled(_ on: Bool) async -> Bool {
        busy = true
        defer { busy = false }
        message = nil
        guard on else {
            setWanted(false)
            effective = false
            denied = false
            if let token = ack?.token { await delete(token) }
            ack = nil
            return false
        }
        var status = await registrar.authorizationStatus()
        if status == .notDetermined || status == .provisional {
            status = await registrar.requestAuthorization() ? .authorized : .denied
        }
        guard status != .denied else {
            denied = true
            setWanted(false)
            return false
        }
        denied = false
        let token: String
        do { token = try await registrar.registerForToken() } catch {
            message = Self.couldNotTurnOn
            setWanted(false)
            return false
        }
        setWanted(true)
        if await sync(token: token, force: true) { return true }
        // the PUT may have landed with its answer lost: make sure no row is left behind
        setWanted(false)
        await delete(token)
        message = Self.couldNotTurnOn
        return false
    }

    func setMode(_ m: HukamnamaMode) {
        mode = m
        defaults.set(m.rawValue, forKey: Self.modeKey)
        scheduleSync()
    }

    func setMinute(_ m: Int) {
        guard (0..<(24 * 60)).contains(m) else { return }
        minute = m
        defaults.set(m, forKey: Self.minuteKey)
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
    /// the last acknowledgement is older than 24 h.
    func refresh() async {
        await flushDeleteQueue()
        guard wanted else { effective = false; return }
        let status = await registrar.authorizationStatus()
        let alerts = await registrar.alertsEnabled()
        guard status != .denied, alerts else {
            // the reader still wants it; iOS won't show it. Remove the row until permission returns.
            denied = true
            effective = false
            if let token = ack?.token { await delete(token) }
            ack = nil
            return
        }
        denied = false
        guard let token = try? await registrar.registerForToken() else { return }
        _ = await sync(token: token, force: false)
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

    @discardableResult
    private func sync(token: String, force: Bool) async -> Bool {
        guard let service, HukamnamaDeviceBody.isValidToken(token) else { effective = false; return false }
        let previous = ack
        let replaces = previous.flatMap { $0.token != token ? $0.token : nil }
        let body = currentBody(replaces: replaces)
        let digest = body.digest(token: token)
        if !force, let previous, previous.token == token, previous.digest == digest,
           now().timeIntervalSince(previous.at) < Self.reackInterval {
            effective = true
            return true
        }
        do {
            try await service.register(token: token, body: body)
            ack = Ack(token: token, digest: digest, at: now())
            deleteQueue = deleteQueue.filter { $0 != token && $0 != replaces }
            effective = true
            return true
        } catch {
            effective = previous?.token == token && !force
            return false
        }
    }

    private func delete(_ token: String) async {
        guard let service else { return }
        do { try await service.unregister(token: token) } catch { deleteQueue = deleteQueue + [token] }
    }

    /// Retry DELETEs that failed offline. A queued token that is the CURRENT registration (the
    /// reader turned it back on) is never deleted.
    func flushDeleteQueue() async {
        guard let service else { return }
        var left: [String] = []
        for token in deleteQueue where token != ack?.token {
            do { try await service.unregister(token: token) } catch { left.append(token) }
        }
        deleteQueue = left
    }

    #if DEBUG
    /// A one-line state for UI tests (shown only under SGGS_UITEST).
    var debugSummary: String {
        "wanted=\(wanted) effective=\(effective) mode=\(mode.rawValue) denied=\(denied)"
    }
    #endif
}
