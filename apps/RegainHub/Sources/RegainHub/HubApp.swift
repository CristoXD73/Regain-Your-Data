import AmazonKit
import InstagramKit
import PhotosKit
import RegainCore
import SnapchatKit
import SwiftUI
import WhatsAppKit

@main
struct RegainHubApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var hub = Hub.shared

    var body: some Scene {
        WindowGroup("Regain Your Data") {
            HubRoot()
                .environment(hub)
                .frame(minWidth: 1000, minHeight: 660)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(hub.current == .home || hub.current == .explorer ? "Open Export in Explorer…" : "Open \(hub.current.name) Export…") { openExport() }
                    .keyboardShortcut("o")
                Button("Open Any Export in Explorer…") { hub.chooseExplorerFolder() }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
            }
            CommandMenu("Go") {
                ForEach(Array(Source.allCases.enumerated()), id: \.element) { i, s in
                    Button(s.name) { hub.current = s }.keyboardShortcut(KeyEquivalent(Character("\(i + 1)")))
                }
            }
            CommandMenu("Library") {
                switch hub.current {
                case .photos: PhotosModule.menuItems()
                case .snapchat: SnapchatModule.menuItems()
                case .instagram: InstagramModule.menuItems()
                case .whatsapp: WhatsAppModule.menuItems()
                case .amazon: AmazonModule.menuItems()
                case .home, .explorer: Text("Nothing for this view")
                }
            }
        }

        Settings {
            TabView {
                PhotosModule.settingsView().tabItem { Label("Photos", systemImage: "photo") }
                Form {
                    InstagramModule.menuItems()
                    Button("Clear Explorer's Preview Copies") { DataFile.clearPreviewCache() }
                }
                .padding(20).tabItem { Label("Other", systemImage: "gearshape") }
            }
            .frame(width: 520)
        }
    }

    @MainActor private func openExport() {
        switch hub.current {
        case .photos: PhotosModule.chooseFolder()
        case .snapchat: SnapchatModule.chooseFolder()
        case .instagram: InstagramModule.chooseFolder()
        case .whatsapp: WhatsAppModule.chooseFolder()
        case .amazon: AmazonModule.chooseFolder()
        case .home, .explorer: hub.chooseExplorerFolder()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        #if DEBUG
        DebugSnapshot.install()
        #endif
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ n: Notification) { DataFile.clearPreviewCache() }
}

struct HubRoot: View {
    @Environment(Hub.self) private var hub

    var body: some View {
        HStack(spacing: 0) {
            Rail()
            ZStack {
                switch hub.current {
                case .home: HomeView()
                case .photos: PhotosModule.makeView()
                case .snapchat: SnapchatModule.makeView()
                case .instagram: InstagramModule.makeView()
                case .whatsapp: WhatsAppModule.makeView()
                case .amazon: AmazonModule.makeView()
                case .explorer: ExplorerView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .id(hub.current)
            .transition(.opacity)
        }
        .animation(.easeOut(duration: 0.15), value: hub.current)
    }
}

// MARK: Rail

/// The switcher down the left side: one icon per app, like a dock. The window's buttons sit on
/// its top.
struct Rail: View {
    @Environment(Hub.self) private var hub

    var body: some View {
        VStack(spacing: 10) {
            Color.clear.frame(height: 34)
            item(.home)
            Capsule().fill(Color.white.opacity(0.15)).frame(width: 32, height: 2).padding(.vertical, 2)
            ForEach(Source.apps) { item($0) }
            Spacer()
            item(.explorer)
            SettingsLink {
                Image(systemName: "gearshape").font(.system(size: 17)).foregroundStyle(Color.white.opacity(0.6))
                    .frame(width: 44, height: 36)
            }
            .buttonStyle(.plain).help("Settings")
            .padding(.bottom, 12)
        }
        .frame(width: 72)
        .frame(maxHeight: .infinity)
        .background(Color(white: 0.085))
        .overlay(alignment: .trailing) { Rectangle().fill(Color.white.opacity(0.07)).frame(width: 1) }
        .environment(\.colorScheme, .dark)
        .ignoresSafeArea()
    }

    private func item(_ s: Source) -> some View {
        let on = hub.current == s
        return Button { hub.current = s } label: {
            SourceIcon(source: s, size: 46)
                .scaleEffect(on ? 1.0 : 0.9)
                .opacity(on ? 1 : 0.8)
                .frame(width: 72, height: 50)
                .overlay(alignment: .leading) {
                    Capsule().fill(.white).frame(width: 4, height: on ? 34 : 0).offset(x: -1)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(s.appName)
    }
}

/// An app's own icon when the hub bundles it, otherwise a symbol tile.
struct SourceIcon: View {
    let source: Source
    var size: CGFloat = 46

    var body: some View {
        if let img = Hub.icon(source) {
            Image(nsImage: img).resizable().interpolation(.high).frame(width: size, height: size)
        } else {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(source == .home ? AnyShapeStyle(LinearGradient(colors: [Color(white: 0.32), Color(white: 0.2)], startPoint: .top, endPoint: .bottom))
                                      : AnyShapeStyle(LinearGradient(colors: [Color(red: 0.25, green: 0.45, blue: 0.95), Color(red: 0.4, green: 0.25, blue: 0.85)], startPoint: .topLeading, endPoint: .bottomTrailing)))
                .overlay(Image(systemName: source.symbol).font(.system(size: size * 0.4, weight: .semibold)).foregroundStyle(.white))
                .frame(width: size * 0.82, height: size * 0.82)
                .frame(width: size, height: size)
        }
    }
}
