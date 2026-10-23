import AppIntents
import Foundation
import UIKit

/// Siri / Shortcuts / Spotlight entry points. Every intent routes through the app's sggs://
/// deep-link table (Router.handle) — one navigation surface, no parallel code paths.

/// A fresh draw: a new Hukam unit each time (the in-app Hukam button).
struct DrawHukamIntent: AppIntent {
    static let title: LocalizedStringResource = "Draw a Hukam"
    static let description = IntentDescription("Draw a complete Hukam unit and read it verbatim.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        // OpenURLIntent is iOS 18+; on the 17.0 target we open in-process (openAppWhenRun
        // guarantees the app is foregrounded before perform runs)
        await UIApplication.shared.open(URL(string: "sggs://hukam")!)
        return .result()
    }
}

/// The Hukam of the day: the same unit all day, and the same verse the widget shows.
struct TodaysHukamIntent: AppIntent {
    static let title: LocalizedStringResource = "Today's Hukam"
    static let description = IntentDescription("Open the Hukam of the day: one Hukam unit for the whole day, the same as the widget's, read verbatim.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        await UIApplication.shared.open(URL(string: "sggs://hukam/today")!)
        return .result()
    }
}

struct WhatRaagNowIntent: AppIntent {
    static let title: LocalizedStringResource = "What raag is it now"
    static let description = IntentDescription("Open the Raag Clock at the current watch.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        await UIApplication.shared.open(URL(string: "sggs://clock")!)
        return .result()
    }
}

struct OpenBaniIntent: AppIntent {
    static let title: LocalizedStringResource = "Read a bani"
    static let description = IntentDescription("Open a Nitnem bani (Japji Sahib, Rehras Sahib, Sukhmani Sahib, …) in the reader.")
    static let openAppWhenRun = true

    @Parameter(title: "Bani", default: .japji) var bani: BaniChoice

    @MainActor
    func perform() async throws -> some IntentResult {
        await UIApplication.shared.open(URL(string: "sggs://bani/\(bani.rawValue)")!)
        return .result()
    }
}

/// The banis a voice request can name (keys match the registry; the app resolves variants).
enum BaniChoice: String, AppEnum {
    case japji, jaap, savaiye, chaupai, anand, rehras, sohila, sukhmani, asa_di_vaar, ardaas
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Bani")
    static let caseDisplayRepresentations: [BaniChoice: DisplayRepresentation] = [
        .japji: "Japji Sahib", .jaap: "Jaap Sahib", .savaiye: "Tav-Prasad Savaiye",
        .chaupai: "Chaupai Sahib", .anand: "Anand Sahib", .rehras: "Rehras Sahib",
        .sohila: "Kirtan Sohila", .sukhmani: "Sukhmani Sahib", .asa_di_vaar: "Asa Di Vaar",
        .ardaas: "Ardaas",
    ]
}

struct OpenVaarIntent: AppIntent {
    static let title: LocalizedStringResource = "Read a Vaar"
    static let description = IntentDescription("Open one of the 22 Vaars of Sri Guru Granth Sahib Ji, woven by voice, or read it straight through.")
    static let openAppWhenRun = true

    @Parameter(title: "Vaar", default: .asa) var vaar: VaarChoice
    @Parameter(title: "Start reading", default: false) var read: Bool

    @MainActor
    func perform() async throws -> some IntentResult {
        await UIApplication.shared.open(URL(string: "sggs://vaar/\(vaar.rawValue)\(read ? "/read" : "")")!)
        return .result()
    }
}

