import SQLite3
import XCTest
@testable import SGGS

/// UI tests must never cost a developer the real data on their own iPhone (2026-10-17: device UI
/// runs had deleted the Nitnem progress and plan files and reset reader settings). Every scenario
/// the vault must survive, with real files, a real SQLite database in WAL mode and real defaults.
@MainActor
final class UITestVaultTests: XCTestCase {
    private let fm = FileManager.default
    private var dir: URL!
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        dir = fm.temporaryDirectory.appendingPathComponent("vault-test-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        suiteName = "test-vault-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        _ = try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.appendingPathComponent("data").path)
        try? fm.removeItem(at: dir)
    }

    // MARK: fixtures

    private var root: URL { dir.appendingPathComponent("vault") }
    private var data: URL { dir.appendingPathComponent("data") }
    private var progress: URL { data.appendingPathComponent("nitnem-progress.json") }
    private var plan: URL { data.appendingPathComponent("nitnem-plan.json") }
    private var store: URL { dir.appendingPathComponent("db/default.store") }   // its own folder, like the App Group
    private var items: [UITestVault.Item] {
        [.init(name: "nitnem-progress", url: progress, kind: .file),
         .init(name: "nitnem-plan", url: plan, kind: .file),
         .init(name: "saved-store", url: store, kind: .sqlite)]
    }
    private var domains: [String: UserDefaults] { [suiteName: defaults] }

    private func seal(now: Date = Date()) -> Bool {
        UITestVault.sealIfNeeded(root: root, items: items, domains: domains, now: now, fm: fm)
    }
    private func restore() -> Bool {
        UITestVault.restoreIfSealed(root: root, items: items, domains: domains, fm: fm)
    }

    private func write(_ text: String, to url: URL) throws {
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }
    private func read(_ url: URL) -> String? { (try? Data(contentsOf: url)).map { String(decoding: $0, as: UTF8.self) } }
    private func exists(_ url: URL) -> Bool { fm.fileExists(atPath: url.path) }

    /// A WAL-mode database whose rows are still in the -wal file (the connection stays open, so
    /// nothing is checkpointed) — what SwiftData leaves on disk mid-session.
    @discardableResult
    private func walStore(rows: [String], keepOpen: Bool = true) throws -> OpaquePointer? {
        try fm.createDirectory(at: store.deletingLastPathComponent(), withIntermediateDirectories: true)
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(store.path, &db), SQLITE_OK)
        exec(db, "PRAGMA journal_mode=WAL; PRAGMA wal_autocheckpoint=0; CREATE TABLE IF NOT EXISTS saved(v TEXT);")
        for r in rows { exec(db, "INSERT INTO saved VALUES('\(r)');") }
        if !keepOpen { sqlite3_close(db); return nil }
        return db
    }
    private func exec(_ db: OpaquePointer?, _ sql: String) {
        XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK, sql)
    }
    private func rows(_ url: URL) -> [String] {
        var db: OpaquePointer?, st: OpaquePointer?
        defer { sqlite3_finalize(st); sqlite3_close(db) }
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              sqlite3_prepare_v2(db, "SELECT v FROM saved ORDER BY rowid", -1, &st, nil) == SQLITE_OK else { return [] }
        var out: [String] = []
        while sqlite3_step(st) == SQLITE_ROW { out.append(String(cString: sqlite3_column_text(st, 0))) }
        return out
    }

    // MARK: launch modes

    func testLaunchModeIsExplicit() {
        XCTAssertEqual(UITestVault.mode([:]), .ordinary)
        XCTAssertEqual(UITestVault.mode(["SGGS_UITEST": "1"]), .testSession)
        XCTAssertEqual(UITestVault.mode(["SGGS_UITEST_RELAUNCH": "1"]), .testRelaunch)
        XCTAssertEqual(UITestVault.mode(["SGGS_UITEST": "1", "SGGS_UITEST_RELAUNCH": "1"]), .testRelaunch,
                       "a relaunch never re-seals or wipes")
        XCTAssertEqual(UITestVault.mode(["SGGS_UITEST": "0"]), .ordinary)
        XCTAssertEqual(UITestVault.mode(["SGGS_UITEST": "true"]), .ordinary, "only the exact test value counts")
    }

    // MARK: round trip

    func testTheRealDataComesBackExactly() throws {
        try write("real progress", to: progress)
        try walStore(rows: ["Ang 1", "Ang 1430"], keepOpen: false)
        defaults.set(1430, forKey: "sggs_last_ang")
        defaults.set("taksal", forKey: "sggs_rehras_variant")
        defaults.set(["nested": ["ਸਤਿ", 1, true]], forKey: "odd")
        defaults.set(Data([0, 255]), forKey: "blob")
        defaults.set(Date(timeIntervalSince1970: 1), forKey: "when")

        XCTAssertTrue(seal())
        // the test run: wipes progress, creates a plan, adds a saved verse, rewrites settings
        try fm.removeItem(at: progress)
        try write("test plan", to: plan)
        let db = try walStore(rows: ["test verse"])
        defaults.set(915, forKey: "sggs_last_ang")
        defaults.removeObject(forKey: "sggs_rehras_variant")
        defaults.set(true, forKey: "sggs_translit")
        sqlite3_close(db)

        XCTAssertTrue(restore())
        XCTAssertEqual(read(progress), "real progress")
        XCTAssertFalse(exists(plan), "a file only the tests created is removed")
        XCTAssertEqual(rows(store), ["Ang 1", "Ang 1430"])
        XCTAssertEqual(defaults.integer(forKey: "sggs_last_ang"), 1430, "a boundary Ang survives")
        XCTAssertEqual(defaults.string(forKey: "sggs_rehras_variant"), "taksal")
        XCTAssertNil(defaults.object(forKey: "sggs_translit"), "a setting only the tests wrote is gone")
        XCTAssertEqual(defaults.dictionary(forKey: "odd") as NSDictionary?, ["nested": ["ਸਤਿ", 1, true]] as NSDictionary)
        XCTAssertEqual(defaults.data(forKey: "blob"), Data([0, 255]))
        XCTAssertEqual(defaults.object(forKey: "when") as? Date, Date(timeIntervalSince1970: 1))
        XCTAssertFalse(exists(root), "the vault is retired once the restore verified")
    }

    /// Rows still in the WAL when the seal runs are part of the backup, and a test's WAL is never
    /// replayed onto the restored database.
    func testPendingWALTransactionsAreKept() throws {
        let wal = URL(fileURLWithPath: store.path + "-wal")
        let real = try walStore(rows: ["real 1", "real 2"])          // open: rows only in -wal
        XCTAssertTrue(exists(wal))
        XCTAssertTrue(seal())
        exec(real, "INSERT INTO saved VALUES('test');")               // the test writes into the WAL
        // a test process that died mid-write leaves its WAL beside the database
        let crashed = dir.appendingPathComponent("crashed-wal")
        try fm.copyItem(at: wal, to: crashed)
        sqlite3_close(real)
        if exists(wal) { try fm.removeItem(at: wal) }
        try fm.copyItem(at: crashed, to: wal)
        XCTAssertTrue(restore())
        XCTAssertFalse(exists(wal), "a test's WAL is never replayed onto the restored database")
        XCTAssertEqual(rows(store), ["real 1", "real 2"])
    }

    func testEmptyOriginalDataRestoresToEmpty() throws {
        XCTAssertTrue(seal())                                         // nothing at all on the device
        try write("test progress", to: progress)
        try walStore(rows: ["test"], keepOpen: false)
        defaults.set(5, forKey: "sggs_last_ang")
        XCTAssertTrue(restore())
        XCTAssertFalse(exists(progress)); XCTAssertFalse(exists(store))
        XCTAssertFalse(exists(URL(fileURLWithPath: store.path + "-wal")))
        XCTAssertNil(defaults.object(forKey: "sggs_last_ang"))
    }

    // MARK: a seal that cannot be trusted wipes nothing

    func testASealThatCannotReadASourceFailsAndLeavesNoVault() throws {
        try write("real progress", to: progress)
        try fm.setAttributes([.posixPermissions: 0o000], ofItemAtPath: progress.path)
        defer { _ = try? fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: progress.path) }
        XCTAssertFalse(seal(), "an unreadable source must stop the wipe")
        XCTAssertFalse(exists(root), "no half vault is published")
        XCTAssertTrue(try fm.contentsOfDirectory(atPath: dir.path).allSatisfy { !$0.contains(".staging-") })
    }

    func testASealThatCannotBeWrittenReportsFalse() throws {
        let blocker = dir.appendingPathComponent("blocked")
        try write("a file where the vault folder should go", to: blocker)
        XCTAssertFalse(UITestVault.sealIfNeeded(root: blocker.appendingPathComponent("vault"),
                                                items: items, domains: domains, fm: fm))
    }

    /// A crash part-way through a seal leaves a staging folder and no vault. The live data was
    /// never wiped, so the next test launch seals afresh from it.
    func testAnInterruptedSealIsDiscardedAndRedone() throws {
        try write("real progress", to: progress)
        let staging = dir.appendingPathComponent("vault.staging-deadbeef")
        try write("partial", to: staging.appendingPathComponent("nitnem-progress"))
        XCTAssertTrue(seal())
        XCTAssertFalse(exists(staging))
        try write("test", to: progress)
        XCTAssertTrue(restore())
        XCTAssertEqual(read(progress), "real progress")
    }

    func testASecondTestLaunchNeverOverwritesTheVault() throws {
        try write("real progress", to: progress)
        XCTAssertTrue(seal())
        try write("test progress", to: progress)
        XCTAssertTrue(seal())                                         // the next test's launch
        XCTAssertTrue(restore())
        XCTAssertEqual(read(progress), "real progress")
    }

    // MARK: a vault that cannot be trusted is never restored and never deleted

    func testATamperedVaultIsNotRestoredAndIsKept() throws {
        try write("real progress", to: progress)
        XCTAssertTrue(seal())
        try write("test progress", to: progress)
        try write("corrupted", to: root.appendingPathComponent("nitnem-progress"))
        XCTAssertFalse(restore())
        XCTAssertEqual(read(progress), "test progress", "the live files are not touched")
        XCTAssertTrue(exists(root), "the only recoverable copy is kept")
    }

    func testAVaultOfAnotherFormatIsNotRestored() throws {
        try write("real progress", to: progress)
        XCTAssertTrue(seal())
        var m = try XCTUnwrap(UITestVault.readManifest(root))
        m.version = 99
        try UITestVault.writeManifest(m, to: root)
        try write("test progress", to: progress)
        XCTAssertFalse(restore())
        XCTAssertEqual(read(progress), "test progress")
        XCTAssertTrue(exists(root))
    }

    /// A test launch that finds an unverified vault sets it aside (never deletes it) and does not
    /// trust it as the real data.
    func testAnUnverifiedVaultIsSetAsideNotOverwritten() throws {
        try write("real progress", to: progress)
        XCTAssertTrue(seal())
        try fm.removeItem(at: root.appendingPathComponent("manifest.json"))
        XCTAssertTrue(seal())
        let aside = try fm.contentsOfDirectory(atPath: dir.path).filter { $0.hasPrefix("vault.unverified-") }
        XCTAssertEqual(aside.count, 1, "the unverified vault is kept beside the new one")
        XCTAssertEqual(read(dir.appendingPathComponent(aside[0]).appendingPathComponent("nitnem-progress")), "real progress")
    }

    func testAVaultNamingUnknownDataIsNotRestored() throws {
        try write("real progress", to: progress)
        XCTAssertTrue(seal())
        try write("test progress", to: progress)
        let fewer = Array(items.dropFirst())
        XCTAssertFalse(UITestVault.restoreIfSealed(root: root, items: fewer, domains: domains, fm: fm))
        XCTAssertEqual(read(progress), "test progress")
        XCTAssertTrue(exists(root))
    }

    // MARK: interrupted restores are repeatable

    /// One file restores, another cannot: the vault stays, and the next launch finishes the job.
    func testAPartialRestoreKeepsTheVaultAndCompletesLater() throws {
        try write("real progress", to: progress)
        try walStore(rows: ["real"], keepOpen: false)
        XCTAssertTrue(seal())
        try write("test progress", to: progress)
        try walStore(rows: ["test"], keepOpen: false)
        try fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: data.path)   // the Nitnem folder is locked
        XCTAssertFalse(restore())
        XCTAssertTrue(exists(root), "an incomplete restore keeps the vault")
        XCTAssertEqual(rows(store), ["real"], "the store (another folder) was restored")
        XCTAssertEqual(read(progress), "test progress", "the locked file was not")
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: data.path)
        XCTAssertTrue(restore(), "the next launch finishes it")
        XCTAssertEqual(read(progress), "real progress")
        XCTAssertEqual(rows(store), ["real"])
        XCTAssertTrue(restore() == false && !exists(root), "a second ordinary launch has nothing to do")
    }

    /// A crash after the retire rename leaves a `.retired-` folder: the restore had verified, so it
    /// is removed, and the restored data is not touched again.
    func testAnInterruptedRetireLeavesTheRestoredDataAlone() throws {
        try write("real progress", to: progress)
        XCTAssertTrue(seal())
        try write("test progress", to: progress)
        XCTAssertTrue(restore())
        let leftover = dir.appendingPathComponent("vault.retired-cafebabe")
        try write("old", to: leftover.appendingPathComponent("nitnem-progress"))
        XCTAssertFalse(restore())
        XCTAssertFalse(exists(leftover))
        XCTAssertEqual(read(progress), "real progress")
    }

    func testAnOrdinaryLaunchWithoutAVaultChangesNothing() throws {
        try write("real progress", to: progress)
        defaults.set(700, forKey: "sggs_last_ang")
        XCTAssertFalse(restore())
        XCTAssertEqual(read(progress), "real progress")
        XCTAssertEqual(defaults.integer(forKey: "sggs_last_ang"), 700)
    }

    // MARK: a stale vault never costs the newer data

    /// An aborted run leaves a vault; the developer then uses the app for real (a release build
    /// never restores). The next test run must keep that newer data too.
    func testAStaleVaultArchivesTheLiveDataBeforeAWipe() throws {
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        try write("old real progress", to: progress)
        XCTAssertTrue(seal(now: t0))
        try write("newer real progress", to: progress)               // real use, hours later
        XCTAssertTrue(seal(now: t0.addingTimeInterval(3 * 3600)))
        let archives = dir.appendingPathComponent("vault-archive")
        let made = try fm.contentsOfDirectory(atPath: archives.path)
        XCTAssertEqual(made.count, 1)
        XCTAssertEqual(read(archives.appendingPathComponent(made[0]).appendingPathComponent("nitnem-progress")),
                       "newer real progress")
        // launches within the same run do not archive again
        XCTAssertTrue(seal(now: t0.addingTimeInterval(3 * 3600 + 60)))
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: archives.path).count, 1)
    }

    func testArchivesAreBounded() throws {
        var t = Date(timeIntervalSince1970: 1_000_000)
        try write("p", to: progress)
        XCTAssertTrue(seal(now: t))
        for _ in 0..<(UITestVault.archivesKept + 3) {
            t = t.addingTimeInterval(3600)
            XCTAssertTrue(seal(now: t))
        }
        let archives = dir.appendingPathComponent("vault-archive")
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: archives.path).count, UITestVault.archivesKept)
    }

    // MARK: the reset list

    func testEveryLeakableReadingSettingIsReset() {
        for key in ["sggs_saroop", "sggs_appearance", "sggs_show_english", "sggs_live_activity", "sggs_last_ang",
                    "sggs_gutka_layout"] {
            XCTAssertTrue(UITestVault.resetKeys.contains(key), key)
        }
        XCTAssertFalse(UITestVault.resetKeys.contains("sggs_accent"), "accent persistence is itself under test")
    }
}
