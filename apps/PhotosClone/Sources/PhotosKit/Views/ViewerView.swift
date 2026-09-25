import AVKit
import SwiftUI

struct ViewerView: View {
    @Environment(LibraryStore.self) private var store
    @FocusState private var focused: Bool

    var body: some View {
        if let v = store.viewer {
            let a = v.current
            ZStack {
                Color.black.ignoresSafeArea()
                MediaStage(asset: a)
                    .id(a.id)
                    .padding(.top, 52)
                    .padding(.bottom, 76)

                HStack {
                    navButton("chevron.left", enabled: v.index > 0) { step(-1) }
                    Spacer()
                    navButton("chevron.right", enabled: v.index < v.assets.count - 1) { step(1) }
                }
                .padding(.horizontal, 12)

                VStack(spacing: 0) {
                    topBar(a, v)
                    Spacer()
                    Filmstrip(assets: v.assets, index: v.index) { i in store.viewer?.index = i }
                }
            }
            .focusable()
            .focused($focused)
            .focusEffectDisabled()
            .onAppear { focused = true }
            .onKeyPress(.leftArrow) { step(-1); return .handled }
            .onKeyPress(.rightArrow) { step(1); return .handled }
            .onKeyPress(.escape) { store.viewer = nil; return .handled }
            .onKeyPress(characters: .init(charactersIn: "i")) { _ in store.showInfo.toggle(); return .handled }
            .onKeyPress(characters: .init(charactersIn: "."), phases: .down) { _ in
                if !a.isDeleted { store.toggleFavorite([a.id]) }
                return .handled
            }
            .onKeyPress(.delete, phases: .down) { press in
                guard press.modifiers.contains(.command) else { return .ignored }
                if a.isDeleted { store.confirmDeleteNow = [a.id] } else { store.moveToTrash([a.id]) }
                return .handled
            }
        }
    }

    private func step(_ d: Int) {
        guard var v = store.viewer else { return }
        v.index = max(0, min(v.assets.count - 1, v.index + d))
        store.viewer = v
        store.selectedIDs = [v.current.id]
    }

