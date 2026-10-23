import Foundation

/// The tiny snapshot the main app writes for the widget extension (compiled into BOTH targets).
/// Widgets NEVER open the ~100 MB corpus DB — they read this <50 KB JSON + the dependency-free
/// GurbaniPahar math. Scripture in the snapshot is verbatim (copied from the DB, never edited).
struct WidgetSnapshot: Codable, Sendable {
    var generatedAt: Date
    /// A complete-unit Hukam verse (first non-header line) + its citation.
    var hukamGurmukhi: String
    var hukamTranslit: String
    var hukamAng: Int
    var hukamCompId: Int
    /// The shown verse's line id, so a tap lands on it. Optional: older snapshots decode.
    var hukamLineId: Int? = nil
    /// Fixed-clock primary raag claims: pahar (1–8) → roman raag names, from /api/timing/clock.
    /// Precomputed so the widget needs zero SQLite/location/solar logic.
    var paharRaags: [Int: [String]]
    /// The same claims' Gurmukhi raag names (verbatim from the timing table), parallel to
    /// `paharRaags`. Optional so a snapshot written by an older app still decodes.
    var paharRaagsGurmukhi: [Int: [String]]? = nil
    /// The reader's clock mode ("fixed" | "solar") and their stored solar coordinates
    /// (already rounded to ~1 km by SolarLocation) at snapshot time, so a widget can mirror
    /// the app's Solar choice without linking CoreLocation. Optional: older snapshots decode.
    var clockMode: String? = nil
    var solarLat: Double? = nil
    var solarLon: Double? = nil
    /// The resolved daily Nitnem sets (registry facts the DB-less widget cannot get itself):
    /// per set key ("morning"/"evening"/"night"), the ordered banis with their titles and
    /// lengths. Progress (completion, position) is read live from `nitnem-progress.json`.
    /// Optional so an older snapshot still decodes.
    var nitnem: NitnemWidgetData? = nil
    /// The Hukam of the day for today and the days after it (`hukamDayCount` of them), so the
    /// widget moves to the next verse at the reader's midnight without the app being opened.
    /// Optional: an older snapshot decodes, and the widget then shows the single verse above.
    var hukamDays: [HukamDay]? = nil

    /// How many days of Hukam the app writes ahead: two weeks away from the app still turns daily.
    static let hukamDayCount = 14

    /// Where a tap on the Hukam widget goes: the composition that holds the shown verse, landed on it.
    var hukamURL: URL? {
        URL(string: "sggs://shabad/\(hukamCompId)" + (hukamLineId.map { "?line=\($0)" } ?? ""))
    }
}

/// One day's Hukam of the day, precomputed by the app: the unit's opening verse, verbatim,
/// with its citation. The widget never opens the corpus DB, so the app writes these ahead.
struct HukamDay: Codable, Sendable, Equatable {
    /// The reader's local calendar date, "yyyy-MM-dd" (`WidgetSnapshot.dayKey`).
    var date: String
    var gurmukhi: String
    var translit: String
    var ang: Int
    var compId: Int
    var lineId: Int

    /// Where a tap goes: the composition that holds the verse, landed on it.
    var url: URL? { URL(string: "sggs://shabad/\(compId)?line=\(lineId)") }
}

extension WidgetSnapshot {
    /// A calendar date as "yyyy-MM-dd" in `calendar`'s time zone; sorts as dates do.
    static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04ld-%02ld-%02ld", c.year ?? 1970, c.month ?? 1, c.day ?? 1)
    }

    /// The start of the day named by `key` in `calendar` (its local midnight, DST included).
    static func startOfDay(key: String, calendar: Calendar) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    /// The Hukam-of-the-day timeline from `now`: today's verse at once, then each later day's
    /// verse at that day's local midnight. Empty when the snapshot has no verse for today (an
    /// older app wrote it, or the app has not been opened for longer than the days it wrote),
    /// so the widget never shows a later day's verse early or an earlier one as today's.
    func hukamSchedule(from now: Date, calendar: Calendar) -> [(date: Date, day: HukamDay)] {
        guard let days = hukamDays else { return [] }
        let today = Self.dayKey(now, calendar: calendar)
        var out: [(date: Date, day: HukamDay)] = []
        for d in days.sorted(by: { $0.date < $1.date }) where d.date >= today {
            if d.date == today { out.append((date: now, day: d)); continue }
            guard let start = Self.startOfDay(key: d.date, calendar: calendar), start > now else { continue }
            out.append((date: start, day: d))
        }
        guard out.first?.day.date == today else { return [] }
        return out
    }
}

/// The Hukam of the day widget's whole timeline decision, shared so tests drive exactly what the
/// widget runs. With days in the snapshot: one entry per local midnight and a reload after the
/// last (`refresh == nil`, i.e. `.atEnd`). Without (an older snapshot, or one past its last day):
/// the single verse, not called today's, re-read after the next 00:05.
enum HukamTimeline {
    struct Entry: Equatable {
        let date: Date
        /// Today's (or that midnight's) verse; nil means "show the snapshot's single verse".
        let day: HukamDay?
    }

