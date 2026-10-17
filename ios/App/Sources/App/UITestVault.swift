#if DEBUG
import CryptoKit
import Foundation
import OSLog
import SQLite3
import SwiftData

/// UI tests wipe and rewrite the app's own storage (Nitnem progress and plan, reader settings,
/// saved verses). On a simulator that storage is disposable; on a developer's own iPhone it is
/// real. This vault keeps it out of the tests' reach. Debug builds only: a TestFlight or App Store
/// build contains none of it (`ios/tools/check_no_test_hooks.sh` checks the built binary).
///
///   SGGS_UITEST=1            seal, then the test may wipe
///   SGGS_UITEST_RELAUNCH=1   a test's own relaunch: keep the test state, leave the vault sealed
///   neither                  restore the real data, then retire the vault
///
/// Invariants (each has a test in `UITestVaultTests`):
/// - nothing is wiped unless every item was copied and verified first (`sealIfNeeded` → true);
/// - a vault is built in a staging folder and published with one rename: whole or absent;
/// - a manifest records every item, present or absent, with its SHA-256. A vault whose manifest or
///   files do not verify is never restored and never deleted;
/// - the saved-verses store is copied with SQLite's backup API (its WAL included) and checked;
/// - restore verifies every file and domain before the vault is retired, and retiring is a rename;
/// - a vault untouched for `staleAfter` may predate real use of the app (an aborted run, then a
///   release build): the live data is archived before any wipe, so it is never lost either.
@MainActor
enum UITestVault {
    private static let log = Logger(subsystem: "org.sggs.app", category: "uitest-vault")
    static let formatVersion = 1
    static let staleAfter: TimeInterval = 30 * 60
    static let archivesKept = 5

    /// Every reading setting a UI test may change and a later test assumes is at its default. The
    /// accent is not here: its persistence across a relaunch is itself under test (and restored).
    static let resetKeys = ["sggs_last_ang", "sggs_translit", "sggs_show_english", "sggs_show_timing",
                            "sggs_rehras_variant", "sggs_reader_tone", "sggs_reader_leading",
                            "sggs_gurmukhi_size", "sggs_focus_mode", "sggs_saroop", "sggs_appearance",
                            "sggs_autoscroll_pace", "sggs_live_activity"]

    enum LaunchMode: Equatable { case testSession, testRelaunch, ordinary }

    /// Explicit and deterministic: only the XCUITest launch environment selects a test mode.
    nonisolated static func mode(_ env: [String: String]) -> LaunchMode {
        if env["SGGS_UITEST_RELAUNCH"] == "1" { return .testRelaunch }
        if env["SGGS_UITEST"] == "1" { return .testSession }
        return .ordinary
    }

    enum Kind: String, Codable { case file, sqlite }
    struct Item { let name: String; let url: URL; let kind: Kind }

    struct Manifest: Codable, Equatable {
        struct Entry: Codable, Equatable { let name: String; let kind: Kind; let sha256: String? }  // nil = absent
        var version: Int
        var id: String
        var created: Date
        var lastTestLaunch: Date
        var files: [Entry]
        var domains: [String]
    }

    enum VaultError: Error { case verify(String), sqlite(String) }

    // MARK: locations

    static func defaultRoot(_ fm: FileManager = .default) -> URL? {
        fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("uitest-vault", isDirectory: true)
    }

    /// Every file the UI tests can change.
    static func defaultItems() -> [Item] {
        var items: [Item] = []
        if let u = NitnemProgressStore.defaultURL() { items.append(Item(name: "nitnem-progress", url: u, kind: .file)) }
        if let u = NitnemPlanStore.defaultURL() { items.append(Item(name: "nitnem-plan", url: u, kind: .file)) }
        if let u = WidgetStore.url() { items.append(Item(name: "widget-snapshot", url: u, kind: .file)) }
        let store = ModelConfiguration(schema: Schema(versionedSchema: SavedLineSchemaV1.self)).url
        items.append(Item(name: "saved-store", url: store, kind: .sqlite))
        return items
    }

    /// The app's own defaults and the App Group's (widgets, clock location).
    static func defaultDomains() -> [String: UserDefaults] {
        let app = Bundle.main.bundleIdentifier ?? "org.sggs.app"
        return [app: .standard, WidgetStore.appGroup: SharedDefaults.suite]
    }

    // MARK: seal

