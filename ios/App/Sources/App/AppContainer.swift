import SwiftUI
import SwiftData
import WidgetKit
import OSLog
import GurbaniSearchKit

/// App-wide dependency root. Owns the CorpusActor + the launch-integrity result + the single shared
/// composition presentation (one root sheet). Injected through the environment.
@MainActor @Observable
final class AppContainer {
    let corpus: CorpusActor?
    let router = Router()
    var startupError: String?
    var integrity: IntegrityReport?
    /// The SINGLE root modal target. One `.sheet(item:)` in RootView drives all modals; setting this
    /// while a sheet is up swaps the content (e.g. drilling from a Trail into a shabad), so there is
    /// never more than one sheet competing to present.
    var presentation: Presentation?
    /// Queued modal to present once the current sheet finishes dismissing (see `present` + RootView onDismiss).
    var pendingPresentation: Presentation?
    /// True from the moment `present` starts a swap-dismiss until RootView's `onDismiss` fires.
    /// Presenting during that window is dropped by SwiftUI, so `present` must keep queueing —
    /// `presentation == nil` alone can't distinguish "no sheet" from "dismiss in flight".
    private var dismissInFlight = false
    /// True while RootView's TabView (the ONLY `.sheet(item:)` host) is mounted. Before the
    /// integrity check passes — and again while a manual re-verify unmounts the TabView —
    /// there is no sheet to dismiss, so `present` must never enter the swap-and-wait path:
    /// its `onDismiss` would never fire and every later `present` would queue forever
    /// (a cold launch from a widget/Spotlight/`sggs://` link during verification hit this).
    var sheetHosted = false
    var meta: CorpusMeta?
    /// Nitnem reading positions + completed days (App Group JSON; never SwiftData).
    let nitnem = NitnemProgressStore()
    /// "My Nitnem" customised sets (order/hidden/added). Sibling file, never a progress migration.
    let nitnemPlan = NitnemPlanStore()
    /// Gentle local reminders (opt-in, no entitlement, no network). Under `SGGS_UITEST` a fake
    /// scheduler stands in so tests never touch the real notification center.
    let reminders: NitnemReminderController
    #if canImport(UserNotifications)
    /// Retained delegate that routes a tapped reminder to `sggs://nitnem`.
    private var notificationRouter: NotificationRouter?
    #endif

    /// The SwiftData store for saved verses. Built explicitly (never via the implicit
    /// `.modelContainer(for:)` result-builder, which fatalErrors on a corrupt store): a broken
    /// bookmarks store must NEVER take scripture reading down with it. Fallback ladder (see
    /// `openSavedStore`): persistent → [second consecutive failure only] destroy-and-recreate
    /// → in-memory (session-only) → nil (hide Save).
    let modelContainer: ModelContainer?
    /// The persistent store was unusable this launch: we fell back to in-memory (or nothing).
    /// Surfaced as a one-time banner, never a crash.
    var savedStoreDegraded = false
    /// The persistent store was destroyed and recreated (only after a SECOND consecutive
    /// launch failure — a one-off I/O hiccup must never cost the reader their bookmarks).
    var savedStoreDestroyed = false

    static let savedStoreFailKey = "sggs_saved_store_fail_count"

    init() {
        do { self.corpus = try CorpusActor() }
        catch {
            // Never surface a raw Error/SQLite string to the user (it would read like
            // "…DBError error 0."); log the detail privately and show a plain sentence.
            self.corpus = nil
            self.startupError = "The scripture database could not be opened. Reinstalling from the App Store usually fixes this."
            Logger(subsystem: "org.sggs", category: "Startup").error("corpus open failed: \(String(describing: error), privacy: .private)")
        }

        let defaults = UserDefaults.standard
        let prior = defaults.integer(forKey: Self.savedStoreFailKey)
        let opened = Self.openSavedStore(url: nil, priorFailures: prior)
        self.modelContainer = opened.container
        self.savedStoreDegraded = opened.degraded
        self.savedStoreDestroyed = opened.destroyed
        if opened.destroyed { SpotlightIndex.removeAll() }   // the store is empty now; so is its index
        else if let store = opened.container {
            switch SpotlightIndex.launchAction(degraded: opened.degraded,
                                               saved: Result { try store.mainContext.fetch(FetchDescriptor<SavedLine>()) }) {
            case .reconcile(let saved): SpotlightIndex.reconcile(with: saved)   // system search = the saved store
            case .leaveAlone: break     // degraded or unreadable: never clear entries we cannot rebuild
            }
        }
        // count consecutive persistent-open failures; a clean open resets the ladder
        defaults.set(opened.degraded && !opened.destroyed ? prior + 1 : 0, forKey: Self.savedStoreFailKey)
        // Gentle reminders: a fake scheduler under UI test, the real notification center otherwise.
        #if canImport(UserNotifications)
        let uiTest = DebugHooks.isUITest
        let scheduler: NotificationScheduling = uiTest ? FakeNotificationScheduler() : SystemNotificationScheduler()
        #else
        let scheduler: NotificationScheduling = FakeNotificationScheduler()
        #endif
        self.reminders = NitnemReminderController(scheduler: scheduler)

        // Reload the Nitnem widget AND refresh reminders the moment a bani is marked read
        // (today's reminder for a now-complete band is removed).
        let remindersRef = self.reminders
        let completed = { [weak self] in await self?.completedReminderBands() ?? [] }
        nitnem.onChange = {
            #if canImport(WidgetKit)
            WidgetCenter.shared.reloadTimelines(ofKind: "NitnemNow")
            #endif
            Task { await remindersRef.reschedule(completedToday: await completed()) }
        }
        // A change to the customised sets re-resolves the widget snapshot and refreshes reminders.
        nitnemPlan.onChange = { [weak self] in
            Task { await self?.refreshWidgetSnapshot(); await self?.refreshReminders() }
        }
        #if canImport(UserNotifications)
        let router = self.router
        let container = self
        let nr = NotificationRouter(onOpen: { url in router.handle(url, container: container) })
        self.notificationRouter = nr
        UNUserNotificationCenter.current().delegate = nr
        #endif
    }

