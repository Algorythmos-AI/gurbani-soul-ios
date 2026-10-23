import SwiftUI

/// A voice's tradition (Guru · Bhagat · Bhatt · Gursikh) and century, for the Voices views.
/// The bundled roster (contributors.json) is the source; a voice the roster does not list yet
/// (e.g. a dataset newer than the vendored roster) falls back to its name, so it still draws in
/// the right colour instead of disappearing.
enum VoiceKind: String, CaseIterable, Sendable {
    case guru, bhagat, bhatt, gursikh

    var title: String {
        switch self {
        case .guru: "The Sikh Gurus"
        case .bhagat: "Bhakti & Sufi saints"
        case .bhatt: "Court bards (Bhatts)"
        case .gursikh: "Gursikh companions"
        }
    }

    /// Short legend label.
    var legend: String {
        switch self {
        case .guru: "Gurus"
        case .bhagat: "Bhagats"
        case .bhatt: "Bhatts"
        case .gursikh: "Gursikhs"
        }
    }

    var color: Color { Contributor.kindColor(rawValue) }

    static func of(_ author: String, roster: [String: Contributor]) -> VoiceKind {
        if let k = roster[author].flatMap({ VoiceKind(rawValue: $0.kind) }) { return k }
        if author.hasPrefix("Guru ") { return .guru }
        if author.hasPrefix("Bhagat ") || author.hasPrefix("Sheikh ") { return .bhagat }
        if author.hasPrefix("Bhatt ") || author.hasPrefix("The Bhatts") { return .bhatt }
        return .gursikh
    }

    /// "15th century" from the roster's birth year (or death year); nil when undated.
    static func century(_ author: String, roster: [String: Contributor]) -> Int? {
        guard let c = roster[author], let y = c.born ?? c.died else { return nil }
        return (y - 1) / 100 + 1
    }

    static func centuryTitle(_ c: Int?) -> String {
        guard let c else { return "Dates uncertain" }
        let suffix = (c % 100 >= 11 && c % 100 <= 13) ? "th" : (["th", "st", "nd", "rd"] + Array(repeating: "th", count: 6))[c % 10]
        return "\(c)\(suffix) century"
    }
}
