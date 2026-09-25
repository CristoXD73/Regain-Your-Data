import AppKit

// App icon: an Amazon-style parcel: kraft-brown tile, blue tape and a smile arrow (own drawing).
//   make-icon.swift icon <dir>     -> <dir>/AppIcon.icon (tape + smile are one glass layer)
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

/// The glyph: a strip of blue packing tape across the top with a torn lower edge, and the
/// smile arrow in black.
func drawGlyph(_ ctx: CGContext) {
    let tape = CGMutablePath()
    tape.move(to: CGPoint(x: 60, y: 924)); tape.addLine(to: CGPoint(x: 964, y: 924)); tape.addLine(to: CGPoint(x: 964, y: 700))
    var x = 964.0, up = true
    while x > 60 { x -= 34; tape.addLine(to: CGPoint(x: max(60, x), y: up ? 718 : 694)); up.toggle() }
    tape.closeSubpath()
    ctx.saveGState()
    ctx.addPath(tape); ctx.clip()
    let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [CGColor(red: 0.36, green: 0.69, blue: 0.90, alpha: 1), CGColor(red: 0.22, green: 0.55, blue: 0.80, alpha: 1)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(g, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 690), options: [])
    ctx.restoreGState()
    // Smile: a curve from lower left to right with an arrowhead.
    ctx.setStrokeColor(CGColor(gray: 0.08, alpha: 1)); ctx.setFillColor(CGColor(gray: 0.08, alpha: 1))
    ctx.setLineWidth(58); ctx.setLineCap(.round)
    let smile = CGMutablePath()
    smile.move(to: CGPoint(x: 262, y: 470))
    smile.addQuadCurve(to: CGPoint(x: 722, y: 452), control: CGPoint(x: 480, y: 250))
    ctx.addPath(smile); ctx.strokePath()
    let head = CGMutablePath()
    head.move(to: CGPoint(x: 640, y: 482)); head.addLine(to: CGPoint(x: 790, y: 500)); head.addLine(to: CGPoint(x: 760, y: 360))
    head.addQuadCurve(to: CGPoint(x: 640, y: 482), control: CGPoint(x: 740, y: 450))
    head.closeSubpath()
    ctx.setLineJoin(.round); ctx.setLineWidth(16)
    ctx.addPath(head); ctx.drawPath(using: .fillStroke)
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
        let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [CGColor(red: 0.78, green: 0.58, blue: 0.33, alpha: 1), CGColor(red: 0.90, green: 0.73, blue: 0.49, alpha: 1)] as CFArray, locations: [0, 1])!
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
    try bitmap(1024) { drawGlyph($0) }.representation(using: .png, properties: [:])!.write(to: root.appendingPathComponent("Assets/parcel.png"))
    let json: [String: Any] = [
        "fill-specializations": [["value": ["linear-gradient": ["srgb:0.90000,0.73000,0.49000,1.00000", "srgb:0.78000,0.58000,0.33000,1.00000"]]], ["appearance": "dark", "value": "system-dark"]],
        "groups": [["name": "Parcel", "layers": [["name": "parcel", "image-name": "parcel.png", "glass": true, "position": ["scale": 1, "translation-in-points": [0, 0]]]],
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