    /// Which reminder bands have their whole set completed for today's Nitnem day. Used to drop
    /// today's nudge for a band the reader has already finished. Empty if the registry is absent.
    func completedReminderBands() async -> Set<NitnemBand> {
        guard let corpus, corpus.capabilities.hasBanis else { return [] }
        let rows = await corpus.banis().banis
        let rehras = UserDefaults.standard.string(forKey: NitnemPrefs.rehrasVariantKey) ?? NitnemPrefs.rehrasDefault
        func done(_ cat: BaniCategory) -> Bool {
            let set = NitnemSets.resolved(category: cat, plan: nitnemPlan.entries(for: cat), registry: rows, rehrasVariant: rehras)
            return !set.isEmpty && set.allSatisfy { nitnem.isCompleted($0.id) }
        }
        var out: Set<NitnemBand> = []
        if done(.nitnemMorning) { out.insert(.amritVela) }
        if done(.nitnemEvening) { out.insert(.evening) }
        if done(.nitnemNight) { out.insert(.night) }
        return out
    }

    /// Reschedule reminders from current preferences (called on foreground).
    func refreshReminders() async {
        await reminders.reschedule(completedToday: await completedReminderBands())
    }

    struct SavedStoreOpen {
        let container: ModelContainer?
        let degraded: Bool
        let destroyed: Bool
    }

