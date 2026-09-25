import AppKit
import LocalAuthentication
import Observation

enum SidebarItem: Hashable {
    case library, favorites, places, memories, sharedAlbums
    case videos, livePhotos, screenshots, screenRecordings, animated
    case hidden, recentlyDeleted, duplicates
    case album(String), memory(String), shared(String), part(String)

    var title: String {
        switch self {
        case .library: "Library"
        case .favorites: "Favorites"
        case .places: "Map"
        case .memories: "Memories"
        case .sharedAlbums: "Shared Albums"
        case .videos: "Videos"
        case .livePhotos: "Live Photos"
        case .screenshots: "Screenshots"
        case .screenRecordings: "Screen Recordings"
        case .animated: "Animated"
        case .hidden: "Hidden"
        case .recentlyDeleted: "Recently Deleted"
        case .duplicates: "Duplicates"
        case .album(let id), .memory(let id), .shared(let id), .part(let id): id
        }
    }

    var icon: String {
        switch self {
        case .library: "photo.on.rectangle"
        case .favorites: "heart"
        case .places: "map"
        case .memories: "memories"
        case .sharedAlbums: "person.2.crop.square.stack"
        case .videos: "video"
        case .livePhotos: "livephoto"
        case .screenshots: "camera.viewfinder"
        case .screenRecordings: "record.circle"
        case .animated: "square.stack.3d.forward.dottedline"
        case .hidden: "eye.slash"
        case .recentlyDeleted: "trash"
        case .duplicates: "square.on.square"
        case .album: "rectangle.stack"
        case .memory: "memories"
        case .shared: "person.2"
        case .part: "archivebox"
        }
    }

    var isLocked: Bool { self == .hidden || self == .recentlyDeleted }
}

enum LibraryZoom: String, CaseIterable, Identifiable {
    case years = "Years", months = "Months", all = "All Photos"
    var id: String { rawValue }
}

struct MonthSection: Identifiable {
    let id: Date
    let title: String
    let assets: [Asset]
}

@MainActor
@Observable
final class LibraryStore {
    enum Phase: Equatable { case welcome, scanning(String), ready }

    var phase: Phase = .welcome
    var library = ExportLibrary(root: URL(fileURLWithPath: "/"))
    var infos: [Int: MediaInfo] = [:]
    var indexed = 0
    var indexingTotal = 0

    var selection: SidebarItem? = .library {
        didSet { if oldValue != selection { selectedIDs = [] } }
    }
    var searchText = "" {
        didSet {
            invalidate()
            if !searchText.trimmingCharacters(in: .whitespaces).isEmpty { wakeAI() }
        }
    }
    var libraryZoom: LibraryZoom = .all
    var thumbnailSize: Double = 150
    var selectedIDs: Set<Int> = []
    var viewer: ViewerState?
    var slideshow: [Asset]?
    /// Items waiting for the user to confirm "Delete Now" (permanent, no undo).
    var confirmDeleteNow: [Int]?
    /// Short status for slow work in progress, e.g. unpacking a large video from its zip.
    var busyMessage: String?

    // "Free Up Space": checking the zips hold everything, and saving thumbnails ahead of time.
    var showStorage = false
    var storageStatus: String?
    var storageReport: (zipBytes: Int64, folders: [FolderReport])?
    var thumbsDone = 0
    var thumbsTotal = 0
    var thumbsRunning = false
    var showInfo = false