    static func build(snapshot: WidgetSnapshot?, now: Date, calendar: Calendar) -> (entries: [Entry], refresh: Date?) {
        let schedule = snapshot?.hukamSchedule(from: now, calendar: calendar) ?? []
        if !schedule.isEmpty {
            return (schedule.map { Entry(date: $0.date, day: $0.day) }, nil)
        }
        let next = calendar.nextDate(after: now, matching: DateComponents(hour: 0, minute: 5), matchingPolicy: .nextTime)
            ?? now.addingTimeInterval(86_400)
        return ([Entry(date: now, day: nil)], next)
    }
}

/// The Nitnem facts a widget needs from the registry (titles, minutes, line counts). Progress
/// is read separately and live, so the snapshot is rewritten only when the sets/variant/DB change.
struct NitnemWidgetData: Codable, Sendable {
    struct Bani: Codable, Sendable, Identifiable {
        var id: String; var key: String; var titleEn: String; var titleGm: String
        var minutes: Int?; var nLines: Int
    }
    /// Set key ("morning"/"evening"/"night") → ordered banis.
    var sets: [String: [Bani]]
}

extension WidgetSnapshot {
    /// This snapshot with its solar coordinates removed, or nil when it holds none (nothing to write).
    func withoutSolarCoords() -> WidgetSnapshot? {
        guard solarLat != nil || solarLon != nil else { return nil }
        var s = self
        s.solarLat = nil
        s.solarLon = nil
        return s
    }
}

/// The App-Group `UserDefaults` suite shared by the app and its widgets — where the clock
/// mode and the rounded solar coordinates live so both surfaces agree. Falls back to
/// `.standard` when the group is unavailable (unsigned simulator builds), so nothing crashes.
enum SharedDefaults {
    static let clockModeKey = "sggs_clock_mode"      // "fixed" | "solar"
    /// What a reader who never chose gets — app picker, snapshot and widgets all read THIS.
    /// Solar is the traditional reckoning; with no location yet it falls back to the fixed
    /// clock (and the app offers a one-tap location card). An explicit choice always wins.
    static let defaultClockMode = "solar"
    static let solarCoordsKey = "sggs_solar_coords"  // "lat,lon" rounded to 2 dp

    /// UserDefaults is documented thread-safe; the type simply predates Sendable.
    nonisolated(unsafe) static let suite: UserDefaults = UserDefaults(suiteName: WidgetStore.appGroup) ?? .standard

    /// One-time migration: copy a value the app stored in `.standard` before the keys moved
    /// to the group. Never overwrites a value already in the suite.
    static func migrateFromStandard() {
        guard suite !== UserDefaults.standard else { return }
        for key in [clockModeKey, solarCoordsKey] where suite.object(forKey: key) == nil {
            if let v = UserDefaults.standard.object(forKey: key) { suite.set(v, forKey: key) }
        }
    }

    static var clockMode: String {
        get { suite.string(forKey: clockModeKey) ?? defaultClockMode }
        set { suite.set(newValue, forKey: clockModeKey) }
    }

    /// Parsed, range-checked stored coordinates.
    static func solarCoords() -> (lat: Double, lon: Double)? {
        guard let s = suite.string(forKey: solarCoordsKey) else { return nil }
        let parts = s.split(separator: ",")
        guard parts.count == 2, let lat = Double(parts[0]), let lon = Double(parts[1]),
              abs(lat) <= 90, abs(lon) <= 180 else { return nil }
        return (lat, lon)
    }

    static func storeSolarCoords(lat: Double, lon: Double) {
        let r = { (x: Double) in (x * 100).rounded() / 100 }   // 2 dp ≈ 1 km — enough for sunrise
        suite.set("\(r(lat)),\(r(lon))", forKey: solarCoordsKey)
    }

    /// "Forget location": removes the coordinates from the App-Group suite, from the
    /// pre-migration `.standard` key (else `migrateFromStandard` would restore it at the next
    /// launch) and from the widget snapshot, which the Raag-now widget falls back to. Solar mode
    /// then shows the fixed clock and offers the location card, exactly as before a first fix.
    static func forgetSolarCoords() {
        suite.removeObject(forKey: solarCoordsKey)
        UserDefaults.standard.removeObject(forKey: solarCoordsKey)
        WidgetStore.clearSolarCoords()
    }
}

enum WidgetStore {
    static let appGroup = "group.org.sggs"
    static let filename = "widget-snapshot.json"

    /// App Group container when entitled; falls back to the caller's own container in
    /// unsigned/simulator builds where the group is unavailable (widget then shows its
    /// placeholder — a designed state, never a crash).
    static func url() -> URL? {
        if let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) {
            return group.appendingPathComponent(filename)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?.appendingPathComponent(filename)
    }

    static func load() -> WidgetSnapshot? {
        guard let url = url(), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    /// Drops the solar coordinates from the stored snapshot; a no-op when it has none.
    static func clearSolarCoords() {
        guard let snapshot = load(), let cleared = snapshot.withoutSolarCoords() else { return }
        save(cleared)
    }

    static func save(_ snapshot: WidgetSnapshot) {
        guard let url = url(), let data = try? JSONEncoder().encode(snapshot) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
