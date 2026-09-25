import Foundation

/// Everything read from a Snapchat "Download My Data" export.
///
/// Snapchat splits the export into mydata~<id>.zip, mydata~<id>-1.zip … Each holds some of:
///   memories/YYYY-MM-DD_<UUID>-main.jpg|mp4     a saved snap
///   memories/YYYY-MM-DD_<UUID>-overlay.png      its caption/sticker layer (same UUID)
///   memories/memories.html                      a grid with only the day per item
///   chat_media/YYYY-MM-DD_b~<id>.jpeg|mp4|png…   media from chats; <id> appears in the
///                                               "Media IDs" of a chat_history.json message
///   chat_media/YYYY-MM-DD_media~zip-<UUID>.ext  older saved snaps / Discover (also overlay~,
///                                               thumbnail~, metadata~ parts with their own UUIDs)
///   shared_story/<uuid>.mp4                     shared story posts
///   json/chat_history.json, json/friends.json   conversations and display names
/// Days in file names are UTC. There are no locations and no times except in chats and videos.
struct SnapLibrary {
    var root: URL
    var snaps: [Snap] = []
    var conversations: [Conversation] = []
    /// Every message, oldest first, per conversation key.
    var messages: [String: [ChatMessage]] = [:]
    /// Chat media by the "b~…" id messages use.
    var snapByMediaID: [String: Int] = [:]
    var zips: [ZipArchive] = []
    var unlinkedChatMedia = 0
    var scanDuration: TimeInterval = 0
}

enum SnapScanner {
    private struct Node { let source: MediaSource; let path: String; let size: Int64 }
    private struct ChatRef { let conversation: String; let from: String; let mine: Bool; let time: Date }

    static let imageExts: Set<String> = ["jpg", "jpeg", "png", "webp", "gif", "heic"]
    static let videoExts: Set<String> = ["mp4", "mov", "m4v"]

    /// Folders under `root` that look like Snapchat exports (for the welcome screen).
    static func suggestedRoots() -> [URL] {
        let fm = FileManager.default
        var bases = [fm.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")]
        if let vols = try? fm.contentsOfDirectory(at: URL(fileURLWithPath: "/Volumes"), includingPropertiesForKeys: nil) { bases += vols }
        var found: [URL] = []
        for base in bases {
            let e = fm.enumerator(at: base, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles, .skipsPackageDescendants])
            while let u = e?.nextObject() as? URL {
                if e!.level > 5 { e?.skipDescendants(); continue }
                if u.lastPathComponent.hasPrefix("mydata~") {
                    found.append(u.deletingLastPathComponent())
                    e?.skipDescendants()
                }
            }
        }
        var seen = Set<String>()
        return found.filter { seen.insert($0.path).inserted }
    }