    var unlocked = false
    var authError: String?
    @ObservationIgnored private var authenticating = false
    var requireAuth = UserDefaults.standard.object(forKey: "requireAuth") as? Bool ?? true {
        didSet { UserDefaults.standard.set(requireAuth, forKey: "requireAuth") }
    }
    var showHiddenAlbum = UserDefaults.standard.object(forKey: "showHiddenAlbum") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showHiddenAlbum, forKey: "showHiddenAlbum") }
    }

    // On-device analysis for search.
    var analyses: [Int: Analysis] = [:]
    var analysisDone = 0
    var analysisTotal = 0
    var textDone = 0
    var textTotal = 0
    var analyzePhotos = UserDefaults.standard.object(forKey: "analyzePhotos") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(analyzePhotos, forKey: "analyzePhotos")
            if !analyzePhotos { analysisTask?.cancel(); analysisTask = nil; aiAwakeUntil = nil }
        }
    }
    var isAnalyzing: Bool { analysisTask != nil }
    /// The on-device model only works while this is in the future: each search pushes it
    /// 10 minutes out, after which analysis pauses until the next search.
    var aiAwakeUntil: Date?
    static let aiAwakeWindow: TimeInterval = {
        #if DEBUG
        if let s = ProcessInfo.processInfo.environment["PHOTOSCLONE_AI_WINDOW"].flatMap(Double.init) { return s }
        #endif
        return 10 * 60
    }()
    var aiAwake: Bool { (aiAwakeUntil ?? .distantPast) > Date() }

    @ObservationIgnored private var edits: EditsStore?
    @ObservationIgnored private var analysisStore: AnalysisStore?
    @ObservationIgnored private var analysisTask: Task<Void, Never>?
    /// Lower-cased recognised text per asset, for fast search.
    @ObservationIgnored private var foldedText: [Int: String] = [:]
    @ObservationIgnored private var cache: [SidebarItem: [Asset]] = [:]
    @ObservationIgnored private var albumTitlesByAsset: [Int: [String]] = [:]
    @ObservationIgnored private var infoStore: MediaInfoStore?
    @ObservationIgnored private var indexTask: Task<Void, Never>?

    var root: URL? {
        get { UserDefaults.standard.string(forKey: "exportRoot").map { URL(fileURLWithPath: $0) } }
        set { UserDefaults.standard.set(newValue?.path, forKey: "exportRoot") }
    }

    init() {
        if let r = root, FileManager.default.fileExists(atPath: r.path) { open(r) }
        // Relock Hidden whenever the Mac sleeps, the screen locks or another user takes over.
        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.lock() }
            }
        }
        DistributedNotificationCenter.default().addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.lock() }
        }
    }

    // MARK: Loading

    func open(_ url: URL) {
        root = url
        indexTask?.cancel()
        phase = .scanning("Opening \(url.lastPathComponent)…")
        Task.detached(priority: .userInitiated) {
            let lib = ExportScanner.scan(root: url) { msg in
                Task { @MainActor in self.phase = .scanning(msg) }
            }
            await MainActor.run { self.finishLoading(lib) }
        }
    }

    private func finishLoading(_ lib: ExportLibrary) {
        var lib = lib
        let edits = EditsStore(root: lib.root)
        for i in lib.assets.indices { edits.apply(to: &lib.assets[i]) }
        self.edits = edits
        library = lib
        albumTitlesByAsset = [:]
        for a in lib.albums + lib.memories + lib.sharedAlbums {
            for id in a.assetIDs { albumTitlesByAsset[id, default: []].append(a.title) }
        }
        invalidate()
        infos = [:]
        analyses = [:]
        foldedText = [:]
        phase = .ready
        startIndexing()
        loadCachedAnalysis()
    }

    func closeLibrary() {
        indexTask?.cancel()
        analysisTask?.cancel()
        root = nil
        phase = .welcome
    }

    private func startIndexing() {
        let store = MediaInfoStore(root: library.root)
        infoStore = store
        let assets = library.assets
        indexingTotal = assets.count
        indexed = 0
        indexTask = Task {
            // Load everything already cached in one go, then read the rest in the background.
            var pending: [Asset] = []
            var batch: [Int: MediaInfo] = [:]
            for a in assets {
                if let i = await store.cached(a) { batch[a.id] = i } else { pending.append(a) }
            }
            apply(batch)
            indexed = batch.count

            var it = pending.makeIterator()
            await withTaskGroup(of: (Int, MediaInfo?).self) { group in
                var running = 0
                var buffer: [Int: MediaInfo] = [:]
                func add(_ a: Asset) {
                    group.addTask(priority: .utility) { (a.id, await MediaInfoReader.read(a)) }
                }
                while running < 6, let a = it.next() { add(a); running += 1 }
                while let (id, result) = await group.next() {
                    if Task.isCancelled { group.cancelAll(); break }
                    // nil: a zipped video nobody has played yet; count it as done, cache nothing.
                    let info = result ?? MediaInfo()
                    buffer[id] = info
                    if result != nil { await store.store(info, for: assets[id]) }
                    if let a = it.next() { add(a) }
                    if buffer.count >= 250 {
                        apply(buffer); indexed += buffer.count; buffer = [:]
                    }
                }
                apply(buffer); indexed += buffer.count
            }
            await store.save()
        }
    }

    private func apply(_ batch: [Int: MediaInfo]) {
        guard !batch.isEmpty else { return }
        var changedDates = false
        for (id, info) in batch {
            infos[id] = info
            // Same-name rows: take the one whose date is closest to the file's own capture date.
            if let rows = library.assets[id].candidateRows, let fd = info.captureDate,
               let best = rows.min(by: { abs(($0.created ?? .distantPast).timeIntervalSince(fd)) < abs(($1.created ?? .distantPast).timeIntervalSince(fd)) }),
               best.created != library.assets[id].csvCreationDate {
                library.assets[id].apply(best)
                edits?.apply(to: &library.assets[id])
                changedDates = true
            }
            let d = DateResolver.resolve(library.assets[id], fileDate: info.captureDate, camera: info.camera)
            if library.assets[id].date != d {
                library.assets[id].date = d
                changedDates = true
            }
        }
        if changedDates { invalidate() }
    }

    var isIndexing: Bool { indexingTotal > 0 && indexed < indexingTotal }

    // MARK: Queries

    func invalidate() { cache = [:] }

    func asset(_ id: Int) -> Asset { library.assets[id] }
    func info(_ a: Asset) -> MediaInfo? { infos[a.id] }
    func albumTitles(for a: Asset) -> [String] { albumTitlesByAsset[a.id] ?? [] }

    /// Items in the main library: not hidden, not deleted, not from a shared album.
    private func inLibrary(_ a: Asset) -> Bool {
        !a.isHidden && !a.isDeleted && !a.isPurged && a.part != "Shared Album"
    }

    func assets(for item: SidebarItem) -> [Asset] {
        if let c = cache[item] { return c }
        let all = library.assets.filter { !$0.isPurged }
        var result: [Asset]
        switch item {
        case .library, .places, .memories, .sharedAlbums: result = all.filter(inLibrary)
        case .favorites: result = all.filter { inLibrary($0) && $0.isFavorite }
        case .videos: result = all.filter { inLibrary($0) && $0.kind == .video }
        case .livePhotos: result = all.filter { inLibrary($0) && $0.kind == .livePhoto }
        case .screenshots: result = all.filter { inLibrary($0) && $0.isScreenshot }
        case .screenRecordings: result = all.filter { inLibrary($0) && $0.isScreenRecording }
        case .animated: result = all.filter { inLibrary($0) && $0.isAnimated }
        case .hidden: result = all.filter { $0.isHidden && !$0.isDeleted }
        case .recentlyDeleted: result = all.filter { $0.isDeleted }
        case .duplicates:
            // Same iCloud checksum AND same size: the checksum alone matched two different files.
            var groups: [String: [Asset]] = [:]
            for a in all where !(a.checksum ?? "").isEmpty { groups["\(a.checksum!)|\(a.fileSize)", default: []].append(a) }
            result = groups.values.filter { $0.count > 1 }.flatMap { $0 }
        case .album(let id):
            result = (library.albums.first { $0.id == id }?.assetIDs ?? []).map { library.assets[$0] }.filter { !$0.isPurged && !$0.isDeleted }
        case .memory(let id):
            result = (library.memories.first { $0.id == id }?.assetIDs ?? []).map { library.assets[$0] }.filter { !$0.isPurged && !$0.isDeleted }
        case .shared(let id):
            result = (library.sharedAlbums.first { $0.id == id }?.assetIDs ?? []).map { library.assets[$0] }.filter { !$0.isPurged && !$0.isDeleted }
        case .part(let p):
            result = all.filter { $0.part == p }
        }
        if case .duplicates = item {
            result.sort { ($0.checksum ?? "", $0.date) < ($1.checksum ?? "", $1.date) }
        } else {
            result.sort(by: DateResolver.ascending)
        }
        let q = searchText.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty {
            let query = SearchQuery(q)
            result = result.filter { matches($0, query) }
        }
        cache[item] = result
        return result
    }

    private static let searchFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy EEEE"
        return f
    }()

    /// Every word must match something: the file name, an album, the date, the camera, the kind
    /// of item, what's in the picture (on-device labels) or text recognised in it.
    private func matches(_ a: Asset, _ q: SearchQuery) -> Bool {
        if q.words.isEmpty { return true }
        let albums = albumTitles(for: a)
        let date = a.date == .distantPast ? "" : Self.searchFormatter.string(from: a.date).lowercased()
        let camera = infos[a.id]?.camera?.lowercased() ?? ""
        let labels = analyses[a.id]?.labels ?? [:]
        let text = foldedText[a.id]
        let name = a.name.lowercased()
        // The whole phrase as typed can match an album or a piece of text ("new york", "flight 42").
        if q.words.count > 1 {
            if albums.contains(where: { $0.localizedCaseInsensitiveContains(q.phrase) }) { return true }
            if let text, text.contains(q.phrase) { return true }
        }
        for w in q.words {
            if name.contains(w.text) || date.contains(w.text) || camera.contains(w.text) { continue }
            if albums.contains(where: { $0.localizedCaseInsensitiveContains(w.text) }) { continue }
            if let kind = w.kind, kind(a) { continue }
            if w.labels.contains(where: { (labels[$0] ?? 0) >= 0.3 }) { continue }
            if w.text.count >= 3, let text, text.contains(w.text) { continue }
            return false
        }
        return true
    }

    func count(_ item: SidebarItem) -> Int {
        switch item {
        case .album(let id): library.albums.first { $0.id == id }?.assetIDs.count ?? 0
        case .memories: library.memories.count
        case .sharedAlbums: library.sharedAlbums.count
        case .places: 0
        default: assets(for: item).count
        }
    }

    func sections(_ assets: [Asset]) -> [MonthSection] {
        let cal = Calendar.current
        let fmt = DateFormatter()
        fmt.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        var out: [MonthSection] = []
        var current: [Asset] = []
        var currentKey: Date?
        for a in assets {
            let key = a.date == .distantPast ? .distantPast : cal.dateInterval(of: .month, for: a.date)!.start
            if key != currentKey, let k = currentKey {
                out.append(MonthSection(id: k, title: k == .distantPast ? "Unknown Date" : fmt.string(from: k), assets: current))
                current = []
            }
            currentKey = key
            current.append(a)
        }
        if let k = currentKey {
            out.append(MonthSection(id: k, title: k == .distantPast ? "Unknown Date" : fmt.string(from: k), assets: current))
        }
        return out
    }

    // MARK: Hidden / Recently Deleted lock

    /// Same prompt macOS uses for app logins: Touch ID, Apple Watch (double-click the side button,
    /// when "Use Apple Watch to unlock applications" is on) or the account password as a fallback.
    func unlock() async {
        guard requireAuth else { unlocked = true; return }
        guard !authenticating else { return }
        authenticating = true
        defer { authenticating = false }
        authError = nil
        let ctx = LAContext()
        ctx.localizedFallbackTitle = "Use Password…"
        var err: NSError?
        // Stay locked if the Mac can't authenticate at all, rather than letting anyone in.
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else {
            authError = err?.localizedDescription ?? "This Mac can't verify your identity right now."
            return
        }
        do {
            unlocked = try await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "view your Hidden and Recently Deleted photos")
        } catch let e as LAError where e.code == .userCancel || e.code == .systemCancel || e.code == .appCancel {
            unlocked = false
        } catch {
            unlocked = false
            authError = error.localizedDescription
        }
    }

    func lock() {
        unlocked = false
        if selection?.isLocked == true { selectedIDs = [] }
        if let v = viewer, v.assets.first.map({ $0.isHidden || $0.isDeleted }) == true { viewer = nil }
    }

    // MARK: Actions

    func open(_ asset: Asset, in list: [Asset]) {
        guard let i = list.firstIndex(of: asset) else { return }
        viewer = ViewerState(assets: list, index: i)
    }

    /// Shows the files in Finder. Zipped items can only be shown as the zip that holds them.
    func revealInFinder(_ assets: [Asset]) {
        let urls = assets.flatMap { [$0.source.containerURL] + ($0.pairedSource.map { [$0.containerURL] } ?? []) }
        NSWorkspace.shared.activateFileViewerSelecting(Array(Set(urls)))
    }

    /// A real file for the item (unpacking it from its zip into the SSD cache if needed), then `body`.
    func withFile(_ a: Asset, _ body: @escaping @MainActor (URL) -> Void) {
        Task {
            if a.isZipped { busyMessage = "Unpacking \(a.name)…" }
            defer { busyMessage = nil }
            guard let url = try? await MediaAccess.fileURL(a.source) else { return }
            body(url)
        }
    }

    /// Copies originals (and the motion half of Live Photos) to a folder the user picks,
    /// unpacking zipped items straight into the destination.
    func export(_ assets: [Asset]) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Export \(assets.count) Item\(assets.count == 1 ? "" : "s")"
        guard panel.runModal() == .OK, let dest = panel.url else { return }
        busyMessage = "Exporting \(assets.count) item\(assets.count == 1 ? "" : "s")…"
        Task.detached {
            let fm = FileManager.default
            for a in assets {
                for src in [a.source] + (a.pairedSource.map { [$0] } ?? []) {
                    let base = (src.name as NSString).deletingPathExtension, ext = (src.name as NSString).pathExtension
                    var target = dest.appendingPathComponent(src.name)
                    var n = 1
                    while fm.fileExists(atPath: target.path) {
                        target = dest.appendingPathComponent("\(base) (\(n)).\(ext)")
                        n += 1
                    }
                    switch src {
                    case .file(let u): try? fm.copyItem(at: u, to: target)
                    case .zip(let e): try? e.archive.extract(e, to: target)
                    }
                    if a.date != .distantPast {
                        try? fm.setAttributes([.creationDate: a.date, .modificationDate: a.date], ofItemAtPath: target.path)
                    }
                }
            }
            await MainActor.run {
                self.busyMessage = nil
                NSWorkspace.shared.open(dest)
            }
        }
    }
}

