import AppKit
import ImageIO
import ObjectiveC
import AVFoundation
import Observation

/// Opened zips, so media can be read by path.
final class ZipLibrary: @unchecked Sendable {
    static let shared = ZipLibrary()
    private var zips: [URL: (ZipArchive, [String: ZipEntry])] = [:]
    private let lock = NSLock()

    func entry(_ path: String, in zip: URL) -> ZipEntry? {
        lock.lock(); defer { lock.unlock() }
        if zips[zip] == nil, let z = try? ZipArchive(url: zip) {
            zips[zip] = (z, Dictionary(z.entries.map { ($0.path, $0) }, uniquingKeysWith: { a, _ in a }))
        }
        return zips[zip]?.1[path]
    }
}

struct Viewer: Equatable {
    var items: [Media]
    var index: Int
    var current: Media { items[index] }
}

@MainActor
@Observable
final class InstaStore {
    /// One store for the app (SwiftUI may build the App value more than once).
    static let shared = InstaStore()

    enum Phase: Equatable { case welcome, loading(String), ready }
    var phase: Phase = .welcome
    var accounts: [Account] = []
    var accountID: String? { didSet { folder = .inbox; openLatest() } }
    var folder: Thread.Folder = .inbox { didSet { openLatest() } }
    var threadID: String?
    var search = ""
    enum Section { case messages, media, profile }
    var section: Section = .messages
    var showMedia = false
    var viewer: Viewer?
    /// Names you gave "Instagram User" chats, by "account|thread".
    var renames: [String: String] = (try? JSONDecoder().decode([String: String].self, from: Data(contentsOf: InstaStore.renamesFile))) ?? [:]
    var gradientBackground = UserDefaults.standard.object(forKey: "gradient") as? Bool ?? true {
        didSet { UserDefaults.standard.set(gradientBackground, forKey: "gradient") }
    }
    static var renamesFile: URL { Paths.support.appendingPathComponent("renames.json") }

    var root: URL? {
        get { UserDefaults.standard.string(forKey: "root").map { URL(fileURLWithPath: $0) } }
        set { UserDefaults.standard.set(newValue?.path, forKey: "root") }
    }

    init() {
        if let r = root, FileManager.default.fileExists(atPath: r.path) { open(r) }
    }

    func open(_ url: URL) {
        root = url
        phase = .loading("Looking for Instagram exports…")
        Task.detached(priority: .userInitiated) {
            let zips = InstagramScanner.accounts(under: url)
            await MainActor.run { self.phase = .loading("Reading \(zips.count) account\(zips.count == 1 ? "" : "s")…") }
            // Accounts load in parallel; each is parsed once, then read from its saved copy.
            let loaded = await withTaskGroup(of: Account?.self) { group in
                for (n, z) in zips.enumerated() { group.addTask { try? InstagramScanner.loadCached(z, idBase: n * 10_000_000) } }
                var out: [Account] = []
                for await a in group { if let a { out.append(a) } }
                return out.sorted { $0.threads.count > $1.threads.count }
            }
            await MainActor.run {
                self.accounts = loaded
                self.accountID = UserDefaults.standard.string(forKey: "account").flatMap { id in loaded.first { $0.id == id }?.id } ?? loaded.first?.id
                self.phase = loaded.isEmpty ? .welcome : .ready
            }
        }
    }

    var account: Account? { accounts.first { $0.id == accountID } }

    /// Opens the most recent conversation, so the window never starts empty.
    private func openLatest() { threadID = threads.first?.id }

    func select(account id: String) {
        accountID = id
        UserDefaults.standard.set(id, forKey: "account")
    }

