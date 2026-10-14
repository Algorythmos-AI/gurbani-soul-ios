// Deterministic app-icon generator — icon v2, "Pothi & Naad".
//
// ੴ set in Sant Lipi ExtraBold, whole and upright, above an open pothi drawn in two lines,
// with rings of naad rising from the pothi's spine. The mark is always ONE flat colour; all
// light and depth live in the field (and, on iOS 26+, in the system's Liquid Glass).
//
// Writes two things from the same geometry:
//   1. the flat appearance legs for the asset catalog (iOS 18 and the App Store image)
//        icon-1024.png         default: luminous gold field, warm-ink mark
//        icon-1024-dark.png    dark:    warm-ink field, brand-gold mark
//        icon-1024-tinted.png  tinted:  white mark on black (the system applies the tint)
//   2. the layered Icon Composer document AppIcon.icon (icon.json + SVG layers) for iOS 26+
//
// Brand values MUST match docs/brand/tokens.json (surfaces.paper dark = ink, soul.accentFill = gold).
// Never a gold mark on red, and no red anywhere (docs: brand book §2, §5).
//
// Usage: swift make_app_icon.swift <SantLipi.ttf> <AppIcon.appiconset> <AppIcon.icon>
import AppKit
import CoreText

let args = CommandLine.arguments
guard args.count == 4 else {
    fatalError("usage: swift make_app_icon.swift <SantLipi.ttf> <AppIcon.appiconset> <AppIcon.icon>")
}
let fontURL = URL(fileURLWithPath: args[1])
let setDir = URL(fileURLWithPath: args[2])
let iconDir = URL(fileURLWithPath: args[3])
let assetsDir = iconDir.appendingPathComponent("Assets")
try? FileManager.default.createDirectory(at: setDir, withIntermediateDirectories: true)
try? FileManager.default.createDirectory(at: assetsDir, withIntermediateDirectories: true)

// MARK: Design constants (1024 canvas, origin bottom-left)

let SIZE: CGFloat = 1024
let INK: UInt32 = 0x171412          // tokens: surfaces.paper (dark)
let GOLD: UInt32 = 0xFFBC0D         // tokens: soul.accentFill
let FIELD_TOP: UInt32 = 0xFFCE45    // luminous gold, top-lit
let FIELD_BOTTOM: UInt32 = 0xF09A00 // deepening to amber — warmer than the literal brand gold
let NIGHT_TOP: UInt32 = 0x2B221B    // warm ink, top-lit
let NIGHT_BOTTOM: UInt32 = 0x0E0C0A

let MARK_WEIGHT: CGFloat = 800      // Sant Lipi wght axis; 900 closes the counters at 40 px
let MARK_WIDTH: CGFloat = 0.80      // ink width as a fraction of the canvas
let MARK_LIFT: CGFloat = 0.088      // raised to leave room for the pothi
let MASS_CENTRING: CGFloat = 0.5    // 0 = bounding box, 1 = centre of mass

let SPINE = CGPoint(x: 512, y: 186) // top of the pothi's spine; the rings' centre
let PAGE_SPAN: [CGFloat] = [300, 268]
let PAGE_GAP: CGFloat = 66
let PAGE_LINE: CGFloat = 40
let RING_FIRST: CGFloat = 150
let RING_STEP: CGFloat = 96
let RING_LINE: CGFloat = 20
let RING_ALPHA: CGFloat = 0.38    // on the gold field; the dark and tinted legs scale it down

// MARK: Geometry

let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
func rgb(_ v: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: sRGB, components: [CGFloat((v >> 16) & 0xFF) / 255, CGFloat((v >> 8) & 0xFF) / 255,
                                           CGFloat(v & 0xFF) / 255, a])!
}

/// ੴ (U+0A74) as an outline, straight from the font — the letterform is never redrawn.
func markOutline() -> CGPath {
    guard let base = (CTFontManagerCreateFontDescriptorsFromURL(fontURL as CFURL) as? [CTFontDescriptor])?.first
    else { fatalError("could not read \(fontURL.path)") }
    let wght = 2_003_265_652 // 'wght'
    let desc = CTFontDescriptorCreateCopyWithVariation(base, wght as CFNumber, MARK_WEIGHT)
    let font = CTFontCreateWithFontDescriptor(desc, 1000, nil)
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: "\u{0A74}", attributes: [.font: font]))
    let path = CGMutablePath()
    for run in CTLineGetGlyphRuns(line) as! [CTRun] {
        let runFont = (CTRunGetAttributes(run) as! [NSAttributedString.Key: Any])[.font] as! CTFont
        let name = CTFontCopyPostScriptName(runFont) as String
        precondition(name.hasPrefix("SantLipi"), "ੴ fell back to \(name) — the mark must be Sant Lipi")
        let n = CTRunGetGlyphCount(run)
        var glyphs = [CGGlyph](repeating: 0, count: n), at = [CGPoint](repeating: .zero, count: n)
        CTRunGetGlyphs(run, CFRange(location: 0, length: n), &glyphs)
        CTRunGetPositions(run, CFRange(location: 0, length: n), &at)
        for i in 0..<n {
            var t = CGAffineTransform(translationX: at[i].x, y: at[i].y)
            if let g = CTFontCreatePathForGlyph(runFont, glyphs[i], &t) { path.addPath(g) }
        }
    }
    return path
}

