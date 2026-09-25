import SwiftUI

enum ChatColors {
    /// Snapchat's chat colours: red for you, blue for friends.
    static let me = Color(red: 0.95, green: 0.24, blue: 0.34)
    static let friend = Color(red: 0.05, green: 0.68, blue: 1.0)
}

struct ChatsView: View {
    @Environment(VaultStore.self) private var store
    @State private var showMedia = false

    var body: some View {
        HStack(spacing: 0) {
            ConversationList()
                .frame(width: 270)
                .background(Color(white: 0.06))
            Group {
                switch store.conversation {
                case nil: SnapGrid(snaps: store.chatSnaps(nil), showSender: true)
                case "saved": SnapGrid(snaps: store.chatSnaps("saved"))
                case let c?:
                    VStack(spacing: 0) {
                        ThreadHeader(conversation: c, showMedia: $showMedia)
                        if showMedia { SnapGrid(snaps: store.chatSnaps(c), showSender: true) } else { ChatThread(conversation: c).id(c) }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct ConversationList: View {
    @Environment(VaultStore.self) private var store
    @State private var filter = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.secondary)
                TextField("Find a friend", text: $filter).textFieldStyle(.plain).font(Theme.body(13, .medium))
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(Theme.card, in: Capsule())
            .padding(10)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    row(nil, "All Chat Media", detail: "\(store.library.snaps.filter { $0.origin == .chat }.count) photos, videos and voice notes", icon: "photo.stack.fill")
                    row("saved", "Saved Snaps", detail: "\(store.library.snaps.filter { $0.origin == .saved }.count) older saves", icon: "square.and.arrow.down.fill")
                    ForEach(store.library.conversations.filter { filter.isEmpty || $0.title.localizedCaseInsensitiveContains(filter) }) { c in
                        row(c.id, c.title, detail: detail(c), icon: c.isGroup ? "person.3.fill" : nil)
                    }
                }
                .padding(.horizontal, 8).padding(.bottom, 10)
            }
        }
    }

    private func detail(_ c: Conversation) -> String {
        var parts: [String] = []
        if c.lastActivity != .distantPast { parts.append(c.lastActivity.formatted(.dateTime.month(.abbreviated).year())) }
        parts.append("\(c.messageCount) message\(c.messageCount == 1 ? "" : "s")")
        return parts.joined(separator: " · ")
    }

    private func row(_ id: String?, _ title: String, detail: String, icon: String?) -> some View {
        let on = store.conversation == id
        return Button { store.conversation = id } label: {
            HStack(spacing: 10) {
                if let icon {
                    Image(systemName: icon).font(.system(size: 13)).frame(width: 36, height: 36).background(Theme.card, in: Circle())
                } else {
                    Avatar(name: title, size: 36)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(Theme.body(14)).lineLimit(1)
                    Text(detail).font(Theme.body(11, .medium)).foregroundStyle(Theme.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(on ? Color.white.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct Avatar: View {
    let name: String
    var size: CGFloat = 32
    var body: some View {
        Text(String(name.split(separator: " ").prefix(2).compactMap(\.first)).uppercased())
            .font(Theme.body(size * 0.36, .heavy)).foregroundStyle(.black)
            .frame(width: size, height: size)
            .background(Self.color(for: name), in: Circle())
    }
    /// A stable colour per friend.
    static func color(for s: String) -> Color {
        let palette: [Color] = [Theme.yellow, .pink, .cyan, .mint, .orange, .purple, .green, .teal]
        return palette[Int(stableHash(s).utf8.reduce(0) { $0 &+ Int($1) }) % palette.count]
    }
}

struct ThreadHeader: View {
    @Environment(VaultStore.self) private var store
    let conversation: String
    @Binding var showMedia: Bool

    var body: some View {
        @Bindable var store = store
        let msgs = store.library.messages[conversation] ?? []
        HStack(spacing: 12) {
            Avatar(name: store.title(for: conversation), size: 40)
            VStack(alignment: .leading, spacing: 1) {
                Text(store.title(for: conversation)).font(Theme.title(18)).foregroundStyle(.white)
                if let first = msgs.first, let last = msgs.last {
                    Text("\(msgs.count) messages · \(first.time.formatted(.dateTime.month(.abbreviated).year())) – \(last.time.formatted(.dateTime.month(.abbreviated).year()))")
                        .font(Theme.body(11, .medium)).foregroundStyle(Theme.secondary)
                }
            }
            Spacer()
            HStack(spacing: 4) {
                ForEach(["Chat", "Media"], id: \.self) { t in
                    let on = (t == "Media") == showMedia
                    Button { showMedia = t == "Media" } label: {
                        Text(t).font(Theme.body(12, .bold)).foregroundStyle(on ? .black : .white)
                            .padding(.horizontal, 14).padding(.vertical, 6)
                            .background(on ? Color.white : Theme.card, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 10)
        .background(Color(white: 0.04))
    }
}

/// A conversation laid out like Snapchat: messages under the sender's name with a coloured bar,
/// day separators, saved messages highlighted, media inline.
struct ChatThread: View {
    @Environment(VaultStore.self) private var store
    let conversation: String

    private struct Block: Identifiable {
        let id: Int
        let day: Date?
        let mine: Bool
        let from: String
        let messages: [ChatMessage]
    }

    var body: some View {
        let msgs = filtered
        let blocks = Self.blocks(msgs)
        let media = store.chatSnaps(conversation).sorted { $0.date < $1.date }
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(blocks) { b in
                    if let day = b.day {
                        Text(day.formatted(.dateTime.weekday(.wide).month(.wide).day().year()).uppercased())
                            .font(Theme.body(10, .heavy)).foregroundStyle(Theme.secondary)
                            .frame(maxWidth: .infinity).padding(.top, 10)
                    }
                    BlockView(mine: b.mine, from: b.from, messages: b.messages, media: media)
                }
            }
            .padding(.horizontal, 22).padding(.vertical, 14)
        }
        .defaultScrollAnchor(.bottom)
        .overlay {
            if msgs.isEmpty {
                Text(store.searchText.isEmpty ? "No messages in this chat" : "No messages match “\(store.searchText)”")
                    .font(Theme.body(15)).foregroundStyle(Theme.secondary)
            }
        }
    }

    /// The top search box filters the conversation too.
    private var filtered: [ChatMessage] {
        let all = store.library.messages[conversation] ?? []
        let q = store.searchText.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? all : all.filter { $0.text.localizedCaseInsensitiveContains(q) }
    }

    /// Consecutive messages from the same person within 10 minutes share one name label.
    private static func blocks(_ msgs: [ChatMessage]) -> [Block] {
        var out: [Block] = []
        var current: [ChatMessage] = []
        var lastDay: Date?
        var dayForBlock: Date?
        let cal = Calendar.current
        func flush() {
            guard let f = current.first else { return }
            out.append(Block(id: f.id, day: dayForBlock, mine: f.mine, from: f.from, messages: current))
            current = []
            dayForBlock = nil
        }
        for m in msgs {
            let day = cal.startOfDay(for: m.time)
            if day != lastDay {
                flush()
                dayForBlock = day
                lastDay = day
            } else if let prev = current.last, prev.mine != m.mine || prev.from != m.from || m.time.timeIntervalSince(prev.time) > 600 {
                flush()
            }
            current.append(m)
        }
        flush()
        return out
    }
}

private struct BlockView: View {
    @Environment(VaultStore.self) private var store
    let mine: Bool
    let from: String
    let messages: [ChatMessage]
    let media: [Snap]

    var body: some View {
        let color = mine ? ChatColors.me : ChatColors.friend
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(mine ? "ME" : from.uppercased()).font(Theme.body(11, .heavy)).foregroundStyle(color)
                Text(messages[0].time.formatted(date: .omitted, time: .shortened)).font(Theme.body(10, .medium)).foregroundStyle(Theme.secondary)
            }
            HStack(alignment: .top, spacing: 8) {
                RoundedRectangle(cornerRadius: 1).fill(color).frame(width: 2)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(messages) { m in MessageRow(message: m, media: media) }
                }
            }
        }
    }
}

private struct MessageRow: View {
    @Environment(VaultStore.self) private var store
    let message: ChatMessage
    let media: [Snap]

    // No saved-message highlight: Snapchat exports only saved messages, so every one is saved.
    var body: some View {
        content.help(message.time.formatted())
    }

    @ViewBuilder
    private var content: some View {
        switch message.kind {
        case .text:
            Text(message.text).font(Theme.body(14, .regular)).foregroundStyle(.white).textSelection(.enabled)
        case .media, .note:
            let snaps = message.mediaIDs.compactMap { store.library.snapByMediaID[$0] }.map { store.snap($0) }
            if snaps.isEmpty {
                label(message.kind == .note ? "mic.fill" : "photo", message.kind == .note ? "Voice note (not in your export)" : "Photo or video (not in your export)")
            } else {
                HStack(spacing: 6) {
                    ForEach(snaps) { s in
                        Tile(snap: s, width: 96)
                            .onTapGesture { store.play(media, from: media.firstIndex(of: s) ?? 0, story: false) }
                    }
                }
            }
            if !message.text.isEmpty && message.kind == .media {
                Text(message.text).font(Theme.body(14, .regular)).foregroundStyle(.white).textSelection(.enabled)
            }
        case .sticker: label("face.smiling", "Sticker")
        case .share: label("arrowshape.turn.up.right.fill", message.text.isEmpty ? "Shared something" : message.text)
        case .location: label("location.fill", message.text.isEmpty ? "Shared a location" : message.text)
        case .snap: label("square.fill", message.mine ? "Sent a Snap" : "Received a Snap")
        case .other: label("ellipsis.bubble", message.text.isEmpty ? "Message" : message.text)
        }
    }

    private func label(_ icon: String, _ text: String) -> some View {
        Label(text, systemImage: icon).font(Theme.body(13, .medium)).foregroundStyle(Theme.secondary).lineLimit(3)
    }
}
