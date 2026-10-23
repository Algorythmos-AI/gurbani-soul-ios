import Foundation
import CoreSpotlight
import GurbaniSearchKit

/// System-search indexing for SAVED verses (a user's own bookmarks — never the full 60k corpus:
/// index size/rebuild cost isn't worth it, and search inside the app is far better), plus the 54
/// themes (names, headwords and counts only — no verse text). Verbatim Gurmukhi + Ang citation;
/// tapping a result deep-links to the composition or the theme page.
enum SpotlightIndex {
    private static let domain = "org.sggs.saved"

    static func identifier(lineId: Int, compId: Int) -> String { "saved-\(lineId)-comp-\(compId)" }

    static func index(lineId: Int, compId: Int, gurmukhi: String, translit: String, ang: Int) {
        CSSearchableIndex.default().indexSearchableItems(
            [item(lineId: lineId, compId: compId, gurmukhi: gurmukhi, translit: translit, ang: ang)])
    }

    static func item(lineId: Int, compId: Int, gurmukhi: String, translit: String, ang: Int) -> CSSearchableItem {
        let attrs = CSSearchableItemAttributeSet(contentType: .text)
        attrs.title = gurmukhi                       // verbatim — never the saroop display form
        attrs.contentDescription = "\(translit)\nSri Guru Granth Sahib Ji · Ang \(ang)"
        attrs.keywords = ["Gurbani", "SGGS", translit]
        return CSSearchableItem(uniqueIdentifier: identifier(lineId: lineId, compId: compId),
                                domainIdentifier: domain, attributeSet: attrs)
    }

    enum LaunchAction { case reconcile([SavedLine]), leaveAlone }

    /// What launch may do to system search. Only a persistent store that was READ successfully may
    /// replace the index (an empty but readable store correctly clears it). A degraded (in-memory)
    /// store or a failed read leaves the index untouched: entries that cannot be rebuilt are never
    /// removed on a guess.
    static func launchAction(degraded: Bool, saved: Result<[SavedLine], Error>) -> LaunchAction {
        guard !degraded, case .success(let rows) = saved else { return .leaveAlone }
        return .reconcile(rows)
    }

    /// Make system search exactly the saved store: every entry is dropped, then every saved verse
    /// re-indexed. Run once per launch with a persistent store, so entries left by a session-only
    /// save, a restore from backup (which brings the store back but not the index) or older builds
    /// are corrected.
    static func reconcile(with saved: [SavedLine]) {
        // plain values cross into the completion handler (the model objects stay on their actor)
        let rows = saved.map { ($0.lineId, $0.compId, $0.gurmukhi, $0.translit, $0.ang) }
        CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [domain]) { _ in
            guard !rows.isEmpty else { return }
            CSSearchableIndex.default().indexSearchableItems(
                rows.map { item(lineId: $0.0, compId: $0.1, gurmukhi: $0.2, translit: $0.3, ang: $0.4) })
        }
    }

    // MARK: themes

    private static let themeDomain = "org.sggs.themes"

    static func themeIdentifier(_ concept: String) -> String { "theme-\(concept)" }

    /// The theme slug of a theme result (nil for any other identifier, or a malformed slug).
    static func themeSlug(fromIdentifier id: String) -> String? {
        guard id.hasPrefix("theme-") else { return nil }
        return ConstellationLink.slug(String(id.dropFirst(6)))
    }

    static func themeItem(_ r: ThemeIndexRow) -> CSSearchableItem {
        let attrs = CSSearchableItemAttributeSet(contentType: .text)
        let name = ConceptName.display(r.concept)
        attrs.title = r.headword.map { "\(name) · \($0)" } ?? name       // the headword verbatim
        attrs.contentDescription = "\(ThemeIndexModel.gloss(r.description))\n\(r.nVerses.formatted()) verses in Sri Guru Granth Sahib Ji"
        attrs.keywords = ["Gurbani", "theme", name, r.concept] + r.terms
        return CSSearchableItem(uniqueIdentifier: themeIdentifier(r.concept), domainIdentifier: themeDomain, attributeSet: attrs)
    }

    /// Make system search's themes exactly the bundled ones (a theme renamed or dropped by a
    /// dataset update does not linger). Cheap: 54 small entries, once per launch.
    static func indexThemes(_ rows: [ThemeIndexRow]) {
        let items = rows.filter { $0.nVerses > 0 }.map(themeItem)
        CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [themeDomain]) { _ in
            guard !items.isEmpty else { return }
            CSSearchableIndex.default().indexSearchableItems(items)
        }
    }

    static func remove(lineId: Int, compId: Int) {
        CSSearchableIndex.default().deleteSearchableItems(
            withIdentifiers: [identifier(lineId: lineId, compId: compId)])
    }

    /// Every saved-verse entry: for when the saved store is recreated empty (the ladder's last
    /// step), or system search would keep offering verses that are no longer saved.
    static func removeAll() {
        CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [domain])
    }

    /// The saved verse's own line id (so the composition opens scrolled to it).
    static func lineId(fromIdentifier id: String) -> Int? {
        guard id.hasPrefix("saved-"), let range = id.range(of: "-comp-") else { return nil }
        return Int(id[id.index(id.startIndex, offsetBy: 6)..<range.lowerBound])
    }

    /// Parse a Spotlight result back to its composition (nil for foreign identifiers).
    static func compId(fromIdentifier id: String) -> Int? {
        guard id.hasPrefix("saved-"), let range = id.range(of: "-comp-") else { return nil }
        return Int(id[range.upperBound...])
    }
}
