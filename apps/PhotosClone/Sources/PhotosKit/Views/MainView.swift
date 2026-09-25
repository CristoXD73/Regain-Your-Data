import SwiftUI

struct MainView: View {
    @Environment(LibraryStore.self) private var store

    var body: some View {
        @Bindable var store = store
        ZStack {
            NavigationSplitView {
                SidebarView()
                    .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 320)
            } detail: {
                DetailView()
                    .inspector(isPresented: $store.showInfo) {
                        InfoPanel(asset: inspectedAsset)
                            .inspectorColumnWidth(min: 260, ideal: 300, max: 400)
                    }
            }
            .searchable(text: $store.searchText, placement: .toolbar, prompt: "Search: dog, beach, receipt, text, 2021…")

            if store.viewer != nil {
                ViewerView()
                    .transition(.opacity)
                    .zIndex(1)
            }
            if let slides = store.slideshow {
                SlideshowView(assets: slides)
                    .transition(.opacity)
                    .zIndex(2)
            }
        }
        .sheet(isPresented: $store.showStorage) { StorageView() }
        .confirmationDialog(deleteNowTitle, isPresented: Binding(get: { store.confirmDeleteNow != nil }, set: { if !$0 { store.confirmDeleteNow = nil } })) {
            Button("Delete", role: .destructive) {
                if let ids = store.confirmDeleteNow { store.deleteNow(ids) }
                store.confirmDeleteNow = nil
            }
        } message: {
            Text("They disappear from Photos Clone for good. The originals stay inside your zips until you compact them with Free Up Space.")
        }
        .animation(.easeOut(duration: 0.18), value: store.viewer != nil)
        .animation(.easeOut(duration: 0.3), value: store.slideshow != nil)
    }

    private var deleteNowTitle: String {
        let n = store.confirmDeleteNow?.count ?? 0
        return n == 1 ? "Delete this item now?" : "Delete \(n) items now?"
    }

    private var inspectedAsset: Asset? {
        if let v = store.viewer { return v.current }
        if let id = store.selectedIDs.first, store.selectedIDs.count == 1 { return store.asset(id) }
        return nil
    }
}

struct SidebarView: View {
    @Environment(LibraryStore.self) private var store
    @State private var albumsExpanded = true
    @State private var partsExpanded = false

