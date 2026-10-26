import SwiftUI
import GurbaniSearchKit

/// The five-tab shell: Nitnem · Reader · Search · Explore · More.
/// Nitnem (the daily reading) and Reader keep the prime positions; Explore is the hub for the
/// browse/insight surfaces (Index, Themes, Insights, Constellation, Raag Clock, …) so nothing
/// is buried two levels deep.
enum Tab: Hashable { case nitnem, reader, search, explore, more }

/// Typed navigation targets pushed onto a tab's stack (Explore hosts most of them; the
/// Nitnem stack hosts `.bani`).
enum Route: Hashable {
    case index
    case themes
    case lineage
    case insights
    case constellation
    case vaars
    /// One Vaar's weave, by `vaars.vaar_id` (1…22).
    case vaar(Int)
    /// A Vaar read straight through (or its pauris only), optionally from a line.
    case vaarReader(id: Int, paurisOnly: Bool, line: Int?, pauri: Int? = nil)
    case clock
    case nitnemJourney
    case theme(String)
    /// Every verse of a theme, optionally narrowed (a word form, refrains, a voice/raag, Angs).
    case themeVerses(String, ThemeFilter)
    /// The reader's own saved verses that carry a theme (Your themes).
    case yourTheme(String)
    /// One voice's page, by `Contributor.slug` (deep link / App Intent; Lineage pushes its own).
    case voice(String)
    /// A bani from the Nitnem registry, by its stable key (variant is a user setting).
    case bani(String)
    /// The same registry bani read as a standalone composition from Explore → Index. Carries the
    /// variant explicitly (the Index asks for a specific form, e.g. Asa Di Vaar as printed) and
    /// reads in the Explore context, so it never offers the Nitnem band's "next" or "Back to Nitnem".
    case composition(key: String, variant: String)
    /// One raag's page (Explore → Index), by its corpus Gurmukhi name.
    case raag(String)
}

/// Where a bani reader was opened from. Decides only the closing chrome — the scripture, the
/// outline and the saved position are identical either way.
enum BaniReaderContext: Hashable, Sendable { case nitnem, explore }

@MainActor @Observable
final class Router {
    var selectedTab: Tab = .nitnem
    var readerAng: Int = 1
    var explorePath = NavigationPath()
    var nitnemPath = NavigationPath()
    /// The bani-reader seq a contents sheet asked to jump to (BaniReaderScreen consumes + clears).
    var pendingBaniSeq: Int?
    /// A deep-linked search query (sggs://search?q=…); SearchScreen consumes and clears it.
    var pendingSearchQuery: String?
    /// True once ANY explicit Ang navigation happened (deep link, intent, widget, in-app).
    /// The Reader's resume-last-Ang must not fire after this — `readerAng == 1` alone can't
    /// distinguish the untouched default from an explicit `sggs://ang/1`.
    private(set) var navigatedToAngExplicitly = false
    /// The verse the Reader should scroll to (and highlight) once the requested Ang is on screen.
    /// Always overwritten by `openAng` — a stale id must never land a later navigation.
    var pendingReaderLineId: Int?

    func openAng(_ n: Int, lineId: Int? = nil) {
        navigatedToAngExplicitly = true
        pendingReaderLineId = (lineId ?? 0) > 0 ? lineId : nil
        readerAng = max(1, min(GranthAngs.count, n))
        selectedTab = .reader
    }

    /// The Reader's pager settled on a new Ang after a finger swipe. Updates `readerAng` WITHOUT
    /// touching the tab or a pending verse (an in-Reader page turn is not an explicit deep-link
    /// navigation, and must not consume a landing meant for another Ang). Together with `openAng`,
    /// these are the ONLY writers of `readerAng` — the single-writer rule that keeps the pager and
    /// the router from feeding each other in a loop.
    func pagerSettled(on n: Int) {
        let c = max(1, min(GranthAngs.count, n))
        guard c != readerAng else { return }
        navigatedToAngExplicitly = true
        readerAng = c
    }

    /// Restore the last-read Ang on a cold launch. A distinct, documented writer of `readerAng`
    /// (alongside `openAng`/`pagerSettled`) so ReaderScreen never assigns the property directly:
    /// it must not mark navigation explicit (an untouched `sggs://ang/1` deep link still wins) and
    /// is a no-op once any explicit navigation has happened.
    func resumeAng(_ n: Int) {
        guard !navigatedToAngExplicitly else { return }
        readerAng = max(1, min(GranthAngs.count, n))
    }

    /// A raag the Clock should focus when opened via deep link / Reader timing chip.
    var pendingClockRaag: String?

    /// A deep-linked Constellation (sggs://constellation?theme=&with=); ConstellationScreen
    /// consumes and clears it.
    var pendingConstellation: ConstellationLink?

    /// The Constellation lives under Explore: select the tab and put it on top of its stack.
    func openConstellation(_ link: ConstellationLink) {
        pendingConstellation = link
        selectedTab = .explore
        explorePath = NavigationPath([Route.constellation])
    }

