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
                     skyPlace: e.skyPlace, timeZone: e.timeZone)
    }

    /// Solar at home: a place on this clock's own meridian, so no "sky over" line is drawn.
    private func homeConfig(at: Date) -> RaagClockConfig {
        let zone = TimeZone.current
        let standard = Double(zone.secondsFromGMT(for: at)) - zone.daylightSavingTimeOffset(for: at)
        return RaagClockConfig(solar: true, lat: 51.48, lon: max(-180, min(180, standard / 3600 * 15)))
    }

    private func entry1640Half(_ snap: WidgetSnapshot) -> Pahar.HalfDay {
        RaagNowTimeline.entry(at: date(16, 40), config: RaagClockConfig(solar: false), snapshot: snap).model.half
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

    /// Runs `body` with the process's system zone set to `id` (what `TimeZone.current` returns),
    /// then restores it — a phone that changed zone after its timeline was saved.
    private func withSystemTimeZone(_ id: String, _ body: () throws -> Void) rethrows {
        let saved = ProcessInfo.processInfo.environment["TZ"]
        setenv("TZ", id, 1); NSTimeZone.resetSystemTimeZone()
        defer {
            if let saved { setenv("TZ", saved, 1) } else { unsetenv("TZ") }
            NSTimeZone.resetSystemTimeZone()
        }
        try body()
    }

    /// How far apart two renders are: the largest per-channel difference (0–255) and the share
    /// of pixels that differ at all. Two `ImageRenderer` passes of the same view differ by a few
    /// levels of anti-aliasing on device (S-iPhone: ≤ 9 levels on ≤ 2.1% of pixels), so render
    /// identity is "within tolerance", never byte equality.
    private struct PixelDiff: CustomStringConvertible {
        static let maxChannelTolerance = 24
        static let fractionTolerance = 0.05
        let maxChannel: Int
        let fraction: Double
        var withinTolerance: Bool { maxChannel <= Self.maxChannelTolerance && fraction <= Self.fractionTolerance }
        var description: String {
            String(format: "max channel diff %d (≤ %d), differing pixels %.2f%% (≤ %.0f%%)",
                   maxChannel, Self.maxChannelTolerance, fraction * 100, Self.fractionTolerance * 100)
        }
    }

    private func rgba(_ img: UIImage) -> (bytes: [UInt8], width: Int, height: Int)? {
        guard let cg = img.cgImage else { return nil }
        let w = cg.width, h = cg.height
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        let drawn = bytes.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        return drawn ? (bytes, w, h) : nil
    }

    /// nil when either image cannot be decoded or their pixel sizes differ.
    private func pixelDiff(_ a: UIImage, _ b: UIImage) -> PixelDiff? {
        guard let pa = rgba(a), let pb = rgba(b), pa.width == pb.width, pa.height == pb.height else { return nil }
        var maxChannel = 0, differing = 0
        for i in stride(from: 0, to: pa.bytes.count, by: 4) {
            var px = 0
            for c in 0..<4 { px = max(px, abs(Int(pa.bytes[i + c]) - Int(pb.bytes[i + c]))) }
            if px > 0 { differing += 1; maxChannel = max(maxChannel, px) }
        }
        return PixelDiff(maxChannel: maxChannel, fraction: Double(differing) / Double(pa.width * pa.height))
    }

    private func attach(_ images: [(String, UIImage)]) {
        for (name, img) in images {
            let a = XCTAttachment(image: img); a.name = name; a.lifetime = .keepAlways; add(a)
        }
    }

    /// An entry resolved in Kolkata (08:18, AM) drawn on a phone now in Sydney (12:48 PM there):
    /// the hands, the ring's angle and its half of the day all read the entry's clock, never the
    /// phone's new one — and the widget renders the same pixels whichever zone the phone is in.
    func testAnEntryKeepsItsOwnClockWhenThePhoneChangesZone() throws {
        let kolkata = try XCTUnwrap(TimeZone(identifier: "Asia/Kolkata"))
        let sydney = try XCTUnwrap(TimeZone(identifier: "Australia/Sydney"))
        var cal = Calendar(identifier: .gregorian); cal.timeZone = kolkata
        let at = try XCTUnwrap(cal.date(from: DateComponents(year: 2026, month: 9, day: 18, hour: 8, minute: 18)))
        let e = RaagNowTimeline.entry(at: at, config: RaagClockConfig(solar: false), snapshot: snapshot(), tz: kolkata)

        var renders: [String: [UIImage]] = [:]
        for zone in ["Australia/Sydney", "Asia/Kolkata"] {
            try withSystemTimeZone(zone) {
                XCTAssertEqual(TimeZone.current.identifier, zone, "precondition: the phone's zone is \(zone)")
                XCTAssertEqual(e.timeZone, kolkata)
                XCTAssertEqual(e.minutesNow, 8 * 60 + 18)
                XCTAssertEqual(e.model.half, .am, "08:18 in Kolkata is the AM half")
                let hand = ClockHands.angles(for: e.date, tz: e.timeZone, wholeMinutes: true).hour * 180 / .pi
                XCTAssertEqual(hand, Pahar.faceDegrees(e.minutesNow), accuracy: 1e-9, "hour hand on the ring's angle")
                XCTAssertEqual(DialMetrics.angle(Double(e.minutesNow)).degrees + 90, hand, accuracy: 1e-9)
                for (family, size, name) in families where [.systemSmall, .systemMedium, .systemLarge].contains(family) {
                    let img = try XCTUnwrap(render(e, family: family, size: size, dark: false), "\(name) in \(zone)")
                    renders[name, default: []].append(img)
                }
            }
        }
        // the phone's own clock would have put the hand elsewhere (and in the other half)
        let phoneHand = ClockHands.angles(for: e.date, tz: sydney, wholeMinutes: true).hour * 180 / .pi
        XCTAssertEqual(phoneHand, Pahar.faceDegrees(12 * 60 + 48), accuracy: 1e-9)
        XCTAssertEqual(Pahar.HalfDay(minute: PaharFormat.minutesOfDay(e.date, tz: sydney)), .pm)
        // What a zone bug would draw: the same instant on the phone's own clock (12:48 PM, PM half).
        let phoneEntry = RaagNowTimeline.entry(at: at, config: RaagClockConfig(solar: false), snapshot: snapshot(), tz: sydney)
        XCTAssertEqual(phoneEntry.model.half, .pm)
        try withSystemTimeZone("Australia/Sydney") {
            for (family, size, name) in families where [.systemSmall, .systemMedium, .systemLarge].contains(family) {
                let images = try XCTUnwrap(renders[name])
                XCTAssertEqual(images.count, 2)
                let onSydney = images[0], onKolkata = images[1]
                let same = try XCTUnwrap(pixelDiff(onSydney, onKolkata), "\(name): renders differ in size")
                if !same.withinTolerance {
                    attach([("\(name)-entry-on-sydney-phone", onSydney), ("\(name)-entry-on-kolkata-phone", onKolkata)])
                }
                XCTAssertTrue(same.withinTolerance,
                              "\(name): the widget must not depend on the phone's current zone — \(same)")

                // the tolerance is far below a real zone bug: the phone's clock must read as different
                let phone = try XCTUnwrap(render(phoneEntry, family: family, size: size, dark: false), "\(name) phone clock")
                let apart = try XCTUnwrap(pixelDiff(onKolkata, phone), "\(name): renders differ in size")
                if apart.withinTolerance {
                    attach([("\(name)-entry-clock", onKolkata), ("\(name)-phone-clock", phone)])
                }
                XCTAssertFalse(apart.withinTolerance,
                               "\(name): the entry's clock and the phone's clock must render visibly apart — \(apart)")
            }
        }
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
        // the morning half: the ring turns to 12 AM–12 PM with the hour hand (one 12-hour scale)
        let morning = RaagNowTimeline.entry(at: date(8, 18), config: homeConfig(at: date(8, 18)), snapshot: snap)
        XCTAssertEqual(morning.model.half, .am)
        XCTAssertEqual(entry1640Half(snap), .pm)
        for (family, size, name) in families where [.systemLarge, .systemSmall, .accessoryCircular].contains(family) {
            let dark = Self.isAccessory(family)
            let img = try XCTUnwrap(render(morning, family: family, size: size, dark: dark), "\(name) morning failed to render")
            let a = XCTAttachment(image: img)
            a.name = "raagnow-\(name)-morning"; a.lifetime = .keepAlways; add(a)
            if let png = img.pngData() {
                try png.write(to: out.appendingPathComponent("raagnow-\(name)-morning-\(dark ? "dark" : "light").png"))
            }
        }
    }
}
