import AppKit

// Generates the app icon from one set of geometry:
//   make-icon.swift icon <dir>     -> <dir>/AppIcon.icon (Icon Composer format, SVG layers)
//   make-icon.swift iconset <dir>  -> <dir>/AppIcon.iconset (flat PNGs for the .icns fallback)
//
// The flower is the Photos flower measured from Apple's icon: eight petals centred on the
// diagonals, 61 units wide, from radius 4 to 100 (on a 256-unit flower canvas). The one change is
// that each petal's round ends are pointed, so a petal is an elongated hexagon.
//
// Where petals overlap, Photos doesn't simply blend them: every pair and triple of neighbours has
// its own colour. Those colours were sampled from the original and are painted as exact polygon
// intersections (petals are convex, so each overlap region is too).

let canvas = 1024.0
let center = CGPoint(x: 512, y: 512)
let unit = 3.0             // flower units -> icon points (tip radius 300 inside the 824 pt tile)

// Petal outline in flower units: u runs outward along the petal's axis, v across it.
let petalShape: [(u: Double, v: Double)] = [
    (4, 0), (34.5, -30.5), (69.5, -30.5), (100, 0), (69.5, 30.5), (34.5, 30.5),
]

// Clockwise from the top.
let petals: [(name: String, rgb: UInt32)] = [
    ("orange", 0xFFB900), ("yellow", 0xF2EB06), ("green", 0xB0E064), ("teal", 0x4DCFA9),
    ("blue", 0x7DBBE6), ("purple", 0xBB9ACF), ("pink", 0xE98DB6), ("salmon", 0xFF938E),
]
// Overlap colours sampled from Photos, keyed by the first petal of each run of neighbours.
let pairColors: [UInt32] = [0xEFB201, 0x9CC802, 0x03AF51, 0x238DA8, 0x736CB4, 0xB44C88, 0xEC2521, 0xFD4E01]   // i & i+1
let tripleColors: [UInt32] = [0xADA301, 0x1FA713, 0x06855F, 0x435F97, 0x7C397A, 0xC01D24, 0xEF2A03, 0xF15801] // i, i+1, i+2

typealias Poly = [CGPoint]

func petal(_ i: Int) -> Poly {
    let a = (-90.0 + Double(i) * 45) * .pi / 180
    return petalShape.map { p in
        CGPoint(x: center.x + unit * (p.u * cos(a) - p.v * sin(a)),
                y: center.y + unit * (p.u * sin(a) + p.v * cos(a)))
    }
}

/// Sutherland–Hodgman: `subject` clipped to the convex polygon `clip`.
func intersect(_ subject: Poly, _ clip: Poly) -> Poly {
    // Signed area tells us which side of each edge is inside.
    var area = 0.0
    for k in clip.indices { let p = clip[k], q = clip[(k + 1) % clip.count]; area += p.x * q.y - q.x * p.y }
    let sign = area > 0 ? 1.0 : -1.0
    func inside(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> Bool {
        sign * ((b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x)) >= 0
    }
    func cross(_ p: CGPoint, _ q: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGPoint {
        let d = (p.x - q.x) * (a.y - b.y) - (p.y - q.y) * (a.x - b.x)
        let t = ((p.x - a.x) * (a.y - b.y) - (p.y - a.y) * (a.x - b.x)) / d
        return CGPoint(x: p.x + t * (q.x - p.x), y: p.y + t * (q.y - p.y))
    }
    var out = subject
    for k in clip.indices {
        let a = clip[k], b = clip[(k + 1) % clip.count]
        let input = out
        out = []
        guard !input.isEmpty else { break }
        for j in input.indices {
            let p = input[j], q = input[(j + 1) % input.count]
            let pin = inside(p, a, b), qin = inside(q, a, b)
            if pin { out.append(p) }
            if pin != qin { out.append(cross(p, q, a, b)) }
        }
    }
    return out
}

/// Every filled shape in paint order: petals, then pair overlaps, then triple overlaps on top.
func shapes() -> [(name: String, poly: Poly, rgb: UInt32)] {
    var s: [(String, Poly, UInt32)] = []
    for i in 0..<8 { s.append(("petal-\(i + 1)-\(petals[i].name)", petal(i), petals[i].rgb)) }
    for i in 0..<8 {
        let p = intersect(petal(i), petal((i + 1) % 8))
        if p.count >= 3 { s.append(("overlap-\(petals[i].name)-\(petals[(i + 1) % 8].name)", p, pairColors[i])) }
    }
    for i in 0..<8 {
        let p = intersect(intersect(petal(i), petal((i + 1) % 8)), petal((i + 2) % 8))
        if p.count >= 3 { s.append(("overlap3-\(petals[(i + 1) % 8].name)", p, tripleColors[i])) }
    }
    return s
}

func hex(_ v: UInt32) -> String { String(format: "#%06X", v) }
func svgPoints(_ p: Poly) -> String { p.map { String(format: "%.2f,%.2f", $0.x, $0.y) }.joined(separator: " ") }

func writeIconComposer(_ dir: String) throws {
    let root = URL(fileURLWithPath: dir).appendingPathComponent("AppIcon.icon")
    let assets = root.appendingPathComponent("Assets")
    try? FileManager.default.removeItem(at: root)
    try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)

    func svg(_ body: String) -> String {
        """
        <svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
        \(body)</svg>

        """
    }
    let all = shapes()
    // One glass layer per petal so the system can light each one, like Photos; the overlap
    // colours sit together in a single layer above them.
    var layers: [[String: Any]] = []
    let overlaps = all.dropFirst(8).map { "  <polygon points=\"\(svgPoints($0.poly))\" fill=\"\(hex($0.rgb))\"/>\n" }.joined()
    try svg(overlaps).write(to: assets.appendingPathComponent("overlaps.svg"), atomically: true, encoding: .utf8)
    layers.append(["name": "overlaps", "image-name": "overlaps.svg", "glass": true,
                   "position": ["scale": 1, "translation-in-points": [0, 0]]])
    // Icon Composer lists layers top-first.
    for s in all.prefix(8).reversed() {
        try svg("  <polygon points=\"\(svgPoints(s.poly))\" fill=\"\(hex(s.rgb))\"/>\n")
            .write(to: assets.appendingPathComponent(s.name + ".svg"), atomically: true, encoding: .utf8)
        layers.append(["name": s.name, "image-name": s.name + ".svg", "glass": true,
                       "position": ["scale": 1, "translation-in-points": [0, 0]]])
    }

    let json: [String: Any] = [
        "fill-specializations": [["value": "system-light"], ["appearance": "dark", "value": "system-dark"]],
        "groups": [[
            "name": "Flower",
            "layers": layers,
            "lighting": "individual",
            "specular": true,
            "shadow": ["kind": "layer-color", "opacity": 0.5],
            "translucency": ["enabled": true, "value": 0.35],
        ]],
        "supported-platforms": ["squares": ["macOS"]],
    ]
    let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: root.appendingPathComponent("icon.json"))
}

