import AVFoundation
import SwiftUI

struct DirectView: View {
    @Environment(InstaStore.self) private var store
    var body: some View {
        HStack(spacing: 0) {
            NavRail()
            Rectangle().fill(IG.separator).frame(width: 1)
            switch store.section {
            case .messages: messages
            case .media: AccountMedia().background(IG.panel.opacity(0.85))
            case .profile: ProfileView().background(IG.panel.opacity(0.85))
            }
        }
    }

    private var messages: some View {
        HStack(spacing: 0) {
            Inbox().frame(width: 360)
            Rectangle().fill(IG.separator).frame(width: 1)
            if let t = store.thread {
                ThreadView(thread: t).id(t.id)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "paperplane.circle").font(.system(size: 80, weight: .ultraLight))
                    Text("Your messages").font(.title2.bold())
                    Text("Pick a conversation from \(store.account?.id ?? "your account").").foregroundStyle(IG.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(IG.panel.opacity(0.6))
            }
        }
    }
}

// MARK: Nav rail

/// The icon column on the left of instagram.com.
struct NavRail: View {
    @Environment(InstaStore.self) private var store
    var body: some View {
        VStack(spacing: 22) {
            LogoMark().frame(width: 30, height: 30).padding(.top, 40).padding(.bottom, 14)
            item("paperplane", "paperplane.fill", .messages, "Messages")
            item("photo.on.rectangle", "photo.fill.on.rectangle.fill", .media, "All photos and videos")
            Spacer()
            Button { store.section = .profile } label: {
                Avatar(name: store.account?.owner ?? "", size: 28, ring: store.section == .profile)
            }
            .buttonStyle(.plain).help("Profile").padding(.bottom, 20)
        }
        .frame(width: 72)
        .background(IG.panel)
    }

    private func item(_ icon: String, _ selected: String, _ s: InstaStore.Section, _ help: String) -> some View {
        Button { store.section = s } label: {
            Image(systemName: store.section == s ? selected : icon)
                .font(.system(size: 22, weight: store.section == s ? .semibold : .regular))
                .foregroundStyle(.white).frame(width: 44, height: 44)
                .background(store.section == s ? Color.white.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain).help(help)
    }
}

/// The camera glyph filled with Instagram's gradient.
struct LogoMark: View {
    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            ZStack {
                RoundedRectangle(cornerRadius: w * 0.3, style: .continuous).strokeBorder(lineWidth: w * 0.11)
                Circle().strokeBorder(lineWidth: w * 0.11).frame(width: w * 0.5, height: w * 0.5)
                Circle().frame(width: w * 0.13, height: w * 0.13).offset(x: w * 0.26, y: -w * 0.26)
            }
            .foregroundStyle(IG.gradient)
        }
    }
}

// MARK: Inbox

struct Inbox: View {
    @Environment(InstaStore.self) private var store

    var body: some View {
        @Bindable var store = store
        VStack(alignment: .leading, spacing: 0) {
            // Account switcher, like tapping your username in Instagram.
            Menu {
                ForEach(store.accounts) { a in
                    Button { store.select(account: a.id) } label: {
                        Label("\(a.id) · \(a.threads.count) chats", systemImage: a.id == store.accountID ? "checkmark.circle.fill" : "person.crop.circle")
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Avatar(name: store.account?.owner ?? "", size: 30, ring: true)
                    Text(store.account?.id ?? "").font(.system(size: 20, weight: .bold))
                    Image(systemName: "chevron.down").font(.system(size: 12, weight: .bold))
                }
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .padding(.horizontal, 20).padding(.top, 36)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(IG.secondary)
                TextField("Search", text: $store.search).textFieldStyle(.plain)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(IG.surface, in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 20).padding(.vertical, 12)

            HStack(spacing: 16) {
                tab("Messages", .inbox)
                HStack(spacing: 5) {
                    tab("Requests", .requests)
                    if store.count(.requests) > 0 {
                        Text("\(store.count(.requests))").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 1).background(IG.red, in: Capsule())
                    }
                }
                if store.count(.unknown) > 0 {
                    HStack(spacing: 5) {
                        tab("Instagram Users", .unknown)
                        Text("\(store.count(.unknown))").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 1).background(Color.white.opacity(0.18), in: Capsule())
                    }
                    .help("Chats with accounts that were deleted or deactivated. Name one to move it to Messages.")
                }
                if store.count(.ai) > 0 { tab("Meta AI", .ai) }
            }
            .padding(.horizontal, 20).padding(.bottom, 6)
            .fixedSize(horizontal: false, vertical: true)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(store.threads) { t in ThreadRow(thread: t) }
                }
            }
        }
        .background(IG.panel)
    }

    private func tab(_ title: String, _ f: Thread.Folder) -> some View {
        Button { store.folder = f } label: {
            Text(title).font(.system(size: 15, weight: store.folder == f ? .bold : .semibold))
                .foregroundStyle(store.folder == f ? .white : IG.secondary)
        }
        .buttonStyle(.plain)
    }
}

