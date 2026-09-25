#if DEBUG
import AppKit

/// Development only: `REGAIN_SOURCE=amazon REGAIN_SNAPSHOT=/tmp/x.png RegainHub` opens a view,
/// saves a picture of the window after a few seconds, and quits. Meant for sample data.
@MainActor
enum DebugSnapshot {
    static func install() {
        let env = ProcessInfo.processInfo.environment
        if let s = env["REGAIN_SOURCE"].flatMap(Source.init(rawValue:)) { Hub.shared.current = s }
        if let e = env["REGAIN_EXPLORE"] { Hub.shared.explore(URL(fileURLWithPath: e)) }
        guard let out = env["REGAIN_SNAPSHOT"] else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + (Double(env["REGAIN_DELAY"] ?? "") ?? 4)) {
            guard let w = NSApp.windows.first(where: { $0.isVisible && $0.frame.width > 400 }) else { exit(2) }
            w.setFrame(NSRect(x: 40, y: 40, width: 1320, height: 860), display: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                guard let v = w.contentView?.superview ?? w.contentView, let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { exit(3) }
                v.cacheDisplay(in: v.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: out))
                exit(0)
            }
        }
    }
}
#endif
