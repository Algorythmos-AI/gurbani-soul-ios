import Foundation

// The Hukamnama from Sri Harmandir Sahib, Amritsar — the model and store shared by the app, the
// Notification Service Extension and (later) its widget. This file is self-contained on purpose:
// the NSE compiles ONLY this file, so it must not reach for WidgetShared or the corpus package.
//
// Fidelity: SGPC's text is used by the server only to LOCATE the shabad. Every Gurmukhi
// character here was copied by our server from our own pinned corpus; the app re-hashes its own
// lines (`range_sha256`) before it renders the shabad, and never renders mismatched lines.
// This feature is separate from the app's "Hukam of the day" (G3 R6) and is never called that.

/// One Amritsar date's Hukamnama, exactly as the service's read API and the push carry it.
struct HukamnamaEntry: Codable, Sendable, Equatable {
    enum Status: String, Codable, Sendable { case published, pending, held }

    /// The Amritsar (Asia/Kolkata) calendar date, "yyyy-MM-dd" — never the reader's local date.
    var amritsarDate: String
    var status: Status
    var ang: Int?
    var firstLineId: Int?
    var lastLineId: Int?
    var compId: Int?
    /// The opening verse, copied by the server from OUR corpus (verbatim). Display-only here:
    /// the sheet always renders from the app's own DB after the range hash matches.
    var openingGurmukhi: String?
    var openingTranslit: String?
    /// sha256 (lowercase hex) of the range's NFC Gurmukhi lines joined by "\n".
    var rangeSHA256: String?
    /// The corpus fingerprint (`scripture_sha256` in sggs-ios.manifest.json) the server used.
    var scriptureSHA256: String?
    var publishedAt: Date?
    var expectedBy: Date?

    enum CodingKeys: String, CodingKey {
        case amritsarDate = "amritsar_date", status, ang
        case firstLineId = "first_line_id", lastLineId = "last_line_id", compId = "comp_id"
        case openingGurmukhi = "opening_gurmukhi", openingTranslit = "opening_translit"
        case rangeSHA256 = "range_sha256", scriptureSHA256 = "scripture_sha256"
        case publishedAt = "published_at", expectedBy = "expected_by"
    }

    /// The longest range the app will ever read for one Hukamnama (a Vaar day crosses comps;
    /// nothing real comes close). A larger span is refused as malformed, never queried.
    static let maxRangeLines = 400

    /// A published entry that carries everything the sheet needs to locate and prove its lines.
    var isLocatable: Bool {
        guard status == .published, let a = ang, a > 0, let f = firstLineId, let l = lastLineId,
              f > 0, l >= f, l - f < Self.maxRangeLines, let h = rangeSHA256 else { return false }
        return Self.isHex64(h)
    }