// MARK: Editing: favorite, hide, delete, restore

extension LibraryStore {
    /// The items an edit command acts on: the photo open in the viewer, else the selection.
    var targetIDs: [Int] {
        if let v = viewer { return [v.current.id] }
        return selectedIDs.sorted()
    }

    private func edit(_ ids: [Int], _ change: (inout Asset, EditsStore) -> Void) {
        guard let edits, !ids.isEmpty else { return }
        for id in ids { change(&library.assets[id], edits) }
        edits.save()
        invalidate()
        // Keep the open viewer in step with the change.
        if var v = viewer {
            v.assets = v.assets.map { library.assets[$0.id] }
            viewer = v
        }
    }

    func toggleFavorite(_ ids: [Int]) {
        let makeFavorite = !ids.allSatisfy { library.assets[$0].isFavorite }
        edit(ids) { a, e in a.isFavorite = makeFavorite; e.update(a) { $0.favorite = makeFavorite } }
    }

    func setHidden(_ ids: [Int], _ hidden: Bool) {
        edit(ids) { a, e in a.isHidden = hidden; e.update(a) { $0.hidden = hidden } }
        dropFromViewer(ids)
    }

    /// Moves items to Recently Deleted, where they stay for 30 days.
    func moveToTrash(_ ids: [Int]) {
        let now = Date()
        edit(ids) { a, e in
            a.isDeleted = true
            a.deletedAt = now
            e.update(a) { $0.deletedAt = now; $0.restored = nil }
        }
        dropFromViewer(ids)
        selectedIDs.subtract(ids)
    }

