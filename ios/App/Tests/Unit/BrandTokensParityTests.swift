import XCTest
import SwiftUI
@testable import SGGS

/// The brand book (§11 Governance) makes the platform's docs/brand/tokens.json the source of truth
/// for the palette and asks for a unit test pinning DesignTokens.swift to it. This is that test.
/// The JSON is the platform's own file, vendored at the pinned platform commit (vendor.lock.json)
/// and bundled into this test target only.
///
/// Fail-closed in both directions: every Swift token below must equal its JSON role in all four
/// legs, and every JSON role must be either pinned here or declared as having no Swift token. A
/// value changed on one side, a role renamed or removed upstream, or a role added upstream fails
/// with the role and leg named, instead of drifting silently. Colours are resolved through UIKit's
/// trait machinery, the path the app draws with, so the system-aliased light legs of canvas and
/// card are checked as the OS resolves them.
final class BrandTokensParityTests: XCTestCase {

    // MARK: the mapping

    /// JSON colour role ("group.role") → the Swift token that must equal it.
    private var colourTokens: [String: Color] {
        let soul = AccentPalette.soul
        return [
            "surfaces.canvas": Ink.canvas,
            "surfaces.card": Ink.card,
            "surfaces.paper": Ink.paper,
            "surfaces.paperWarm": Ink.paperWarm,
            "soul.accent": soul.accent,
            "soul.accentFill": soul.accentFill,
            "soul.accentText": soul.accentText,
            "soul.onAccent": soul.onAccent,
            "soul.accentDeep": soul.accentDeep,
            "status.positive": Ink.positive,
            "status.negative": Ink.negative,
            "status.info": Ink.info,
            "status.special": Ink.special,
        ]
    }

    /// JSON colour roles the app has no token for: brand red, maroon and kraft are web and
    /// marketing colours today. Giving one a Swift token means moving it into `colourTokens`.
    private let colourRolesWithoutSwiftToken: Set<String> = [
        "brand.red", "brand.onRed", "brand.maroon", "brand.kraft",
    ]

    /// JSON scalar role → the Swift token (points) that must equal it.
    private let scalarTokens: [String: CGFloat] = [
        "spacing.xs": Theme.Space.xs,
        "spacing.s": Theme.Space.s,
        "spacing.m": Theme.Space.m,
        "spacing.l": Theme.Space.l,
        "spacing.xl": Theme.Space.xl,
        "radius.card": Theme.Radius.card,
        "radius.chip": Theme.Radius.chip,
    ]

    /// JSON scalar roles with no Swift token (buttons use the system shapes).
    private let scalarRolesWithoutSwiftToken: Set<String> = ["radius.button"]

    // MARK: tests

    func testEveryColourTokenMatchesTokensJSONInAllFourLegs() throws {
        let json = colourRoles(try loadTokens())
        let swift = colourTokens
        assertCoverage(json: Set(json.keys), pinned: Set(swift.keys),
                       withoutSwiftToken: colourRolesWithoutSwiftToken, kind: "colour")

        for (role, color) in swift.sorted(by: { $0.key < $1.key }) {
            guard let hexes = json[role] else { continue }          // reported by assertCoverage
            guard hexes.count == legs.count else {
                XCTFail("tokens.json \(role) has \(hexes.count) legs, expected 4 [light, dark, lightHC, darkHC]")
                continue
            }
            for (leg, raw) in zip(legs, hexes) {
                guard let expected = normalisedHex(raw) else {
                    XCTFail("tokens.json \(role) [\(leg.name)] is \"\(raw)\", not #RRGGBB")
                    continue
                }
                let actual = hex(color, leg)
                XCTAssertEqual(actual, expected,
                               "\(role) [\(leg.name)]: DesignTokens.swift resolves to \(actual), tokens.json says \(expected)")
            }
        }
    }

    func testSpacingAndRadiusMatchTokensJSON() throws {
        let json = scalarRoles(try loadTokens())
        assertCoverage(json: Set(json.keys), pinned: Set(scalarTokens.keys),
                       withoutSwiftToken: scalarRolesWithoutSwiftToken, kind: "scalar")

        for (role, value) in scalarTokens.sorted(by: { $0.key < $1.key }) {
            guard let expected = json[role] else { continue }
            XCTAssertEqual(Double(value), expected,
                           "\(role): Swift token is \(value) pt, tokens.json says \(expected)")
        }
    }

