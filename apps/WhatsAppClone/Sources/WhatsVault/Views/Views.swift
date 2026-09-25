import AVKit
import SwiftUI

/// WhatsApp desktop's dark theme.
enum WA {
    static let background = Color(red: 0.043, green: 0.078, blue: 0.102)     // #0B141A
    static let panel = Color(red: 0.067, green: 0.106, blue: 0.129)          // #111B21
    static let bar = Color(red: 0.125, green: 0.173, blue: 0.2)              // #202C33
    static let mine = Color(red: 0.0, green: 0.361, blue: 0.294)             // #005C4B
    static let theirs = Color(red: 0.125, green: 0.173, blue: 0.2)           // #202C33
    static let green = Color(red: 0.0, green: 0.659, blue: 0.518)            // #00A884
    static let secondary = Color(red: 0.525, green: 0.588, blue: 0.627)      // #8696A0
    static let tick = Color(red: 0.325, green: 0.741, blue: 0.922)           // #53BDEB
    static let chip = Color(red: 0.094, green: 0.133, blue: 0.161)           // #182229
    static let system = Color(red: 1.0, green: 0.824, blue: 0.475)           // #FFD279
}

struct WhatsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var store = WAStore.shared
    var body: some Scene {
        WindowGroup("WhatsApp Clone") {
            RootView().environment(store).frame(minWidth: 900, minHeight: 620).preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) { Button("Open Export Folder…") { chooseFolder(store) }.keyboardShortcut("o") }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ n: Notification) { NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true) }
    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { true }
}

@MainActor
func chooseFolder(_ store: WAStore) {
    let p = NSOpenPanel()
    p.canChooseDirectories = true
    p.canChooseFiles = false
    p.message = "Choose the folder that holds your “WhatsApp Chat - ….zip” exports."
    if p.runModal() == .OK, let u = p.url { store.open(u) }
}

struct RootView: View {
    @Environment(WAStore.self) private var store
    @State private var found: [URL] = []
    var body: some View {
        ZStack {
            WA.background.ignoresSafeArea()
            switch store.phase {
            case .loading: ProgressView().controlSize(.large)
            case .ready: MainView()
            case .welcome:
                VStack(spacing: 16) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 120, height: 120)
                    Text("WhatsApp Clone").font(.system(size: 28, weight: .bold))
                    Text("Your exported WhatsApp chats, read straight from the zips. Nothing leaves this Mac.").foregroundStyle(WA.secondary)
                    ForEach(found, id: \.self) { u in
                        Button(u.path) { store.open(u) }.buttonStyle(.link).lineLimit(1).truncationMode(.middle).frame(maxWidth: 460)
                    }
                    Button("Choose Folder…") { chooseFolder(store) }.buttonStyle(.borderedProminent).tint(WA.green).controlSize(.large)
                }
                .task { found = await Task.detached { WhatsAppScanner.suggestedRoots() }.value }
            }
            if store.viewer != nil { MediaViewer().zIndex(1) }
        }
    }
}

struct Avatar: View {
    let name: String
    var size: CGFloat = 49
    var body: some View {
        Circle().fill(Color(white: 0.42)).frame(width: size, height: size)
            .overlay(Image(systemName: "person.fill").font(.system(size: size * 0.55)).foregroundStyle(Color(white: 0.82)).offset(y: size * 0.08))
            .clipShape(Circle())
    }
}

struct MainView: View {
    @Environment(WAStore.self) private var store
    var body: some View {
        HStack(spacing: 0) {
            ChatList().frame(width: 380).background(WA.panel)
            Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1)
            if let c = store.chat { ChatView(chat: c).id(c.id) } else { WA.background }
        }
    }
}

