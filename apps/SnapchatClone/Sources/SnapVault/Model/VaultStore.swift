import AppKit
import Observation

enum Tab: String, CaseIterable, Identifiable {
    case snaps = "Snaps", stories = "Stories", chats = "Chats", eyesOnly = "My Eyes Only"
    var id: String { rawValue }
}

/// A run of memories from one day, shown as a story card (Snapchat groups Memories the same way).
struct DayStory: Identifiable, Hashable {
    let id: Date
    let snapIDs: [Int]
    var title: String { id.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year()) }
}

struct Flashback: Identifiable {
    let id: Int          // years ago
    let snapIDs: [Int]
}

/// What's playing full screen: a single snap with neighbours, or a story that auto-advances.
struct Playback: Equatable {
    var snaps: [Snap]
    var index: Int
    var isStory: Bool
    var title: String?
    var current: Snap { snaps[index] }
}

@MainActor
@Observable
final class VaultStore {
    /// One store for the app. SwiftUI may build the App value more than once, and each extra
    /// store would scan the export and start its own background work.
    static let shared = VaultStore()

    enum Phase: Equatable { case welcome, scanning(String), ready }

    var phase: Phase = .welcome
    var library = SnapLibrary(root: URL(fileURLWithPath: "/"))
    var tab: Tab = .snaps {
        didSet { if oldValue == .eyesOnly && tab != .eyesOnly { lock.lock() } }
    }
    var conversation: String? = nil
    var searchText = ""
    var tileWidth: Double = 130
    var playback: Playback?
    var selected: Set<Int> = []
    var eyesOnly: Set<String> = []
    var videoInfo: [String: VideoInfo] = [:]
    var prepared = 0
    var preparing = 0
    let lock = EyesOnlyLock()

    @ObservationIgnored private var infoFile: URL { Paths.support.appendingPathComponent("videos-\(stableHash(library.root.path)).json") }
    @ObservationIgnored private var editsFile: URL { Paths.support.appendingPathComponent("eyes-only-\(stableHash(library.root.path)).json") }

    var root: URL? {
        get { UserDefaults.standard.string(forKey: "root").map { URL(fileURLWithPath: $0) } }
        set { UserDefaults.standard.set(newValue?.path, forKey: "root") }
    }