    /// `range_sha256` / `scripture_sha256` shape: exactly 64 lowercase hex characters.
    static func isHex64(_ s: String) -> Bool {
        s.utf8.count == 64 && s.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    /// The citation line the server appends to the push body ("Sri Guru Granth Sahib Ji · Ang N").
    static func citation(ang: Int) -> String { "Sri Guru Granth Sahib Ji · Ang \(String(ang))" }

    /// The entry a Hukamnama push carries (custom keys beside `aps`). Nil for any other
    /// notification, or when a field is malformed (a hostile payload is ignored, never stored).
    /// The opening verse comes from `opening_gurmukhi` when present; otherwise it is the alert
    /// body minus its final citation line — and only when that line is exactly our citation for
    /// this Ang (the body is never truncated by the server, so nothing is guessed).
    init?(pushUserInfo info: [AnyHashable: Any]) {
        func int(_ k: String) -> Int? {
            if let n = info[k] as? Int { return n }
            if let n = info[k] as? NSNumber { return n.intValue }
            if let s = info[k] as? String { return Int(s) }
            return nil
        }
        func str(_ k: String) -> String? { info[k] as? String }
        guard let date = str("amritsar_date"), AmritsarDate.isValidKey(date),
              let ang = int("ang"), let first = int("first_line_id"), let last = int("last_line_id"),
              let hash = str("range_sha256"), Self.isHex64(hash) else { return nil }
        var opening = str("opening_gurmukhi")
        if opening == nil, let aps = info["aps"] as? [String: Any],
           let alert = aps["alert"] as? [String: Any], let body = alert["body"] as? String {
            let suffix = "\n" + Self.citation(ang: ang)
            if body.hasSuffix(suffix) {
                let verse = String(body.dropLast(suffix.count))
                opening = verse.isEmpty || verse.contains("\n") ? nil : verse
            }
        }
        self.init(amritsarDate: date, status: .published, ang: ang, firstLineId: first, lastLineId: last,
                  compId: int("comp_id"), openingGurmukhi: opening, openingTranslit: str("opening_translit"),
                  rangeSHA256: hash, scriptureSHA256: str("scripture_sha256").flatMap { Self.isHex64($0) ? $0 : nil },
                  publishedAt: nil, expectedBy: nil)
        guard isLocatable else { return nil }
    }

    init(amritsarDate: String, status: Status, ang: Int? = nil, firstLineId: Int? = nil, lastLineId: Int? = nil,
         compId: Int? = nil, openingGurmukhi: String? = nil, openingTranslit: String? = nil,
         rangeSHA256: String? = nil, scriptureSHA256: String? = nil, publishedAt: Date? = nil, expectedBy: Date? = nil) {
        self.amritsarDate = amritsarDate; self.status = status; self.ang = ang
        self.firstLineId = firstLineId; self.lastLineId = lastLineId; self.compId = compId
        self.openingGurmukhi = openingGurmukhi; self.openingTranslit = openingTranslit
        self.rangeSHA256 = rangeSHA256; self.scriptureSHA256 = scriptureSHA256
        self.publishedAt = publishedAt; self.expectedBy = expectedBy
    }

    /// Where a tap goes: this date's Hukamnama sheet.
    var url: URL? { URL(string: "sggs://hukamnama/\(amritsarDate)") }
}

/// The ONE date function for this feature: the calendar date in Amritsar (Asia/Kolkata, which has
/// no DST). Every label, store key and widget decision uses it — never the reader's local date,
/// and never a naive date.
enum AmritsarDate {
    static let timeZone: TimeZone = TimeZone(identifier: "Asia/Kolkata") ?? TimeZone(secondsFromGMT: 19_800) ?? .gmt

    static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = timeZone
        return c
    }

    /// "yyyy-MM-dd" for the Amritsar date at `now`.
    static func key(_ now: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: now)
        return String(format: "%04ld-%02ld-%02ld", c.year ?? 1970, c.month ?? 1, c.day ?? 1)
    }

    /// Amritsar midnight that starts `key`'s day, or nil when `key` is not a strict, real date.
    static func startOfDay(_ key: String) -> Date? {
        guard key.utf8.count == 10 else { return nil }
        let b = Array(key.utf8)
        guard b[4] == 45, b[7] == 45,   // "-"
              b.enumerated().allSatisfy({ $0.offset == 4 || $0.offset == 7 || (48...57).contains($0.element) })
        else { return nil }
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...12).contains(parts[1]), (1...31).contains(parts[2]),
              let d = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])),
              Self.key(d) == key   // round-trips: 2026-02-30 is rejected, not rolled into March
        else { return nil }
        return d
    }

    static func isValidKey(_ key: String) -> Bool { startOfDay(key) != nil }

    /// "Mon 9 Nov · Amritsar" — the label every surface uses for this feature's date.
    static func label(_ key: String) -> String? {
        guard let d = startOfDay(key) else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.calendar = calendar
        f.timeZone = timeZone
        f.dateFormat = "EEE d MMM"
        return "\(f.string(from: d)) · Amritsar"
    }
}

/// `hukamnama-snapshot.json` in the App Group: the last 7 Amritsar dates' entries. A SEPARATE
/// file from `widget-snapshot.json` (which the app rewrites whole), written by the app, the NSE
/// and the widget. Every writer merges by date — read, merge, atomic write — inside one
/// `NSFileCoordinator` write, so two processes never lose each other's update.
enum HukamnamaStore {
    static let appGroup = "group.org.sggs"
    static let filename = "hukamnama-snapshot.json"
    /// How many Amritsar dates are kept.
    static let keep = 7
    /// The app's corpus fingerprint (manifest `scripture_sha256`), copied into the App Group so
    /// the NSE and the widget can compare an entry's fingerprint without opening the DB.
    static let scriptureKey = "sggs_hukamnama_scripture_sha256"

