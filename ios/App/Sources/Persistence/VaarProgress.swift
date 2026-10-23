import Foundation
import Observation

/// Where the reader is in each Vaar, and when each was last finished. A small JSON file beside
/// the Nitnem progress (`vaar-progress.json`), with the same rules: never SwiftData, a newer-schema
/// file is read but never written back, an undecodable one is moved aside — never deleted.
///
/// Positions are verbatim corpus line ids, so they survive any rebuild that keeps the corpus; a
/// saved line that no longer belongs to its Vaar is simply ignored on resume.
struct VaarPosition: Codable, Equatable, Sendable {
    var lineId: Int
    var pauriNo: Int?
    var nPauris: Int
    var lastReadAt: Date
    var completedAt: Date?
}

struct VaarProgressFile: Codable, Equatable, Sendable {
    var schemaVersion: Int = 1
    /// Keyed by `vaars.vaar_id` as a string (JSON object keys).
    var vaars: [String: VaarPosition] = [:]
}

@MainActor @Observable
final class VaarProgressStore {
    static let filename = "vaar-progress.json"
    static let schemaVersion = 1

    private(set) var file: VaarProgressFile
    private(set) var isReadOnly: Bool
    let url: URL?

    init(url: URL? = VaarProgressStore.defaultURL()) {
        self.url = url
        let (f, ro) = Self.load(from: url)
        file = f
        isReadOnly = ro
    }

    // MARK: reads

    func position(for vaarId: Int) -> VaarPosition? { file.vaars[String(vaarId)] }

    /// The most recently read Vaar that is not finished since that read — the home's Continue card.
    func current() -> (vaarId: Int, position: VaarPosition)? {
        file.vaars.compactMap { k, p -> (Int, VaarPosition)? in
            guard let id = Int(k), p.completedAt.map({ $0 < p.lastReadAt }) ?? true else { return nil }
            return (id, p)
        }
        .max { $0.1.lastReadAt < $1.1.lastReadAt }
        .map { (vaarId: $0.0, position: $0.1) }
    }

    /// The fraction of pauris reached (0…1); 1 once finished.
    func fraction(for vaarId: Int) -> Double {
        guard let p = position(for: vaarId) else { return 0 }
        if let done = p.completedAt, done >= p.lastReadAt { return 1 }
        guard p.nPauris > 0, let n = p.pauriNo else { return 0 }
        return min(1, max(0, Double(n) / Double(p.nPauris)))
    }

    // MARK: writes

    func setPosition(_ vaarId: Int, lineId: Int, pauriNo: Int?, nPauris: Int, at date: Date = Date()) {
        var p = position(for: vaarId) ?? VaarPosition(lineId: lineId, pauriNo: pauriNo, nPauris: nPauris, lastReadAt: date)
        guard p.lineId != lineId || p.pauriNo != pauriNo || p.nPauris != nPauris else { return }
        p.lineId = lineId; p.pauriNo = pauriNo; p.nPauris = nPauris; p.lastReadAt = date
        file.vaars[String(vaarId)] = p
        save()
    }

    func markComplete(_ vaarId: Int, at date: Date = Date()) {
        guard var p = position(for: vaarId) else { return }
        p.completedAt = date
        p.lastReadAt = min(p.lastReadAt, date)
        file.vaars[String(vaarId)] = p
        save()
    }

    func reset(_ vaarId: Int) {
        guard file.vaars.removeValue(forKey: String(vaarId)) != nil else { return }
        save()
    }

    // MARK: persistence

    static func defaultURL() -> URL? {
        if let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetStore.appGroup) {
            return group.appendingPathComponent(filename)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?.appendingPathComponent(filename)
    }

    /// -> (file, isReadOnly). Mirrors `NitnemProgressStore.load`.
    static func load(from url: URL?) -> (VaarProgressFile, Bool) {
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return (VaarProgressFile(), false) }
        guard let data = try? Data(contentsOf: url) else { return (VaarProgressFile(), true) }
        guard let f = try? JSONDecoder().decode(VaarProgressFile.self, from: data) else {
            if NitnemFiles.version(of: data, key: "schemaVersion") ?? 0 > schemaVersion { return (VaarProgressFile(), true) }
            return (VaarProgressFile(), !NitnemFiles.moveAside(url))
        }
        if f.schemaVersion > schemaVersion { return (f, true) }
        return (f, false)
    }

    func save() {
        guard !isReadOnly, let url, let data = try? JSONEncoder().encode(file) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    /// Debug/UI-test residue wipe (never called in release flows).
    static func wipe() {
        guard let url = defaultURL() else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
