import AppKit

// Generates the app icon from one set of shapes:
//   make-icon.swift icon <dir>     -> <dir>/AppIcon.icon (Icon Composer format: one SVG per layer)
//   make-icon.swift iconset <dir>  -> <dir>/AppIcon.iconset (flat PNGs for the .icns fallback)
//
// A white ghost with a bold black outline on Snapchat yellow. In the layered version the ghost
// is a glass layer, so macOS can render the icon in its default, dark, clear and tinted styles.

let yellow = (r: 1.0, g: 0.988, b: 0.0)

/// Path pieces in SVG coordinates (y down), shared by the SVG and CoreGraphics outputs.
enum Seg { case move(CGPoint), line(CGPoint), curve(CGPoint, CGPoint, CGPoint) }
func P(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x, y: y) }

/// A friendly ghost in the Snapchat spirit: domed head, little arms, flared feet, wavy hem.
/// Drawn symmetric around x = 512 from the right half.
let ghost: [Seg] = {
    let right: [Seg] = [
        .curve(P(630, 238), P(706, 322), P(706, 446)),   // crown to right cheek
        .line(P(706, 492)),
        .curve(P(748, 494), P(772, 520), P(744, 544)),   // arm
        .curve(P(730, 555), P(714, 556), P(706, 554)),
        .curve(P(712, 612), P(746, 642), P(786, 652)),   // flare down to the right foot
        .curve(P(772, 686), P(728, 688), P(696, 700)),
        .curve(P(672, 728), P(646, 748), P(608, 734)),   // hem scallop
        .curve(P(574, 752), P(546, 774), P(512, 774)),   // centre of the hem
    ]
    func mirror(_ p: CGPoint) -> CGPoint { P(1024 - p.x, p.y) }
    // Walk the right side, then the same curves mirrored in reverse back to the crown.
    var segs: [Seg] = [.move(P(512, 238))]
    segs += right
    var ends = [P(512, 238)]
    for seg in right { switch seg { case .curve(_, _, let e), .line(let e): ends.append(e); case .move: break } }
    for (i, seg) in right.enumerated().reversed() {
        let start = mirror(ends[i])
        switch seg {
        case .curve(let c1, let c2, _): segs.append(.curve(mirror(c2), mirror(c1), start))
        case .line: segs.append(.line(start))
        case .move: break
        }
    }
    return segs
}()
let ghostStroke = 26.0

func svgPath(_ segs: [Seg]) -> String {
    segs.map { s -> String in
        switch s {
        case .move(let p): return String(format: "M %.1f %.1f", p.x, p.y)
        case .line(let p): return String(format: "L %.1f %.1f", p.x, p.y)
        case .curve(let a, let b, let c): return String(format: "C %.1f %.1f %.1f %.1f %.1f %.1f", a.x, a.y, b.x, b.y, c.x, c.y)
        }
    }.joined(separator: " ") + " Z"
}

func cgPath(_ segs: [Seg]) -> CGPath {
    let p = CGMutablePath()
    for s in segs {
        switch s {
        case .move(let a): p.move(to: a)
        case .line(let a): p.addLine(to: a)
        case .curve(let a, let b, let c): p.addCurve(to: c, control1: a, control2: b)
        }
    }
    p.closeSubpath()
    return p
}

func ghostSVG() -> String {
    """
    <svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
      <path d="\(svgPath(ghost))" fill="#FFFFFF" stroke="#000000" stroke-width="\(ghostStroke)" stroke-linejoin="round"/>
    </svg>

    """
}

func writeIconComposer(_ dir: String) throws {
    let root = URL(fileURLWithPath: dir).appendingPathComponent("AppIcon.icon")
    let assets = root.appendingPathComponent("Assets")
    try? FileManager.default.removeItem(at: root)
    try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
    try ghostSVG().write(to: assets.appendingPathComponent("ghost.svg"), atomically: true, encoding: .utf8)
    let json: [String: Any] = [
        // Snapchat yellow; dark mode uses the system's dark fill with the white ghost on top.
        "fill-specializations": [
            ["value": ["solid": String(format: "srgb:%.5f,%.5f,%.5f,1.00000", yellow.r, yellow.g, yellow.b)]],
            ["appearance": "dark", "value": "system-dark"],
        ],
        "groups": [[
            "name": "Ghost",
            "layers": [["name": "ghost", "image-name": "ghost.svg", "glass": true,
                        "position": ["scale": 1, "translation-in-points": [0, 0]]]],
            "lighting": "individual", "specular": true,
            "shadow": ["kind": "neutral", "opacity": 0.5],
            "translucency": ["enabled": true, "value": 0.2],
        ]],
        "supported-platforms": ["squares": ["macOS"]],
    ]
    let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: root.appendingPathComponent("icon.json"))
}

/// macOS icon tile: an 824 pt superellipse centred on the 1024 canvas (Apple's icon grid).
func squircle(_ r: CGRect) -> CGPath {
    let p = CGMutablePath()
    for step in 0...360 {
        let t = Double(step) * .pi / 180, n = 5.0
        let c = cos(t), s = sin(t)
        let pt = CGPoint(x: r.midX + r.width / 2 * (c < 0 ? -1 : 1) * pow(abs(c), 2 / n),
                         y: r.midY + r.height / 2 * (s < 0 ? -1 : 1) * pow(abs(s), 2 / n))
        step == 0 ? p.move(to: pt) : p.addLine(to: pt)
    }
    p.closeSubpath()
    return p
}

func renderFlat(_ px: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
    ctx.scaleBy(x: Double(px) / 1024, y: Double(px) / 1024)
    // Flip to SVG coordinates so both outputs share the same geometry.
    ctx.translateBy(x: 0, y: 1024)
    ctx.scaleBy(x: 1, y: -1)

    let tile = squircle(CGRect(x: 100, y: 100, width: 824, height: 824))
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: NSColor.black.withAlphaComponent(0.3).cgColor)
    ctx.addPath(tile); ctx.setFillColor(CGColor(red: yellow.r, green: yellow.g, blue: yellow.b, alpha: 1)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState(); ctx.addPath(tile); ctx.clip()
    let path = cgPath(ghost)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 20, color: NSColor.black.withAlphaComponent(0.18).cgColor)
    ctx.addPath(path); ctx.setFillColor(CGColor(gray: 1, alpha: 1)); ctx.fillPath()
    ctx.restoreGState()
    ctx.addPath(path)
    ctx.setStrokeColor(CGColor(gray: 0, alpha: 1)); ctx.setLineWidth(ghostStroke); ctx.setLineJoin(.round); ctx.strokePath()
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