struct ChatList: View {
    @Environment(WAStore.self) private var store
    var body: some View {
        @Bindable var store = store
        VStack(alignment: .leading, spacing: 0) {
            Text("Chats").font(.system(size: 22, weight: .bold)).padding(.horizontal, 18).padding(.top, 38).padding(.bottom, 12)
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(WA.secondary)
                TextField("Search", text: $store.search).textFieldStyle(.plain)
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(WA.bar, in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 14).padding(.bottom, 8)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(store.filteredChats) { c in
                        Button { store.chatID = c.id; store.showMedia = false } label: { row(c) }.buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func row(_ c: Chat) -> some View {
        let last = c.messages.last
        return HStack(spacing: 14) {
            Avatar(name: c.title)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(c.title).font(.system(size: 16)).lineLimit(1)
                    Spacer()
                    if let t = last?.time { Text(t.formatted(date: .numeric, time: .omitted)).font(.system(size: 12)).foregroundStyle(WA.secondary) }
                }
                HStack(spacing: 4) {
                    if last?.mine == true { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(WA.tick) }
                    Text(last.map(preview) ?? "").lineLimit(1).font(.system(size: 14)).foregroundStyle(WA.secondary)
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(store.chatID == c.id ? WA.bar : .clear)
        .contentShape(Rectangle())
    }

    private func preview(_ m: Message) -> String {
        switch m.kind {
        case .photo: "📷 Photo"
        case .sticker: "Sticker"
        case .gif: "GIF"
        case .video: "🎥 Video"
        case .audio: "🎤 Voice message"
        case .document: "📄 " + (m.file ?? "Document")
        case .deleted: "🚫 This message was deleted"
        default: m.text.replacingOccurrences(of: "\n", with: " ")
        }
    }
}

// MARK: Conversation

struct ChatView: View {
    @Environment(WAStore.self) private var store
    let chat: Chat
    @State private var find = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            if store.showMedia { MediaGrid(chat: chat) } else { transcript }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Avatar(name: chat.title, size: 40)
            VStack(alignment: .leading, spacing: 1) {
                Text(chat.title).font(.system(size: 16, weight: .medium))
                Text("\(chat.messages.count.formatted()) messages · \(chat.participants.joined(separator: ", "))").font(.system(size: 12)).foregroundStyle(WA.secondary).lineLimit(1)
            }
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(WA.secondary)
                TextField("Search in chat", text: $find).textFieldStyle(.plain).frame(width: 150)
            }
            .padding(.horizontal, 10).padding(.vertical, 6).background(WA.chip, in: Capsule())
            Button { store.showMedia.toggle() } label: {
                Image(systemName: store.showMedia ? "bubble.left.and.bubble.right" : "photo.on.rectangle.angled").font(.system(size: 17))
            }
            .buttonStyle(.plain).help(store.showMedia ? "Back to the chat" : "Media, links and docs")
            if chat.participants.count > 1 {
                Menu {
                    ForEach(chat.participants, id: \.self) { p in
                        Button { store.setMe(p) } label: { Label(p, systemImage: p == chat.me ? "checkmark" : "person") }
                    }
                } label: { Image(systemName: "person.crop.circle.badge.checkmark") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .help("Which of these is you?")
            }
        }
        .padding(.horizontal, 16).padding(.top, 30).padding(.bottom, 10)
        .background(WA.bar)
    }

    private var transcript: some View {
        let q = find.trimmingCharacters(in: .whitespaces)
        let msgs = q.isEmpty ? chat.messages : chat.messages.filter { $0.text.localizedCaseInsensitiveContains(q) }
        let cal = Calendar.current
        return ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(Array(msgs.enumerated()), id: \.element.id) { i, m in
                    let prev = i > 0 ? msgs[i - 1] : nil
                    if prev == nil || !cal.isDate(prev!.time, inSameDayAs: m.time) {
                        Text(dayLabel(m.time)).font(.system(size: 12.5, weight: .medium)).foregroundStyle(WA.secondary)
                            .padding(.horizontal, 12).padding(.vertical, 6).background(WA.chip, in: RoundedRectangle(cornerRadius: 8))
                            .padding(.vertical, 10)
                    }
                    let first = prev == nil || prev!.sender != m.sender || !cal.isDate(prev!.time, inSameDayAs: m.time)
                    Bubble(message: m, chat: chat, first: first).padding(.top, first ? 6 : 0)
                }
            }
            .padding(.horizontal, 50).padding(.vertical, 12)
        }
        .defaultScrollAnchor(.bottom)
        .background { Wallpaper() }
    }