    func restore(_ ids: [Int]) {
        edit(ids) { a, e in
            a.isDeleted = false
            a.deletedAt = nil
            e.update(a) { $0.deletedAt = nil; $0.restored = true }
        }
        dropFromViewer(ids)
        selectedIDs.subtract(ids)
    }

    /// Deletes from Photos Clone for good. The bytes stay inside the zip until it is compacted.
    func deleteNow(_ ids: [Int]) {
        edit(ids) { a, e in a.isPurged = true; e.update(a) { $0.purged = true } }
        dropFromViewer(ids)
        selectedIDs.subtract(ids)
    }

    /// Items deleted for good whose bytes are still in the export (for Free Up Space).
    var purgedStats: (count: Int, bytes: Int64) {
        let p = library.assets.filter(\.isPurged)
        return (p.count, p.reduce(0) { $0 + $1.fileSize })
    }

    /// If the photo on screen just left the current view, move on to the next one.
    private func dropFromViewer(_ ids: [Int]) {
        guard var v = viewer else { return }
        let gone = Set(ids)
        guard gone.contains(v.current.id) else { return }
        v.assets.removeAll { gone.contains($0.id) }
        if v.assets.isEmpty { viewer = nil; return }
        v.index = min(v.index, v.assets.count - 1)
        viewer = v
    }
}

