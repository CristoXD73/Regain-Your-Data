import AppKit

// App icon: WhatsApp-style green tile with a white speech bubble holding a phone (own drawing).
//   make-icon.swift icon <dir>     -> <dir>/AppIcon.icon (the bubble + phone is one glass layer)
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

/// The white glyph: bubble outline with a tail at the lower left, and a phone inside.
func drawGlyph(_ ctx: CGContext) {
    ctx.setStrokeColor(CGColor(gray: 1, alpha: 1)); ctx.setFillColor(CGColor(gray: 1, alpha: 1))
    ctx.setLineWidth(44); ctx.setLineJoin(.round)
    let c = CGPoint(x: 522, y: 522), r = 230.0
    let bubble = CGMutablePath()
    bubble.addArc(center: c, radius: r, startAngle: 1.22 * .pi, endAngle: 1.12 * .pi, clockwise: false)
    bubble.addLine(to: CGPoint(x: 290, y: 290))
    bubble.closeSubpath()
    ctx.addPath(bubble); ctx.strokePath()
    let cfg = NSImage.SymbolConfiguration(pointSize: 200, weight: .bold)
    if let phone = NSImage(systemSymbolName: "phone.fill", accessibilityDescription: nil)?.withSymbolConfiguration(cfg),
       let cg = phone.cgImage(forProposedRect: nil, context: nil, hints: nil) {
        let w = 230.0, h = w * Double(cg.height) / Double(cg.width)
        let rect = CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h)
        ctx.saveGState(); ctx.clip(to: rect, mask: cg); ctx.fill(rect); ctx.restoreGState()
    }
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
        let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [CGColor(red: 0.157, green: 0.820, blue: 0.275, alpha: 1), CGColor(red: 0.373, green: 0.988, blue: 0.482, alpha: 1)] as CFArray, locations: [0, 1])!
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
    try bitmap(1024) { drawGlyph($0) }.representation(using: .png, properties: [:])!.write(to: root.appendingPathComponent("Assets/bubble.png"))
    let json: [String: Any] = [
        "fill-specializations": [["value": ["linear-gradient": ["srgb:0.37300,0.98800,0.48200,1.00000", "srgb:0.15700,0.82000,0.27500,1.00000"]]], ["appearance": "dark", "value": "system-dark"]],
        "groups": [["name": "Bubble", "layers": [["name": "bubble", "image-name": "bubble.png", "glass": true, "position": ["scale": 1, "translation-in-points": [0, 0]]]],
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