    /// The Raag Clock lives under Explore: select the tab and put the clock on top of its stack.
    func openClock(raag: String? = nil) {
        pendingClockRaag = raag
        selectedTab = .explore
        explorePath = NavigationPath([Route.clock])
    }

    /// Open a bani in the Nitnem tab (deep link, intent, "Next bani").
    func openBani(key: String) {
        guard Router.isValidBaniKey(key) else { return }
        selectedTab = .nitnem
        nitnemPath = NavigationPath([Route.bani(key)])
    }

    /// Open a registry bani as a standalone composition inside Explore, pushed on top of the
    /// Index. Never selects the Nitnem tab.
    func openComposition(key: String, variant: String = "") {
        guard Router.isValidBaniKey(key), Router.isValidBaniVariant(variant) else { return }
        selectedTab = .explore
        explorePath = NavigationPath([Route.index, Route.composition(key: key, variant: variant)])
    }

    /// A raag's page, pushed on top of the Index inside Explore. `value` is a deep-link slug
    /// ("gauri", "nat-narayan"), the corpus roman ("gaurhee"), or the Gurmukhi name; anything
    /// that names no raag is ignored (never pushed, never queried).
    func openRaag(_ value: String) {
        guard let name = Router.raagName(value) else { return }
        selectedTab = .explore
        explorePath = NavigationPath([Route.index, Route.raag(name)])
    }

