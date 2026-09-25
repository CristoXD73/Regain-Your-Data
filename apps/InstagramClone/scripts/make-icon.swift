import AppKit

// App icon: Instagram-style warm gradient tile with a white camera outline (own drawing).
//   make-icon.swift icon <dir>     -> <dir>/AppIcon.icon (Icon Composer: the camera is a glass layer)
//   make-icon.swift iconset <dir>  -> <dir>/AppIcon.iconset (flat PNGs for the .icns fallback)

// Instagram's palette: yellow #FEDA75, orange #FA7E1E, red-pink #D62976, purple #962FBF, blue #4F5BD5,
// spread radially from the bottom-left corner so the red-pink fills the middle of the tile.
let stops: [(Double, Double, Double)] = [(0.996, 0.855, 0.459), (0.980, 0.494, 0.118), (0.839, 0.161, 0.463), (0.588, 0.184, 0.749), (0.310, 0.357, 0.835)]
let locations: [CGFloat] = [0, 0.18, 0.48, 0.78, 1]

func cameraSVG() -> String {
    """
    <svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
      <rect x="292" y="292" width="440" height="440" rx="128" fill="none" stroke="#FFFFFF" stroke-width="52"/>
      <circle cx="512" cy="512" r="108" fill="none" stroke="#FFFFFF" stroke-width="52"/>
      <circle cx="636" cy="388" r="30" fill="#FFFFFF"/>
    </svg>

    """
}

func writeIconComposer(_ dir: String) throws {
    let root = URL(fileURLWithPath: dir).appendingPathComponent("AppIcon.icon")
    try? FileManager.default.removeItem(at: root)
    try FileManager.default.createDirectory(at: root.appendingPathComponent("Assets"), withIntermediateDirectories: true)
    try cameraSVG().write(to: root.appendingPathComponent("Assets/camera.svg"), atomically: true, encoding: .utf8)
    // Icon Composer gradients take two colours: orange into the red-pink.
    let colors = [stops[1], stops[2]].map { String(format: "srgb:%.5f,%.5f,%.5f,1.00000", $0.0, $0.1, $0.2) }
    let json: [String: Any] = [
        "fill-specializations": [["value": ["linear-gradient": colors]], ["appearance": "dark", "value": "system-dark"]],
        "groups": [["name": "Camera",
                    "layers": [["name": "camera", "image-name": "camera.svg", "glass": true,
                                "position": ["scale": 1, "translation-in-points": [0, 0]]]],
                    "lighting": "individual", "specular": true,
                    "shadow": ["kind": "neutral", "opacity": 0.5], "translucency": ["enabled": true, "value": 0.2]]],
        "supported-platforms": ["squares": ["macOS"]],
    ]
    try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]).write(to: root.appendingPathComponent("icon.json"))
}

func squircle(_ r: CGRect) -> CGPath {
    let p = CGMutablePath()
    for step in 0...360 {
        let t = Double(step) * .pi / 180, n = 5.0, c = cos(t), s = sin(t)
        let pt = CGPoint(x: r.midX + r.width / 2 * (c < 0 ? -1 : 1) * pow(abs(c), 2 / n),
                         y: r.midY + r.height / 2 * (s < 0 ? -1 : 1) * pow(abs(s), 2 / n))
        step == 0 ? p.move(to: pt) : p.addLine(to: pt)
    }
    p.closeSubpath()
    return p
}

func render(_ px: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
    ctx.scaleBy(x: Double(px) / 1024, y: Double(px) / 1024)
    let tile = squircle(CGRect(x: 100, y: 100, width: 824, height: 824))
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: NSColor.black.withAlphaComponent(0.3).cgColor)
    ctx.addPath(tile); ctx.setFillColor(CGColor(gray: 0, alpha: 1)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState(); ctx.addPath(tile); ctx.clip()
    let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                       colors: stops.map { CGColor(red: $0.0, green: $0.1, blue: $0.2, alpha: 1) } as CFArray,
                       locations: locations)!
    // CoreGraphics puts y = 0 at the bottom, so this centre is the bottom-left corner.
    ctx.drawRadialGradient(g, startCenter: CGPoint(x: 200, y: 110), startRadius: 0,
                           endCenter: CGPoint(x: 200, y: 110), endRadius: 1050, options: [.drawsAfterEndLocation])
    ctx.setStrokeColor(CGColor(gray: 1, alpha: 1)); ctx.setLineWidth(52)
    ctx.addPath(CGPath(roundedRect: CGRect(x: 292, y: 292, width: 440, height: 440), cornerWidth: 128, cornerHeight: 128, transform: nil)); ctx.strokePath()
    ctx.strokeEllipse(in: CGRect(x: 404, y: 404, width: 216, height: 216))
    ctx.setFillColor(CGColor(gray: 1, alpha: 1)); ctx.fillEllipse(in: CGRect(x: 606, y: 606, width: 60, height: 60))
    ctx.restoreGState()
    return rep
}

let args = CommandLine.arguments
guard args.count == 3 else { print("usage: make-icon.swift icon|iconset <dir>"); exit(1) }
if args[1] == "icon" { try writeIconComposer(args[2]) } else {
    let out = URL(fileURLWithPath: args[2]).appendingPathComponent("AppIcon.iconset")
    try? FileManager.default.removeItem(at: out)
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    for s in [16, 32, 128, 256, 512] { for k in [1, 2] {
        try render(s * k).representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent(k == 1 ? "icon_\(s)x\(s).png" : "icon_\(s)x\(s)@2x.png"))
    } }
}