    private func dayLabel(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "TODAY" }
        if cal.isDateInYesterday(d) { return "YESTERDAY" }
        return d.formatted(.dateTime.month(.wide).day().year()).uppercased()
    }
}

/// WhatsApp's faint doodle wallpaper.
struct Wallpaper: View {
    var body: some View {
        Canvas { ctx, size in
            let symbols = ["heart", "star", "camera", "music.note", "cloud", "leaf", "gift", "moon", "bicycle", "cup.and.saucer", "paperplane", "sun.max"]
            var i = 0
            for y in stride(from: 0.0, to: size.height + 60, by: 64) {
                for x in stride(from: (Int(y / 64) % 2 == 0 ? 0.0 : 32.0), to: size.width + 60, by: 64) {
                    let img = ctx.resolve(Image(systemName: symbols[i % symbols.count]))
                    ctx.opacity = 0.05
                    ctx.draw(img, at: CGPoint(x: x, y: y))
                    i += 5
                }
            }
        }
        .background(WA.background)
        .foregroundStyle(.white)
    }
}

struct Bubble: View {
    @Environment(WAStore.self) private var store
    let message: Message
    let chat: Chat
    let first: Bool

    var body: some View {
        let mine = message.mine
        if message.kind == .system {
            Text(message.text).font(.system(size: 12.5)).foregroundStyle(WA.system).multilineTextAlignment(.center)
                .padding(.horizontal, 12).padding(.vertical, 6).background(WA.chip, in: RoundedRectangle(cornerRadius: 8))
                .frame(maxWidth: 520).padding(.vertical, 6)
        } else if message.kind == .sticker, store.entry(message, in: chat) != nil {
            HStack { if mine { Spacer() }; Sticker(message: message, chat: chat); if !mine { Spacer() } }
        } else {
            HStack {
                if mine { Spacer(minLength: 120) }
                VStack(alignment: .leading, spacing: 3) {
                    if chat.isGroup && !mine && first {
                        Text(message.sender).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(nameColor(message.sender))
                    }
                    content
                    HStack(spacing: 3) {
                        Spacer(minLength: 0)
                        Text(message.time.formatted(date: .omitted, time: .shortened)).font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
                        if mine { Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy)).foregroundStyle(WA.tick).overlay(Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy)).foregroundStyle(WA.tick).offset(x: 4)).padding(.trailing, 4) }
                    }
                }
                .padding(.horizontal, 9).padding(.top, 6).padding(.bottom, 5)
                .background(mine ? WA.mine : WA.theirs, in: BubbleShape(mine: mine, tail: first))
                .help(message.time.formatted(date: .complete, time: .standard))
                if !mine { Spacer(minLength: 120) }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch message.kind {
        case .photo, .gif, .video:
            if store.entry(message, in: chat) != nil { Picture(message: message, chat: chat) } else { missing }
            if !message.text.isEmpty { text }
        case .audio: VoiceNote(message: message, chat: chat)
        case .document:
            Button { store.openExternally(message, in: chat) } label: {
                HStack(spacing: 10) {
                    Image(systemName: "doc.fill").font(.system(size: 26)).foregroundStyle(Color(red: 0.9, green: 0.3, blue: 0.3))
                    Text(message.file ?? "Document").font(.system(size: 14)).lineLimit(2)
                }
                .padding(10).frame(maxWidth: 280, alignment: .leading).background(Color.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain).help("Open")
        case .deleted:
            Label("This message was deleted", systemImage: "nosign").font(.system(size: 14).italic()).foregroundStyle(WA.secondary)
        case .omitted: missing
        default: text
        }
    }

    private var text: some View {
        Text(message.text).font(.system(size: 14.2)).foregroundStyle(.white).textSelection(.enabled)
    }

    private var missing: some View {
        Label("\(message.text.isEmpty ? "Attachment" : message.text) (not in the export)", systemImage: "paperclip")
            .font(.system(size: 13).italic()).foregroundStyle(WA.secondary)
    }

    private func nameColor(_ s: String) -> Color {
        let colors: [Color] = [.orange, .pink, .cyan, .mint, .yellow, .purple, .green, .teal]
        return colors[Int(s.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }) % colors.count]
    }
}