    /// Resolves a raag deep-link value to its corpus Gurmukhi name, without the DB: the 31 names
    /// are fixed (GranthNames), so a cold-launch link resolves before the corpus opens.
    static func raagName(_ value: String) -> String? {
        if GranthNames.raags[value] != nil { return value }
        let known = GranthNames.raags.keys.map { (name: $0, roman: String?.none) }
        if let hit = GranthNames.raagName(forSlug: value, in: known) { return hit }
        return GranthNames.romanToRaag[value.lowercased().replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")]
    }

    /// The Vaars live under Explore. `id` must be a vaar id (1…22, `vaars.vaar_id`); `read` opens
    /// the reader on top of the weave, at `pauri` or `line` when given (each range-checked).
    func openVaar(_ id: Int?, read: Bool = false, pauri: Int? = nil, line: Int? = nil) {
        guard let id else {
            selectedTab = .explore
            explorePath = NavigationPath([Route.vaars])
            return
        }
        guard Router.vaarIds.contains(id) else { return }
        selectedTab = .explore
        var path: [Route] = [.vaars, .vaar(id)]
        let p = pauri.flatMap { (1...36).contains($0) ? $0 : nil }
        if read || p != nil || line != nil {
            path.append(.vaarReader(id: id, paurisOnly: false, line: line, pauri: p))
        }
        explorePath = NavigationPath(path)
    }

    /// The 22 Vaars' ids in `vaars` (pinned by VaarTextTests on the shipped DB).
    nonisolated static let vaarIds = 1...22

    /// Same allowlist as the API: lowercase ascii, digits, underscore, 1–32 chars.
    static func isValidBaniKey(_ key: String) -> Bool {
        !key.isEmpty && key.count <= 32 && key.allSatisfy { ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "_" }
    }

    /// `Contributor.slug` shape: lowercase ascii, digits and single hyphens, 1–64 chars.
    nonisolated static func isValidVoiceSlug(_ s: String) -> Bool {
        !s.isEmpty && s.count <= 64 && !s.hasPrefix("-") && !s.hasSuffix("-") && !s.contains("--")
            && s.allSatisfy { ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "-" }
    }

    /// Mirrors serve.py `_BANI_VARIANTS`. "" means "whichever row is the registry default".
    static let baniVariants = ["", "sgpc", "taksal", "kirtan", "printed"]
    static func isValidBaniVariant(_ v: String) -> Bool { baniVariants.contains(v) }

    /// The sggs:// deep-link table (widgets/App Intents/Spotlight route through here):
    ///   sggs://ang/1430[?line=Y] · sggs://theme/naam[?term=ਸਹਜਿ&rahao=1] · sggs://shabad/123[?line=Y] ·
    ///   sggs://search?q=mercy · sggs://clock (optional /<raag-roman>) · sggs://nitnem ·
    ///   sggs://bani/<key>[?variant=] · sggs://composition/<key>[?variant=] ·
    ///   sggs://raag/<slug> (gauri, nat-narayan, or the corpus roman) ·
    ///   sggs://constellation[?theme=naam&with=haumai | &alone=1] ·
    ///   sggs://hukam (a fresh draw) · sggs://hukam/today (the Hukam of the day) ·
    ///   sggs://vaars · sggs://vaar/<1–22>[/read][?pauri=N | ?line=Y] ·
    ///   sggs://voice/<slug> (a voice's page, e.g. guru-tegh-bahadur-ji)
    /// `line` lands on that verse (scrolled + highlighted). Out-of-range/malformed values are
    /// ignored (never crash on a hostile URL).
    func handle(_ url: URL, container: AppContainer) {
        guard url.scheme == "sggs" else { return }
        let host = url.host ?? ""
        let value = url.pathComponents.dropFirst().first ?? ""     // path only — the query is excluded
        let line: Int? = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "line" })?.value.flatMap(Int.init).flatMap { $0 > 0 ? $0 : nil }
        let variant: String? = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "variant" })?.value
        switch host {
        case "ang":
            if let n = Int(value), GranthAngs.all.contains(n) {
                // A deep link / intent to an Ang must land ON the Reader, not behind a shabad/hukam
                // sheet that happened to be open (the reader would otherwise be hidden until dismissed).
                container.dismissSheetForNavigation()
                openAng(n, lineId: line)
            }
        case "clock":
            openClock(raag: value.isEmpty ? nil : value)
        case "nitnem":
            selectedTab = .nitnem
            nitnemPath = NavigationPath()
        case "bani":
            // A variant is an explicit request for ONE form of a bani (e.g. the Vaar as printed
            // vs its kirtan interleave), which is a composition read, not the day's Nitnem.
            if let v = variant, !v.isEmpty {
                openComposition(key: value, variant: v)
            } else {
                openBani(key: value)
            }
        case "vaars":
            container.dismissSheetForNavigation()
            openVaar(nil)
        case "vaar":
            // sggs://vaar/5 · sggs://vaar/5/read · sggs://vaar/5?pauri=12 · sggs://vaar/5?line=20900
            guard let id = Int(value), Router.vaarIds.contains(id) else { break }
            let pauri = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "pauri" })?.value.flatMap(Int.init)
            container.dismissSheetForNavigation()
            openVaar(id, read: url.pathComponents.dropFirst().dropFirst().first == "read", pauri: pauri, line: line)
        case "composition":
            openComposition(key: value, variant: variant ?? "")
        case "raag":
            // Only a value that names a raag may close an open sheet; anything else changes nothing.
            if Router.raagName(value) != nil {
                container.dismissSheetForNavigation()
                openRaag(value)
            }
        case "themes":
            container.dismissSheetForNavigation()
            selectedTab = .explore
            explorePath = NavigationPath([Route.themes])
        case "theme":
            // sggs://theme/<slug>[?term=<Gurmukhi word>&rahao=1]: the theme page, or its verse list
            // when narrowed. A malformed slug is ignored, never queried.
            // a well-formed name that is not one of the themes (a Siri phrase like "mercy") opens
            // the index rather than a not-found page
            if let slug = ConstellationLink.slug(value),
               container.meta.map({ $0.concepts.contains { $0.concept == slug } }) == false {
                container.dismissSheetForNavigation()
                selectedTab = .explore
                explorePath = NavigationPath([Route.themes])
            } else if let slug = ConstellationLink.slug(value) {
                let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
                let term = items.first(where: { $0.name == "term" })?.value
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .flatMap { $0.isEmpty || $0.count > 40 ? nil : $0 }
                let rahao = items.first(where: { $0.name == "rahao" })?.value == "1"
                container.dismissSheetForNavigation()      // never land behind an open shabad sheet
                selectedTab = .explore
                if term != nil || rahao {
                    let f = ThemeFilter(term: term, lens: ConstellationLens(rahaoOnly: rahao))
                    explorePath = NavigationPath([Route.themes, Route.theme(slug), Route.themeVerses(slug, f)])
                } else {
                    explorePath = NavigationPath([Route.themes, Route.theme(slug)])
                }
            }
        case "shabad":
            if let c = Int(value), (1...Int(Int32.max)).contains(c) {
                container.present(.shabad(compId: c, focusLineId: line))
            }
        case "hukam":
            // sggs://hukam draws afresh; sggs://hukam/today opens the Hukam of the day (the widget's verse)
            container.present(value == "today" ? .hukamOfTheDay : .hukam)
        case "constellation":
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            func q(_ k: String) -> String? { items.first(where: { $0.name == k })?.value.flatMap(ConstellationLink.slug) }
            container.dismissSheetForNavigation()
            openConstellation(ConstellationLink(theme: q("theme") ?? "naam", with: q("with"),
                                                alone: items.first(where: { $0.name == "alone" })?.value == "1"))
        case "voice":
            if Router.isValidVoiceSlug(value) {
                container.dismissSheetForNavigation()
                selectedTab = .explore
                explorePath = NavigationPath([Route.lineage, Route.voice(value)])
            }
        case "search":
            let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "q" })?.value ?? ""
            if !q.isEmpty {
                pendingSearchQuery = q
                selectedTab = .search
            }
        default: break
        }
    }
}

/// A Constellation to land on: the centre theme, and optionally a pair (or its alone verses) to open.
struct ConstellationLink: Hashable {
    let theme: String
    let with: String?
    let alone: Bool

    /// A theme key as the corpus spells them: lowercase ascii and underscores, 1–32 chars (a
    /// hostile or malformed value is ignored, never queried). A known alternative spelling
    /// (`waheguru`) resolves to its theme's key (`vahiguru`).
    static func slug(_ raw: String) -> String? {
        let k = raw.lowercased()
        return !k.isEmpty && k.count <= 32 && k.allSatisfy({ ("a"..."z").contains($0) || $0 == "_" })
            ? ConceptName.canonical(k) : nil
    }
}