    /// The bookmarks-store fallback ladder, pure enough to unit-test against a temp URL:
    ///   persistent → (only if a previous launch ALSO failed) destroy + recreate persistent
    ///   → in-memory (session-only) → nil (Save hidden).
    /// `url == nil` uses SwiftData's default store location.
    static func openSavedStore(url: URL?, priorFailures: Int) -> SavedStoreOpen {
        let schema = Schema(versionedSchema: SavedLineSchemaV1.self)
        func config(inMemory: Bool = false) -> ModelConfiguration {
            if let url { return ModelConfiguration(schema: schema, url: url) }
            return ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        }
        func open(_ cfg: ModelConfiguration) -> ModelContainer? {
            try? ModelContainer(for: schema, migrationPlan: SavedLineMigrationPlan.self, configurations: cfg)
        }
        if let persistent = open(config()) {
            return SavedStoreOpen(container: persistent, degraded: false, destroyed: false)
        }
        if priorFailures >= 1, moveAside(storeAt: config().url) {
            // second consecutive failure: the store file is unusable, not merely busy.
            // Bookmarks are user annotations (never scripture) — a clean store beats a
            // permanently dead feature. The old files were MOVED aside first (see moveAside), so
            // a cause that was not corruption costs nothing: support can still recover them.
            if let recreated = open(config()) {
                return SavedStoreOpen(container: recreated, degraded: true, destroyed: true)
            }
        }
        if let memory = open(ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)) {
            return SavedStoreOpen(container: memory, degraded: true, destroyed: false)
        }
        return SavedStoreOpen(container: nil, degraded: true, destroyed: false)
    }

    /// Move an unusable SQLite store (and its -wal/-shm) into a new, uniquely named folder beside
    /// it. Returns true only when every file that existed has been moved — then, and only then, a
    /// fresh store may be created at the path. Nothing is ever deleted: if any move fails, the
    /// files stay where they are and the caller keeps the session in memory.
    /// Order matters: -wal and -shm first, the main file last, so an interruption never leaves a
    /// stale WAL beside a newly created store (a half-done move just fails to open again and is
    /// retried on the next launch).
    static func moveAside(storeAt url: URL) -> Bool {
        let fm = FileManager.default
        let files = ["-wal", "-shm", ""].map { URL(fileURLWithPath: url.path + $0) }.filter { fm.fileExists(atPath: $0.path) }
        guard !files.isEmpty else { return true }
        let folder = url.deletingLastPathComponent()
            .appendingPathComponent("\(url.lastPathComponent).unusable-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString.prefix(8))")
        guard (try? fm.createDirectory(at: folder, withIntermediateDirectories: false)) != nil else { return false }
        for f in files {
            guard (try? fm.moveItem(at: f, to: folder.appendingPathComponent(f.lastPathComponent))) != nil else { return false }
        }
        Logger(subsystem: "org.sggs", category: "SavedStore").error("unusable bookmarks store moved aside to \(folder.lastPathComponent, privacy: .public)")
        return true
    }

    /// Present a modal through the single root sheet. If a sheet is already up (e.g. opening a shabad
    /// from inside the Trail/Cluster), queue it and dismiss the current one — RootView's sheet
    /// `onDismiss` then presents the queued modal AFTER the dismiss animation completes (presenting
    /// during the dismiss is dropped by SwiftUI).
    func present(_ p: Presentation) {
        guard sheetHosted else {
            // No host yet: nothing is on screen to dismiss. Latest intent wins; the sheet
            // presents as soon as the TabView mounts (`.sheet(item:)` shows a non-nil item).
            pendingPresentation = nil
            dismissInFlight = false
            presentation = p
            return
        }
        if presentation != nil {
            pendingPresentation = p
            dismissInFlight = true
            presentation = nil
        } else if dismissInFlight {
            // A swap-dismiss is still animating; presenting now would be silently dropped by
            // SwiftUI. Replace the queued modal — latest intent wins (rapid taps).
            pendingPresentation = p
        } else {
            presentation = p
        }
    }

    /// Dismiss any covering sheet so a deep-link/intent navigation to the Reader is visible. Clears
    /// the queued modal too (a stale queued shabad must not pop up over the freshly-opened Ang).
    /// RootView's `onDismiss` → `flushPendingPresentation` then re-arms the present protocol.
    func dismissSheetForNavigation() {
        pendingPresentation = nil
        if presentation != nil { presentation = nil }
    }

    /// Called from RootView's sheet onDismiss: flush any queued modal. If another modal was already
    /// presented in the meantime (rapid taps), keep it and drop the stale queue entry.
    /// RootView calls this when the TabView unmounts (integrity re-verify): any in-flight
    /// dismiss can no longer complete, so the protocol is re-armed rather than left latched.
    func sheetHostDidDisappear() {
        sheetHosted = false
        dismissInFlight = false
    }

    /// RootView calls this when the TabView mounts: present anything that was queued while
    /// there was no host (e.g. a deep link that arrived during the integrity check).
    func sheetHostDidAppear() {
        sheetHosted = true
        flushPendingPresentation()
    }

    /// Watchdog-safe flush: presents a queued modal ONLY when nothing is presenting and no
    /// dismiss is in flight. Unlike `flushPendingPresentation` it may be called from any
    /// lifecycle point (e.g. scene becomes active) without racing a swap-dismiss.
    func flushIfIdle() {
        guard sheetHosted, !dismissInFlight, presentation == nil, let p = pendingPresentation else { return }
        pendingPresentation = nil
        presentation = p
    }

    func flushPendingPresentation() {
        dismissInFlight = false
        guard let pending = pendingPresentation else { return }
        pendingPresentation = nil
        guard presentation == nil else { return }
        presentation = pending
    }

    func runIntegrity() async {
        guard let corpus else { return }
        integrity = await LaunchIntegrity.run(corpus: corpus)
    }

    /// Manual re-verify from the failure screen (clears the report so the "verifying" state
    /// shows, then re-runs the full check — a transient I/O failure shouldn't need a reinstall).
    func retryIntegrity() async {
        integrity = nil
        await runIntegrity()
    }

    /// Number of Vaars in the bundled DB (Explore caption; nil until loaded).
    var vaarCount: Int?
    /// Number of voices in the bundled roster (Explore caption).
    let contributorCount: Int? = ContributorsStore.load()?.count

    func loadMeta() async {
        guard meta == nil, let corpus else { return }
        meta = try? await corpus.meta()
        vaarCount = await corpus.vaars().count
    }

    /// Refresh the <50 KB widget snapshot (App Group JSON): today's Hukam opening verse +
    /// the fixed-clock pahar→raags table. Widgets NEVER open the corpus DB.
    /// Runs post-launch (after integrity passes) and is cheap enough to run every launch.
    func refreshWidgetSnapshot() async {
        SharedDefaults.migrateFromStandard()   // clock mode + solar coords moved to the App Group
        guard let corpus, integrity?.ok == true else { return }
        guard let hukam = try? await corpus.randomHukam(),
              let firstVerse = hukam.lines.first(where: { !$0.isHeader }) else { return }
        var paharRaags: [Int: [String]] = [:]
        var paharRaagsGurmukhi: [Int: [String]] = [:]
        let clock = await corpus.timingClock()
        if clock.available {
            for p in 1...8 {
                let claims = clock.raags(forPahar: p)
                paharRaags[p] = claims.compactMap { $0.roman ?? $0.raagName }
                paharRaagsGurmukhi[p] = claims.compactMap { $0.raagName ?? $0.roman }
            }
        }
        // Nitnem: resolve the daily sets (registry facts the DB-less widget can't get itself).
        var nitnemData: NitnemWidgetData? = nil
        if corpus.capabilities.hasBanis {
            let rehras = UserDefaults.standard.string(forKey: NitnemPrefs.rehrasVariantKey) ?? NitnemPrefs.rehrasDefault
            let rows = await corpus.banis().banis
            func brief(_ cat: BaniCategory) -> [NitnemWidgetData.Bani] {
                // honour the reader's customised set so the widget and the home never disagree
                NitnemSets.resolved(category: cat, plan: nitnemPlan.entries(for: cat), registry: rows, rehrasVariant: rehras)
                    .map { NitnemWidgetData.Bani(id: $0.id, key: $0.key, titleEn: $0.titleEn, titleGm: $0.titleGm, minutes: $0.estimatedMinutes, nLines: $0.nLines) }
            }
            nitnemData = NitnemWidgetData(sets: ["morning": brief(.nitnemMorning), "evening": brief(.nitnemEvening), "night": brief(.nitnemNight)])
        }
        WidgetStore.save(WidgetSnapshot(
            generatedAt: Date(),
            hukamGurmukhi: firstVerse.gurmukhi,     // verbatim — copied, never edited
            hukamTranslit: firstVerse.translit,
            hukamAng: firstVerse.ang,
            // The unit can open before its seed (a Vaar's saloks precede the pauri): cite the
            // composition and line of the verse actually shown, so a tap opens what was read.
            hukamCompId: firstVerse.compId,
            hukamLineId: firstVerse.id,
            paharRaags: paharRaags,
            paharRaagsGurmukhi: paharRaagsGurmukhi,
            clockMode: SharedDefaults.clockMode,
            solarLat: SharedDefaults.solarCoords()?.lat,
            solarLon: SharedDefaults.solarCoords()?.lon,
            nitnem: nitnemData))
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}

