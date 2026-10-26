import XCTest
import SwiftUI
import WidgetKit
import GurbaniPahar
@testable import SGGS

/// Renders the Raag Now widget in EVERY family (fixed + solar; the Home Screen families light +
/// dark) through `ImageRenderer`. A regression gate that each layout composes without trapping,
/// and — when `SGGS_WIDGET_SNAPSHOT_DIR` is set — a PNG per family for visual review (the
/// simulator's widget gallery cannot be scripted). Widget sizes are the iPhone 17 point sizes.
///
/// The Lock Screen families are drawn once, as the Lock Screen draws them: light content on the
/// dark ground, whatever the phone's appearance. A "light" accessory render put black text on
/// that ground and came out blank (fixed, solar and away identical in run 40380564001).
@MainActor
final class WidgetRenderTests: XCTestCase {

    private let families: [(WidgetFamily, CGSize, String)] = [
        (.systemSmall, CGSize(width: 158, height: 158), "small"),
        (.systemMedium, CGSize(width: 338, height: 158), "medium"),
        (.systemLarge, CGSize(width: 338, height: 354), "large"),
        (.accessoryCircular, CGSize(width: 72, height: 72), "circular"),
        (.accessoryRectangular, CGSize(width: 172, height: 76), "rectangular"),
        (.accessoryInline, CGSize(width: 260, height: 24), "inline"),
    ]

    private func snapshot() -> WidgetSnapshot {
        WidgetSnapshot(generatedAt: .now, hukamGurmukhi: "", hukamTranslit: "", hukamAng: 1, hukamCompId: 2,
                       paharRaags: [1: ["aasaa", "bhairo", "raamkalee"], 2: ["gaurhee", "saarang", "bilaaval", "todee", "soohee", "gond"],
                                    3: ["dhanaasaree", "jaijaavantee", "tilang"], 4: ["maajh", "gaurhee", "tilang", "tukhaaree"],
                                    5: ["sorath", "kalyaan", "kedaaraa", "naat", "maalee gaurhaa", "prabhaatee"],
                                    6: ["bihaagarhaa", "jaitsree", "malaar", "maaroo", "kaanrhaa", "basant"], 8: ["sireeraag", "bhairo", "aasaa", "prabhaatee"]],
                       paharRaagsGurmukhi: [4: ["ਮਾਝ", "ਗਉੜੀ", "ਤਿਲੰਗ", "ਤੁਖਾਰੀ"], 1: ["ਆਸਾ", "ਭੈਰਉ", "ਰਾਮਕਲੀ"]])
    }

    private func date(_ h: Int, _ mi: Int) -> Date {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = .current
        return cal.date(from: DateComponents(year: 2026, month: 9, day: 18, hour: h, minute: mi))!
    }

    /// `Text(_, style: .relative)` counts from the REAL clock at render time, while this face is
    /// pinned to 16:40 on 2026-09-18 — rendered days later it read "next watch in 4 days, 18 hrs".
    /// On device an entry is drawn at its own date, so the snapshot shows it as of that moment:
    /// the countdown target keeps the entry's own lead (16:40 → 18:00 = 1 hr, 20 min), re-anchored
    /// to the render clock (+30 s so render time never rounds it down a minute). All else stays pinned.
    private func asRenderedAtItsOwnDate(_ e: RaagNowEntry, now: Date = .now) -> RaagNowEntry {
        RaagNowEntry(date: e.date, pahar: e.pahar, windows: e.windows, sunrise: e.sunrise, sunset: e.sunset,
                     nextPahar: e.nextPahar, boundaryDate: now.addingTimeInterval(e.boundaryDate.timeIntervalSince(e.date) + 30),
                     raags: e.raags, raagsGurmukhi: e.raagsGurmukhi, beads: e.beads, hasSnapshot: e.hasSnapshot, solar: e.solar,
                     skyPlace: e.skyPlace)
    }

    static func isAccessory(_ family: WidgetFamily) -> Bool {
        [.accessoryCircular, .accessoryRectangular, .accessoryInline].contains(family)
    }

    /// Dark flags to draw a family in: the Home Screen families in both appearances, the Lock
    /// Screen families in the Lock Screen's own (light on the dark ground).
    static func schemes(_ family: WidgetFamily) -> [Bool] { isAccessory(family) ? [true] : [false, true] }