    /// Called on every UI-test session launch, before anything is wiped. Returns true only when a
    /// verified vault holds the real data (and, for a stale vault, the live data is archived too).
    @discardableResult
    static func sealIfNeeded(root: URL? = defaultRoot(), items: [Item] = defaultItems(),
                             domains: [String: UserDefaults] = defaultDomains(),
                             now: Date = Date(), fm: FileManager = .default) -> Bool {
        guard let root else { return false }
        let parent = root.deletingLastPathComponent()
        removeLeftovers(of: root, suffix: ".staging-", fm: fm)   // a seal that never finished: live was untouched
        if fm.fileExists(atPath: root.path) {
            guard var manifest = readManifest(root), verifyVault(root, manifest) else {
                // never deleted and never overwritten: set aside for a person, then seal afresh
                let aside = parent.appendingPathComponent(
                    "\(root.lastPathComponent).unverified-\(stamp(now))-\(UUID().uuidString.prefix(8))")
                do { try fm.moveItem(at: root, to: aside) } catch {
                    log.error("an unverified vault could not be set aside; nothing will be wiped")
                    return false
                }
                log.error("an unverified vault was set aside as \(aside.lastPathComponent, privacy: .public)")
                return sealIfNeeded(root: root, items: items, domains: domains, now: now, fm: fm)
            }
            if now.timeIntervalSince(manifest.lastTestLaunch) > staleAfter {
                // the vault may predate real use of the app: keep the live data as well
                let archives = parent.appendingPathComponent("\(root.lastPathComponent)-archive", isDirectory: true)
                let dest = archives.appendingPathComponent("\(stamp(now))-\(UUID().uuidString.prefix(8))")
                do { try build(at: dest, items: items, domains: domains, now: now, fm: fm) } catch {
                    log.error("stale vault: archiving the live data failed; nothing will be wiped")
                    return false
                }
                prune(archives, keep: archivesKept, fm: fm)
                log.notice("stale vault: the live data was archived before the test wipe")
            }
            manifest.lastTestLaunch = now
            do { try writeManifest(manifest, to: root) } catch { return false }
            return true
        }
        do {
            try build(at: root, items: items, domains: domains, now: now, fm: fm)
            log.notice("sealed the real data before a UI test")
            return true
        } catch {
            log.error("seal failed, nothing will be wiped: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    /// Copy every item and domain into a staging folder, verify each copy, write the manifest, then
    /// publish the folder with one rename.
    static func build(at dest: URL, items: [Item], domains: [String: UserDefaults], now: Date,
                      fm: FileManager) throws {
        let staging = dest.deletingLastPathComponent()
            .appendingPathComponent("\(dest.lastPathComponent).staging-\(UUID().uuidString.prefix(8))")
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        do {
            var entries: [Manifest.Entry] = []
            for item in items {
                let copy = staging.appendingPathComponent(item.name)
                guard fm.fileExists(atPath: item.url.path) else {
                    entries.append(.init(name: item.name, kind: item.kind, sha256: nil)); continue
                }
                switch item.kind {
                case .file:
                    try fm.copyItem(at: item.url, to: copy)
                    guard let a = sha256(item.url), a == sha256(copy) else { throw VaultError.verify(item.name) }
                case .sqlite:
                    try sqliteSnapshot(from: item.url, to: copy)
                }
                guard let hash = sha256(copy) else { throw VaultError.verify(item.name) }
                entries.append(.init(name: item.name, kind: item.kind, sha256: hash))
            }
            for (name, defaults) in domains {
                let dict = defaults.persistentDomain(forName: name) ?? [:]
                let file = staging.appendingPathComponent("defaults-\(name).plist")
                try PropertyListSerialization.data(fromPropertyList: dict, format: .binary, options: 0).write(to: file)
                guard let back = readDomain(file), (back as NSDictionary).isEqual(to: dict) else {
                    throw VaultError.verify("defaults \(name)")
                }
            }
            let manifest = Manifest(version: formatVersion, id: UUID().uuidString, created: now, lastTestLaunch: now,
                                    files: entries, domains: domains.keys.sorted())
            try writeManifest(manifest, to: staging)
            try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.moveItem(at: staging, to: dest)        // whole or absent
        } catch {
            try? fm.removeItem(at: staging)
            throw error
        }
    }

    // MARK: restore

    /// Put the real data back exactly, verify it, then retire the vault. A vault that does not
    /// verify is left untouched together with the live data; a restore that cannot finish keeps
    /// the vault, so the next launch tries again.
    @discardableResult
    static func restoreIfSealed(root: URL? = defaultRoot(), items: [Item] = defaultItems(),
                                domains: [String: UserDefaults] = defaultDomains(),
                                fm: FileManager = .default) -> Bool {
        guard let root else { return false }
        removeLeftovers(of: root, suffix: ".retired-", fm: fm)    // a retire interrupted part-way
        guard fm.fileExists(atPath: root.path) else { return false }
        guard let manifest = readManifest(root), verifyVault(root, manifest) else {
            log.error("the vault did not verify; nothing restored, the vault is kept for a person to inspect")
            return false
        }
        let byName = Dictionary(items.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        guard manifest.files.allSatisfy({ byName[$0.name] != nil }),
              manifest.domains.allSatisfy({ domains[$0] != nil }) else {
            log.error("the vault names data this build does not know; nothing restored")
            return false
        }
        var ok = true
        for entry in manifest.files {
            do { try restore(byName[entry.name]!, entry, from: root, fm: fm) } catch {
                ok = false
                log.error("restore of \(entry.name, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            }
        }
        for name in manifest.domains {
            guard let defaults = domains[name], let dict = readDomain(root.appendingPathComponent("defaults-\(name).plist"))
            else { ok = false; continue }
            defaults.setPersistentDomain(dict, forName: name)
            if !((defaults.persistentDomain(forName: name) ?? [:]) as NSDictionary).isEqual(to: dict) { ok = false }
        }
        guard ok else {
            log.error("restore incomplete; the vault is kept for the next launch")
            return false
        }
        let retired = root.deletingLastPathComponent()
            .appendingPathComponent("\(root.lastPathComponent).retired-\(UUID().uuidString.prefix(8))")
        do { try fm.moveItem(at: root, to: retired) } catch { return false }   // one rename retires it
        try? fm.removeItem(at: retired)
        log.notice("restored the real data after UI tests")
        return true
    }

    private static func restore(_ item: Item, _ entry: Manifest.Entry, from root: URL, fm: FileManager) throws {
        if item.kind == .sqlite {
            // a test's WAL must never be replayed onto the restored database
            for suffix in ["-wal", "-shm"] {
                let s = URL(fileURLWithPath: item.url.path + suffix)
                if fm.fileExists(atPath: s.path) { try fm.removeItem(at: s) }
            }
        }
        guard let hash = entry.sha256 else {
            if fm.fileExists(atPath: item.url.path) { try fm.removeItem(at: item.url) }
            return
        }
        let dir = item.url.deletingLastPathComponent()
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let temp = dir.appendingPathComponent(".\(item.url.lastPathComponent).restoring-\(UUID().uuidString.prefix(8))")
        try fm.copyItem(at: root.appendingPathComponent(entry.name), to: temp)
        if fm.fileExists(atPath: item.url.path) {
            _ = try fm.replaceItemAt(item.url, withItemAt: temp)
        } else {
            try fm.moveItem(at: temp, to: item.url)
        }
        guard sha256(item.url) == hash else { throw VaultError.verify(entry.name) }
    }

    // MARK: verification

    static func readManifest(_ root: URL) -> Manifest? {
        guard let data = try? Data(contentsOf: root.appendingPathComponent("manifest.json")) else { return nil }
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        guard let m = try? d.decode(Manifest.self, from: data), m.version == formatVersion else { return nil }
        return m
    }

    static func writeManifest(_ m: Manifest, to root: URL) throws {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.sortedKeys, .prettyPrinted]
        try e.encode(m).write(to: root.appendingPathComponent("manifest.json"), options: .atomic)
    }

    /// Every present file hashes to its manifest entry, and every domain file parses.
    static func verifyVault(_ root: URL, _ m: Manifest) -> Bool {
        for entry in m.files {
            guard let want = entry.sha256 else { continue }
            guard sha256(root.appendingPathComponent(entry.name)) == want else { return false }
        }
        return m.domains.allSatisfy { readDomain(root.appendingPathComponent("defaults-\($0).plist")) != nil }
    }

    static func sha256(_ url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func readDomain(_ url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
    }

    /// A consistent copy of a live SQLite database, WAL content included, via the backup API.
    /// The source is opened read-only, so the copy never changes the live files.
    static func sqliteSnapshot(from src: URL, to dst: URL) throws {
        var s: OpaquePointer?, d: OpaquePointer?
        defer { sqlite3_close(s); sqlite3_close(d) }
        guard sqlite3_open_v2(src.path, &s, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            throw VaultError.sqlite("open source")
        }
        guard sqlite3_open_v2(dst.path, &d, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK else {
            throw VaultError.sqlite("open copy")
        }
        guard let b = sqlite3_backup_init(d, "main", s, "main") else { throw VaultError.sqlite("backup init") }
        let step = sqlite3_backup_step(b, -1)
        let finish = sqlite3_backup_finish(b)
        guard step == SQLITE_DONE, finish == SQLITE_OK else { throw VaultError.sqlite("backup") }
        // one self-contained file in the vault: no WAL beside it
        guard sqlite3_exec(d, "PRAGMA journal_mode=DELETE", nil, nil, nil) == SQLITE_OK else {
            throw VaultError.sqlite("journal mode")
        }
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(d, "PRAGMA quick_check", -1, &stmt, nil) == SQLITE_OK,
              sqlite3_step(stmt) == SQLITE_ROW, let text = sqlite3_column_text(stmt, 0),
              String(cString: text) == "ok" else { throw VaultError.sqlite("quick_check") }
    }

    // MARK: housekeeping

    private static func stamp(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return f.string(from: d)
    }

    /// Folders `<root-name><suffix>…` left by an interrupted seal (staging) or retire (retired).
    /// Neither can hold the only copy of anything: a staging folder was never published (the live
    /// data was not wiped), and a vault is renamed to retired only after its restore verified.
    private static func removeLeftovers(of root: URL, suffix: String, fm: FileManager) {
        let parent = root.deletingLastPathComponent()
        let prefix = root.lastPathComponent + suffix
        for name in (try? fm.contentsOfDirectory(atPath: parent.path)) ?? [] where name.hasPrefix(prefix) {
            try? fm.removeItem(at: parent.appendingPathComponent(name))
        }
    }

    private static func prune(_ dir: URL, keep: Int, fm: FileManager) {
        let names = ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).filter { !$0.contains(".staging-") }.sorted()
        for name in names.dropLast(keep) { try? fm.removeItem(at: dir.appendingPathComponent(name)) }
    }
}
#endif
