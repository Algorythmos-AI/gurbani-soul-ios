#if DEBUG
import Foundation
import OSLog
import SwiftData

/// UI tests wipe and rewrite the app's own storage (Nitnem progress and plan, reader settings,
/// saved verses). On a simulator that storage is disposable; on a developer's own iPhone it is
/// real. So the first UI-test launch copies it into a vault before anything is wiped, and the next
/// ordinary launch puts it back exactly — files the tests created are removed — then deletes the
/// vault. Debug builds only: a TestFlight or App Store build never contains this.
///
///   SGGS_UITEST=1            seal (once), then the test may wipe
///   SGGS_UITEST_RELAUNCH=1   a test's own relaunch: keep the test state, leave the vault sealed
///   neither                  restore the real data, then remove the vault
@MainActor
enum UITestVault {
    private static let log = Logger(subsystem: "org.sggs.app", category: "uitest-vault")

    struct Item { let name: String; let url: URL }

    static func defaultRoot(_ fm: FileManager = .default) -> URL? {
        fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("uitest-vault", isDirectory: true)
    }

    /// Every file the UI tests can change. The saved-verses store is listed with its -wal/-shm.
    static func defaultItems() -> [Item] {
        var items: [Item] = []
        if let u = NitnemProgressStore.defaultURL() { items.append(Item(name: "nitnem-progress", url: u)) }
        if let u = NitnemPlanStore.defaultURL() { items.append(Item(name: "nitnem-plan", url: u)) }
        let store = ModelConfiguration(schema: Schema(versionedSchema: SavedLineSchemaV1.self)).url
        for suffix in ["", "-wal", "-shm"] {
            items.append(Item(name: "saved-store\(suffix)", url: URL(fileURLWithPath: store.path + suffix)))
        }
        return items
    }

    /// The app's own defaults and the App Group's (widgets, clock location).
    static func defaultDomains() -> [String: UserDefaults] {
        let app = Bundle.main.bundleIdentifier ?? "org.sggs.app"
        return [app: .standard, WidgetStore.appGroup: SharedDefaults.suite]
    }

    /// Copy the real data into the vault unless it is already there. Returns true when the vault
    /// holds the real data and the test may wipe; false means nothing may be wiped.
    @discardableResult
    static func sealIfNeeded(root: URL? = defaultRoot(), items: [Item] = defaultItems(),
                             domains: [String: UserDefaults] = defaultDomains(),
                             fm: FileManager = .default) -> Bool {
        guard let root else { return false }
        let sealed = root.appendingPathComponent("sealed")
        if fm.fileExists(atPath: sealed.path) { return true }       // never overwrite real data with test residue
        try? fm.removeItem(at: root)                                // a seal interrupted part-way
        do {
            try fm.createDirectory(at: root, withIntermediateDirectories: true)
            for item in items where fm.fileExists(atPath: item.url.path) {
                try fm.copyItem(at: item.url, to: root.appendingPathComponent(item.name))
            }
            for (name, defaults) in domains {
                let dict = defaults.persistentDomain(forName: name) ?? [:]
                let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .binary, options: 0)
                try data.write(to: root.appendingPathComponent("defaults-\(name).plist"))
            }
            try Data().write(to: sealed)
            log.notice("sealed the real data before a UI test")
            return true
        } catch {
            log.error("seal failed, nothing will be wiped: \(error.localizedDescription, privacy: .public)")
            try? fm.removeItem(at: root)
            return false
        }
    }

    /// Put the real data back and remove the vault. If any step fails the vault is kept, so the
    /// next launch tries again — the real data is never lost to a half-finished restore.
    @discardableResult
    static func restoreIfSealed(root: URL? = defaultRoot(), items: [Item] = defaultItems(),
                                domains: [String: UserDefaults] = defaultDomains(),
                                fm: FileManager = .default) -> Bool {
        guard let root, fm.fileExists(atPath: root.appendingPathComponent("sealed").path) else { return false }
        var ok = true
        for item in items {
            let kept = root.appendingPathComponent(item.name)
            do {
                if fm.fileExists(atPath: item.url.path) { try fm.removeItem(at: item.url) }
                if fm.fileExists(atPath: kept.path) {
                    try fm.createDirectory(at: item.url.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try fm.copyItem(at: kept, to: item.url)
                }
            } catch { ok = false }
        }
        for (name, defaults) in domains {
            let file = root.appendingPathComponent("defaults-\(name).plist")
            guard let data = try? Data(contentsOf: file),
                  let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
            else { ok = false; continue }
            defaults.setPersistentDomain(dict, forName: name)
        }
        if ok {
            try? fm.removeItem(at: root)
            log.notice("restored the real data after UI tests")
        } else {
            log.error("restore incomplete; the vault is kept for the next launch")
        }
        return ok
    }
}
#endif