    init(autoOpen: Bool = true) {
        if autoOpen, let r = root, FileManager.default.fileExists(atPath: r.path) { open(r) }
        let ws = NSWorkspace.shared.notificationCenter
        for n in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            ws.addObserver(forName: n, object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.lockEyesOnly() } }
        }
        DistributedNotificationCenter.default().addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.lockEyesOnly() }
        }
    }

    func open(_ url: URL) {
        root = url
        phase = .scanning("Opening…")
        Task.detached(priority: .userInitiated) {
            let lib = SnapScanner.scan(root: url) { msg in Task { @MainActor in self.phase = .scanning(msg) } }
            await MainActor.run { self.loaded(lib) }
        }
    }

    /// Loads a scanned library without the background thumbnail pass (for `--check`).
    func loadForChecking(_ lib: SnapLibrary) { loaded(lib, prepare: false) }

    private func loaded(_ lib: SnapLibrary, prepare: Bool = true) {
        library = lib
        videoInfo = (try? JSONDecoder().decode([String: VideoInfo].self, from: Data(contentsOf: infoFile))) ?? [:]
        eyesOnly = Set((try? JSONDecoder().decode([String].self, from: Data(contentsOf: editsFile))) ?? [])
        applyVideoTimes()
        phase = .ready
        if prepare { prepareInBackground() }
    }

    /// Videos record their own time; use it when it falls on the file name's day (or for
    /// shared-story posts, which have no day in their name).
    private func applyVideoTimes() {
        for i in library.snaps.indices where library.snaps[i].isVideo && library.snaps[i].time == nil {
            guard let rec = videoInfo[library.snaps[i].cacheKey]?.recorded else { continue }
            let s = library.snaps[i]
            if s.origin == .story || (rec >= s.day && rec < s.day.addingTimeInterval(86_400)) {
                library.snaps[i].time = rec
            }
        }
    }

    /// Saves thumbnails and video times for everything once, reading each file a single time.
    private func prepareInBackground() {
        // Voice notes have no picture; once known, don't try again.
        let todo = library.snaps.filter { s in
            let info = videoInfo[s.cacheKey]
            if s.isVideo && info?.hasVideo == false { return false }
            return !Thumbnails.shared.isOnDisk(s, size: 256) || (s.isVideo && (info == nil || info?.hasVideo == nil))
        }
        preparing = todo.count
        prepared = 0
        guard !todo.isEmpty else { return }
        Task {
            await withTaskGroup(of: (String, VideoInfo?).self) { group in
                var it = todo.makeIterator()
                func add(_ s: Snap) {
                    group.addTask(priority: .utility) {
                        nonisolated(unsafe) var found: VideoInfo?
                        _ = await Thumbnails.shared.image(s, size: 256, info: s.isVideo ? { found = $0 } : nil)
                        return (s.cacheKey, found)
                    }
                }
                for _ in 0..<3 { if let s = it.next() { add(s) } }
                while let (key, info) = await group.next() {
                    prepared += 1
                    if let info { videoInfo[key] = info }
                    if prepared % 200 == 0 { saveVideoInfo() }
                    if let s = it.next() { add(s) }
                }
            }
            saveVideoInfo()
            applyVideoTimes()
            preparing = 0
        }
    }

    private func saveVideoInfo() {
        if let d = try? JSONEncoder().encode(videoInfo) { try? d.write(to: infoFile, options: .atomic) }
    }

    // MARK: Queries

    func snap(_ id: Int) -> Snap { library.snaps[id] }
    func duration(_ s: Snap) -> Double? { videoInfo[s.cacheKey]?.duration }
    func isVoiceNote(_ s: Snap) -> Bool { s.isVideo && videoInfo[s.cacheKey]?.hasVideo == false }
    func isEyesOnly(_ s: Snap) -> Bool { eyesOnly.contains(s.cacheKey) }

    private func visible(_ s: Snap) -> Bool { !isEyesOnly(s) && matches(s) }

    private func matches(_ s: Snap) -> Bool {
        let q = searchText.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return true }
        let text = [s.date.formatted(.dateTime.month(.wide).year().day().weekday(.wide)),
                    s.conversation.flatMap { c in library.conversations.first { $0.id == c }?.title } ?? "",
                    s.sender ?? "", isVoiceNote(s) ? "voice note audio" : s.isVideo ? "video" : "photo"].joined(separator: " ")
        return q.split(separator: " ").allSatisfy { text.localizedCaseInsensitiveContains($0) }
    }

    /// Newest first, like Snapchat.
    private func newestFirst(_ list: [Snap]) -> [Snap] { list.sorted { $0.date > $1.date } }

    var memories: [Snap] { newestFirst(library.snaps.filter { $0.origin == .memory && visible($0) }) }

    var eyesOnlySnaps: [Snap] { newestFirst(library.snaps.filter { isEyesOnly($0) && matches($0) }) }

    func chatSnaps(_ conversation: String?) -> [Snap] {
        switch conversation {
        case nil: newestFirst(library.snaps.filter { $0.origin == .chat && visible($0) })
        case "saved": newestFirst(library.snaps.filter { $0.origin == .saved && visible($0) })
        case let c?: newestFirst(library.snaps.filter { $0.conversation == c && visible($0) })
        }
    }

    var sharedStory: [Snap] { library.snaps.filter { $0.origin == .story && visible($0) }.sorted { $0.date < $1.date } }

    /// Days with at least three memories become story cards.
    var dayStories: [DayStory] {
        let cal = Calendar.current
        let groups = Dictionary(grouping: memories, by: { cal.startOfDay(for: $0.date) })
        return groups.filter { $0.value.count >= 3 }
            .map { DayStory(id: $0.key, snapIDs: $0.value.sorted { $0.date < $1.date }.map(\.id)) }
            .sorted { $0.id > $1.id }
    }

    /// Memories from this day in earlier years (never from My Eyes Only).
    var flashbacks: [Flashback] {
        let cal = Calendar.current
        let today = cal.dateComponents([.month, .day, .year], from: Date())
        var byYears: [Int: [Int]] = [:]
        for s in library.snaps where s.origin == .memory && !isEyesOnly(s) {
            let c = cal.dateComponents([.month, .day, .year], from: s.date)
            if c.month == today.month, c.day == today.day, let y = c.year, let ty = today.year, y < ty {
                byYears[ty - y, default: []].append(s.id)
            }
        }
        return byYears.map { Flashback(id: $0.key, snapIDs: $0.value.sorted { snap($0).date < snap($1).date }) }.sorted { $0.id < $1.id }
    }

    func title(for conversation: String) -> String {
        library.conversations.first { $0.id == conversation }?.title ?? conversation
    }

    // MARK: Actions

    func play(_ snaps: [Snap], from index: Int = 0, story: Bool, title: String? = nil) {
        guard !snaps.isEmpty else { return }
        playback = Playback(snaps: snaps, index: index, isStory: story, title: title)
    }

    func toggleEyesOnly(_ snaps: [Snap]) {
        let moveIn = !snaps.allSatisfy(isEyesOnly)
        for s in snaps { if moveIn { eyesOnly.insert(s.cacheKey) } else { eyesOnly.remove(s.cacheKey) } }
        if let d = try? JSONEncoder().encode(eyesOnly.sorted()) { try? d.write(to: editsFile, options: .atomic) }
        selected = []
        // Leave the viewer if the snap on screen just moved out of this view.
        if var p = playback, snaps.contains(p.current) {
            p.snaps.removeAll { snaps.contains($0) }
            if p.snaps.isEmpty { playback = nil } else { p.index = min(p.index, p.snaps.count - 1); playback = p }
        }
    }

    func lockEyesOnly() {
        lock.lock()
        if tab == .eyesOnly { playback = nil; selected = [] }
    }

    func revealInFinder(_ snaps: [Snap]) {
        NSWorkspace.shared.activateFileViewerSelecting(Array(Set(snaps.map(\.source.containerURL))))
    }
}
