import Foundation

/// Does the saved solar place share this phone's clock? Solar mode draws the sky of the STORED
/// place on the phone's own clock, so after travel (or with an old fix) it can quietly show
/// another place's watches: a Sydney fix on a London phone read "2nd pahar of night" at 1:30 PM.
/// The clock must say so. Pure and on-device: the stored longitude against the zone's offset —
/// no geocoding, nothing sent.
///
/// The rule: the sun keeps 15° of longitude an hour, so a place's solar offset is `lon / 15` h.
/// Compared with the zone's STANDARD offset (daylight saving removed — DST moves clocks, not the
/// sky, so a DST change never flips the answer), wrapped to −12…12 h across the date line. Real
/// zones run up to ~1.6 h from their own longitudes (western Spain, western Argentina), so 2 h
/// is clear of that; western China on Beijing time (~2.2 h) is the known exception, and there
/// "Keep this place" silences the notice.
enum SolarPlace {
    static let awayThresholdHours = 2.0

    /// Hours the saved place's sun runs ahead (+) or behind (−) the zone's standard time.
    static func leadHours(lon: Double, tz: TimeZone, at date: Date) -> Double {
        let standard = (Double(tz.secondsFromGMT(for: date)) - tz.daylightSavingTimeOffset(for: date)) / 3600
        let d = (lon / 15 - standard + 12).truncatingRemainder(dividingBy: 24)
        return (d < 0 ? d + 24 : d) - 12
    }

    /// True when the place is clearly not on this zone's clock.
    static func isAway(lon: Double, tz: TimeZone, at date: Date) -> Bool {
        abs(leadHours(lon: lon, tz: tz, at: date)) >= awayThresholdHours
    }

    /// The place as the reader stored it (2 dp ≈ 1 km): "33.87° S, 151.21° E". `short` is the
    /// widget form, "33.9°S 151.2°E". POSIX digits, so it reads the same as the manual entry.
    static func label(lat: Double, lon: Double, short: Bool = false) -> String {
        let f = short ? "%.1f" : "%.2f"
        let la = String(format: f, abs(lat)) + (short ? "°" : "° ") + (lat < 0 ? "S" : "N")
        let lo = String(format: f, abs(lon)) + (short ? "°" : "° ") + (lon < 0 ? "W" : "E")
        return la + (short ? " " : ", ") + lo
    }

    /// VoiceOver form: "33.87 degrees south, 151.21 degrees east".
    static func spokenLabel(lat: Double, lon: Double) -> String {
        String(format: "%.2f", abs(lat)) + " degrees " + (lat < 0 ? "south" : "north") + ", "
            + String(format: "%.2f", abs(lon)) + " degrees " + (lon < 0 ? "west" : "east")
    }

    /// "about 10 hours ahead of" / "about 3 hours behind" — for the notice's one-line reason.
    static func leadPhrase(_ lead: Double) -> String {
        let h = Int(abs(lead).rounded())
        return "about \(h) hour\(h == 1 ? "" : "s") \(lead > 0 ? "ahead of" : "behind")"
    }
}