    struct File: Codable, Sendable { var version = 1; var entries: [HukamnamaEntry] }

    /// UserDefaults is documented thread-safe; the type simply predates Sendable.
    nonisolated(unsafe) static let suite: UserDefaults = UserDefaults(suiteName: appGroup) ?? .standard

    static var localScriptureSHA256: String? {
        get { suite.string(forKey: scriptureKey) }
        set { suite.set(newValue, forKey: scriptureKey) }
    }

    static func defaultURL() -> URL? {
        if let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) {
            return group.appendingPathComponent(filename)
        }
        // unsigned simulator builds have no group: the caller's own container (a designed state)
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?.appendingPathComponent(filename)
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.sortedKeys]; return e
    }()
    static let decoder: JSONDecoder = {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }()

    private static func read(_ url: URL) -> [HukamnamaEntry] {
        guard let data = try? Data(contentsOf: url),
              let file = try? decoder.decode(File.self, from: data) else { return [] }
        return file.entries.filter { AmritsarDate.isValidKey($0.amritsarDate) }
    }

    /// Newest first.
    static func load(url: URL? = defaultURL()) -> [HukamnamaEntry] {
        guard let url else { return [] }
        var out: [HukamnamaEntry] = []
        var err: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: url, options: [], error: &err) { u in
            out = read(u)
        }
        return out.sorted { $0.amritsarDate > $1.amritsarDate }
    }

    static func entry(for date: String, url: URL? = defaultURL()) -> HukamnamaEntry? {
        load(url: url).first { $0.amritsarDate == date }
    }

    /// The newest PUBLISHED entry (what "latest" means to the sheet and the card).
    static func latestPublished(url: URL? = defaultURL()) -> HukamnamaEntry? {
        load(url: url).first { $0.status == .published }
    }

    /// Merge `incoming` into the file under one coordinated write; returns what was written.
    @discardableResult
    static func merge(_ incoming: [HukamnamaEntry], url: URL? = defaultURL()) -> [HukamnamaEntry] {
        guard let url, !incoming.isEmpty else { return [] }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var written: [HukamnamaEntry] = []
        var err: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: .forMerging, error: &err) { u in
            let out = Self.merged(existing: read(u), incoming: incoming)
            if let data = try? encoder.encode(File(entries: out)) {
                try? data.write(to: u, options: .atomic)
                written = out
            }
        }
        return written
    }

    /// The pure merge rule, per Amritsar date:
    /// - a new date is added;
    /// - a published entry is never downgraded by a later `pending`/`held` read of the same date;
    /// - otherwise the incoming entry wins (an approved correction replaces the first), keeping
    ///   the stored opening verse when the incoming one lacks it and proves the same range.
    /// Newest `keep` dates survive; malformed dates are dropped.
    static func merged(existing: [HukamnamaEntry], incoming: [HukamnamaEntry]) -> [HukamnamaEntry] {
        var byDate: [String: HukamnamaEntry] = [:]
        for e in existing where AmritsarDate.isValidKey(e.amritsarDate) { byDate[e.amritsarDate] = e }
        for var e in incoming where AmritsarDate.isValidKey(e.amritsarDate) {
            if let old = byDate[e.amritsarDate] {
                if old.status == .published && e.status != .published { continue }
                if old.rangeSHA256 != nil && old.rangeSHA256 == e.rangeSHA256 {
                    if e.openingGurmukhi == nil { e.openingGurmukhi = old.openingGurmukhi }
                    if e.openingTranslit == nil { e.openingTranslit = old.openingTranslit }
                    if e.compId == nil { e.compId = old.compId }
                    if e.publishedAt == nil { e.publishedAt = old.publishedAt }
                }
            }
            byDate[e.amritsarDate] = e
        }
        return byDate.values.sorted { $0.amritsarDate > $1.amritsarDate }.prefix(keep).map { $0 }
    }
}