    private func navButton(_ icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.title2.weight(.semibold))
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .opacity(enabled ? 0.9 : 0)
        .disabled(!enabled)
    }

    private func topBar(_ a: Asset, _ v: ViewerState) -> some View {
        HStack(spacing: 14) {
            Button { store.viewer = nil } label: {
                Label("Back", systemImage: "chevron.backward")
            }
            .keyboardShortcut(.cancelAction)

            VStack(alignment: .leading, spacing: 1) {
                Text(a.date == .distantPast ? a.name : a.date.formatted(date: .long, time: .omitted)).font(.headline)
                Text(a.date == .distantPast ? "Unknown date" : a.date.formatted(date: .omitted, time: .shortened) + " · " + a.name)
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(v.index + 1) of \(v.assets.count)").font(.caption).foregroundStyle(.secondary).monospacedDigit()
            if a.isHidden { Image(systemName: "eye.slash").foregroundStyle(.secondary).help("Hidden") }
            if a.isDeleted {
                Button("Recover") { store.restore([a.id]) }
                Button { store.confirmDeleteNow = [a.id] } label: { Image(systemName: "trash.slash") }
                    .help("Delete now")
            } else {
                Button { store.toggleFavorite([a.id]) } label: {
                    Image(systemName: a.isFavorite ? "heart.fill" : "heart").foregroundStyle(a.isFavorite ? .pink : .white)
                }
                .help("Favorite (.)")
                Button { store.moveToTrash([a.id]) } label: { Image(systemName: "trash") }
                    .help("Delete (⌘⌫)")
            }
            Button { store.revealInFinder([a]) } label: { Image(systemName: "folder") }
                .help(a.isZipped ? "Show the zip that holds it in Finder" : "Show in Finder")
            if let url = a.source.fileURL {
                ShareLink(items: [url] + (a.pairedSource?.fileURL.map { [$0] } ?? [])) { Image(systemName: "square.and.arrow.up") }
            } else {
                Button { store.export([a]) } label: { Image(systemName: "square.and.arrow.up") }
                    .help("Export the original out of its zip")
            }
            Button { store.showInfo.toggle() } label: { Image(systemName: store.showInfo ? "info.circle.fill" : "info.circle") }
                .help("Info (⌘I)")
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(.black.opacity(0.6))
        .environment(\.colorScheme, .dark)
    }
}

/// Shows one asset: zoomable still, video player, or Live Photo that plays on hover.
struct MediaStage: View {
    let asset: Asset
    @State private var image: NSImage?
    @State private var zoom: CGFloat = 1
    @State private var baseZoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var baseOffset: CGSize = .zero
    @State private var playingLive = false

    var body: some View {
        switch asset.kind {
        case .video:
            SourceVideo(source: asset.source)
        case .photo, .livePhoto:
            GeometryReader { geo in
                ZStack {
                    if let image {
                        Image(nsImage: image)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                            .scaleEffect(zoom)
                            .offset(offset)
                    } else {
                        ProgressView().tint(.white)
                    }
                    if playingLive, let mov = asset.pairedSource {
                        SourceVideo(source: mov, controls: false, quiet: true) { playingLive = false }
                            .allowsHitTesting(false)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .contentShape(Rectangle())
                .gesture(MagnifyGesture()
                    .onChanged { zoom = max(1, min(8, baseZoom * $0.magnification)) }
                    .onEnded { _ in baseZoom = zoom; if zoom == 1 { offset = .zero; baseOffset = .zero } })
                .simultaneousGesture(DragGesture()
                    .onChanged { g in
                        guard zoom > 1 else { return }
                        offset = CGSize(width: baseOffset.width + g.translation.width, height: baseOffset.height + g.translation.height)
                    }
                    .onEnded { _ in baseOffset = offset })
                .onTapGesture(count: 2) {
                    withAnimation(.spring(duration: 0.3)) {
                        if zoom > 1 { zoom = 1; offset = .zero } else { zoom = 2.5 }
                        baseZoom = zoom; baseOffset = offset
                    }
                }
            }
            .overlay(alignment: .topLeading) {
                if asset.kind == .livePhoto {
                    Label("LIVE", systemImage: "livephoto")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.ultraThinMaterial, in: Capsule())
                        .environment(\.colorScheme, .dark)
                        .padding(12)
                        .onHover { if $0 { playingLive = true } }
                        .onTapGesture { playingLive = true }
                        .help("Hover or click to play the Live Photo")
                }
            }
            .task {
                image = await ThumbnailLoader.shared.image(for: asset, size: 512)
                if let full = await ThumbnailLoader.displayImage(asset.source) { image = full }
            }
        }
    }
}

/// Plays a video from disk, or unpacks it from its zip into the SSD cache first.
struct SourceVideo: View {
    let source: MediaSource
    var controls = true
    /// Live Photo motion: small enough that a spinner would only flash, so none is shown.
    var quiet = false
    var onEnd: (() -> Void)? = nil
    @State private var url: URL?
    @State private var failed = false

    var body: some View {
        ZStack {
            if let url {
                VideoStage(url: url, autoplay: true, muted: false, loop: false, controls: controls, onEnd: onEnd)
            } else if failed {
                Label("Couldn't open this video", systemImage: "exclamationmark.triangle").foregroundStyle(.white)
            } else if !quiet {
                VStack(spacing: 10) {
                    ProgressView().tint(.white)
                    if case .zip(let e) = source {
                        Text("Unpacking \(ByteCountFormatter.string(fromByteCount: Int64(e.size), countStyle: .file)) video from \(e.archive.url.deletingPathExtension().lastPathComponent)…")
                            .font(.callout).foregroundStyle(.white.opacity(0.8))
                    }
                }
            }
        }
        .task(id: source) {
            do { url = try await MediaAccess.fileURL(source) } catch { failed = true }
        }
    }
}

struct VideoStage: NSViewRepresentable {
    let url: URL
    var autoplay = true
    var muted = false
    var loop = false
    var controls = true
    var onEnd: (() -> Void)? = nil

    func makeNSView(context: Context) -> AVPlayerView {
        let v = AVPlayerView()
        v.controlsStyle = controls ? .floating : .none
        v.showsFullScreenToggleButton = true
        v.videoGravity = .resizeAspect
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        player.isMuted = muted
        v.player = player
        context.coordinator.observe(item, loop: loop, player: player, onEnd: onEnd)
        if autoplay { player.play() }
        return v
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {}

    static func dismantleNSView(_ nsView: AVPlayerView, coordinator: Coordinator) {
        nsView.player?.pause()
        nsView.player = nil
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        private var token: NSObjectProtocol?
        func observe(_ item: AVPlayerItem, loop: Bool, player: AVPlayer, onEnd: (() -> Void)?) {
            token = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { _ in
                if loop { player.seek(to: .zero); player.play() } else { onEnd?() }
            }
        }
        deinit { if let token { NotificationCenter.default.removeObserver(token) } }
    }
}

struct Filmstrip: View {
    let assets: [Asset]
    let index: Int
    let select: (Int) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 3) {
                    ForEach(Array(assets.enumerated()), id: \.element.id) { i, a in
                        StripThumb(asset: a, current: i == index)
                            .id(i)
                            .onTapGesture { select(i) }
                    }
                }
                .padding(.horizontal, 12)
            }
            .frame(height: 64)
            .padding(.vertical, 6)
            .background(.black.opacity(0.6))
            .onAppear { proxy.scrollTo(index, anchor: .center) }
            .onChange(of: index) { _, i in withAnimation { proxy.scrollTo(i, anchor: .center) } }
        }
    }
}

private struct StripThumb: View {
    let asset: Asset
    let current: Bool
    @State private var image: NSImage?

    var body: some View {
        Color.gray.opacity(0.3)
            .frame(width: current ? 64 : 40, height: 56)
            .overlay { if let image { Image(nsImage: image).resizable().scaledToFill() } }
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.white, lineWidth: current ? 2 : 0))
            .animation(.easeOut(duration: 0.15), value: current)
            .task { image = await ThumbnailLoader.shared.image(for: asset, size: 256) }
    }
}
