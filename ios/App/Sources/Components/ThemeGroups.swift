import SwiftUI

/// The 54 corpus themes in their six theological groups — one list for Themes and the
/// Constellation (web parity: frontend/src/scripts/themegroups.ts). Each group has one colour
/// (ThemeGroupInk, docs/brand/tokens.json themeGroup.*), so a star, chip or legend swatch says
/// which family a theme belongs to. `kaal` (time/death) sits with the Human Condition beside jam;
/// `akal` (the Timeless) stays with the Divine Reality. A slug no group names falls into
/// "More Themes" wherever groups are listed — a theme is NEVER dropped.
struct ThemeGroup: Identifiable, Hashable {
    let key: String
    let title: String
    let caption: String
    let keys: [String]
    var id: String { key }

    var color: Color {
        switch key {
        case "divine": ThemeGroupInk.divine
        case "condition": ThemeGroupInk.condition
        case "vices": ThemeGroupInk.vices
        case "path": ThemeGroupInk.path
        case "virtues": ThemeGroupInk.virtues
        default: ThemeGroupInk.states
        }
    }

    /// A one- or two-word name for the family chip bar (the full title is its VoiceOver label).
    var shortTitle: String {
        switch key {
        case "divine": "Divine"
        case "condition": "Human condition"
        case "vices": "Five vices"
        case "path": "Path"
        case "virtues": "Virtues"
        case "states": "States"
        default: title
        }
    }

    static let all: [ThemeGroup] = [
        ThemeGroup(key: "divine", title: "The Divine Reality", caption: "God, the Names, and the cosmic Word",
                   keys: ["ik_onkar", "vahiguru", "karta", "akal", "hukam", "naam", "shabad", "bani", "jot", "anhad", "patit_pavan"]),
        ThemeGroup(key: "condition", title: "The Human Condition & Illusions", caption: "Ego, mind, attachment, and the wheel of birth–death",
                   keys: ["haumai", "maya", "man", "sansar", "janam_maran", "avagavan", "manmukh", "bharam", "dukh_sukh", "garab", "trishna", "bhavjal", "jam", "kaal"]),
        ThemeGroup(key: "vices", title: "The Five Vices", caption: "The panj chor that rob the soul",
                   keys: ["kaam", "krodh", "lobh", "moh", "ahankar"]),
        ThemeGroup(key: "path", title: "The Path & Praxis", caption: "The Guru, the Sangat, and the daily practice",
                   keys: ["satguru", "gurmukh", "simran", "bhagti", "seva", "sangat", "sant_sadh", "sifat_salah", "darshan", "charan", "marag_panth"]),
        ThemeGroup(key: "virtues", title: "Virtues & Divine Attributes", caption: "The qualities the gurmukh cultivates and the Lord embodies",
                   keys: ["prem_pyar", "daya", "nimrata", "santokh", "bhau", "bhana", "karam_nadar"]),
        ThemeGroup(key: "states", title: "Spiritual States", caption: "The fruits of the path — poise, bliss, liberation",
                   keys: ["anand", "sahaj", "sach", "mukti", "amrit", "maran_jeevan"]),
    ]

    private static let byTheme: [String: ThemeGroup] = {
        var out: [String: ThemeGroup] = [:]
        for g in all { for k in g.keys { out[k] = g } }
        return out
    }()

    /// The group a theme belongs to (nil for a slug no group names).
    static func of(_ concept: String) -> ThemeGroup? { byTheme[concept] }
    /// A theme's group colour; muted ink for a theme no group names.
    static func color(_ concept: String) -> Color { byTheme[concept]?.color ?? Ink.muted }
}