/// A bubble with WhatsApp's little corner tail on the first message of a run.
struct BubbleShape: Shape {
    let mine: Bool
    let tail: Bool
    func path(in r: CGRect) -> Path {
        var p = Path(roundedRect: r, cornerRadius: 8)
        guard tail else { return p }
        if mine {
            p.move(to: CGPoint(x: r.maxX - 8, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX + 8, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.minY + 10))
        } else {
            p.move(to: CGPoint(x: r.minX + 8, y: r.minY))
            p.addLine(to: CGPoint(x: r.minX - 8, y: r.minY))
            p.addLine(to: CGPoint(x: r.minX, y: r.minY + 10))
        }
        return p
    }
}

struct Picture: View {
    @Environment(WAStore.self) private var store
    let message: Message
    let chat: Chat
    @State private var image: NSImage?
    var body: some View {
        let size = image.map { fit($0.size) } ?? CGSize(width: 260, height: 260)
        Color.black.opacity(0.2)
            .frame(width: size.width, height: size.height)
            .overlay { if let image { Image(nsImage: image).resizable().scaledToFill() } }
            .overlay { if message.kind != .photo { Image(systemName: message.kind == .gif ? "play.circle" : "play.circle.fill").font(.system(size: 44)).foregroundStyle(.white).shadow(radius: 4) } }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
            .onTapGesture { store.openViewer(message, in: chat) }
            .task { if let e = store.entry(message, in: chat) { image = await Thumbs.shared.image(e, video: message.kind != .photo) } }
    }
    private func fit(_ s: CGSize) -> CGSize {
        guard s.width > 0, s.height > 0 else { return CGSize(width: 260, height: 260) }
        let k = min(300 / s.width, 340 / s.height)
        return CGSize(width: s.width * k, height: s.height * k)
    }
}

struct Sticker: View {
    @Environment(WAStore.self) private var store
    let message: Message
    let chat: Chat
    @State private var image: NSImage?
    var body: some View {
        ZStack {
            if let image { Image(nsImage: image).resizable().scaledToFit() } else { Color.clear }
        }
        .frame(width: 150, height: 150)
        .help(message.time.formatted(date: .complete, time: .shortened))
        .task { if let e = store.entry(message, in: chat) { image = await Thumbs.shared.image(e, video: false, size: 300) } }
    }
}

/// Voice message. WhatsApp's .opus files play in-app when macOS can decode them; otherwise the
/// play button opens them with the default app.
struct VoiceNote: View {
    @Environment(WAStore.self) private var store
    let message: Message
    let chat: Chat
    @State private var player: AVPlayer?
    @State private var playing = false
    var body: some View {
        HStack(spacing: 10) {
            Avatar(name: message.sender, size: 40).overlay(alignment: .bottomTrailing) {
                Image(systemName: "mic.fill").font(.system(size: 12)).foregroundStyle(WA.tick)
            }
            Button { toggle() } label: { Image(systemName: playing ? "pause.fill" : "play.fill").font(.system(size: 20)) }.buttonStyle(.plain)
            HStack(spacing: 2) {
                ForEach(0..<30, id: \.self) { i in
                    Capsule().fill(Color.white.opacity(0.5)).frame(width: 3, height: 4 + 18 * abs(sin(Double(i) * 1.3 + Double(message.id % 7))))
                }
            }
        }
        .padding(.vertical, 4)
    }
    private func toggle() {
        guard let e = store.entry(message, in: chat) else { return }
        if player == nil, let a = try? MediaLoader.asset(e) {
            let item = AVPlayerItem(asset: a)
            player = AVPlayer(playerItem: item)
        }
        if playing { player?.pause(); playing = false; return }
        player?.play()
        playing = true
        // If macOS can't decode it in-app, hand it to the default player after a moment.
        Task {
            try? await Task.sleep(for: .seconds(1))
            if player?.currentItem?.status == .failed || (player?.currentTime().seconds ?? 0) == 0 {
                playing = false
                store.openExternally(message, in: chat)
            }
        }
    }
}