    static func scan(root: URL, progress: @escaping (String) -> Void) -> SnapLibrary {
        let start = Date()
        var lib = SnapLibrary(root: root)
        let fm = FileManager.default

        // 1. Collect files by their path inside the export ("memories/…"), unzipped copies first.
        progress("Looking through the export…")
        var nodes: [String: Node] = [:]
        var zipURLs: [URL] = []
        let walker = fm.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey], options: [.skipsHiddenFiles])
        while let u = walker?.nextObject() as? URL {
            let name = u.lastPathComponent
            if name.hasPrefix("._") { continue }
            if u.pathExtension == "zip", name.hasPrefix("mydata~") { zipURLs.append(u); continue }
            guard let exportDir = u.pathComponents.lastIndex(where: { $0.hasPrefix("mydata~") }),
                  (try? u.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true else { continue }
            let rel = u.pathComponents[(exportDir + 1)...].joined(separator: "/")
            let size = Int64((try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            nodes[rel] = Node(source: .file(u), path: rel, size: size)
        }
        for z in zipURLs.sorted(by: { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }) {
            progress("Opening \(z.lastPathComponent)…")
            guard let zip = try? ZipArchive(url: z) else { continue }
            lib.zips.append(zip)
            for e in zip.entries where !e.name.hasPrefix("._") {
                // Snapchat writes "memories//memories.html"; collapse the double slash.
                let rel = e.path.replacingOccurrences(of: "//", with: "/")
                if nodes[rel] == nil { nodes[rel] = Node(source: .zip(e), path: rel, size: Int64(e.size)) }
            }
        }

        // 2. Chats: which conversation each media ID belongs to, who sent it and when.
        progress("Reading chats…")
        var names: [String: String] = [:]
        if let n = nodes["json/friends.json"], let data = try? MediaAccess.data(n.source),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for case let list as [[String: Any]] in json.values {
                for f in list {
                    if let u = f["Username"] as? String, let d = f["Display Name"] as? String, !d.isEmpty { names[u] = d }
                }
            }
        }
        var chatRefs: [String: ChatRef] = [:]
        var titles: [String: String] = [:]
        var messages: [String: [ChatMessage]] = [:]
        var messageID = 0
        let created = DateFormatter()
        created.locale = Locale(identifier: "en_US_POSIX")
        created.timeZone = TimeZone(identifier: "UTC")
        created.dateFormat = "yyyy-MM-dd HH:mm:ss 'UTC'"
        func time(_ m: [String: Any]) -> Date {
            if let micros = m["Created(microseconds)"] as? Double, micros > 0 { return Date(timeIntervalSince1970: micros / 1_000_000) }
            return (m["Created"] as? String).flatMap(created.date) ?? .distantPast
        }
        for (file, kindOverride) in [("json/chat_history.json", nil as ChatMessage.Kind?), ("json/snap_history.json", .snap)] {
            guard let n = nodes[file], let data = try? MediaAccess.data(n.source),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: [[String: Any]]] else { continue }
            for (key, list) in json {
                for m in list {
                    if let t = m["Conversation Title"] as? String, !t.isEmpty { titles[key] = t }
                    let ids = (m["Media IDs"] as? String ?? "").split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                    let from = m["From"] as? String ?? ""
                    let mine = m["IsSender"] as? Bool ?? false
                    let t = time(m)
                    let kind = kindOverride ?? ChatMessage.Kind(rawValue: m["Media Type"] as? String ?? "") ?? .other
                    messages[key, default: []].append(ChatMessage(id: messageID, time: t, from: from, mine: mine, kind: kind,
                                                                  text: m["Content"] as? String ?? "", mediaIDs: ids,
                                                                  saved: m["IsSaved"] as? Bool ?? false))
                    messageID += 1
                    for id in ids { chatRefs[id] = ChatRef(conversation: key, from: from, mine: mine, time: t) }
                }
            }
        }
        func display(_ user: String) -> String { names[user] ?? user }

        // 3. Build snaps.
        progress("Building your memories…")
        let dayFormat = DateFormatter()
        dayFormat.locale = Locale(identifier: "en_US_POSIX")
        dayFormat.timeZone = TimeZone(identifier: "UTC")
        dayFormat.dateFormat = "yyyy-MM-dd"
        func day(_ s: String) -> Date? { dayFormat.date(from: String(s.prefix(10))) }

        var overlays: [String: MediaSource] = [:]
        for n in nodes.values where n.path.hasPrefix("memories/") && n.path.hasSuffix("-overlay.png") {
            if let uuid = memoryUUID(n.path) { overlays[uuid] = n.source }
        }
        var snaps: [Snap] = []
        var byConversation: [String: [Int]] = [:]
        for n in nodes.values.sorted(by: { $0.path < $1.path }) {
            let file = (n.path as NSString).lastPathComponent
            var ext = (file as NSString).pathExtension.lowercased()
            if n.path.hasPrefix("memories/") {
                guard file.contains("-main."), let d = day(file) else { continue }
                let isVideo = videoExts.contains(ext)
                guard isVideo || imageExts.contains(ext) else { continue }
                var s = Snap(id: snaps.count, source: n.source, isVideo: isVideo, origin: .memory, day: d, size: n.size)
                s.overlay = memoryUUID(n.path).flatMap { overlays[$0] }
                snaps.append(s)
            } else if n.path.hasPrefix("chat_media/") {
                guard let d = day(file), n.size > 0 else { continue }
                if ext == "unknown" { ext = sniff(n.source) ?? ext }
                let isVideo = videoExts.contains(ext)
                guard isVideo || imageExts.contains(ext) else { continue }
                let stem = (String(file.dropFirst(11)) as NSString).deletingPathExtension
                if stem.hasPrefix("b~") {
                    var s = Snap(id: snaps.count, source: n.source, isVideo: isVideo, origin: .chat, day: d, size: n.size)
                    s.mediaID = stem
                    lib.snapByMediaID[stem] = s.id
                    if let ref = chatRefs[stem] {
                        s.conversation = ref.conversation
                        s.sender = display(ref.from)
                        s.sentByMe = ref.mine
                        if ref.time.timeIntervalSince1970 > 0 { s.time = ref.time }
                        byConversation[ref.conversation, default: []].append(s.id)
                    } else {
                        lib.unlinkedChatMedia += 1
                    }
                    snaps.append(s)
                } else if stem.hasPrefix("media~") {
                    snaps.append(Snap(id: snaps.count, source: n.source, isVideo: isVideo, origin: .saved, day: d, size: n.size))
                }
                // overlay~/thumbnail~/metadata~ parts have their own UUIDs and can't be matched to media.
            } else if n.path.hasPrefix("shared_story/") {
                guard videoExts.contains(ext) || imageExts.contains(ext) else { continue }
                // Story IDs in shared_story.json don't match these file names; the videos' own
                // recorded date is filled in when they're read (VaultStore).
                snaps.append(Snap(id: snaps.count, source: n.source, isVideo: videoExts.contains(ext), origin: .story, day: .distantPast, size: n.size))
            }
        }
        lib.snaps = snaps
        // Friends' names on messages, and every conversation (not only those with media).
        lib.messages = messages.mapValues { list in
            list.map { m in ChatMessage(id: m.id, time: m.time, from: display(m.from), mine: m.mine, kind: m.kind,
                                        text: m.text, mediaIDs: m.mediaIDs, saved: m.saved) }
                .sorted { $0.time < $1.time }
        }
        let keys = Set(messages.keys).union(byConversation.keys)
        lib.conversations = keys.map { key in
            var c = Conversation(id: key, title: titles[key] ?? display(key), snapIDs: byConversation[key] ?? [])
            c.messageCount = lib.messages[key]?.count ?? 0
            c.lastActivity = lib.messages[key]?.last?.time ?? .distantPast
            c.isGroup = titles[key] != nil
            return c
        }.sorted { $0.lastActivity > $1.lastActivity }
        lib.scanDuration = Date().timeIntervalSince(start)
        return lib
    }

    /// "memories/2019-06-15_6B4A0BA8-…-main.mp4" -> "6B4A0BA8-…"
    private static func memoryUUID(_ path: String) -> String? {
        let file = (path as NSString).lastPathComponent
        guard file.count > 11 else { return nil }
        let rest = String(file.dropFirst(11))
        guard let dash = rest.range(of: "-main.") ?? rest.range(of: "-overlay.") else { return nil }
        return String(rest[..<dash.lowerBound])
    }

    /// Snapchat labels some chat files ".unknown"; tell images from videos by their first bytes.
    private static func sniff(_ s: MediaSource) -> String? {
        guard let d = try? MediaAccess.data(s, limit: 16), d.count >= 12 else { return nil }
        let b = [UInt8](d)
        if b[0] == 0xFF && b[1] == 0xD8 { return "jpg" }
        if b[0] == 0x89 && b[1] == 0x50 { return "png" }
        if b[0] == 0x52 && b[1] == 0x49 && b[8] == 0x57 { return "webp" }
        if b[4] == 0x66 && b[5] == 0x74 && b[6] == 0x79 && b[7] == 0x70 { return "mp4" }
        return nil
    }
}
