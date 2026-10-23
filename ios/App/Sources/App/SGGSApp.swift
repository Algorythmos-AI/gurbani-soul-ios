import SwiftUI
import SwiftData
import CoreSpotlight

@main
struct SGGSApp: App {
    @State private var container: AppContainer
    @Environment(\.scenePhase) private var scenePhase

    init() {
        #if DEBUG
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
            // D10: a cold integrity verify (full re-hash), as after an install or an update
            if ProcessInfo.processInfo.environment["SGGS_UITEST_COLD_VERIFY"] == "1" {
                UserDefaults.standard.removeObject(forKey: LaunchIntegrity.cacheKey)
            }
        }
        #endif
        Brand.applyNavigationTitleFonts()
        _container = State(initialValue: AppContainer())
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
                await container.runIntegrity()
                await container.loadMeta()
                await container.refreshWidgetSnapshot()
                await container.refreshReminders()
                await container.indexThemesForSpotlight()   // also warms the Themes index
            }
            .onOpenURL { url in container.router.handle(url, container: container) }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    container.flushIfIdle()   // never presents mid-dismiss
                    Task { await container.refreshReminders() }   // re-plan dated reminders on return
                    Task { await container.refreshWidgetSnapshotIfStale() }   // keep the Hukam days ahead
                }
            }
            // The dated plan drops "today" once its time has passed, so a time-zone or clock change
            // while the app is open re-plans at once rather than waiting for the next foreground.
            .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
                Task { await container.refreshReminders() }
                Task { await container.refreshWidgetSnapshotIfStale() }   // a new local date may need today's verse
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
