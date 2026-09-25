import SwiftUI

/// The account laid out like an Instagram profile: ring avatar, stats, story circles for your top
/// friends, messages per year, and a photo grid.
struct ProfileView: View {
    @Environment(InstaStore.self) private var store

    var body: some View {
        if let a = store.account {
            let msgs = a.threads.flatMap(\.messages)
            let media = store.allMedia
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    HStack(alignment: .center, spacing: 60) {
                        Avatar(name: a.owner, size: 150, ring: true)
                        VStack(alignment: .leading, spacing: 18) {
                            Text(a.id).font(.system(size: 22, weight: .regular))
                            HStack(spacing: 36) {
                                stat(a.threads.filter { store.effectiveFolder($0) == .inbox }.count, "chats")
                                stat(msgs.count, "messages")
                                stat(media.count, "photos & videos")
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                Text(a.owner).font(.system(size: 14, weight: .semibold))
                                Text("Messages you sent: \(msgs.filter(\.mine).count.formatted())").font(.system(size: 14))
                                if !a.exportDate.isEmpty { Text("Downloaded from Instagram on \(a.exportDate)").font(.system(size: 14)).foregroundStyle(IG.secondary) }
                            }
                        }
                    }
                    .padding(.top, 30)

                    // Story-highlight circles: the people you talk to most.
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 22) {
                            ForEach(store.topFriends) { t in
                                Button { store.open(t) } label: {
                                    VStack(spacing: 6) {
                                        Avatar(name: store.title(t), size: 64, ring: true)
                                        Text(store.title(t)).font(.system(size: 12, weight: .semibold)).lineLimit(1).frame(width: 78)
                                    }
                                }
                                .buttonStyle(.plain)
                                .help("\(t.messages.count.formatted()) messages")
                            }
                        }
                    }

                    ActivityChart(messages: msgs)

                    Rectangle().fill(IG.separator).frame(height: 1)
                    HStack(spacing: 6) {
                        Image(systemName: "square.grid.3x3")
                        Text("PHOTOS & VIDEOS").font(.system(size: 12, weight: .semibold)).kerning(1)
                    }
                    .frame(maxWidth: .infinity)
                    MediaTiles(items: Array(media.prefix(60)))
                }
                .frame(maxWidth: 930)
                .padding(.horizontal, 30).padding(.bottom, 30)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func stat(_ n: Int, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(n.formatted()).font(.system(size: 15, weight: .semibold))
            Text(label).font(.system(size: 15))
        }
    }
}

/// Messages per year as bars in Instagram's gradient.
struct ActivityChart: View {
    let messages: [Message]
    var body: some View {
        let cal = Calendar.current
        let years = Dictionary(grouping: messages.filter { $0.time != .distantPast }, by: { cal.component(.year, from: $0.time) }).mapValues(\.count)
        let maxCount = max(1, years.values.max() ?? 1)
        VStack(alignment: .leading, spacing: 10) {
            Text("Messages per year").font(.system(size: 15, weight: .semibold))
            HStack(alignment: .bottom, spacing: 14) {
                ForEach(years.keys.sorted(), id: \.self) { y in
                    VStack(spacing: 6) {
                        Text(years[y]!.formatted()).font(.system(size: 11)).foregroundStyle(IG.secondary)
                        RoundedRectangle(cornerRadius: 6).fill(IG.gradient)
                            .frame(width: 42, height: max(4, 120 * CGFloat(years[y]!) / CGFloat(maxCount)))
                        Text(String(y)).font(.system(size: 12, weight: .semibold))
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(IG.surface, in: RoundedRectangle(cornerRadius: 16))
    }
}

/// Every photo and video in the account, newest first.
struct AccountMedia: View {
    @Environment(InstaStore.self) private var store
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Photos & videos").font(.system(size: 22, weight: .bold)).padding(.top, 34)
                MediaTiles(items: store.allMedia)
            }
            .padding(.horizontal, 24).padding(.bottom, 24)
        }
    }
}

/// Instagram's 3-column square grid. Clicking opens the viewer; the chat name shows on hover.
struct MediaTiles: View {
    @Environment(InstaStore.self) private var store
    let items: [(Media, Thread)]
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 3), spacing: 4) {
            ForEach(items, id: \.0.path) { m, t in Tile(media: m, thread: t) }
        }
    }

    private struct Tile: View {
        @Environment(InstaStore.self) private var store
        let media: Media
        let thread: Thread
        @State private var image: NSImage?
        @State private var hover = false
        var body: some View {
            Color(white: 0.12)
                .aspectRatio(1, contentMode: .fit)
                .overlay { if let image { Image(nsImage: image).resizable().scaledToFill() } }
                .overlay(alignment: .topTrailing) {
                    if media.kind == .video { Image(systemName: "play.rectangle.fill").foregroundStyle(.white).shadow(radius: 3).padding(8) }
                }
                .overlay {
                    if hover {
                        ZStack {
                            Color.black.opacity(0.35)
                            Label(store.title(thread), systemImage: "bubble.left.fill").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                        }
                    }
                }
                .clipped()
                .contentShape(Rectangle())
                .onHover { hover = $0 }
                .onTapGesture { store.openViewer(media, in: thread) }
                .task(id: media.path) { if let e = store.entry(media) { image = await Thumbs.shared.image(e, kind: media.kind, size: 400) } }
        }
    }
}
