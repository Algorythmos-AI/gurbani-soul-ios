import SwiftUI

/// Feature gates for the Voices surfaces that need a scholar's sign-off before readers see them.
enum VoicesFeatures {
    /// The map shows a place and a date for every voice. It stays off until a scholar (gate G3)
    /// has signed every `region_point` and date in contributors.json. Reviewers can turn it on
    /// for a build with the launch argument `-sggs_voices_map YES`.
    static var mapEnabled: Bool { UserDefaults.standard.bool(forKey: "sggs_voices_map") }
}

/// One voice as the map needs it, read straight from the bundled roster's `place` field
/// (contributors.json v2, sggs-platform). Independent of `Contributor`, so the roster decoder can
/// evolve without touching the map. A v1 roster has no `place`: the map then has nothing to show.
struct MapVoice: Identifiable, Equatable, Sendable {
    let name: String
    let kind: String
    let year: Int?
    let era: String
    let label: String
    let lat: Double
    let lon: Double
    var id: String { name }

    private struct File: Decodable { let contributors: [Entry] }
    private struct Entry: Decodable {
        let name: String
        let kind: String
        let born: Int?
        let died: Int?
        let era: String?
        let place: Place?
        struct Place: Decodable { let label: String?; let lat: Double; let lon: Double }

        private enum CodingKeys: String, CodingKey { case name, kind, born, died, era, place }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = try c.decode(String.self, forKey: .name)
            kind = try c.decode(String.self, forKey: .kind)
            born = try? c.decodeIfPresent(Int.self, forKey: .born)
            died = try? c.decodeIfPresent(Int.self, forKey: .died)
            era = try? c.decodeIfPresent(String.self, forKey: .era)
            // one malformed place must cost only that pin, never the whole map
            place = try? c.decodeIfPresent(Place.self, forKey: .place)
        }
    }

    /// Voices with a place, from roster JSON; [] for a roster without places or unreadable data.
    static func decode(_ data: Data) -> [MapVoice] {
        guard let file = try? JSONDecoder().decode(File.self, from: data) else { return [] }
        return file.contributors.compactMap { e in
            guard let p = e.place, p.lat.isFinite, p.lon.isFinite else { return nil }
            return MapVoice(name: e.name, kind: e.kind, year: e.born ?? e.died, era: e.era ?? "",
                            label: p.label ?? "", lat: p.lat, lon: p.lon)
        }
    }

    static func loadBundled(_ bundle: Bundle = .main) -> [MapVoice] {
        guard let url = bundle.url(forResource: "contributors", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return [] }
        return decode(data)
    }
}

/// "From Multan to Banaras": the voices on a coastline-only map of the subcontinent (no modern
/// borders — they did not exist then), appearing as a century scrubber moves from 1170 to 1680.
/// Every point is the roster's cited, approximate `place`; voices whose dates are uncertain are
/// listed beneath rather than placed in time.
struct VoicesMap: View {
    let voices: [MapVoice]
    @Binding var selected: String?
    @State private var year: Double = 1680

    static let years: ClosedRange<Double> = 1170...1680

    private var dated: [MapVoice] { voices.filter { $0.year != nil } }
    private var undated: [MapVoice] { voices.filter { $0.year == nil } }
    private var shownCount: Int { dated.filter { Double($0.year!) <= year }.count }

    /// Equirectangular, x scaled by cos(21.5°) — the latitude at the map's centre.
    static func project(lon: Double, lat: Double, in size: CGSize) -> CGPoint {
        let lonSpan = SouthAsiaLand.lonRange.upperBound - SouthAsiaLand.lonRange.lowerBound
        let latSpan = SouthAsiaLand.latRange.upperBound - SouthAsiaLand.latRange.lowerBound
        let aspect = lonSpan * cos(21.5 * .pi / 180) / latSpan
        let w = min(size.width, size.height * aspect), h = w / aspect
        let ox = (size.width - w) / 2, oy = (size.height - h) / 2
        return CGPoint(x: ox + (lon - SouthAsiaLand.lonRange.lowerBound) / lonSpan * w,
                       y: oy + (SouthAsiaLand.latRange.upperBound - lat) / latSpan * h)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            GeometryReader { geo in
                ZStack {
                    Canvas { ctx, size in
                        for poly in SouthAsiaLand.polygons {
                            var path = Path()
                            for (i, p) in poly.enumerated() {
                                let q = Self.project(lon: p.0, lat: p.1, in: size)
                                if i == 0 { path.move(to: q) } else { path.addLine(to: q) }
                            }
                            path.closeSubpath()
                            ctx.fill(path, with: .color(Ink.raised))
                            ctx.stroke(path, with: .color(Color.secondary.opacity(0.35)), lineWidth: 0.6)
                        }
                    }
                    ForEach(voices) { v in
                        let p = Self.project(lon: v.lon, lat: v.lat, in: geo.size)
                        let shown = v.year.map { Double($0) <= year } ?? true
                        let color = Contributor.kindColor(v.kind)
                        Button {
                            MotionGate.run(Motion.gentle) { selected = selected == v.name ? nil : v.name }
                        } label: {
                            Circle().fill(color)
                                .frame(width: selected == v.name ? 14 : 9, height: selected == v.name ? 14 : 9)
                                .overlay(Circle().strokeBorder(Ink.base, lineWidth: 1.5))
                                .frame(width: 30, height: 30)          // touch target
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .position(p)
                        .opacity(shown ? (selected == nil || selected == v.name ? 1 : 0.35) : 0)
                        .allowsHitTesting(shown)
                        .accessibilityHidden(!shown)
                        .accessibilityLabel("\(AuthorName(v.name).spoken), \(v.label), approximate")
                        .appAnimation(Motion.gentle, value: shown)
                    }
                }
            }
            .aspectRatio(1.05, contentMode: .fit)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Map of the subcontinent with the voices of the Granth")

            HStack {
                Text(String(Int(Self.years.lowerBound))).font(.caption2).monospacedDigit()
                Slider(value: $year, in: Self.years, step: 10)
                    .accessibilityLabel("Year")
                    .accessibilityValue("\(Int(year)), \(shownCount) voices")
                    .accessibilityIdentifier("voicesMapYear")
                Text(String(Int(Self.years.upperBound))).font(.caption2).monospacedDigit()
            }
            .foregroundStyle(.secondary)
            Text("By \(String(Int(year))): \(shownCount) of \(dated.count) dated voices")
                .font(.footnote.weight(.semibold))
                .sensoryFeedback(.selection, trigger: Int(year) / 100)   // once per century
            if let s = selected, let v = voices.first(where: { $0.name == s }) {
                Text([AuthorName(v.name).english, v.label, v.era].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !undated.isEmpty {
                Text("Dates uncertain: " + undated.map { AuthorName($0.name).english }.joined(separator: ", "))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("Places are approximate and cited in the roster; years are birth (or death) years, often traditional. Voices without a known place are not mapped. Coastline: Natural Earth.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }
}
