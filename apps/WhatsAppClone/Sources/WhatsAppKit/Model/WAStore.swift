import AppKit
import Observation

struct Viewer: Equatable {
    var items: [Message]
    var index: Int
    var current: Message { items[index] }
}

@MainActor
@Observable
final class WAStore {
    /// One store for the app (SwiftUI may build the App value more than once).
    static let shared = WAStore()

    enum Phase: Equatable { case welcome, loading, ready }
    var phase: Phase = .welcome
    var chats: [Chat] = []
    var chatID: String?
    var search = ""
    var showMedia = false
    var viewer: Viewer?

    var root: URL? {
        get { Prefs.defaults.string(forKey: "root").map { URL(fileURLWithPath: $0) } }
        set { Prefs.defaults.set(newValue?.path, forKey: "root") }
    }

    init() { if let r = root, FileManager.default.fileExists(atPath: r.path) { open(r) } }

    func open(_ url: URL) {
        root = url
        phase = .loading
        Task.detached(priority: .userInitiated) {
            let list = WhatsAppScanner.chats(under: url).enumerated().compactMap { n, z in try? WhatsAppScanner.load(z, idBase: n * 10_000_000) }
            await MainActor.run {
                self.chats = list.sorted { ($0.messages.last?.time ?? .distantPast) > ($1.messages.last?.time ?? .distantPast) }
                self.chatID = self.chats.first?.id
                self.phase = self.chats.isEmpty ? .welcome : .ready
            }
        }
    }

    var chat: Chat? { chats.first { $0.id == chatID } }

    var filteredChats: [Chat] {
        let q = search.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return chats }
        return chats.filter { c in c.title.localizedCaseInsensitiveContains(q) || c.messages.contains { $0.text.localizedCaseInsensitiveContains(q) } }
    }

    /// Changes who "me" is (for group chats where the guess is wrong).
    func setMe(_ name: String) {
        guard let i = chats.firstIndex(where: { $0.id == chatID }) else { return }
        chats[i].me = name
        for j in chats[i].messages.indices { chats[i].messages[j].mine = chats[i].messages[j].sender == name }
    }

    func entry(_ m: Message, in c: Chat) -> ZipEntry? {
        m.file.flatMap { f in ZipLibrary.shared.entry(byName: f, in: c.zip) }
    }

    func openViewer(_ m: Message, in c: Chat) {
        let all = c.messages.filter { $0.file != nil && [.photo, .video, .gif].contains($0.kind) }
        viewer = Viewer(items: all, index: all.firstIndex(of: m) ?? 0)
    }

    /// Opens a document (or a voice note macOS can't play in-app) with its default app, after
    /// unpacking it into the cache.
    func openExternally(_ m: Message, in c: Chat) {
        guard let e = entry(m, in: c) else { return }
        Task {
            if let url = try? await MediaAccess.fileURL(.zip(e)) {
                let named = url.deletingLastPathComponent().appendingPathComponent(e.name)
                try? FileManager.default.removeItem(at: named)
                try? FileManager.default.copyItem(at: url, to: named)
                NSWorkspace.shared.open(named)
            }
        }
    }
}
