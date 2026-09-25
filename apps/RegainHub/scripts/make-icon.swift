import AppKit

// App icon: a multi-tool opened into a fan, one blade in each app's colour, on a graphite tile.
//   make-icon.swift icon <dir>     -> <dir>/AppIcon.icon (the blades are one glass layer)
//   make-icon.swift iconset <dir>  -> <dir>/AppIcon.iconset (flat PNGs)

func squircle(_ r: CGRect) -> CGPath {
    let p = CGMutablePath()
    for step in 0...360 {
        let t = Double(step) * .pi / 180, n = 5.0, c = cos(t), s = sin(t)
        let pt = CGPoint(x: r.midX + r.width / 2 * (c < 0 ? -1 : 1) * pow(abs(c), 2 / n), y: r.midY + r.height / 2 * (s < 0 ? -1 : 1) * pow(abs(s), 2 / n))
        step == 0 ? p.move(to: pt) : p.addLine(to: pt)
    }
    p.closeSubpath()
    return p
}

func rgb(_ hex: UInt32) -> CGColor {
    CGColor(red: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

/// Blades from left to right: Amazon blue, WhatsApp green, Snapchat yellow, Photos orange,
/// Instagram magenta. Each overlaps the one before, with a rivet at the pivot.
func drawGlyph(_ ctx: CGContext) {
    let pivot = CGPoint(x: 512, y: 285)
    let blades: [(Double, UInt32, UInt32)] = [
        (52, 0x5AB0E8, 0x2F7FC0), (26, 0x4CE07C, 0x1FA855), (0, 0xFFF45C, 0xF5CE00), (-26, 0xFFB340, 0xFF5E3A), (-52, 0xF0508F, 0xA93BC8),
    ]
    let w = 124.0, len = 480.0
    for (angle, top, bottom) in blades {
        ctx.saveGState()
        ctx.translateBy(x: pivot.x, y: pivot.y)
        ctx.rotate(by: angle * .pi / 180)
        let rect = CGRect(x: -w / 2, y: -w / 2, width: w, height: len)
        let blade = CGPath(roundedRect: rect, cornerWidth: w / 2, cornerHeight: w / 2, transform: nil)
        ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 18, color: CGColor(gray: 0, alpha: 0.45))
        ctx.addPath(blade); ctx.setFillColor(rgb(bottom)); ctx.fillPath()
        ctx.setShadow(offset: .zero, blur: 0, color: nil)
        ctx.addPath(blade); ctx.clip()
        let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [rgb(bottom), rgb(top)] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: len - w / 2), options: [])
        // A lighter edge down one side, like a bevel.
        ctx.setFillColor(CGColor(gray: 1, alpha: 0.18))
        ctx.fill(CGRect(x: -w / 2, y: -w / 2, width: 16, height: len))
        ctx.restoreGState()
    }
    // Rivet.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -4), blur: 10, color: CGColor(gray: 0, alpha: 0.5))
    ctx.addEllipse(in: CGRect(x: pivot.x - 58, y: pivot.y - 58, width: 116, height: 116))
    ctx.setFillColor(CGColor(gray: 0.86, alpha: 1)); ctx.fillPath()
    ctx.restoreGState()
    ctx.addEllipse(in: CGRect(x: pivot.x - 30, y: pivot.y - 30, width: 60, height: 60))
    ctx.setFillColor(CGColor(gray: 0.62, alpha: 1)); ctx.fillPath()
}

func bitmap(_ px: Int, _ draw: (CGContext) -> Void) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    ctx.scaleBy(x: Double(px) / 1024, y: Double(px) / 1024)
    draw(ctx)
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func flat(_ px: Int) -> NSBitmapImageRep {
    bitmap(px) { ctx in
        let tile = squircle(CGRect(x: 100, y: 100, width: 824, height: 824))
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: NSColor.black.withAlphaComponent(0.3).cgColor)
        ctx.addPath(tile); ctx.setFillColor(CGColor(gray: 0, alpha: 1)); ctx.fillPath()
        ctx.restoreGState()
        ctx.saveGState(); ctx.addPath(tile); ctx.clip()
        let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [rgb(0x15161B), rgb(0x34363F)] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(g, start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 924), options: [])
        drawGlyph(ctx)
        ctx.restoreGState()
    }
}

let args = CommandLine.arguments
guard args.count == 3 else { print("usage: make-icon.swift icon|iconset <dir>"); exit(1) }
if args[1] == "icon" {
    let root = URL(fileURLWithPath: args[2]).appendingPathComponent("AppIcon.icon")
    try? FileManager.default.removeItem(at: root)
    try FileManager.default.createDirectory(at: root.appendingPathComponent("Assets"), withIntermediateDirectories: true)
    try bitmap(1024) { drawGlyph($0) }.representation(using: .png, properties: [:])!.write(to: root.appendingPathComponent("Assets/fan.png"))
    let json: [String: Any] = [
        "fill-specializations": [["value": ["linear-gradient": ["srgb:0.20400,0.21200,0.24700,1.00000", "srgb:0.08200,0.08600,0.10600,1.00000"]]], ["appearance": "dark", "value": "system-dark"]],
        "groups": [["name": "Fan", "layers": [["name": "fan", "image-name": "fan.png", "glass": true, "position": ["scale": 1, "translation-in-points": [0, 0]]]],
                    "lighting": "individual", "specular": true, "shadow": ["kind": "neutral", "opacity": 0.5], "translucency": ["enabled": true, "value": 0.2]]],
        "supported-platforms": ["squares": ["macOS"]],
    ]
    try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]).write(to: root.appendingPathComponent("icon.json"))
} else {
    let out = URL(fileURLWithPath: args[2]).appendingPathComponent("AppIcon.iconset")
    try? FileManager.default.removeItem(at: out)
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    for s in [16, 32, 128, 256, 512] { for k in [1, 2] {
        try flat(s * k).representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent(k == 1 ? "icon_\(s)x\(s).png" : "icon_\(s)x\(s)@2x.png"))
    } }
}