// MARK: On-device analysis for search

extension LibraryStore {
    func analysis(_ a: Asset) -> Analysis? { analyses[a.id] }

    /// Loads what earlier sessions already analysed, without running the model.
    private func loadCachedAnalysis() {
        let store = AnalysisStore(root: library.root)
        analysisStore = store
        let assets = library.assets
        analysisTotal = assets.count
        Task {
            var n = 0
            for a in assets { if let c = await store.cached(a.cacheKey) { record(c, for: a.id); n += 1 } }
            analysisDone = n
        }
    }

    /// Called on every search. Starts (or keeps) the model working for the next 10 minutes.
    func wakeAI() {
        guard analyzePhotos, phase == .ready else { return }
        aiAwakeUntil = Date().addingTimeInterval(Self.aiAwakeWindow)
        if analysisTask == nil { startAnalysis() }
    }

    /// Analyses items that don't have results yet, only while awake. Pass 1 labels items from their
    /// 256 px thumbnails (no external-drive reads). Pass 2 reads text in screenshots and document-like
    /// photos from the full image. Stops scheduling work the moment the awake window ends.
    private func startAnalysis() {
        guard let store = analysisStore else { return }
        let assets = library.assets
        analysisTask = Task {
            defer { analysisTask = nil }
            let pending = assets.filter { analyses[$0.id] == nil }
            analysisDone = assets.count - pending.count

            // Pass 1: labels.
            await withTaskGroup(of: (Int, Analysis?).self) { group in
                var it = pending.makeIterator()
                @MainActor func add() -> Bool {
                    guard aiAwake, let a = it.next() else { return false }
                    group.addTask(priority: .utility) {
                        guard let img = await ThumbnailLoader.shared.image(for: a, size: 256),
                              let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return (a.id, nil) }
                        return (a.id, Analysis(labels: PhotoAnalyzer.labels(cg)))
                    }
                    return true
                }
                for _ in 0..<2 { _ = add() }
                var n = 0
                while let (id, result) = await group.next() {
                    if let result {
                        analysisDone += 1
                        record(result, for: id)
                        // Items that still need a text pass are cached after it.
                        if !PhotoAnalyzer.needsText(assets[id], labels: result.labels) {
                            await store.store(result, key: assets[id].cacheKey)
                        }
                    }
                    _ = add()
                    n += 1
                    if n % 500 == 0 { invalidateIfSearching() }
                }
            }
            await store.save()
            invalidateIfSearching()

            // Pass 2: text, for screenshots and photos that look like documents, receipts, signs…
            let needText = assets.filter { a in
                guard let an = analyses[a.id] else { return false }
                return an.text == nil && PhotoAnalyzer.needsText(a, labels: an.labels)
            }
            textTotal = needText.count
            textDone = 0
            await withTaskGroup(of: (Int, String?).self) { group in
                var it = needText.makeIterator()
                @MainActor func add() -> Bool {
                    guard aiAwake, let a = it.next() else { return false }
                    group.addTask(priority: .background) {
                        guard let img = await ThumbnailLoader.displayImage(a.source, maxPixel: 2048),
                              let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return (a.id, nil) }
                        return (a.id, PhotoAnalyzer.text(cg))
                    }
                    return true
                }
                _ = add()
                var n = 0
                while let (id, text) = await group.next() {
                    textDone += 1
                    if let text, var an = analyses[id] {
                        an.text = text
                        record(an, for: id)
                        await store.store(an, key: assets[id].cacheKey)
                    }
                    _ = add()
                    n += 1
                    if n % 100 == 0 { invalidateIfSearching() }
                }
            }
            await store.save()
            invalidateIfSearching()
        }
    }

    private func record(_ a: Analysis, for id: Int) {
        analyses[id] = a
        if let t = a.text, !t.isEmpty {
            foldedText[id] = t.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).lowercased()
        }
    }

    private func invalidateIfSearching() {
        if !searchText.isEmpty { invalidate() }
    }
}