    /// Conversations in the current folder, newest first; search matches names and message text.
    var threads: [Thread] {
        guard let a = account else { return [] }
        let list = a.threads.filter { effectiveFolder($0) == folder }
        let q = search.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return list }
        return list.filter { t in
            title(t).localizedCaseInsensitiveContains(q) || t.messages.contains { $0.text.localizedCaseInsensitiveContains(q) }
        }
    }

    var thread: Thread? { account?.threads.first { $0.id == threadID } }

    func count(_ f: Thread.Folder) -> Int { account?.threads.filter { effectiveFolder($0) == f }.count ?? 0 }

    // MARK: "Instagram User" chats

    private func renameKey(_ t: Thread) -> String { "\(accountID ?? "")|\(t.id)" }

    /// A chat with an account that no longer exists: Instagram names it "Instagram User".
    func isUnknownUser(_ t: Thread) -> Bool {
        t.title == "Instagram User" || (!t.isGroup && t.participants.filter { $0 != account?.owner }.allSatisfy { $0 == "Instagram User" } && !t.participants.isEmpty)
    }

    func renamed(_ t: Thread) -> String? { renames[renameKey(t)] }

    /// The name shown for a chat: yours if you named it.
    func title(_ t: Thread) -> String { renamed(t) ?? t.title }

    /// Unnamed "Instagram User" chats go to their own tab; once named they join Messages.
    func effectiveFolder(_ t: Thread) -> Thread.Folder {
        guard isUnknownUser(t) else { return t.folder }
        return renamed(t) == nil ? .unknown : .inbox
    }

    /// The sender name to show: your name for them replaces "Instagram User".
    func senderName(_ m: Message, in t: Thread) -> String {
        if m.sender == "Instagram User", let n = renamed(t) { return n }
        return m.sender
    }

    func rename(_ t: Thread, to name: String?) {
        let clean = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        renames[renameKey(t)] = (clean?.isEmpty ?? true) ? nil : clean
        if let d = try? JSONEncoder().encode(renames) { try? d.write(to: Self.renamesFile, options: .atomic) }
        // Follow the chat to the tab it now belongs in.
        let f = effectiveFolder(t)
        if folder != f { folder = f }
        threadID = t.id
    }

    /// Friends you message most (by message count, inbox only): they get story rings.
    var topFriends: [Thread] {
        Array((account?.threads ?? []).filter { effectiveFolder($0) == .inbox && !$0.isGroup }.sorted { $0.messages.count > $1.messages.count }.prefix(12))
    }
    func isTopFriend(_ t: Thread) -> Bool { topFriends.prefix(10).contains(t) }

    /// Every photo and video in the account, newest first, with the chat it came from.
    var allMedia: [(Media, Thread)] {
        (account?.threads ?? []).flatMap { t in t.messages.flatMap { m in m.media.filter { $0.kind != .audio }.map { ($0, t, m.time) } } }
            .sorted { $0.2 > $1.2 }.map { ($0.0, $0.1) }
    }

    func open(_ t: Thread) {
        section = .messages
        if folder != effectiveFolder(t) { folder = effectiveFolder(t) }
        threadID = t.id
    }

    func entry(_ m: Media) -> ZipEntry? {
        guard let a = account else { return nil }
        return ZipLibrary.shared.entry(m.path, in: a.zip)
    }

    func openViewer(_ m: Media, in thread: Thread) {
        let all = thread.messages.flatMap(\.media).filter { $0.kind == .photo || $0.kind == .video || $0.kind == .gif }
        viewer = Viewer(items: all, index: all.firstIndex(of: m) ?? 0)
    }

    func openLink(_ s: String) {
        if let u = URL(string: s) { NSWorkspace.shared.open(u) }
    }
}

// MARK: Media loading

enum MediaLoader {
    private static var loaderKey: UInt8 = 0

    static func asset(_ e: ZipEntry) throws -> AVURLAsset {
        let data = try e.archive.data(e)
        let ext = (e.name as NSString).pathExtension.lowercased()
        let asset = AVURLAsset(url: URL(string: "igmem://\(stableHash(e.path)).\(ext)")!)
        let type = ext == "aac" ? "public.aac-audio" : ext == "m4a" ? "com.apple.m4a-audio" : ext == "mov" ? "com.apple.quicktime-movie" : "public.mpeg-4"
        let loader = MemoryLoader(data: data, type: type)
        asset.resourceLoader.setDelegate(loader, queue: MemoryLoader.queue)
        objc_setAssociatedObject(asset, &loaderKey, loader, .OBJC_ASSOCIATION_RETAIN)
        return asset
    }

    static func image(_ e: ZipEntry, maxPixel: Int) -> CGImage? {
        guard let d = try? e.archive.data(e), let src = CGImageSourceCreateWithData(d as CFData, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(src, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ] as CFDictionary)
    }
}

/// Thumbnails for chat photos and videos, cached on the Mac's SSD.
final class Thumbs: @unchecked Sendable {
    static let shared = Thumbs()
    private let dir: URL
    private let memory = NSCache<NSString, NSImage>()
    private let gate = AsyncGate(limit: 6)

    init() {
        dir = Paths.caches.appendingPathComponent("thumbs")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        memory.countLimit = 1500
    }

    func image(_ e: ZipEntry, kind: Media.Kind, size: Int = 512) async -> NSImage? {
        let key = stableHash("\(e.archive.url.lastPathComponent)|\(e.path)|\(e.size)") + "-\(size)"
        if let m = memory.object(forKey: key as NSString) { return m }
        let file = dir.appendingPathComponent(key + ".jpg")
        if let img = NSImage(contentsOf: file) { memory.setObject(img, forKey: key as NSString); return img }
        await gate.enter()
        defer { Task { await gate.leave() } }
        var cg: CGImage?
        if kind == .video {
            if let asset = try? MediaLoader.asset(e) {
                let gen = AVAssetImageGenerator(asset: asset)
                gen.appliesPreferredTrackTransform = true
                gen.maximumSize = CGSize(width: size, height: size)
                cg = try? await gen.image(at: CMTime(seconds: 0.3, preferredTimescale: 600)).image
            }
        } else {
            cg = MediaLoader.image(e, maxPixel: size)
        }
        guard let cg else { return nil }
        let img = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        memory.setObject(img, forKey: key as NSString)
        if let d = CGImageDestinationCreateWithURL(file as CFURL, "public.jpeg" as CFString, 1, nil) {
            CGImageDestinationAddImage(d, cg, [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary)
            CGImageDestinationFinalize(d)
        }
        return img
    }
}