/// macOS icon tile: an 824 pt superellipse centred on the 1024 canvas (Apple's icon grid).
func squircle(in r: CGRect) -> CGPath {
    let path = CGMutablePath()
    let n = 5.0
    let a = r.width / 2, b = r.height / 2
    for step in 0...360 {
        let t = Double(step) * .pi / 180
        let c = cos(t), s = sin(t)
        let x = r.midX + a * (c < 0 ? -1 : 1) * pow(abs(c), 2 / n)
        let y = r.midY + b * (s < 0 ? -1 : 1) * pow(abs(s), 2 / n)
        step == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
    }
    path.closeSubpath()
    return path
}

func cgColor(_ v: UInt32) -> CGColor {
    CGColor(srgbRed: Double(v >> 16 & 255) / 255, green: Double(v >> 8 & 255) / 255, blue: Double(v & 255) / 255, alpha: 1)
}

func renderFlat(_ px: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
    let k = Double(px) / canvas
    ctx.scaleBy(x: k, y: k)
    // Flip to SVG coordinates so both outputs share the same geometry.
    ctx.translateBy(x: 0, y: canvas)
    ctx.scaleBy(x: 1, y: -1)

    let tile = squircle(in: CGRect(x: 100, y: 100, width: 824, height: 824))
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: NSColor.black.withAlphaComponent(0.28).cgColor)
    ctx.addPath(tile)
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(tile)
    ctx.clip()
    let bg = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                        colors: [NSColor(white: 1, alpha: 1).cgColor, NSColor(white: 0.95, alpha: 1).cgColor] as CFArray,
                        locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 924), options: [])
    for s in shapes() {
        ctx.beginPath()
        ctx.addLines(between: s.poly)
        ctx.closePath()
        ctx.setFillColor(cgColor(s.rgb))
        ctx.fillPath()
    }
    ctx.restoreGState()
    return rep
}

func writeIconset(_ dir: String) throws {
    let out = URL(fileURLWithPath: dir).appendingPathComponent("AppIcon.iconset")
    try? FileManager.default.removeItem(at: out)
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    for s in [16, 32, 128, 256, 512] {
        for scale in [1, 2] {
            let name = scale == 1 ? "icon_\(s)x\(s).png" : "icon_\(s)x\(s)@2x.png"
            try renderFlat(s * scale).representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent(name))
        }
    }
}

let args = CommandLine.arguments
guard args.count == 3 else { print("usage: make-icon.swift icon|iconset <dir>"); exit(1) }
do {
    switch args[1] {
    case "icon": try writeIconComposer(args[2])
    case "iconset": try writeIconset(args[2])
    default: print("unknown mode \(args[1])"); exit(1)
    }
} catch {
    print("error: \(error)"); exit(1)
}