struct ThreadRow: View {
    @Environment(InstaStore.self) private var store
    let thread: Thread

    var body: some View {
        let on = store.threadID == thread.id
        Button { store.threadID = thread.id; store.showMedia = false } label: {
            HStack(spacing: 12) {
                Avatar(name: store.title(thread), size: 52, ring: store.isTopFriend(thread))
                VStack(alignment: .leading, spacing: 3) {
                    Text(store.title(thread)).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    HStack(spacing: 4) {
                        Text(preview).lineLimit(1)
                        if let t = thread.last?.time { Text("· \(Self.ago(t))").layoutPriority(1) }
                    }
                    .font(.system(size: 13)).foregroundStyle(IG.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20).padding(.vertical, 8)
            .background(on ? IG.surface : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var preview: String {
        guard let m = thread.last else { return "" }
        let who = m.mine ? "You: " : (thread.isGroup ? "\(m.sender.split(separator: " ").first ?? ""): " : "")
        if !m.text.isEmpty { return who + m.text.replacingOccurrences(of: "\n", with: " ") }
        if let k = m.media.first?.kind { return who + (k == .audio ? "Sent a voice message" : k == .video ? "Sent a video" : "Sent a photo") }
        if m.link != nil { return who + "Shared a link" }
        return who + "Sent an attachment"
    }

    /// Instagram-style short age: 3w, 2y …
    static func ago(_ d: Date) -> String {
        let s = Date().timeIntervalSince(d)
        switch s {
        case ..<3600: return "\(max(1, Int(s / 60)))m"
        case ..<86_400: return "\(Int(s / 3600))h"
        case ..<(7 * 86_400): return "\(Int(s / 86_400))d"
        case ..<(365 * 86_400): return "\(Int(s / (7 * 86_400)))w"
        default: return "\(Int(s / (365 * 86_400)))y"
        }
    }
}

// MARK: Thread

struct ThreadView: View {
    @Environment(InstaStore.self) private var store
    let thread: Thread

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(IG.separator).frame(height: 1)
            if store.showMedia { MediaGrid(thread: thread) } else { messages }
        }
        .background(IG.panel.opacity(0.85))
    }

    private var header: some View {
        HStack(spacing: 12) {
            Avatar(name: store.title(thread), size: 40, ring: true)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(store.title(thread)).font(.system(size: 16, weight: .semibold))
                    if store.isUnknownUser(thread) { RenameButton(thread: thread) }
                }
                Text(subtitle).font(.system(size: 12)).foregroundStyle(IG.secondary).lineLimit(1)
            }
            Spacer()
            Button { store.showMedia.toggle() } label: {
                Image(systemName: store.showMedia ? "bubble.left.and.bubble.right" : "photo.on.rectangle")
                    .font(.system(size: 18)).frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .help(store.showMedia ? "Back to the chat" : "Photos and videos in this chat")
        }
        .padding(.horizontal, 18).padding(.top, 30).padding(.bottom, 10)
    }

    private var subtitle: String {
        var parts = ["\(thread.messages.count.formatted()) messages"]
        if let f = thread.messages.first?.time { parts.append("since \(f.formatted(.dateTime.month(.abbreviated).year()))") }
        if thread.isGroup { parts.append("\(thread.participants.count) members") }
        return parts.joined(separator: " · ")
    }

    /// Messages, with a centred time whenever an hour or more passed, and avatars at the end of
    /// each run of someone else's messages.
    private var messages: some View {
        let msgs = filtered
        return GeometryReader { viewport in ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(Array(msgs.enumerated()), id: \.element.id) { i, m in
                    let prev = i > 0 ? msgs[i - 1] : nil
                    let next = i + 1 < msgs.count ? msgs[i + 1] : nil
                    if prev == nil || m.time.timeIntervalSince(prev!.time) > 3600 {
                        Text(Self.stamp(m.time)).font(.system(size: 11, weight: .semibold)).foregroundStyle(IG.secondary)
                            .padding(.top, 14).padding(.bottom, 6)
                    }
                    let firstOfRun = prev == nil || prev!.sender != m.sender || m.time.timeIntervalSince(prev!.time) > 3600
                    let lastOfRun = next == nil || next!.sender != m.sender || next!.time.timeIntervalSince(m.time) > 3600
                    MessageRow(message: m, thread: thread, showName: thread.isGroup && !m.mine && firstOfRun, showAvatar: !m.mine && lastOfRun)
                        .padding(.bottom, lastOfRun ? 6 : 0)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
        }
        .coordinateSpace(name: "viewport")
        .environment(\.viewportHeight, viewport.size.height)
        }
        .defaultScrollAnchor(.bottom)
        .overlay {
            if msgs.isEmpty { Text("No messages match “\(store.search)”").foregroundStyle(IG.secondary) }
        }
    }

    /// The inbox search also filters the open chat.
    private var filtered: [Message] {
        let q = store.search.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? thread.messages : thread.messages.filter { $0.text.localizedCaseInsensitiveContains(q) }
    }

    static func stamp(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDate(d, equalTo: Date(), toGranularity: .year) {
            return d.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
        }
        return d.formatted(.dateTime.month(.abbreviated).day().year().hour().minute())
    }
}

struct MessageRow: View {
    @Environment(InstaStore.self) private var store
    let message: Message
    let thread: Thread
    let showName: Bool
    let showAvatar: Bool

    var body: some View {
        let mine = message.mine
        VStack(alignment: mine ? .trailing : .leading, spacing: 2) {
            if showName {
                Text(store.senderName(message, in: thread)).font(.system(size: 11)).foregroundStyle(IG.secondary).padding(.leading, 44)
            }
            HStack(alignment: .bottom, spacing: 8) {
                if !mine {
                    if showAvatar { Avatar(name: store.senderName(message, in: thread), size: 28) } else { Color.clear.frame(width: 28, height: 1) }
                }
                if mine { Spacer(minLength: 80) }
                VStack(alignment: mine ? .trailing : .leading, spacing: 4) {
                    ForEach(message.media, id: \.path) { m in MediaBubble(media: m, thread: thread, mine: mine) }
                    if let link = message.link { LinkCard(url: link, mine: mine) }
                    if !message.text.isEmpty { textBubble }
                    if message.isUnavailable {
                        Text(message.mine ? "You sent something that isn't in the export" : "Sent something that isn't in the export")
                            .font(.system(size: 12).italic()).foregroundStyle(IG.secondary)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .overlay(Capsule().strokeBorder(IG.separator))
                    }
                    if !message.reactions.isEmpty { reactions }
                }
                .help(message.time.formatted(date: .complete, time: .shortened))
                if !mine { Spacer(minLength: 80) }
            }
        }
        .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
    }

    private var textBubble: some View {
        let onlyEmoji = message.text.count <= 3 && message.text.unicodeScalars.allSatisfy { $0.properties.isEmojiPresentation || $0.properties.isEmoji && $0.value > 0x238C }
        return Group {
            if onlyEmoji {
                Text(message.text).font(.system(size: 40))
            } else {
                Text(message.text)
                    .font(.system(size: 14.5))
                    .foregroundStyle(.white)
                    .textSelection(.enabled)
                    .padding(.horizontal, 13).padding(.vertical, 8)
                    .background { BubbleFill(mine: message.mine) }
            }
        }
    }

    /// Instagram shows reactions as a small pill under the bubble.
    private var reactions: some View {
        let emoji = message.reactions.map { r in String(r.prefix { !$0.isLetter && !$0.isNumber && $0 != " " }) }.filter { !$0.isEmpty }
        return HStack(spacing: 2) {
            Text(Array(Set(emoji)).prefix(3).joined())
            if message.reactions.count > 1 { Text("\(message.reactions.count)").foregroundStyle(IG.secondary) }
        }
        .font(.system(size: 12))
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(IG.theirs, in: Capsule())
        .overlay(Capsule().strokeBorder(IG.background, lineWidth: 2))
        .offset(y: -8)
        .help(message.reactions.joined(separator: "\n"))
    }
}

struct LinkCard: View {
    @Environment(InstaStore.self) private var store
    let url: String
    let mine: Bool
    var body: some View {
        let host = URL(string: url)?.host?.replacingOccurrences(of: "www.", with: "") ?? "link"
        let kind = url.contains("/reel") ? "Reel" : url.contains("/p/") ? "Post" : url.contains("/stories/") ? "Story" : host
        Button { store.openLink(url) } label: {
            HStack(spacing: 10) {
                Image(systemName: url.contains("instagram.com") ? "play.rectangle.on.rectangle" : "link")
                    .font(.system(size: 18)).frame(width: 40, height: 40)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Shared \(kind == host ? "a link" : "a \(kind.lowercased())")").font(.system(size: 13, weight: .semibold))
                    Text(url).font(.system(size: 11)).foregroundStyle(IG.secondary).lineLimit(1).truncationMode(.middle)
                }
            }
            .padding(10).frame(maxWidth: 280, alignment: .leading)
            .background(IG.theirs, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("Open in your browser")
    }
}

struct MediaBubble: View {
    @Environment(InstaStore.self) private var store
    let media: Media
    let thread: Thread
    let mine: Bool
    @State private var image: NSImage?

    var body: some View {
        if media.kind == .audio {
            VoiceNote(media: media, mine: mine)
        } else {
            let size = image.map { fit($0.size) } ?? CGSize(width: 220, height: 280)
            Color(white: 0.12)
                .frame(width: size.width, height: size.height)
                .overlay { if let image { Image(nsImage: image).resizable().scaledToFill() } }
                .overlay { if media.kind == .video { Image(systemName: "play.fill").font(.system(size: 30)).foregroundStyle(.white).shadow(radius: 6) } }
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .contentShape(Rectangle())
                .onTapGesture { store.openViewer(media, in: thread) }
                .task(id: media.path) {
                    if let e = store.entry(media) { image = await Thumbs.shared.image(e, kind: media.kind) }
                }
        }
    }

    private func fit(_ s: CGSize) -> CGSize {
        guard s.width > 0, s.height > 0 else { return CGSize(width: 220, height: 280) }
        let scale = min(260 / s.width, 340 / s.height)
        return CGSize(width: s.width * scale, height: s.height * scale)
    }
}

/// Voice message: play/pause, progress and length, in the sender's bubble colour.
struct VoiceNote: View {
    @Environment(InstaStore.self) private var store
    let media: Media
    let mine: Bool
    @State private var player: AVPlayer?
    @State private var playing = false
    @State private var progress: Double = 0
    @State private var duration: Double = 0

    var body: some View {
        HStack(spacing: 10) {
            Button { toggle() } label: {
                Image(systemName: playing ? "pause.fill" : "play.fill").font(.system(size: 16)).frame(width: 24)
            }
            .buttonStyle(.plain)
            GeometryReader { g in
                HStack(spacing: 2) {
                    ForEach(0..<28, id: \.self) { i in
                        let h = 6 + 16 * abs(sin(Double(i) * 1.7 + Double(media.path.count)))
                        Capsule().fill(Double(i) / 28 < progress ? Color.white : Color.white.opacity(0.4))
                            .frame(width: (g.size.width - 54) / 28, height: h)
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .frame(width: 170, height: 28)
            Text(duration > 0 ? String(format: "%d:%02d", Int(duration) / 60, Int(duration) % 60) : "")
                .font(.system(size: 12).monospacedDigit())
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background { BubbleFill(mine: mine, shape: AnyShape(Capsule())) }
        .onDisappear { player?.pause() }
        .task {
            if let e = store.entry(media), let a = try? MediaLoader.asset(e), let d = try? await a.load(.duration), d.isNumeric { duration = d.seconds }
        }
    }

    private func toggle() {
        if player == nil, let e = store.entry(media), let a = try? MediaLoader.asset(e) {
            let p = AVPlayer(playerItem: AVPlayerItem(asset: a))
            p.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 10), queue: .main) { t in
                MainActor.assumeIsolated {
                    if duration > 0 { progress = t.seconds / duration }
                    if progress >= 0.999 { playing = false; progress = 0; p.seek(to: .zero) }
                }
            }
            player = p
        }
        if playing { player?.pause() } else { player?.play() }
        playing.toggle()
    }
}

struct MediaGrid: View {
    @Environment(InstaStore.self) private var store
    let thread: Thread
    var body: some View {
        let items = thread.messages.reversed().flatMap(\.media).filter { $0.kind != .audio }
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 3)], spacing: 3) {
                ForEach(items, id: \.path) { m in GridCell(media: m, thread: thread) }
            }
            .padding(3)
        }
        .overlay { if items.isEmpty { Text("No photos or videos in this chat").foregroundStyle(IG.secondary) } }
    }
}

private struct GridCell: View {
    @Environment(InstaStore.self) private var store
    let media: Media
    let thread: Thread
    @State private var image: NSImage?
    var body: some View {
        Color(white: 0.12)
            .aspectRatio(1, contentMode: .fit)
            .overlay { if let image { Image(nsImage: image).resizable().scaledToFill() } }
            .overlay(alignment: .topTrailing) {
                if media.kind == .video { Image(systemName: "video.fill").font(.system(size: 12)).foregroundStyle(.white).shadow(radius: 3).padding(6) }
            }
            .clipped()
            .contentShape(Rectangle())
            .onTapGesture { store.openViewer(media, in: thread) }
            .task(id: media.path) { if let e = store.entry(media) { image = await Thumbs.shared.image(e, kind: media.kind, size: 320) } }
    }
}

/// Height of the visible chat area, for the position-based bubble colour.
private struct ViewportHeightKey: EnvironmentKey { static let defaultValue: CGFloat = 800 }
extension EnvironmentValues {
    var viewportHeight: CGFloat {
        get { self[ViewportHeightKey.self] }
        set { self[ViewportHeightKey.self] = newValue }
    }
}

/// A bubble background: grey for others; for me, the colour of Instagram's chat gradient at the
/// bubble's current height on screen (purple at the top, red-pink at the bottom).
struct BubbleFill: View {
    let mine: Bool
    var shape = AnyShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    @Environment(\.viewportHeight) private var height