func coverage(_ path: CGPath) -> [UInt8] {
    let n = Int(SIZE)
    var buf = [UInt8](repeating: 0, count: n * n)
    let ctx = CGContext(data: &buf, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n,
                        space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
    ctx.setFillColor(gray: 1, alpha: 1); ctx.addPath(path); ctx.fillPath()
    return buf // row 0 is the top row
}

/// Scale to MARK_WIDTH, centre on the bounding box, then pull halfway toward the centre of mass
/// (the kaar's sweep makes the bounding-box centre sit visibly low-left), then lift.
let mark: CGPath = {
    let raw = markOutline(), box = raw.boundingBoxOfPath
    let k = MARK_WIDTH * SIZE / box.width
    var t = CGAffineTransform(translationX: SIZE / 2, y: SIZE / 2).scaledBy(x: k, y: k)
        .translatedBy(x: -box.midX, y: -box.midY)
    let centred = raw.copy(using: &t)!
    let m = coverage(centred), n = Int(SIZE)
    var sx = 0.0, sy = 0.0, sw = 0.0
    for y in 0..<n { for x in 0..<n { let w = Double(m[y * n + x]); if w > 0 { sx += w * Double(x); sy += w * Double(y); sw += w } } }
    let dx = -(CGFloat(sx / sw) - SIZE / 2) * MASS_CENTRING
    let dyDown = -(CGFloat(sy / sw) - SIZE / 2) * MASS_CENTRING
    var shift = CGAffineTransform(translationX: dx.rounded(), y: (-dyDown + MARK_LIFT * SIZE).rounded())
    return centred.copy(using: &shift)!
}()

/// One side of a page edge: from the spine out to the fore-edge, bulging like an open leaf.
func pageEdge(_ sign: CGFloat, y: CGFloat, span: CGFloat) -> (CGPoint, CGPoint, CGPoint, CGPoint) {
    (CGPoint(x: SPINE.x, y: y), CGPoint(x: SPINE.x + sign * span * 0.30, y: y + 64),
     CGPoint(x: SPINE.x + sign * span * 0.70, y: y + 60), CGPoint(x: SPINE.x + sign * span, y: y + 45))
}

/// The pothi: two page lines, each a single stroke through the spine.
let pothiLines: [CGPath] = (0..<2).map { i in
    let y = SPINE.y - CGFloat(i) * PAGE_GAP, p = CGMutablePath()
    let l = pageEdge(-1, y: y, span: PAGE_SPAN[i]), r = pageEdge(1, y: y, span: PAGE_SPAN[i])
    p.move(to: l.3); p.addCurve(to: l.0, control1: l.2, control2: l.1)
    p.addCurve(to: r.3, control1: r.1, control2: r.2)
    return p
}

/// Everything above the top page edge — the rings are clipped to it so they rise from the pothi.
let horizon: CGPath = {
    let l = pageEdge(-1, y: SPINE.y, span: PAGE_SPAN[0]), r = pageEdge(1, y: SPINE.y, span: PAGE_SPAN[0])
    let p = CGMutablePath()
    p.move(to: CGPoint(x: 0, y: SIZE)); p.addLine(to: CGPoint(x: SIZE, y: SIZE))
    p.addLine(to: CGPoint(x: SIZE, y: r.3.y)); p.addLine(to: r.3)
    p.addCurve(to: r.0, control1: r.2, control2: r.1)
    p.addCurve(to: l.3, control1: l.1, control2: l.2)
    p.addLine(to: CGPoint(x: 0, y: l.3.y)); p.closeSubpath()
    return p
}()

/// (radius, relative strength) — strength fades with distance from the spine.
let rings: [(CGFloat, CGFloat)] = stride(from: RING_FIRST, to: 1200, by: RING_STEP).map {
    ($0, max(0.3, 1 - ($0 - RING_FIRST) / 1300))
}

// MARK: Gates — the mark must stay clear of the icon mask and survive at 58 px

do {
    let m = coverage(mark), n = Int(SIZE)
    var clearance = 1.0, runs: [Int] = []
    for y in 0..<n {
        var run = 0
        for x in 0..<n {
            if m[y * n + x] > 127 {
                run += 1
                let nx = abs(Double(x) + 0.5 - 512) / 512, ny = abs(Double(y) + 0.5 - 512) / 512
                clearance = min(clearance, 1 - pow(pow(nx, 5) + pow(ny, 5), 0.2)) // superellipse, n = 5
            } else if run > 0 { runs.append(run); run = 0 }
        }
    }
    for x in 0..<n { var run = 0; for y in 0..<n { if m[y * n + x] > 127 { run += 1 } else if run > 0 { runs.append(run); run = 0 } } }
    let stroke58 = Double(runs.sorted()[runs.count / 4]) * 58 / 1024
    let lowest = mark.boundingBoxOfPath.minY, pageTop = SPINE.y + 64
    print(String(format: "mark: clearance %.3f of half-width, stroke %.2f px at 58 px, %.0f px above the pothi",
                 clearance, stroke58, lowest - pageTop))
    precondition(clearance >= 0.08, "the kaar is too close to the icon mask")
    precondition(stroke58 >= 2.0, "the stroke is under 2 px at 58 px")
    precondition(lowest - pageTop >= 40, "the mark crowds the pothi")
}

// MARK: Flat legs

struct Leg {
    let name: String
    let top: UInt32, bottom: UInt32
    let ink: UInt32          // mark and pothi
    let ring: UInt32, ringAlpha: CGFloat
    let lift: CGFloat        // soft top light
}

func writeFlat(_ leg: Leg) {
    let n = Int(SIZE)
    let ctx = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    let field = CGGradient(colorsSpace: sRGB, colors: [rgb(leg.top), rgb(leg.bottom)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(field, start: CGPoint(x: 0, y: SIZE), end: .zero, options: [])
    if leg.lift > 0 {
        let glow = CGGradient(colorsSpace: sRGB, colors: [rgb(0xFFFFFF, leg.lift), rgb(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
        let c = CGPoint(x: 512, y: 900)
        ctx.drawRadialGradient(glow, startCenter: c, startRadius: 0, endCenter: c, endRadius: 760, options: [])
    }
    ctx.saveGState(); ctx.addPath(horizon); ctx.clip()
    ctx.setLineWidth(RING_LINE)
    for (r, strength) in rings {
        ctx.setStrokeColor(rgb(leg.ring, leg.ringAlpha * strength))
        ctx.strokeEllipse(in: CGRect(x: SPINE.x - r, y: SPINE.y - r, width: 2 * r, height: 2 * r))
    }
    ctx.restoreGState()
    ctx.setStrokeColor(rgb(leg.ink)); ctx.setLineWidth(PAGE_LINE); ctx.setLineCap(.round); ctx.setLineJoin(.round)
    for line in pothiLines { ctx.addPath(line); ctx.strokePath() }
    ctx.setFillColor(rgb(leg.ink)); ctx.addPath(mark); ctx.fillPath()
    let png = NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
    let url = setDir.appendingPathComponent("\(leg.name).png")
    try! png.write(to: url); print("wrote \(url.path)")
}

writeFlat(Leg(name: "icon-1024", top: FIELD_TOP, bottom: FIELD_BOTTOM, ink: INK, ring: 0xFFFFFF, ringAlpha: RING_ALPHA, lift: 0.18))
writeFlat(Leg(name: "icon-1024-dark", top: NIGHT_TOP, bottom: NIGHT_BOTTOM, ink: GOLD, ring: GOLD, ringAlpha: 0.16, lift: 0.05))
writeFlat(Leg(name: "icon-1024-tinted", top: 0x000000, bottom: 0x000000, ink: 0xFFFFFF, ring: 0xFFFFFF, ringAlpha: 0.14, lift: 0))

// MARK: Layered icon (Icon Composer) — SVG is y-down, so every point is flipped

func f(_ v: CGFloat) -> String { String(format: "%.2f", v) }
func pt(_ p: CGPoint) -> String { "\(f(p.x)) \(f(SIZE - p.y))" }

func svgData(_ path: CGPath) -> String {
    var d: [String] = []
    path.applyWithBlock { e in
        let p = e.pointee.points
        switch e.pointee.type {
        case .moveToPoint: d.append("M\(pt(p[0]))")
        case .addLineToPoint: d.append("L\(pt(p[0]))")
        case .addQuadCurveToPoint: d.append("Q\(pt(p[0])) \(pt(p[1]))")
        case .addCurveToPoint: d.append("C\(pt(p[0])) \(pt(p[1])) \(pt(p[2]))")
        case .closeSubpath: d.append("Z")
        @unknown default: break
        }
    }
    return d.joined(separator: " ")
}

func svg(_ body: String) -> String {
    "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"1024\" height=\"1024\" viewBox=\"0 0 1024 1024\">\n\(body)\n</svg>\n"
}

func writeText(_ text: String, _ url: URL) { try! text.write(to: url, atomically: true, encoding: .utf8); print("wrote \(url.path)") }

writeText(svg("<path fill=\"#000\" d=\"\(svgData(mark))\"/>"), assetsDir.appendingPathComponent("mark.svg"))
// Layers are plain filled outlines — no strokes, clip paths or per-shape opacity. The iOS 26
// renderer fills a clip path as if it were artwork and ignores opacity once a layer has a fill.
let pothiOutline = CGMutablePath()
for line in pothiLines {
    pothiOutline.addPath(line.copy(strokingWithWidth: PAGE_LINE, lineCap: .round, lineJoin: .round, miterLimit: 10))
}
let ringOutline = CGMutablePath()
for (r, _) in rings {
    let ring = CGPath(ellipseIn: CGRect(x: SPINE.x - r, y: SPINE.y - r, width: 2 * r, height: 2 * r), transform: nil)
        .copy(strokingWithWidth: RING_LINE, lineCap: .butt, lineJoin: .miter, miterLimit: 10)
    ringOutline.addPath(ring.intersection(horizon))
}
writeText(svg("<path fill=\"#000\" d=\"\(svgData(pothiOutline.normalized()))\"/>"), assetsDir.appendingPathComponent("pothi.svg"))
writeText(svg("<path fill=\"#fff\" d=\"\(svgData(ringOutline))\"/>"), assetsDir.appendingPathComponent("naad.svg"))

func c(_ v: UInt32, _ a: Double = 1) -> String {
    String(format: "srgb:%.5f,%.5f,%.5f,%.5f", Double((v >> 16) & 0xFF) / 255, Double((v >> 8) & 0xFF) / 255, Double(v & 0xFF) / 255, a)
}
func gradient(_ top: UInt32, _ bottom: UInt32) -> [String: Any] {
    ["linear-gradient": [c(top), c(bottom)], "orientation": ["start": ["x": 0.5, "y": 0], "stop": ["x": 0.5, "y": 1]]]
}
func solid(_ v: UInt32, _ a: Double = 1) -> [String: Any] { ["solid": c(v, a)] }
/// A specialised value: the first entry (no appearance) is the default.
func each(_ base: Any, dark: Any? = nil, tinted: Any? = nil) -> [[String: Any]] {
    var out: [[String: Any]] = [["value": base]]
    if let dark { out.append(["appearance": "dark", "value": dark]) }
    if let tinted { out.append(["appearance": "tinted", "value": tinted]) }
    return out
}
func inkLayer(_ name: String) -> [String: Any] {
    ["image-name": "\(name).svg", "name": name, "glass": true,
     "fill-specializations": each(solid(INK), dark: solid(GOLD), tinted: solid(0xFFFFFF))]
}
let document: [String: Any] = [
    "fill-specializations": each(gradient(FIELD_TOP, FIELD_BOTTOM), dark: gradient(NIGHT_TOP, NIGHT_BOTTOM)),
    "groups": [
        // front: the mark and the pothi — one flat colour. Specular is off: on iOS 26 it turns
        // the strokes into glossy tubes, and the mark is never embossed.
        ["name": "mark", "layers": [inkLayer("mark"), inkLayer("pothi")],
         "shadow": ["kind": "neutral", "opacity": 0.35], "translucency": ["enabled": false, "value": 0.5],
         "specular": false, "lighting": "combined"],
        // back: the rings, a flat tone in the field
        ["name": "naad", "layers": [[
            // One even tone per appearance, carried in the colour's alpha.
            "image-name": "naad.svg", "name": "naad", "glass": false,
            "fill-specializations": each(solid(0xFFFFFF, 0.30), dark: solid(GOLD, 0.14), tinted: solid(0xFFFFFF, 0.14)),
        ]], "shadow": ["kind": "none", "opacity": 0], "translucency": ["enabled": false, "value": 0.5], "specular": false],
    ],
    "supported-platforms": ["squares": "shared"],
]
let json = try! JSONSerialization.data(withJSONObject: document, options: [.prettyPrinted, .sortedKeys])
try! json.write(to: iconDir.appendingPathComponent("icon.json")); print("wrote \(iconDir.path)/icon.json")