    private func render(_ pinned: RaagNowEntry, family: WidgetFamily, size: CGSize, dark: Bool) -> UIImage? {
        let entry = asRenderedAtItsOwnDate(pinned)
        let accessory = Self.isAccessory(family)
        let view = ZStack {
            if accessory { Color.black } else { PaperGround() }
            RaagNowView(entry: entry, familyOverride: family)
                .padding(accessory ? 4 : 14)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: family == .accessoryCircular ? size.width / 2 : 20, style: .continuous))
        .environment(\.colorScheme, dark ? .dark : .light)
        let r = ImageRenderer(content: view)
        r.scale = 3
        return r.uiImage
    }

    func testEveryFamilyRendersInBothSchemesAndModes() throws {
        // PNGs land in the env-named dir when given, else in the host's temp dir (printed).
        let out = ProcessInfo.processInfo.environment["SGGS_WIDGET_SNAPSHOT_DIR"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("sggs-widget-snapshots")
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        print("SGGS_WIDGET_SNAPSHOT_DIR=\(out.path)")
        let snap = snapshot()
        // Solar at home: a place on this clock's own meridian (Greenwich's latitude), so the face
        // shows the solar sky and no "sky over" line. A fixed Sydney place was the away state on
        // any clock but Sydney's: on the UTC runner solar and away rendered alike.
        let zone = TimeZone.current, at = date(16, 40)
        let standard = Double(zone.secondsFromGMT(for: at)) - zone.daylightSavingTimeOffset(for: at)
        let home = RaagClockConfig(solar: true, lat: 51.48, lon: max(-180, min(180, standard / 3600 * 15)))
        let configs: [(String, RaagClockConfig)] = [
            ("fixed", RaagClockConfig(solar: false)),
            ("solar", home),
        ]
        for (mode, cfg) in configs {
            let entry = RaagNowTimeline.entry(at: date(16, 40), config: cfg, snapshot: snap)
            XCTAssertNil(entry.skyPlace, "\(mode): the place is this clock's own, so no sky is named")
            if mode == "fixed" {
                // what `.relative` renders: under one 3-hour pahar (1 hr, 20 min), never days
                let rendered = asRenderedAtItsOwnDate(entry).boundaryDate.timeIntervalSinceNow
                XCTAssertGreaterThan(rendered, 0)
                XCTAssertLessThan(rendered, 3 * 3600, "rendered countdown must be under one pahar")
                XCTAssertEqual(rendered, 80 * 60 + 30, accuracy: 5)
            }
            for (family, size, name) in families {
                for dark in Self.schemes(family) {
                    let img = try XCTUnwrap(render(entry, family: family, size: size, dark: dark),
                                            "\(name) \(mode) \(dark ? "dark" : "light") failed to render")
                    XCTAssertGreaterThan(img.size.width, 0)
                    if let png = img.pngData() {
                        try png.write(to: out.appendingPathComponent("raagnow-\(name)-\(mode)-\(dark ? "dark" : "light").png"))
                    }
                }
            }
        }
        // A saved place far from this phone's zone (Sydney on a London clock): every family names
        // the sky it shows. Attached to the result bundle for review.
        let away = RaagNowTimeline.entry(at: date(16, 40), config: RaagClockConfig(solar: true, lat: -33.87, lon: 151.21),
                                         snapshot: snap, tz: TimeZone(identifier: "Europe/London")!)
        XCTAssertEqual(away.skyPlace, "33.9°S 151.2°E")
        for (family, size, name) in families {
            let dark = Self.isAccessory(family)          // the Lock Screen's own appearance
            let img = try XCTUnwrap(render(away, family: family, size: size, dark: dark),
                                    "\(name) away failed to render")
            let a = XCTAttachment(image: img)
            a.name = "raagnow-\(name)-away"; a.lifetime = .keepAlways; add(a)
            if let png = img.pngData() {
                try png.write(to: out.appendingPathComponent("raagnow-\(name)-away-\(dark ? "dark" : "light").png"))
            }
        }
        // the silent watch and the no-snapshot state must also compose
        let silent = RaagNowTimeline.entry(at: date(1, 0), config: RaagClockConfig(solar: false), snapshot: snap)
        XCTAssertNotNil(render(silent, family: .systemMedium, size: CGSize(width: 338, height: 158), dark: true))
        let empty = RaagNowTimeline.entry(at: date(1, 0), config: RaagClockConfig(solar: false), snapshot: nil)
        XCTAssertNotNil(render(empty, family: .systemSmall, size: CGSize(width: 158, height: 158), dark: false))
        if let png = render(silent, family: .systemMedium, size: CGSize(width: 338, height: 158), dark: true)?.pngData() {
            try png.write(to: out.appendingPathComponent("raagnow-medium-silent-dark.png"))
        }
    }
}
