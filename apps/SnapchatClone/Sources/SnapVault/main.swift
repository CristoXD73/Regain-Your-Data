import Foundation

// `SnapVault --scan <folder>` prints what the scanner finds, without opening a window.
if let i = CommandLine.arguments.firstIndex(of: "--scan"), i + 1 < CommandLine.arguments.count {
    let lib = SnapScanner.scan(root: URL(fileURLWithPath: CommandLine.arguments[i + 1])) { _ in }
    let s = lib.snaps
    func n(_ f: (Snap) -> Bool) -> Int { s.filter(f).count }
    let years = Dictionary(grouping: s.filter { $0.origin == .memory }, by: { Calendar(identifier: .gregorian).component(.year, from: $0.day) }).mapValues(\.count).sorted { $0.key < $1.key }
    print("""
    zips: \(lib.zips.count)  scan \(String(format: "%.1f", lib.scanDuration))s
    memories: \(n { $0.origin == .memory }) (videos \(n { $0.origin == .memory && $0.isVideo }), with overlay \(n { $0.overlay != nil }))
    chat media: \(n { $0.origin == .chat }) (linked to a chat \(n { $0.conversation != nil }), not linked \(lib.unlinkedChatMedia), sent by me \(n { $0.sentByMe }))
    saved/Discover media: \(n { $0.origin == .saved })   shared story: \(n { $0.origin == .story })
    conversations with media: \(lib.conversations.count), top sizes: \(lib.conversations.prefix(5).map(\.snapIDs.count))
    memories per year: \(years.map { "\($0.key):\($0.value)" }.joined(separator: " "))
    duplicate cache keys: \(Dictionary(grouping: s, by: \.cacheKey).filter { $0.value.count > 1 }.count)
    """)
    exit(0)
}

// `SnapVault --media-test <folder>` reads a few zipped clips from memory (no disk writes).
if let i = CommandLine.arguments.firstIndex(of: "--media-test"), i + 1 < CommandLine.arguments.count {
    let lib = SnapScanner.scan(root: URL(fileURLWithPath: CommandLine.arguments[i + 1])) { _ in }
    let sem = DispatchSemaphore(value: 0)
    Task.detached {
        let clips = lib.snaps.filter { $0.isVideo && $0.source.isZipped }.shuffled().prefix(6)
        for s in clips {
            let t = Date()
            var info = VideoInfo()
            let img = await Thumbnails.shared.image(s, size: 256) { info = $0 }
            print(String(format: "%@ %@ %.1f MB: frame %@, %.1fs long, recorded %@, overlay %@ (%.2fs)",
                         s.origin.rawValue, s.name.prefix(10) as CVarArg, Double(s.size) / 1e6, img == nil ? "NO" : "\(Int(img!.size.width))x\(Int(img!.size.height))",
                         info.duration ?? -1, info.recorded.map { "\($0)" } ?? "-", s.overlay == nil ? "no" : "yes", Date().timeIntervalSince(t)))
        }
        let withOverlay = lib.snaps.first { $0.overlay != nil && !$0.isVideo }
        if let o = withOverlay { print("photo with overlay composited:", await Thumbnails.shared.image(o, size: 256) != nil) }
        sem.signal()
    }
    sem.wait()
    exit(0)
}

// `SnapVault --check <folder>` loads the export through the app's own logic and prints what
// each tab would show (counts only).
if let i = CommandLine.arguments.firstIndex(of: "--check"), i + 1 < CommandLine.arguments.count {
    MainActor.assumeIsolated {
        let store = VaultStore(autoOpen: false)
        store.loadForChecking(SnapScanner.scan(root: URL(fileURLWithPath: CommandLine.arguments[i + 1])) { _ in })
        let mem = store.memories
        print("Snaps tab: \(mem.count) memories, newest \(mem.first?.date.formatted(date: .abbreviated, time: .omitted) ?? "-"), oldest \(mem.last?.date.formatted(date: .abbreviated, time: .omitted) ?? "-")")
        print("videos with a known length: \(store.library.snaps.filter { $0.isVideo && store.duration($0) != nil }.count) of \(store.library.snaps.filter(\.isVideo).count)")
        print("Flashbacks today: \(store.flashbacks.map { "\($0.id)y:\($0.snapIDs.count)" })")
        let days = store.dayStories
        print("Stories tab: \(days.count) day stories (\(days.reduce(0) { $0 + $1.snapIDs.count }) snaps), biggest \(days.map(\.snapIDs.count).max() ?? 0); shared story \(store.sharedStory.count)")
        let msgs = store.library.messages.values.flatMap { $0 }
        let kinds = Dictionary(grouping: msgs, by: \.kind.rawValue).mapValues(\.count).sorted { $0.value > $1.value }
        let mediaMsgs = msgs.filter { !$0.mediaIDs.isEmpty }
        let resolved = mediaMsgs.filter { m in m.mediaIDs.contains { store.library.snapByMediaID[$0] != nil } }
        print("messages: \(msgs.count) in \(store.library.messages.count) conversations; kinds \(kinds.map { "\($0.key)=\($0.value)" }.joined(separator: " "))")
        print("messages with media: \(mediaMsgs.count), whose media is in the export: \(resolved.count); saved messages: \(msgs.filter(\.saved).count); undated: \(msgs.filter { $0.time == .distantPast }.count)")
        print("conversations listed: \(store.library.conversations.count) (groups \(store.library.conversations.filter(\.isGroup).count))")
        print("Chats tab: all \(store.chatSnaps(nil).count), saved \(store.chatSnaps("saved").count), friends \(store.library.conversations.count)")
        store.searchText = "2018"
        print("search '2018': \(store.memories.count) memories")
        store.searchText = "July 2020"
        print("search 'July 2020': \(store.memories.count) memories")
        store.searchText = ""
        print("voice notes: \(store.library.snaps.filter(store.isVoiceNote).count)")
        let missing = store.library.snaps.filter { !Thumbnails.shared.isOnDisk($0, size: 256) && !store.isVoiceNote($0) }
        print("no thumbnail: \(missing.count) by origin \(Dictionary(grouping: missing, by: \.origin.rawValue).mapValues(\.count)), videos \(missing.filter(\.isVideo).count), zipped \(missing.filter { $0.source.isZipped }.count)")
        print("  e.g. \(missing.prefix(6).map { "\($0.name) \($0.size / 1000)KB" })")
        print("My Eyes Only items: \(store.eyesOnlySnaps.count); lock state: \(store.lock.state)")
    }
    exit(0)
}

SnapVaultApp.main()
