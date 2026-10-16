import XCTest
@testable import SGGS

/// UI tests must never cost a developer the real data on their own iPhone (2026-10-17: device UI
/// runs had deleted the Nitnem progress and plan files and reset reader settings).
@MainActor
final class UITestVaultTests: XCTestCase {
    private var dir: URL!
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("vault-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        suiteName = "test-vault-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: dir)
    }

    private var root: URL { dir.appendingPathComponent("vault") }
    private var progress: URL { dir.appendingPathComponent("data/nitnem-progress.json") }
    private var store: URL { dir.appendingPathComponent("data/default.store") }
    private var items: [UITestVault.Item] {
        [.init(name: "nitnem-progress", url: progress), .init(name: "saved-store", url: store)]
    }
    private var domains: [String: UserDefaults] { [suiteName: defaults] }

    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }
    private func read(_ url: URL) -> String? { (try? Data(contentsOf: url)).map { String(decoding: $0, as: UTF8.self) } }

    func testTheRealDataComesBackExactlyAfterATestRun() throws {
        try write("real progress", to: progress)
        defaults.set(700, forKey: "sggs_last_ang")
        defaults.set("taksal", forKey: "sggs_rehras_variant")

        XCTAssertTrue(UITestVault.sealIfNeeded(root: root, items: items, domains: domains))
        // the test run: wipes progress, creates a store, rewrites settings
        try FileManager.default.removeItem(at: progress)
        try write("test verses", to: store)
        defaults.set(915, forKey: "sggs_last_ang")
        defaults.removeObject(forKey: "sggs_rehras_variant")
        defaults.set(true, forKey: "sggs_translit")

        XCTAssertTrue(UITestVault.restoreIfSealed(root: root, items: items, domains: domains))
        XCTAssertEqual(read(progress), "real progress")
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.path), "a store the tests created is removed")
        XCTAssertEqual(defaults.integer(forKey: "sggs_last_ang"), 700)
        XCTAssertEqual(defaults.string(forKey: "sggs_rehras_variant"), "taksal")
        XCTAssertNil(defaults.object(forKey: "sggs_translit"), "a setting only the tests wrote is gone")
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path), "the vault is removed once restored")
    }

    func testASecondTestLaunchNeverOverwritesTheVault() throws {
        try write("real progress", to: progress)
        XCTAssertTrue(UITestVault.sealIfNeeded(root: root, items: items, domains: domains))
        try write("test progress", to: progress)
        XCTAssertTrue(UITestVault.sealIfNeeded(root: root, items: items, domains: domains))   // next test's launch
        XCTAssertTrue(UITestVault.restoreIfSealed(root: root, items: items, domains: domains))
        XCTAssertEqual(read(progress), "real progress")
    }

    func testAnOrdinaryLaunchWithoutAVaultChangesNothing() throws {
        try write("real progress", to: progress)
        defaults.set(700, forKey: "sggs_last_ang")
        XCTAssertFalse(UITestVault.restoreIfSealed(root: root, items: items, domains: domains))
        XCTAssertEqual(read(progress), "real progress")
        XCTAssertEqual(defaults.integer(forKey: "sggs_last_ang"), 700)
    }

    /// A restore that cannot finish keeps the vault, so the real data is still there next launch.
    func testAFailedRestoreKeepsTheVault() throws {
        try write("real progress", to: progress)
        XCTAssertTrue(UITestVault.sealIfNeeded(root: root, items: items, domains: domains))
        try FileManager.default.removeItem(at: root.appendingPathComponent("defaults-\(suiteName!).plist"))
        XCTAssertFalse(UITestVault.restoreIfSealed(root: root, items: items, domains: domains))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("nitnem-progress").path))
    }

    /// No vault, no wipe: when the seal cannot be written the caller must not wipe anything.
    func testASealThatCannotBeWrittenReportsFalse() throws {
        let blocker = dir.appendingPathComponent("blocked")
        try write("a file where the vault folder should go", to: blocker)
        XCTAssertFalse(UITestVault.sealIfNeeded(root: blocker.appendingPathComponent("vault"),
                                                items: items, domains: domains))
    }
}