    // MARK: tokens.json

    private func loadTokens() throws -> [String: Any] {
        let url = try XCTUnwrap(
            Bundle(for: Self.self).url(forResource: "tokens", withExtension: "json"),
            "tokens.json is not in the SGGSTests bundle: it is docs/brand/tokens.json, vendored from "
                + "the platform (vendor.lock.json) and bundled by ios/App/project.yml")
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        return try XCTUnwrap(object as? [String: Any], "tokens.json is not a JSON object")
    }

    /// Colour roles: every top-level object whose members are all arrays of strings (surfaces,
    /// soul, brand and status today). Detected rather than listed, so a colour group added
    /// upstream is covered, and has to be mapped, without an edit here.
    private func colourRoles(_ json: [String: Any]) -> [String: [String]] {
        roles(json) { $0 as? [String] }
    }

    /// Scalar roles: every top-level object whose members are all numbers (spacing, radius).
    private func scalarRoles(_ json: [String: Any]) -> [String: Double] {
        roles(json) { ($0 as? NSNumber)?.doubleValue }
    }

    private func roles<T>(_ json: [String: Any], _ member: (Any) -> T?) -> [String: T] {
        var out: [String: T] = [:]
        for (group, value) in json {
            guard let members = value as? [String: Any], !members.isEmpty else { continue }
            let typed = members.compactMapValues(member)
            guard typed.count == members.count else { continue }
            for (role, v) in typed { out["\(group).\(role)"] = v }
        }
        return out
    }

    // MARK: coverage

    private func assertCoverage(json: Set<String>, pinned: Set<String>, withoutSwiftToken: Set<String>,
                                kind: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(json.isEmpty, "tokens.json has no \(kind) roles: has its format changed?",
                       file: file, line: line)
        for role in json.subtracting(pinned).subtracting(withoutSwiftToken).sorted() {
            XCTFail("tokens.json \(role) is neither pinned to a Swift token nor declared as having none: "
                        + "map it in BrandTokensParityTests or list it as without a Swift token",
                    file: file, line: line)
        }
        for role in pinned.union(withoutSwiftToken).subtracting(json).sorted() {
            XCTFail("\(role) is named in BrandTokensParityTests but tokens.json has no such \(kind) role "
                        + "(renamed or removed upstream?)",
                    file: file, line: line)
        }
        for role in pinned.intersection(withoutSwiftToken).sorted() {
            XCTFail("\(role) is both pinned and declared as having no Swift token", file: file, line: line)
        }
    }

    // MARK: legs and colour resolution

    /// tokens.json's leg order: [light, dark, lightHC, darkHC].
    private struct Leg {
        let name: String
        let style: UIUserInterfaceStyle
        let contrast: UIAccessibilityContrast
        var traits: UITraitCollection {
            UITraitCollection(traitsFrom: [
                UITraitCollection(userInterfaceStyle: style),
                UITraitCollection(accessibilityContrast: contrast),
            ])
        }
    }

    private let legs: [Leg] = [
        .init(name: "light", style: .light, contrast: .normal),
        .init(name: "dark", style: .dark, contrast: .normal),
        .init(name: "lightHC", style: .light, contrast: .high),
        .init(name: "darkHC", style: .dark, contrast: .high),
    ]

    /// The token as the app draws it in `leg`, as #RRGGBB (sRGB, 8 bits per channel). Anything
    /// that is not an opaque sRGB colour is described instead, so it can never equal a JSON hex.
    private func hex(_ color: Color, _ leg: Leg) -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(color).resolvedColor(with: leg.traits).getRed(&r, green: &g, blue: &b, alpha: &a) else {
            return "a colour with no sRGB representation"
        }
        guard a == 1 else { return "a translucent colour (alpha \(a))" }
        let byte = { (c: CGFloat) in Int((c * 255).rounded()) }
        guard [r, g, b].allSatisfy({ (0...1).contains($0) }) else {
            return "an extended-range colour (\(r), \(g), \(b))"
        }
        return String(format: "#%02X%02X%02X", byte(r), byte(g), byte(b))
    }

    private func normalisedHex(_ raw: String) -> String? {
        raw.range(of: "^#[0-9A-Fa-f]{6}$", options: .regularExpression) == nil ? nil : raw.uppercased()
    }
}