/// The shared shabad/hukam modal target (passed to ShabadSheet).
enum CompositionPresentation: Identifiable, Hashable {
    /// `focusLineId`: the verse the sheet scrolls to and highlights (nil = top). Deliberately
    /// NOT part of `id` — `.sheet(item:)` keys on `id`, and a focus change must never re-present.
    case shabad(compId: Int, focusLineId: Int? = nil)
    case hukam
    var id: String { switch self { case .shabad(let c, _): return "shabad-\(c)"; case .hukam: return "hukam" } }
}

/// Every root modal, behind ONE `.sheet(item:)`. Identifiable only (associated values needn't be Hashable).
enum Presentation: Identifiable {
    case shabad(compId: Int, focusLineId: Int? = nil)
    case hukam
    case trail(TrailStart)
    /// The verses two themes share (or one theme carries alone) — the Constellation's pair sheet.
    case pair(PairRequest)
    /// The bani reader's Contents sheet (jump to a pauri/ashtapadi) — routed through the one
    /// sheet host so it can never collide with a deep-linked shabad/hukam.
    case baniContents(BaniContentsRequest)
    /// The bani reader's reading-settings sheet (size, spacing, paper tone, toggles).
    case readingSettings
    var id: String {
        switch self {
        case .shabad(let c, _): return "shabad-\(c)"
        case .hukam: return "hukam"
        case .trail(let t): return "trail-\(t.id)"
        case .pair(let r): return "pair-\(r.id)"
        case .baniContents(let r): return "contents-\(r.baniId)"
        case .readingSettings: return "reading-settings"
        }
    }
    /// The shabad/hukam subset, for ShabadSheet.
    var composition: CompositionPresentation? {
        switch self {
        case .shabad(let c, let l): return .shabad(compId: c, focusLineId: l)
        case .hukam: return .hukam
        default: return nil
        }
    }
}

/// A verse the Semantic Trail starts (or steps to). Carries verbatim text so the Trail can pin it.
struct TrailStart: Identifiable, Hashable {
    let id: Int            // line id
    let gurmukhi: String
    let translit: String
    let ang: Int
    let compId: Int
}

/// Generic async load state for screen models.
enum LoadState<T: Sendable>: Sendable {
    case idle, loading, loaded(T), empty, failed(String)
}
