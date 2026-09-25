import SwiftUI

enum Theme {
    static let yellow = Color(red: 1, green: 0.988, blue: 0)          // #FFFC00
    static let background = Color.black
    static let card = Color(white: 0.11)
    /// Snapchat shows audio in purple.
    static let voice = LinearGradient(colors: [Color(red: 0.55, green: 0.33, blue: 0.95), Color(red: 0.36, green: 0.2, blue: 0.75)], startPoint: .top, endPoint: .bottom)
    static let secondary = Color(white: 0.62)
    static func title(_ size: CGFloat) -> Font { .system(size: size, weight: .heavy, design: .rounded) }
    static func body(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font { .system(size: size, weight: weight, design: .rounded) }
}

struct SnapVaultApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var store = VaultStore.shared

    var body: some Scene {
        WindowGroup("Snapchat Clone") {
            RootView()
                .environment(store)
                .frame(minWidth: 820, minHeight: 600)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Snapchat Export…") { chooseFolder(store) }.keyboardShortcut("o")
            }
            CommandMenu("Memories") {
                ForEach(Array(Tab.allCases.enumerated()), id: \.element) { i, t in
                    Button(t.rawValue) { store.tab = t }.keyboardShortcut(KeyEquivalent(Character("\(i + 1)")))
                }
                Divider()
                Button("Lock My Eyes Only") { store.lockEyesOnly() }.keyboardShortcut("l", modifiers: [.command, .control])
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
func chooseFolder(_ store: VaultStore) {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.message = "Choose the folder that holds your Snapchat export (the mydata~… zips or folder)."
    if panel.runModal() == .OK, let url = panel.url { store.open(url) }
}

struct RootView: View {
    @Environment(VaultStore.self) private var store
    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            switch store.phase {
            case .welcome: WelcomeView()
            case .scanning(let m):
                VStack(spacing: 14) {
                    ProgressView().tint(Theme.yellow).controlSize(.large)
                    Text(m).font(Theme.body(14, .medium)).foregroundStyle(Theme.secondary)
                }
            case .ready: MainView()
            }
        }
    }
}

struct WelcomeView: View {
    @Environment(VaultStore.self) private var store
    @State private var found: [URL] = []

    var body: some View {
        VStack(spacing: 20) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 120, height: 120)
            Text("Snapchat Clone").font(Theme.title(34)).foregroundStyle(.white)
            Text("Your Snapchat Memories and chat snaps, from the export you downloaded. Nothing leaves this Mac.")
                .font(Theme.body(15, .medium)).foregroundStyle(Theme.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: 420)
            ForEach(found, id: \.self) { url in
                Button { store.open(url) } label: {
                    HStack {
                        Image(systemName: "externaldrive.fill")
                        VStack(alignment: .leading) {
                            Text(url.lastPathComponent).font(Theme.body(14))
                            Text(url.path).font(Theme.body(11, .regular)).foregroundStyle(Theme.secondary).lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .padding(14).frame(width: 440)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain).foregroundStyle(.white)
            }
            Button { chooseFolder(store) } label: {
                Text("Choose Folder…").font(Theme.body(15, .bold)).foregroundStyle(.black)
                    .padding(.horizontal, 26).padding(.vertical, 12)
                    .background(Theme.yellow, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(40)
        .task { found = await Task.detached { SnapScanner.suggestedRoots() }.value }
    }
}

struct MainView: View {
    @Environment(VaultStore.self) private var store

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                TopBar()
                Group {
                    switch store.tab {
                    case .snaps: SnapsView()
                    case .stories: StoriesView()
                    case .chats: ChatsView()
                    case .eyesOnly: EyesOnlyView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if store.playback != nil {
                PlayerView().transition(.opacity).zIndex(1)
            }
        }
        .animation(.easeOut(duration: 0.2), value: store.playback != nil)
    }
}

struct TopBar: View {
    @Environment(VaultStore.self) private var store

    var body: some View {
        @Bindable var store = store
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                Text("Memories").font(Theme.title(26)).foregroundStyle(.white)
                Spacer()
                if store.preparing > 0 {
                    HStack(spacing: 6) {
                        ProgressView(value: Double(store.prepared), total: Double(store.preparing)).frame(width: 80).tint(Theme.yellow)
                        Text("Preparing \(store.prepared)/\(store.preparing)").font(Theme.body(11, .medium)).foregroundStyle(Theme.secondary).monospacedDigit()
                    }
                }
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.secondary)
                    TextField("Search dates, friends", text: $store.searchText)
                        .textFieldStyle(.plain).font(Theme.body(13, .medium)).frame(width: 180)
                }
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Theme.card, in: Capsule())
                Slider(value: $store.tileWidth, in: 80...240).frame(width: 90).tint(Theme.yellow)
                    .help("Tile size")
                if !store.selected.isEmpty { SelectionActions() }
            }
            HStack(spacing: 8) {
                ForEach(Tab.allCases) { t in
                    Button { store.tab = t } label: {
                        HStack(spacing: 5) {
                            if t == .eyesOnly { Image(systemName: store.lock.state == .unlocked ? "lock.open.fill" : "lock.fill").font(.system(size: 11, weight: .bold)) }
                            Text(t.rawValue)
                        }
                        .font(Theme.body(14, .bold))
                        .foregroundStyle(store.tab == t ? .black : .white)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(store.tab == t ? Color.white : Theme.card, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 34)
        .padding(.bottom, 12)
        .background(Theme.background)
    }
}

struct SelectionActions: View {
    @Environment(VaultStore.self) private var store
    var body: some View {
        let snaps = store.selected.sorted().map { store.snap($0) }
        HStack(spacing: 8) {
            Text("\(snaps.count) selected").font(Theme.body(12)).foregroundStyle(Theme.secondary)
            pill(store.tab == .eyesOnly ? "Move Out" : "My Eyes Only", "lock.fill") { store.toggleEyesOnly(snaps) }
            pill("Export", "square.and.arrow.up") { Exporter.export(snaps) }
            pill("Done", "xmark") { store.selected = [] }
        }
    }
    private func pill(_ t: String, _ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(t, systemImage: icon).font(Theme.body(12, .bold)).foregroundStyle(.black)
                .padding(.horizontal, 10).padding(.vertical, 6).background(Theme.yellow, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