/// A search split into words, with each word's possible meanings worked out once.
struct SearchQuery {
    struct Word {
        let text: String
        let labels: Set<String>
        let kind: ((Asset) -> Bool)?
    }
    let phrase: String
    let words: [Word]

    static let stopWords: Set<String> = ["the", "a", "an", "of", "in", "at", "on", "with", "and", "my", "me", "from",
                                         "photo", "photos", "picture", "pictures", "pic", "pics", "show", "find", "some"]

    init(_ q: String) {
        phrase = q.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).lowercased()
        words = phrase.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
            .filter { !Self.stopWords.contains($0) }
            .map { w in
                let kind: ((Asset) -> Bool)? = switch w {
                case "video", "videos": { $0.kind == .video }
                case "live": { $0.kind == .livePhoto }
                case "screenshot", "screenshots": { $0.isScreenshot }
                case "favorite", "favorites", "favourite", "favourites": { $0.isFavorite }
                case "recording", "recordings": { $0.isScreenRecording }
                case "gif", "gifs", "animated": { $0.isAnimated }
                default: nil
                }
                return Word(text: w, labels: PhotoAnalyzer.labels(for: w), kind: kind)
            }
    }
}

extension LibraryStore {
    func runStorageCheck() {
        guard storageStatus == nil else { return }
        storageStatus = "Starting…"
        let root = library.root, zips = library.zips
        Task.detached(priority: .userInitiated) {
            let result = StorageCheck.run(root: root, zips: zips) { msg in
                Task { @MainActor in self.storageStatus = msg }
            }
            await MainActor.run {
                self.storageReport = result
                self.storageStatus = nil
            }
        }
    }

