#if DEBUG
import AppKit

/// Debug builds only: lets scripts drive the app (never captures what is on screen). Post with:
///   swift scripts/debug-cmd.swift "select videos" | "open 0" | "close" | "zoom years"
@MainActor
enum DebugHooks {
    static func install(_ store: LibraryStore) {
        DistributedNotificationCenter.default().addObserver(forName: .init("PhotosClone.debug"), object: nil, queue: .main) { note in
            guard let cmd = note.object as? String else { return }
            MainActor.assumeIsolated { run(cmd, store) }
        }
    }

    static func run(_ cmd: String, _ store: LibraryStore) {
        let parts = cmd.split(separator: " ", maxSplits: 1).map(String.init)
        let arg = parts.count > 1 ? parts[1] : ""
        switch parts.first {
        case "dump":
            // Text-only state report: counts and flags, no file names or image data.
            var out = "selection=\(store.selection.map { "\($0)" } ?? "nil") unlocked=\(store.unlocked) zoom=\(store.libraryZoom.rawValue)\n"
            out += "viewer=\(store.viewer.map { "\($0.index + 1)/\($0.assets.count) kind=\($0.current.kind)" } ?? "closed") showInfo=\(store.showInfo) slideshow=\(store.slideshow?.count ?? 0)\n"
            out += "indexed=\(store.indexed)/\(store.indexingTotal) withLocation=\(store.infos.values.filter(\.hasLocation).count)\n"
            for item: SidebarItem in [.library, .favorites, .videos, .livePhotos, .screenshots, .screenRecordings, .animated, .hidden, .recentlyDeleted, .duplicates] {
                out += "\(item.title)=\(store.assets(for: item).count) "
            }
            out += "\nzipped=\(store.library.zippedCount) zips=\(store.library.zips.count) thumbs=\(store.thumbsDone)/\(store.thumbsTotal) running=\(store.thumbsRunning) storage=\(store.storageStatus ?? (store.storageReport == nil ? "none" : "done: \(store.storageReport!.folders.filter(\.safe).count) safe"))"
            out += "\nai: awake=\(store.aiAwake) working=\(store.isAnalyzing) labelled=\(store.analysisDone)/\(store.analysisTotal) text=\(store.textDone)/\(store.textTotal) results(\(store.searchText))=\(store.assets(for: store.selection ?? .library).count) trash=\(store.assets(for: .recentlyDeleted).count) favorites=\(store.assets(for: .favorites).count)"
            out += "\nsections(library)=\(store.sections(store.assets(for: .library)).count) memories=\(store.library.memories.count)\n"
            try? out.write(toFile: arg, atomically: true, encoding: .utf8)
        case "select":
            let map: [String: SidebarItem] = ["library": .library, "favorites": .favorites, "map": .places, "memories": .memories,
                                              "videos": .videos, "live": .livePhotos, "screenshots": .screenshots, "hidden": .hidden,
                                              "deleted": .recentlyDeleted, "duplicates": .duplicates, "shared": .sharedAlbums]
            if let item = map[arg] { store.selection = item }
            else if let a = store.library.albums.first(where: { $0.title == arg }) { store.selection = .album(a.id) }
            else if let m = store.library.memories.first(where: { $0.title == arg }) { store.selection = .memory(m.id) }
        case "zoom": store.libraryZoom = LibraryZoom.allCases.first { $0.rawValue.lowercased().hasPrefix(arg) } ?? .all
        case "open":
            let list = store.assets(for: store.selection ?? .library)
            let i = Int(arg) ?? 0
            let idx = i < 0 ? list.count + i : i
            if list.indices.contains(idx) { store.open(list[idx], in: list) }
        case "close": store.viewer = nil; store.slideshow = nil
        case "info": store.showInfo.toggle()
        case "storage": store.showStorage = true
        case "trash-first":
            if let a = store.assets(for: .library).last { store.moveToTrash([a.id]) }
        case "fav-first":
            if let a = store.assets(for: .library).last { store.toggleFavorite([a.id]) }
        case "restore-all":
            store.restore(store.assets(for: .recentlyDeleted).filter { $0.deletedAt != nil }.map(\.id))
        case "unlock": store.unlocked = true
        case "search": store.searchText = arg
        case "size": NSApp.windows.first { $0.isVisible && $0.frame.width > 400 }?.setFrame(NSRect(x: 40, y: 40, width: 1400, height: 900), display: true)
        default: break
        }
    }
}
#endif