struct MediaGrid: View {
    @Environment(WAStore.self) private var store
    let chat: Chat
    var body: some View {
        let items = chat.messages.reversed().filter { [.photo, .video, .gif].contains($0.kind) && $0.file != nil }
        let docs = chat.messages.filter { $0.kind == .document && $0.file != nil }
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Media").font(.system(size: 15, weight: .semibold)).foregroundStyle(WA.green)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 4)], spacing: 4) {
                    ForEach(items) { m in Cell(message: m, chat: chat) }
                }
                if !docs.isEmpty {
                    Text("Docs").font(.system(size: 15, weight: .semibold)).foregroundStyle(WA.green).padding(.top, 8)
                    ForEach(docs) { d in
                        Button { store.openExternally(d, in: chat) } label: { Label(d.file ?? "", systemImage: "doc.fill") }.buttonStyle(.link)
                    }
                }
            }
            .padding(18)
        }
        .background(WA.background)
    }

    private struct Cell: View {
        @Environment(WAStore.self) private var store
        let message: Message
        let chat: Chat
        @State private var image: NSImage?
        var body: some View {
            Color.black.opacity(0.3).aspectRatio(1, contentMode: .fit)
                .overlay { if let image { Image(nsImage: image).resizable().scaledToFill() } }
                .overlay(alignment: .bottomLeading) { if message.kind != .photo { Image(systemName: "video.fill").foregroundStyle(.white).padding(6) } }
                .clipped().contentShape(Rectangle())
                .onTapGesture { store.openViewer(message, in: chat) }
                .task { if let e = store.entry(message, in: chat) { image = await Thumbs.shared.image(e, video: message.kind != .photo, size: 300) } }
        }
    }
}

struct MediaViewer: View {
    @Environment(WAStore.self) private var store
    @FocusState private var focused: Bool
    var body: some View {
        if let v = store.viewer, let c = store.chat {
            ZStack {
                Color.black.opacity(0.95).ignoresSafeArea()
                Stage(message: v.current, chat: c).id(v.current.id).padding(.vertical, 60).padding(.horizontal, 70)
                VStack {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(v.current.mine ? "You" : v.current.sender).font(.system(size: 15, weight: .semibold))
                            Text(v.current.time.formatted(date: .abbreviated, time: .shortened)).font(.system(size: 12)).foregroundStyle(WA.secondary)
                        }
                        Spacer()
                        Button { store.viewer = nil } label: { Image(systemName: "xmark").font(.system(size: 18)) }.buttonStyle(.plain).keyboardShortcut(.cancelAction)
                    }
                    Spacer()
                }
                .padding(.horizontal, 22).padding(.top, 30)
            }
            .focusable().focused($focused).focusEffectDisabled().onAppear { focused = true }
            .onKeyPress(.leftArrow) { step(-1); return .handled }
            .onKeyPress(.rightArrow) { step(1); return .handled }
        }
    }
    private func step(_ d: Int) {
        guard var v = store.viewer, v.items.indices.contains(v.index + d) else { return }
        v.index += d
        store.viewer = v
    }

    private struct Stage: View {
        @Environment(WAStore.self) private var store
        let message: Message
        let chat: Chat
        @State private var image: NSImage?
        @State private var player: AVPlayer?
        var body: some View {
            ZStack {
                if let player { PlayerLayer(player: player) } else if let image { Image(nsImage: image).resizable().scaledToFit() } else { ProgressView() }
            }
            .task {
                guard let e = store.entry(message, in: chat) else { return }
                if message.kind == .photo {
                    if let cg = await Task.detached(operation: { MediaLoader.image(e, maxPixel: 2400) }).value { image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height)) }
                } else if let a = try? MediaLoader.asset(e) {
                    let p = AVPlayer(playerItem: AVPlayerItem(asset: a))
                    if message.kind == .gif { p.actionAtItemEnd = .none; NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: p.currentItem, queue: .main) { _ in p.seek(to: .zero); p.play() } }
                    player = p
                    p.play()
                }
            }
            .onDisappear { player?.pause() }
        }
    }
}

struct PlayerLayer: NSViewRepresentable {
    let player: AVPlayer
    func makeNSView(context: Context) -> AVPlayerView {
        let v = AVPlayerView()
        v.controlsStyle = .floating
        v.player = player
        return v
    }
    func updateNSView(_ v: AVPlayerView, context: Context) { v.player = player }
}