    /// Makes grid thumbnails for everything now, while the fast unzipped copies still exist, so
    /// zipped videos never need unpacking just to show a thumbnail. Runs once; later runs only
    /// fill in what's missing.
    func prebuildThumbnails() {
        guard !thumbsRunning else { return }
        thumbsRunning = true
        let assets = library.assets.filter { $0.fileSize > 0 }
        thumbsTotal = assets.count
        thumbsDone = 0
        let infoStore = MediaInfoStore(root: library.root)
        Task {
            await withTaskGroup(of: Void.self) { group in
                var it = assets.makeIterator()
                func add(_ a: Asset) {
                    group.addTask(priority: .utility) {
                        _ = await ThumbnailLoader.shared.image(for: a, size: 256, keepInMemory: false, allowUnpack: true)
                    }
                }
                for _ in 0..<8 { if let a = it.next() { add(a) } }
                while await group.next() != nil {
                    thumbsDone += 1
                    if let a = it.next() { add(a) }
                }
            }
            // Videos that only exist inside the zips: now that they're unpacked, record their
            // length and date too, so the grid can show durations without unpacking again.
            var found: [Int: MediaInfo] = [:]
            for a in assets where a.kind == .video && a.isZipped && infos[a.id]?.duration == nil {
                if let info = await MediaInfoReader.read(a) {
                    found[a.id] = info
                    await infoStore.store(info, for: a)
                }
            }
            await infoStore.save()
            for (id, info) in found { infos[id] = info }
            thumbsRunning = false
        }
    }
}

struct ViewerState: Equatable {
    var assets: [Asset]
    var index: Int
    var current: Asset { assets[index] }
}
