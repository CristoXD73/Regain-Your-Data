import SwiftUI


public struct PhotosCloneApp: App {
    public init() {}
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var store = LibraryStore()

    public var body: some Scene {
        WindowGroup("Photos Clone") {
            RootView()
                .environment(store)
                .frame(minWidth: 900, minHeight: 600)
                #if DEBUG
                .onAppear { DebugHooks.install(store) }
                #endif
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Export Folder…") { chooseFolder(store) }.keyboardShortcut("o")
                Button("Free Up Space…") { store.showStorage = true }
                    .disabled(store.phase != .ready)
            }
            CommandMenu("Image") {
                Button("Favorite / Unfavorite") { store.toggleFavorite(store.targetIDs) }
                    .disabled(store.targetIDs.isEmpty)
                Button("Hide") { store.setHidden(store.targetIDs, true) }
                    .keyboardShortcut("l")
                    .disabled(store.targetIDs.isEmpty)
                // No ⌘⌫ here: it would fire while typing in the search field. The grid and viewer
                // handle ⌘⌫ themselves when they have focus.
                Button("Delete") { store.moveToTrash(store.targetIDs) }
                    .disabled(store.targetIDs.isEmpty || store.selection == .recentlyDeleted)
            }
            CommandMenu("View Options") {
                Button("Zoom In") { store.thumbnailSize = min(400, store.thumbnailSize + 40) }.keyboardShortcut("+")
                Button("Zoom Out") { store.thumbnailSize = max(70, store.thumbnailSize - 40) }.keyboardShortcut("-")
                Divider()
                Button(store.showInfo ? "Hide Info" : "Show Info") { store.showInfo.toggle() }.keyboardShortcut("i")
                Divider()
                Button("Lock Hidden Album") { store.lock() }.keyboardShortcut("l", modifiers: [.command, .control])
            }
        }

        Settings {
            SettingsView().environment(store)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Launched as a bare executable (swift run) there is no bundle, so ask to be a normal app.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@MainActor
func chooseFolder(_ store: LibraryStore) {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.message = "Choose the folder that holds your “iCloud Photos Part … of …” folders or zips."
    panel.prompt = "Open"
    if panel.runModal() == .OK, let url = panel.url { store.open(url) }
}

struct RootView: View {
    @Environment(LibraryStore.self) private var store

    var body: some View {
        switch store.phase {
        case .welcome: WelcomeView()
        case .scanning(let msg): ScanningView(message: msg)
        case .ready: MainView()
        }
    }
}

struct ScanningView: View {
    let message: String
    var body: some View {
        VStack(spacing: 16) {
            ProgressView().controlSize(.large)
            Text(message).foregroundStyle(.secondary).monospacedDigit()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct WelcomeView: View {
    @Environment(LibraryStore.self) private var store
    @State private var suggestions: [URL] = []

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "photo.stack")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(.linearGradient(colors: [.orange, .pink, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
            Text("Photos Clone").font(.largeTitle.bold())
            Text("Browse the copy of iCloud Photos you downloaded from privacy.apple.com: your library, albums, memories, Hidden and Recently Deleted.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 460)

            if !suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Found on this Mac").font(.headline)
                    ForEach(suggestions, id: \.self) { url in
                        Button { store.open(url) } label: {
                            HStack {
                                Image(systemName: "externaldrive")
                                VStack(alignment: .leading) {
                                    Text(url.lastPathComponent).fontWeight(.medium)
                                    Text(url.path).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                            }
                            .padding(10)
                            .frame(width: 440)
                            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Button("Choose Folder…") { chooseFolder(store) }
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            Text("Pick the folder containing “iCloud Photos Part 1 of N”, “Part 2 of N”… (unzipped or still zipped).")
                .font(.caption).foregroundStyle(.tertiary)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { suggestions = await Task.detached { ExportScanner.suggestedRoots() }.value }
    }
}

struct SettingsView: View {
    @Environment(LibraryStore.self) private var store

    var body: some View {
        @Bindable var store = store
        Form {
            Section("Privacy") {
                Toggle("Use Touch ID, Apple Watch or password to view Hidden and Recently Deleted", isOn: $store.requireAuth)
                Text("To unlock with your watch, turn on “Use Apple Watch to unlock applications and your Mac” in System Settings › Touch ID & Password.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Show Hidden album in sidebar", isOn: $store.showHiddenAlbum)
            }
            Section("Search") {
                Toggle("Recognize what's in photos and read text in screenshots", isOn: $store.analyzePhotos)
                Text("Runs on this Mac only, using Apple's Vision framework, and only after you search: it keeps working for 10 minutes after your last search, then sleeps. Nothing is uploaded.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Library") {
                LabeledContent("Export folder", value: store.root?.path ?? "None")
                HStack {
                    Button("Change…") { chooseFolder(store) }
                    Button("Clear Thumbnail Cache") {
                        try? FileManager.default.removeItem(at: Paths.caches.appendingPathComponent("thumbs"))
                        try? FileManager.default.createDirectory(at: Paths.caches.appendingPathComponent("thumbs"), withIntermediateDirectories: true)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .padding()
    }
}
