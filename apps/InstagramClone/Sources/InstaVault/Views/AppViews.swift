import SwiftUI

enum IG {
    static let background = Color.black
    /// Panels float over the gradient: dark enough to read, clear enough to let the colour through.
    static let panel = Color.black.opacity(0.72)
    /// The brand gradient behind the app: warm orange at the top left, hot pink through the
    /// middle, purple at the bottom right.
    static let backdrop = LinearGradient(stops: [
        .init(color: Color(red: 0.98, green: 0.63, blue: 0.22), location: 0),
        .init(color: Color(red: 0.96, green: 0.33, blue: 0.33), location: 0.28),
        .init(color: Color(red: 0.90, green: 0.18, blue: 0.53), location: 0.55),
        .init(color: Color(red: 0.62, green: 0.20, blue: 0.80), location: 0.85),
        .init(color: Color(red: 0.45, green: 0.20, blue: 0.86), location: 1),
    ], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let surface = Color(white: 0.07)
    static let separator = Color(white: 0.15)
    static let secondary = Color(white: 0.66)
    static let theirs = Color(white: 0.15)                                   // #262626
    static let blue = Color(red: 0.216, green: 0.592, blue: 0.941)          // #3797F0
    static let gradient = LinearGradient(colors: [Color(red: 0.99, green: 0.69, blue: 0.27), Color(red: 0.99, green: 0.11, blue: 0.43),
                                                  Color(red: 0.51, green: 0.23, blue: 0.71)], startPoint: .bottomLeading, endPoint: .topTrailing)
    /// Instagram's notification red (#FF3040), used for badges.
    static let red = Color(red: 1.0, green: 0.188, blue: 0.251)
    /// Static version of my bubble colours (voice notes, previews).
    static let mine = LinearGradient(colors: [mineStops[1], mineStops[3]], startPoint: .top, endPoint: .bottom)

    /// Instagram's chat gradient: my bubbles take their colour from where they sit on screen,
    /// purple at the top through magenta to red-pink at the bottom, so they shift as you scroll.
    static let mineStops: [Color] = [
        Color(red: 0.345, green: 0.318, blue: 0.859),   // #5851DB
        Color(red: 0.514, green: 0.227, blue: 0.706),   // #833AB4
        Color(red: 0.757, green: 0.208, blue: 0.518),   // #C13584
        Color(red: 0.882, green: 0.188, blue: 0.424),   // #E1306C
        Color(red: 0.992, green: 0.114, blue: 0.114),   // #FD1D1D
    ]

    /// Colour at a position from 0 (top of the chat) to 1 (bottom).
    static func mineColor(at t: Double) -> Color {
        let t = min(1, max(0, t)) * Double(mineStops.count - 1)
        let i = min(Int(t), mineStops.count - 2)
        let f = t - Double(i)
        let a = NSColor(mineStops[i]).usingColorSpace(.sRGB)!, b = NSColor(mineStops[i + 1]).usingColorSpace(.sRGB)!
        return Color(red: a.redComponent + (b.redComponent - a.redComponent) * f,
                     green: a.greenComponent + (b.greenComponent - a.greenComponent) * f,
                     blue: a.blueComponent + (b.blueComponent - a.blueComponent) * f)
    }
}

struct InstaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var store = InstaStore.shared

    var body: some Scene {
        WindowGroup("Instagram Clone") {
            RootView()
                .environment(store)
                .frame(minWidth: 900, minHeight: 620)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Export Folder…") { chooseFolder(store) }.keyboardShortcut("o")
            }
            CommandGroup(after: .toolbar) {
                Toggle("Gradient Background", isOn: Binding(get: { store.gradientBackground }, set: { store.gradientBackground = $0 }))
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@MainActor
func chooseFolder(_ store: InstaStore) {
    let p = NSOpenPanel()
    p.canChooseDirectories = true
    p.canChooseFiles = false
    p.message = "Choose the folder that holds your instagram-….zip exports (subfolders are searched too)."
    if p.runModal() == .OK, let u = p.url { store.open(u) }
}

struct RootView: View {
    @Environment(InstaStore.self) private var store
    var body: some View {
        ZStack {
            if store.gradientBackground { IG.backdrop.ignoresSafeArea() } else { IG.background.ignoresSafeArea() }
            switch store.phase {
            case .welcome: WelcomeView()
            case .loading(let m):
                VStack(spacing: 12) {
                    ProgressView().controlSize(.large)
                    Text(m).foregroundStyle(IG.secondary)
                }
            case .ready: DirectView()
            }
            if store.viewer != nil { MediaViewer().transition(.opacity).zIndex(1) }
        }
        .animation(.easeOut(duration: 0.18), value: store.viewer != nil)
    }
}

struct WelcomeView: View {
    @Environment(InstaStore.self) private var store
    @State private var found: [URL] = []
    var body: some View {
        VStack(spacing: 18) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 120, height: 120)
            Text("Instagram Clone").font(.system(size: 30, weight: .bold))
            Text("Your Instagram messages from the export you downloaded, read straight from the zips. Nothing leaves this Mac.")
                .foregroundStyle(IG.secondary).multilineTextAlignment(.center).frame(maxWidth: 420)
            ForEach(found, id: \.self) { u in
                Button { store.open(u) } label: {
                    HStack {
                        Image(systemName: "externaldrive.fill")
                        Text(u.path).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .padding(12).frame(width: 460)
                    .background(IG.surface, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
            Button("Choose Folder…") { chooseFolder(store) }
                .buttonStyle(.borderedProminent).tint(IG.blue).controlSize(.large)
        }
        .padding(40)
        .task { found = await Task.detached { InstagramScanner.suggestedRoots() }.value }
    }
}

/// A circle with initials on a colour picked from the name, ringed like an Instagram story.
struct Avatar: View {
    let name: String
    var size: CGFloat = 44
    var ring = false
    var body: some View {
        let initials = String(name.split(separator: " ").prefix(2).compactMap(\.first)).uppercased()
        Text(initials.isEmpty ? "?" : initials)
            .font(.system(size: size * 0.36, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Self.color(name), in: Circle())
            .padding(ring ? 3 : 0)
            .overlay { if ring { Circle().strokeBorder(IG.gradient, lineWidth: 2.5) } }
    }
    static func color(_ s: String) -> LinearGradient {
        let hues: [Double] = [0.0, 0.07, 0.55, 0.62, 0.75, 0.83, 0.92, 0.4]
        let h = hues[Int(stableHash(s).utf8.reduce(0) { $0 &+ Int($1) }) % hues.count]
        return LinearGradient(colors: [Color(hue: h, saturation: 0.55, brightness: 0.75), Color(hue: h + 0.05, saturation: 0.65, brightness: 0.55)],
                              startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}