    var body: some View {
        if mine {
            GeometryReader { g in
                let y = g.frame(in: .named("viewport")).midY
                shape.fill(IG.mineColor(at: Double(y / max(1, height))))
            }
        } else {
            shape.fill(IG.theirs)
        }
    }
}

/// Name an "Instagram User" chat; the name moves it into Messages. Clearing it moves it back.
struct RenameButton: View {
    @Environment(InstaStore.self) private var store
    let thread: Thread
    @State private var editing = false
    @State private var name = ""
    var body: some View {
        Button { name = store.renamed(thread) ?? ""; editing = true } label: {
            Image(systemName: "pencil.circle.fill").font(.system(size: 16)).foregroundStyle(IG.secondary)
        }
        .buttonStyle(.plain)
        .help("Name this person")
        .popover(isPresented: $editing, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Who was this?").font(.headline)
                Text("Instagram only says “Instagram User” because the account was deleted or deactivated. Give it a name and the chat moves to Messages.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                TextField("Name", text: $name).textFieldStyle(.roundedBorder).onSubmit { save() }
                HStack {
                    if store.renamed(thread) != nil {
                        Button("Remove Name") { store.rename(thread, to: nil); editing = false }
                    }
                    Spacer()
                    Button("Cancel") { editing = false }
                    Button("Save") { save() }.keyboardShortcut(.defaultAction).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(16).frame(width: 320)
        }
    }
    private func save() {
        store.rename(thread, to: name)
        editing = false
    }
}
