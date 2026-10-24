import Foundation

/// Display name for a corpus concept slug (`concepts.concept`, e.g. `dukh_sukh` → "Dukh Sukh").
/// One mapping for every theme surface — Themes, Constellation, Theme Network — so a slug's
/// underscores never leak into the UI (`String.capitalized` keeps them: "Dukh_Sukh").
/// Presentation only: the slug itself stays the key for queries, routes and deep links.
enum ConceptName {
    static func display(_ slug: String) -> String {
        slug.split(separator: "_").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }

    /// The English label a theme is known by, from its `concepts.description` ("Divine
    /// Command/Order — the sovereign will…" → "Divine Command/Order"). The head of the
    /// description up to " — ", ";" or ":", without any Gurmukhi parenthetical (Gurmukhi is never
    /// set inline in an English label); a comma ends a long head. A head still longer than 48
    /// characters, or no description at all, falls back to `display(slug)`.
    static func label(_ slug: String, description: String?) -> String {
        guard var head = description?.components(separatedBy: " — ").first else { return display(slug) }
        for sep in [";", ":"] { head = head.components(separatedBy: sep).first ?? head }
        // "(ਭਵਜਲੁ / ਭਉਜਲੁ" may be cut open by the separator above: drop to the end in that case.
        while let r = head.range(of: #"\s*\([^)]*\p{Script=Gurmukhi}[^)]*(\)|$)"#, options: .regularExpression) {
            head.removeSubrange(r)
        }
        head = head.trimmingCharacters(in: .whitespaces)
        if head.count > 48, let comma = head.firstIndex(of: ",") { head = String(head[..<comma]) }
        return head.isEmpty || head.count > 48 || head.unicodeScalars.contains(where: { (0x0A00...0x0A7F).contains($0.value) })
            ? display(slug) : head
    }
}
