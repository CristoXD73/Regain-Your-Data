import AppKit

// App icon: a tax return with a check mark on a green-teal tile (own drawing).
//   make-icon.swift icon <dir>     -> <dir>/AppIcon.icon (document + badge are one glass layer)
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

/// The glyph: a white document with a folded corner and lines of text, and a round gold badge
/// with a check mark: a return, ready for review.
func drawGlyph(_ ctx: CGContext) {
    let doc = CGMutablePath()
    let l = 300.0, r = 700.0, b = 230.0, t = 800.0, fold = 110.0
    doc.move(to: CGPoint(x: l, y: b)); doc.addLine(to: CGPoint(x: r, y: b)); doc.addLine(to: CGPoint(x: r, y: t - fold))
    doc.addLine(to: CGPoint(x: r - fold, y: t)); doc.addLine(to: CGPoint(x: l, y: t)); doc.closeSubpath()
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 20, color: CGColor(gray: 0, alpha: 0.3))
    ctx.addPath(doc); ctx.setFillColor(CGColor(gray: 1, alpha: 1)); ctx.fillPath()
    ctx.restoreGState()
    // Folded corner.
    let corner = CGMutablePath()
    corner.move(to: CGPoint(x: r - fold, y: t)); corner.addLine(to: CGPoint(x: r - fold, y: t - fold)); corner.addLine(to: CGPoint(x: r, y: t - fold)); corner.closeSubpath()
    ctx.addPath(corner); ctx.setFillColor(CGColor(gray: 0.82, alpha: 1)); ctx.fillPath()
    // Lines of text.
    ctx.setFillColor(CGColor(red: 0.62, green: 0.72, blue: 0.70, alpha: 1))
    for (i, w) in [260.0, 330.0, 300.0, 330.0, 200.0].enumerated() {
        let y = 640.0 - Double(i) * 70
        ctx.addPath(CGPath(roundedRect: CGRect(x: l + 45, y: y, width: w, height: 26), cornerWidth: 13, cornerHeight: 13, transform: nil)); ctx.fillPath()
    }
    // Badge.
    let c = CGPoint(x: 668, y: 300), rad = 118.0
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 14, color: CGColor(gray: 0, alpha: 0.3))
    ctx.addEllipse(in: CGRect(x: c.x - rad, y: c.y - rad, width: rad * 2, height: rad * 2))
    ctx.setFillColor(CGColor(red: 1.0, green: 0.74, blue: 0.20, alpha: 1)); ctx.fillPath()
    ctx.restoreGState()
    ctx.setStrokeColor(CGColor(gray: 1, alpha: 1)); ctx.setLineWidth(34); ctx.setLineCap(.round); ctx.setLineJoin(.round)
    ctx.move(to: CGPoint(x: c.x - 58, y: c.y + 2)); ctx.addLine(to: CGPoint(x: c.x - 14, y: c.y - 44)); ctx.addLine(to: CGPoint(x: c.x + 62, y: c.y + 48))
    ctx.strokePath()
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
        let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [CGColor(red: 0.05, green: 0.36, blue: 0.40, alpha: 1), CGColor(red: 0.16, green: 0.62, blue: 0.46, alpha: 1)] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(g, start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 924), options: [])
        drawGlyph(ctx)
        ctx.restoreGState()
    }
}

let args = CommandLine.arguments
if args[1] == "icon" {
    let root = URL(fileURLWithPath: args[2]).appendingPathComponent("AppIcon.icon")
    try? FileManager.default.removeItem(at: root)
    try FileManager.default.createDirectory(at: root.appendingPathComponent("Assets"), withIntermediateDirectories: true)
    try bitmap(1024) { drawGlyph($0) }.representation(using: .png, properties: [:])!.write(to: root.appendingPathComponent("Assets/return.png"))
    let json: [String: Any] = [
        "fill-specializations": [["value": ["linear-gradient": ["srgb:0.16000,0.62000,0.46000,1.00000", "srgb:0.05000,0.36000,0.40000,1.00000"]]], ["appearance": "dark", "value": "system-dark"]],
        "groups": [["name": "Return", "layers": [["name": "return", "image-name": "return.png", "glass": true, "position": ["scale": 1, "translation-in-points": [0, 0]]]],
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