    var body: some View {
        @Bindable var store = store
        List(selection: $store.selection) {
            Section("Photos") {
                row(.library)
                row(.favorites)
                row(.places)
                row(.memories)
            }
            Section("Media Types") {
                row(.videos)
                row(.livePhotos)
                row(.screenshots)
                row(.screenRecordings)
                row(.animated)
            }
            Section("Utilities") {
                if store.showHiddenAlbum {
                    row(.hidden, lockable: true)
                }
                row(.recentlyDeleted, lockable: true)
                row(.duplicates)
            }
            if !store.library.sharedAlbums.isEmpty {
                Section("Shared Albums") {
                    ForEach(store.library.sharedAlbums) { a in
                        Label(a.title, systemImage: "person.2").badge(a.assetIDs.count).tag(SidebarItem.shared(a.id))
                    }
                }
            }
            Section(isExpanded: $albumsExpanded) {
                ForEach(store.library.albums) { a in
                    Label(a.title, systemImage: "rectangle.stack").badge(a.assetIDs.count).tag(SidebarItem.album(a.id))
                }
            } header: {
                Text("My Albums")
            }
            Section(isExpanded: $partsExpanded) {
                ForEach(store.library.parts, id: \.self) { p in
                    let name = String(p.dropFirst("iCloud Photos ".count))
                    Label(name, systemImage: "archivebox").tag(SidebarItem.part(name))
                }
            } header: {
                Text("Export Parts")
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) { IndexingFooter() }
    }

    @ViewBuilder
    private func row(_ item: SidebarItem, lockable: Bool = false) -> some View {
        Label {
            HStack {
                Text(item.title)
                Spacer()
                if lockable && store.requireAuth {
                    Image(systemName: store.unlocked ? "lock.open" : "lock.fill")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        } icon: {
            Image(systemName: item.icon)
        }
        .tag(item)
    }
}

struct IndexingFooter: View {
    @Environment(LibraryStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if store.isIndexing {
                ProgressView(value: Double(store.indexed), total: Double(max(1, store.indexingTotal)))
                    .controlSize(.small)
                Text("Reading dates & places… \(store.indexed.formatted()) of \(store.indexingTotal.formatted())")
                    .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
            } else if store.isAnalyzing {
                let textPhase = store.textTotal > 0 && store.analysisDone >= store.analysisTotal
                ProgressView(value: Double(textPhase ? store.textDone : store.analysisDone),
                             total: Double(max(1, textPhase ? store.textTotal : store.analysisTotal)))
                    .controlSize(.small)
                Text(textPhase
                     ? "Reading text in screenshots… \(store.textDone.formatted()) of \(store.textTotal.formatted())"
                     : "Recognizing what's in photos… \(store.analysisDone.formatted()) of \(store.analysisTotal.formatted())")
                    .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                if let until = store.aiAwakeUntil {
                    Text("AI sleeps \(until, style: .relative) after your last search")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            } else {
                if store.analyzePhotos && store.analysisDone < store.analysisTotal {
                    Label("AI asleep: search to wake it (\(store.analysisDone.formatted()) of \(store.analysisTotal.formatted()) analysed)", systemImage: "moon.zzz")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Text("\(store.library.assets.count.formatted()) items · \(store.library.parts.count) parts")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12).padding(.vertical, 8)
    }
}

struct DetailView: View {
    @Environment(LibraryStore.self) private var store

    var body: some View {
        let item = store.selection ?? .library
        Group {
            if item.isLocked && !store.unlocked {
                LockedView(item: item)
            } else {
                switch item {
                case .library: LibraryView()
                case .places: PlacesView()
                case .memories: MemoriesView()
                case .sharedAlbums: MemoriesView()
                case .album, .memory, .shared, .duplicates:
                    AssetGridView(item: item, grouped: false)
                default:
                    AssetGridView(item: item, grouped: true)
                }
            }
        }
        .navigationTitle(title(item))
        .navigationSubtitle(subtitle(item))
        .toolbar { toolbar(item) }
        .overlay(alignment: .bottom) {
            if let msg = store.busyMessage {
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text(msg) }
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .padding(12)
            }
        }
    }

    private func title(_ item: SidebarItem) -> String {
        switch item {
        case .album(let id): store.library.albums.first { $0.id == id }?.title ?? "Album"
        case .memory(let id): store.library.memories.first { $0.id == id }?.title ?? "Memory"
        case .shared(let id): store.library.sharedAlbums.first { $0.id == id }?.title ?? "Shared Album"
        default: item.title
        }
    }

    private func subtitle(_ item: SidebarItem) -> String {
        if item.isLocked && !store.unlocked { return "" }
        if case .memories = item { return "\(store.library.memories.count) memories" }
        if case .places = item { return "" }
        let list = store.assets(for: item)
        let photos = list.filter { $0.kind != .video }.count
        let videos = list.count - photos
        var parts: [String] = []
        if photos > 0 { parts.append("\(photos.formatted()) Photo\(photos == 1 ? "" : "s")") }
        if videos > 0 { parts.append("\(videos.formatted()) Video\(videos == 1 ? "" : "s")") }
        if !store.selectedIDs.isEmpty { parts.append("\(store.selectedIDs.count) selected") }
        return parts.joined(separator: ", ")
    }

    @ToolbarContentBuilder
    private func toolbar(_ item: SidebarItem) -> some ToolbarContent {
        @Bindable var store = store
        if case .library = item {
            ToolbarItem(placement: .principal) {
                Picker("Zoom", selection: $store.libraryZoom) {
                    ForEach(LibraryZoom.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
        }
        if case .memory = item {
            ToolbarItem {
                Button { store.slideshow = store.assets(for: item).filter { $0.kind != .video } } label: {
                    Label("Play Memory", systemImage: "play.fill")
                }
            }
        }
        ToolbarItemGroup {
            if !store.selectedIDs.isEmpty {
                let sel = store.selectedIDs.sorted().map { store.asset($0) }
                Button { store.export(sel) } label: { Label("Export", systemImage: "square.and.arrow.up.on.square") }
                    .help("Copy the original files to a folder")
                Button { store.revealInFinder(sel) } label: { Label("Show in Finder", systemImage: "folder") }
            }
            if item == .recentlyDeleted && store.unlocked {
                let ids = store.selectedIDs.isEmpty ? store.assets(for: item).map(\.id) : store.selectedIDs.sorted()
                Button(store.selectedIDs.isEmpty ? "Recover All" : "Recover") { store.restore(ids) }
                    .disabled(ids.isEmpty)
                Button(store.selectedIDs.isEmpty ? "Delete All…" : "Delete…") { store.confirmDeleteNow = ids }
                    .disabled(ids.isEmpty)
            }
            if item.isLocked && store.unlocked && store.requireAuth {
                Button { store.lock() } label: { Label("Lock", systemImage: "lock") }
            }
            Slider(value: $store.thumbnailSize, in: 70...400)
                .frame(width: 110)
                .help("Thumbnail size")
            Button { store.showInfo.toggle() } label: { Label("Info", systemImage: "info.circle") }
        }
    }
}

struct LockedView: View {
    @Environment(LibraryStore.self) private var store
    let item: SidebarItem

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.fill").font(.system(size: 44)).foregroundStyle(.secondary)
            Text("\(item.title) Album is Locked").font(.title2.bold())
            Text("Use Touch ID, your Apple Watch or your password to view this album.")
                .foregroundStyle(.secondary)
            if let e = store.authError {
                Text(e).font(.callout).foregroundStyle(.red)
            }
            Button("View Album") { Task { await store.unlock() } }
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await store.unlock() }
    }
}
