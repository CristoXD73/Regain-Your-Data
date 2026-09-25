import Foundation

enum SnapOrigin: String, Codable {
    /// Saved to Memories (memories/…-main.jpg|mp4, with an optional -overlay.png).
    case memory
    /// Sent or received in a chat (chat_media/…_b~ID.ext, linked from chat_history.json).
    case chat
    /// Old saved snaps and Discover content in chat_media (…_media~zip-UUID.ext), not linked to a chat.
    case saved
    /// Posted to a shared story (shared_story/UUID.mp4).
    case story
}

struct Snap: Identifiable, Hashable {
    let id: Int
    let source: MediaSource
    /// Captions, stickers and drawings, as a transparent PNG drawn over the media.
    var overlay: MediaSource?
    let isVideo: Bool
    let origin: SnapOrigin
    /// The day in the file name (Snapchat writes UTC days).
    let day: Date
    /// Exact time when known: chat messages carry it; videos record it (see VaultStore).
    var time: Date?
    let size: Int64

    // Chats
    /// "b~…" id that chat messages use to refer to this file.
    var mediaID: String?
    var conversation: String?
    var sender: String?
    var sentByMe = false

    var date: Date { time ?? day.addingTimeInterval(12 * 3600) }
    var name: String { source.name }
    /// Identifies the snap across launches and between zipped and unzipped copies.
    var cacheKey: String { "\(name)|\(size)" }

    static func == (a: Snap, b: Snap) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

struct Conversation: Identifiable, Hashable {
    let id: String
    let title: String
    var snapIDs: [Int]
    var messageCount = 0
    var lastActivity: Date = .distantPast
    var isGroup = false
}

/// One line of chat_history.json (or snap_history.json, for snaps sent and received).
struct ChatMessage: Identifiable {
    enum Kind: String { case text = "TEXT", media = "MEDIA", sticker = "STICKER", share = "SHARE", note = "NOTE", location = "LOCATION", snap = "SNAP", other }
    let id: Int
    let time: Date
    let from: String
    let mine: Bool
    let kind: Kind
    let text: String
    let mediaIDs: [String]
    let saved: Bool
}
