import SwiftUI
import SwiftData
import CoreSpotlight
import UserNotifications

@main
struct SGGSApp: App {
    /// APNs registration callbacks (the Hukamnama push) → PushTokenBroker.
    @UIApplicationDelegateAdaptor(SGGSAppDelegate.self) private var appDelegate
    @State private var container: AppContainer
    @Environment(\.scenePhase) private var scenePhase

    init() {
        #if DEBUG
        LaunchClock.mark(.appInit)
        if LaunchClock.exposed { LaunchClock.discardPersisted() }   // never read an earlier launch's timeline
        // XCUITest launches set SGGS_UITEST=1: clear per-launch residue that would otherwise
        // leak between tests (resume-last-Ang, the transliteration toggle). Never the accent —
        // its persistence across a relaunch is itself under test. Debug builds only.
        // UITestVault keeps a developer's real data out of the tests' reach: sealed before the
        // first wipe, restored on the next ordinary launch. A seal that fails wipes nothing.
        switch UITestVault.mode(ProcessInfo.processInfo.environment) {
        case .testRelaunch:
            break                                   // a test's own relaunch keeps the state it built
        case .ordinary:
            UITestVault.restoreIfSealed()
        case .testSession:
            // a seal that is not verified wipes nothing
            guard UITestVault.sealIfNeeded() else { break }
            for key in UITestVault.resetKeys {
                UserDefaults.standard.removeObject(forKey: key)
            }
            NitnemProgressStore.wipe()
            NitnemPlanStore.wipe()
            VaarProgressStore.wipe()
            if let u = HukamnamaStore.defaultURL() { try? FileManager.default.removeItem(at: u) }
        }
        // D10: a cold integrity verify (full re-hash), as after an install or an update. It drops the
        // verified fingerprint only, never any data, so it also applies to an ordinary launch: the
        // bench's D10 outside XCTest (ios/tools/device_bench.sh d10) launches the app that way.
        if ProcessInfo.processInfo.environment["SGGS_UITEST_COLD_VERIFY"] == "1" {
            UserDefaults.standard.removeObject(forKey: LaunchIntegrity.cacheKey)
        }
        #endif
        Brand.applyNavigationTitleFonts()
        _container = State(initialValue: AppContainer())
        #if DEBUG
        LaunchClock.mark(.containerReady)
        #endif
    }

    var body: some Scene {
        WindowGroup {
            // The SwiftData container is built (with fallbacks) in AppContainer — never via the
            // implicit `.modelContainer(for:)`, which fatalErrors on an unopenable store. If even
            // the in-memory fallback failed (container nil), the app still runs: scripture
            // reading must never be hostage to the bookmarks store.
            Group {
                if let modelContainer = container.modelContainer {
                    RootView().modelContainer(modelContainer)
                } else {
                    RootView()
                }
            }
            .environment(container)
            .task {
                CrashMonitor.shared.start()   // local-only diagnostics; QA requires zero collected
                ReadingActivityController.sweepOrphaned()   // clear any activity left by a prior launch
                #if DEBUG
                // A cold launch straight into a deep link (as a notification tap or a widget does),
                // delivered while the integrity check is still running: the presentation must queue
                // and appear only once the sheet host mounts.
                if let raw = DebugHooks.environment["SGGS_UITEST_OPEN_URL"], let url = URL(string: raw) {
                    container.router.handle(url, container: container)
                }
                // A device check of the notification-tap path: a LOCAL notification on the
                // Hukamnama thread, carrying today's URL, N seconds after launch. A tap goes through
                // the same `NotificationRouter.didReceive` as a real push (lock the phone, tap it).
                if let raw = DebugHooks.environment["SGGS_DEBUG_LOCAL_HUKAMNAMA"], let secs = Double(raw), secs >= 1 {
                    let content = UNMutableNotificationContent()
                    content.title = "Hukamnama · Sri Harmandir Sahib (device check)"
                    content.body = "Tap: the Hukamnama sheet should open"
                    content.threadIdentifier = NotificationRouter.hukamnamaThread
                    content.userInfo = ["url": "sggs://hukamnama/\(AmritsarDate.key(Date()))"]
                    let request = UNNotificationRequest(identifier: "debug.hukamnama", content: content,
                        trigger: UNTimeIntervalNotificationTrigger(timeInterval: secs, repeats: false))
                    try? await UNUserNotificationCenter.current().add(request)
                }
                #endif
                await container.runIntegrity()
                await container.loadMeta()
                await container.refreshWidgetSnapshot()
                await container.refreshReminders()
                await container.refreshHukamnama()   // registers with APNs on every launch while wanted
                await container.indexThemesForSpotlight()   // once per build, after launch settles
            }
            .onOpenURL { url in container.router.handle(url, container: container) }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    container.flushIfIdle()   // never presents mid-dismiss
                    Task { await container.refreshReminders() }   // re-plan dated reminders on return
                    Task { await container.refreshWidgetSnapshotIfStale() }   // keep the Hukam days ahead
                    Task { await container.refreshHukamnama() }   // denied → DELETE; 24 h re-ack; queued DELETEs
                }
            }
            // The dated plan drops "today" once its time has passed, so a time-zone or clock change
            // while the app is open re-plans at once rather than waiting for the next foreground.
            .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
                Task { await container.refreshReminders() }
                Task { await container.refreshWidgetSnapshotIfStale() }   // a new local date may need today's verse
                if HukamnamaConfig.enabled { container.hukamnamaPush.scheduleSync() }   // new DST slots, debounced
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSSystemClockDidChange)) { _ in
                Task { await container.refreshReminders() }
            }
            .onContinueUserActivity(CSSearchableItemActionType) { activity in
                // a saved verse tapped in system search → open its composition; a theme → its page
                guard let id = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String else { return }
                if let compId = SpotlightIndex.compId(fromIdentifier: id) {
                    container.present(.shabad(compId: compId, focusLineId: SpotlightIndex.lineId(fromIdentifier: id)))
                } else if let slug = SpotlightIndex.themeSlug(fromIdentifier: id), let url = URL(string: "sggs://theme/\(slug)") {
                    container.dismissSheetForNavigation()
                    container.router.handle(url, container: container)
                }
            }
        }
    }
}
