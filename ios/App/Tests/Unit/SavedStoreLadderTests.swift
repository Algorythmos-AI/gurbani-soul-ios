import XCTest
import SwiftData
@testable import SGGS

/// The bookmarks-store fallback ladder must never delete a reader's saved verses on a
/// one-off open failure: first failure → session-only in-memory store (nothing lost);
/// only a second consecutive failure destroys and recreates the file.
final class SavedStoreLadderTests: XCTestCase {
    private func garbageStore() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sggs-ladder-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("saved.store")
        try Data(repeating: 0x5A, count: 4096).write(to: url)   // not a SQLite file
        return url
    }

    /// Upgrade gate: the host app's real default store (created by earlier, un-versioned
    /// builds on this simulator) must open through the versioned schema WITHOUT hitting any
    /// fallback rung — otherwise an app update would silently reset readers' bookmarks.
    @MainActor
    func testExistingDefaultStoreOpensWithoutDegradation() {
        let c = AppContainer()
        XCTAssertNotNil(c.modelContainer)
        XCTAssertFalse(c.savedStoreDegraded, "default store must open cleanly on upgrade")
        XCTAssertFalse(c.savedStoreDestroyed)
        XCTAssertEqual(UserDefaults.standard.integer(forKey: AppContainer.savedStoreFailKey), 0)
    }

    @MainActor
    func testHealthyStoreOpensPersistently() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sggs-ladder-ok-\(UUID().uuidString).store")
        let r = AppContainer.openSavedStore(url: url, priorFailures: 0)
        XCTAssertNotNil(r.container)
        XCTAssertFalse(r.degraded); XCTAssertFalse(r.destroyed)
    }

    @MainActor
    func testFirstFailureFallsBackToMemoryWithoutDeleting() throws {
        let url = try garbageStore()
        let before = try Data(contentsOf: url)
        let r = AppContainer.openSavedStore(url: url, priorFailures: 0)
        XCTAssertNotNil(r.container, "in-memory fallback must still give a usable store")
        XCTAssertTrue(r.degraded)
        XCTAssertFalse(r.destroyed, "a first failure must never destroy the file")
        XCTAssertEqual(try Data(contentsOf: url), before, "the store file must be untouched")
    }

    @MainActor
    func testSecondConsecutiveFailureRecreates() throws {
        let url = try garbageStore()
        let before = try Data(contentsOf: url)
        let r = AppContainer.openSavedStore(url: url, priorFailures: 1)
        XCTAssertNotNil(r.container)
        XCTAssertTrue(r.degraded); XCTAssertTrue(r.destroyed)
        // the unusable file is moved aside with every byte, never deleted
        let kept = try asideFolders(beside: url)
        XCTAssertEqual(kept.count, 1, "the old store must be kept beside the new one")
        XCTAssertEqual(try Data(contentsOf: kept[0].appendingPathComponent("saved.store")), before)
        // the recreated store is a real persistent one: it opens cleanly next time
        let again = AppContainer.openSavedStore(url: url, priorFailures: 0)
        XCTAssertFalse(again.degraded)
    }

    private func asideFolders(beside url: URL) throws -> [URL] {
        let dir = url.deletingLastPathComponent()
        return try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.hasPrefix("saved.store.unusable-") }.sorted()
            .map { dir.appendingPathComponent($0) }
    }

    /// The -wal and -shm travel with the store, so a fresh store never meets a stale WAL.
    @MainActor
    func testWalAndShmMoveWithTheStore() throws {
        let url = try garbageStore()
        try Data(repeating: 0x11, count: 512).write(to: URL(fileURLWithPath: url.path + "-wal"))
        try Data(repeating: 0x22, count: 512).write(to: URL(fileURLWithPath: url.path + "-shm"))
        let r = AppContainer.openSavedStore(url: url, priorFailures: 1)
        XCTAssertTrue(r.destroyed)
        let kept = try asideFolders(beside: url)
        XCTAssertEqual(kept.count, 1)
        let names = Set(try FileManager.default.contentsOfDirectory(atPath: kept[0].path))
        XCTAssertEqual(names, ["saved.store", "saved.store-wal", "saved.store-shm"])
        XCTAssertEqual(try Data(contentsOf: kept[0].appendingPathComponent("saved.store-wal")), Data(repeating: 0x11, count: 512))
    }

    /// Two recoveries in the same second never collide, and neither overwrites the other.
    @MainActor
    func testRepeatedRecoveriesNeverCollide() throws {
        let url = try garbageStore()
        XCTAssertTrue(AppContainer.openSavedStore(url: url, priorFailures: 1).destroyed)
        try Data(repeating: 0x7A, count: 4096).write(to: url)          // the fresh store goes bad too
        for suffix in ["-wal", "-shm"] { try? FileManager.default.removeItem(atPath: url.path + suffix) }
        XCTAssertTrue(AppContainer.openSavedStore(url: url, priorFailures: 1).destroyed)
        let kept = try asideFolders(beside: url)
        XCTAssertEqual(kept.count, 2, "each recovery keeps its own copy")
        let bytes = try kept.map { try Data(contentsOf: $0.appendingPathComponent("saved.store")) }
        XCTAssertTrue(bytes.contains(Data(repeating: 0x5A, count: 4096)))
        XCTAssertTrue(bytes.contains(Data(repeating: 0x7A, count: 4096)))
    }

    /// If the store cannot be moved (a read-only or full volume), nothing is destroyed: the file
    /// stays exactly as it was and the session runs in memory.
    @MainActor
    func testAStoreThatCannotBeMovedIsNeverDestroyed() throws {
        let url = try garbageStore()
        let before = try Data(contentsOf: url)
        let dir = url.deletingLastPathComponent()
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path) }
        let r = AppContainer.openSavedStore(url: url, priorFailures: 1)
        XCTAssertFalse(r.destroyed, "a store that could not be moved aside must not be replaced")
        XCTAssertTrue(r.degraded)
        XCTAssertNotNil(r.container, "the session still gets an in-memory store")
        XCTAssertEqual(try Data(contentsOf: url), before)
    }

    /// Repeated failed launches never delete: each one either falls back to memory or moves the
    /// store aside, and the bytes the reader had are always somewhere on disk.
    @MainActor
    func testRepeatedFailedLaunchesKeepTheOriginalBytes() throws {
        let url = try garbageStore()
        let before = try Data(contentsOf: url)
        var prior = 0
        for _ in 0..<4 {
            let r = AppContainer.openSavedStore(url: url, priorFailures: prior)
            prior = r.degraded && !r.destroyed ? prior + 1 : 0
        }
        let kept = try asideFolders(beside: url).map { try Data(contentsOf: $0.appendingPathComponent("saved.store")) }
        XCTAssertTrue(kept.contains(before), "the reader's original store must survive any number of launches")
    }
}