/// The 22 Vaars by `vaars.vaar_id` (Granth order). Names follow the Vaar's raag and pauri voice;
/// pinned to the shipped DB by VaarLinkTests.
enum VaarChoice: Int, AppEnum, CaseIterable {
    case sriRaag = 1, majh, gauriM4, gauriM5, asa, gujariM3, gujariM5, bihagara, vadhans, sorath, jaitsari,
         suhi, bilaval, ramkaliM3, ramkaliM5, ramkaliSattaBalwand, maruM3, maruM5, basant, sarang, malar, kanara
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Vaar")
    static let caseDisplayRepresentations: [VaarChoice: DisplayRepresentation] = [
        .sriRaag: "Sri Raag Ki Vaar (M4)", .majh: "Majh Ki Vaar (M1)", .gauriM4: "Gauri Ki Vaar (M4)",
        .gauriM5: "Gauri Ki Vaar (M5)", .asa: "Asa Ki Vaar (M1)", .gujariM3: "Gujari Ki Vaar (M3)",
        .gujariM5: "Gujari Ki Vaar (M5)", .bihagara: "Bihagara Ki Vaar (M4)", .vadhans: "Vadhans Ki Vaar (M4)",
        .sorath: "Sorath Ki Vaar (M4)", .jaitsari: "Jaitsari Ki Vaar (M5)", .suhi: "Suhi Ki Vaar (M3)",
        .bilaval: "Bilaval Ki Vaar (M4)", .ramkaliM3: "Ramkali Ki Vaar (M3)", .ramkaliM5: "Ramkali Ki Vaar (M5)",
        .ramkaliSattaBalwand: "Ramkali Ki Vaar (Satta & Balwand)", .maruM3: "Maru Ki Vaar (M3)",
        .maruM5: "Maru Ki Vaar (M5)", .basant: "Basant Ki Vaar (M5)", .sarang: "Sarang Ki Vaar (M4)",
        .malar: "Malar Ki Vaar (M1)", .kanara: "Kanara Ki Vaar (M4)",
    ]
}

struct SearchGurbaniIntent: AppIntent {
    static let title: LocalizedStringResource = "Search Gurbani"
    static let description = IntentDescription("Search the Granth by word, sound, first letters or theme.")
    static let openAppWhenRun = true

    @Parameter(title: "Query") var query: String

    @MainActor
    func perform() async throws -> some IntentResult {
        var comps = URLComponents(string: "sggs://search")!
        comps.queryItems = [URLQueryItem(name: "q", value: query)]
        await UIApplication.shared.open(comps.url!)
        return .result()
    }
}

struct OpenAngIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Ang"
    static let description = IntentDescription("Open the Reader at a specific Ang (1–1430).")
    static let openAppWhenRun = true

    @Parameter(title: "Ang", inclusiveRange: (1, 1430)) var ang: Int

    @MainActor
    func perform() async throws -> some IntentResult {
        await UIApplication.shared.open(URL(string: "sggs://ang/\(ang)")!)
        return .result()
    }
}

struct OpenConstellationIntent: AppIntent {
    static let title: LocalizedStringResource = "Show the constellation"
    static let description = IntentDescription("See which themes a theme's verses also carry, matched by each theme's Gurmukhi words.")
    static let openAppWhenRun = true

    @Parameter(title: "Theme", description: "A theme such as Naam, Haumai or Seva.") var theme: String?

    @MainActor
    func perform() async throws -> some IntentResult {
        var comps = URLComponents(string: "sggs://constellation")!
        let key = (theme ?? "naam").trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " ", with: "_")
        comps.queryItems = [URLQueryItem(name: "theme", value: ConstellationLink.slug(key) ?? "naam")]
        await UIApplication.shared.open(comps.url!)
        return .result()
    }
}

struct SGGSShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: TodaysHukamIntent(),
                    phrases: ["Today's Hukam in \(.applicationName)",
                              "Hukam of the day in \(.applicationName)"],
                    shortTitle: "Today's Hukam", systemImageName: "sun.horizon")
        AppShortcut(intent: DrawHukamIntent(),
                    phrases: ["Draw a Hukam in \(.applicationName)"],
                    shortTitle: "Draw a Hukam", systemImageName: "sparkles")
        AppShortcut(intent: WhatRaagNowIntent(),
                    phrases: ["What raag is it now in \(.applicationName)",
                              "Show the raag clock in \(.applicationName)"],
                    shortTitle: "Raag now", systemImageName: "clock")
        AppShortcut(intent: OpenBaniIntent(),
                    phrases: ["Read a bani in \(.applicationName)",
                              "Open Nitnem in \(.applicationName)"],
                    shortTitle: "Read a bani", systemImageName: "sun.horizon")
        AppShortcut(intent: OpenVaarIntent(),
                    phrases: ["Read a Vaar in \(.applicationName)",
                              "Open the Vaars in \(.applicationName)"],
                    shortTitle: "Read a Vaar", systemImageName: "list.number")
        AppShortcut(intent: SearchGurbaniIntent(),
                    phrases: ["Search Gurbani in \(.applicationName)"],
                    shortTitle: "Search Gurbani", systemImageName: "magnifyingglass")
        AppShortcut(intent: OpenConstellationIntent(),
                    phrases: ["Show the constellation in \(.applicationName)",
                              "Explore themes in \(.applicationName)"],
                    shortTitle: "Constellation", systemImageName: "sparkle.magnifyingglass")
    }
}
