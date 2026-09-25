import AVKit
import SwiftUI

struct PlayerView: View {
    @Environment(VaultStore.self) private var store
    @State private var progress: Double = 0
    @State private var paused = false
    @FocusState private var focused: Bool

    /// Photos in a story stay up this long, as in Snapchat.
    private let photoSeconds = 5.0

    var body: some View {
        if let p = store.playback {
            let s = p.current
            ZStack {
                Color.black.ignoresSafeArea()
                SnapStage(snap: s, loop: !p.isStory, paused: paused) { next() }
                    .id(s.id)
                    .padding(.vertical, 60)
                // Tap zones: left third back, the rest forward.
                HStack(spacing: 0) {
                    Color.clear.contentShape(Rectangle()).frame(maxWidth: .infinity).onTapGesture { step(-1) }
                    Color.clear.contentShape(Rectangle()).frame(maxWidth: .infinity).onTapGesture { step(1) }
                    Color.clear.contentShape(Rectangle()).frame(maxWidth: .infinity).onTapGesture { step(1) }
                }
                .padding(.vertical, 60)
                VStack(spacing: 10) {
                    if p.isStory { bars(p) }
                    header(p, s)
                    Spacer()
                    footer(s)
                }
                .padding(.horizontal, 20).padding(.top, 34).padding(.bottom, 16)
            }
            .focusable().focused($focused).focusEffectDisabled()
            .onAppear { focused = true }
            .onKeyPress(.escape) { store.playback = nil; return .handled }
            .onKeyPress(.rightArrow) { step(1); return .handled }
            .onKeyPress(.leftArrow) { step(-1); return .handled }
            .onKeyPress(.space) { paused.toggle(); return .handled }
            .task(id: "\(s.id)-\(p.isStory)") { await runTimer(p) }
        }
    }

    /// Story mode: photos advance after a few seconds; videos advance when they end (onEnd).
    private func runTimer(_ p: Playback) async {
        progress = 0
        guard p.isStory, !p.current.isVideo else { return }
        let start = Date()
        var elapsed = 0.0
        while elapsed < photoSeconds {
            try? await Task.sleep(for: .milliseconds(50))
            if Task.isCancelled { return }
            if paused { continue }
            elapsed = Date().timeIntervalSince(start)
            progress = min(1, elapsed / photoSeconds)
        }
        next()
    }

    private func next() {
        guard let p = store.playback else { return }
        if p.index < p.snaps.count - 1 { step(1) } else if p.isStory { store.playback = nil }
    }

    private func step(_ d: Int) {
        guard var p = store.playback else { return }
        let i = p.index + d
        guard p.snaps.indices.contains(i) else { if d > 0 && p.isStory { store.playback = nil }; return }
        p.index = i
        store.playback = p
    }

    private func bars(_ p: Playback) -> some View {
        HStack(spacing: 3) {
            ForEach(p.snaps.indices, id: \.self) { i in
                GeometryReader { g in
                    Capsule().fill(Color.white.opacity(0.3))
                        .overlay(alignment: .leading) {
                            Capsule().fill(Color.white)
                                .frame(width: g.size.width * (i < p.index ? 1 : i == p.index ? (p.current.isVideo ? 0.5 : progress) : 0))
                        }
                }
                .frame(height: 3)
            }
        }
    }

    private func header(_ p: Playback, _ s: Snap) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                if let t = p.title { Text(t).font(Theme.body(12, .bold)).foregroundStyle(Theme.yellow) }
                Text(dateLine(s)).font(Theme.title(17)).foregroundStyle(.white)
                Text(sourceLine(s)).font(Theme.body(12, .medium)).foregroundStyle(Theme.secondary)
            }
            Spacer()
            Text("\(p.index + 1) / \(p.snaps.count)").font(Theme.body(12, .bold)).foregroundStyle(Theme.secondary).monospacedDigit()
            Button { store.playback = nil } label: {
                Image(systemName: "xmark").font(.system(size: 15, weight: .heavy)).foregroundStyle(.white)
                    .frame(width: 34, height: 34).background(Color.white.opacity(0.15), in: Circle())
            }
            .buttonStyle(.plain).keyboardShortcut(.cancelAction)
        }
        .shadow(color: .black.opacity(0.5), radius: 4)
    }

    private func footer(_ s: Snap) -> some View {
        HStack(spacing: 10) {
            Spacer()
            action(store.isEyesOnly(s) ? "Remove from My Eyes Only" : "My Eyes Only", "lock.fill") { store.toggleEyesOnly([s]) }
            action("Export", "square.and.arrow.up") { Exporter.export([s]) }
            action("Show in Finder", "folder") { store.revealInFinder([s]) }
            Spacer()
        }
    }

    private func action(_ t: String, _ icon: String, _ f: @escaping () -> Void) -> some View {
        Button(action: f) {
            Label(t, systemImage: icon).font(Theme.body(12, .bold)).foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 8).background(Color.white.opacity(0.15), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func dateLine(_ s: Snap) -> String {
        if s.day == .distantPast && s.time == nil { return "Unknown date" }
        let d = s.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year())
        return s.time.map { "\(d) · \($0.formatted(date: .omitted, time: .shortened))" } ?? d
    }

    private func sourceLine(_ s: Snap) -> String {
        switch s.origin {
        case .memory: return s.overlay != nil ? "Memories · with caption" : "Memories"
        case .story: return "Shared Story"
        case .saved: return "Saved Snap"
        case .chat:
            let chat = s.conversation.map { store.title(for: $0) } ?? "a chat"
            if store.isVoiceNote(s) { return s.sentByMe ? "Voice note you sent in \(chat)" : "Voice note from \(s.sender ?? "someone") in \(chat)" }
            return s.sentByMe ? "You sent in \(chat)" : "\(s.sender ?? "Someone") in \(chat)"
        }
    }
}

/// Media plus its caption/sticker layer, both fitted to the same frame so they line up.
struct SnapStage: View {
    @Environment(VaultStore.self) private var store
    let snap: Snap
    var loop: Bool
    var paused: Bool
    var onEnd: () -> Void
    @State private var image: NSImage?
    @State private var overlay: NSImage?
    @State private var player: AVPlayer?

    var body: some View {
        ZStack {
            if store.isVoiceNote(snap) {
                VStack(spacing: 16) {
                    Image(systemName: "waveform").font(.system(size: 90, weight: .bold)).foregroundStyle(.white)
                        .symbolEffect(.variableColor.iterative, isActive: !paused)
                    Text("Voice note").font(Theme.title(20)).foregroundStyle(.white)
                }
                .frame(width: 320, height: 420)
                .background(Theme.voice, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            } else if snap.isVideo {
                if let player { PlayerLayer(player: player) } else { ProgressView().tint(Theme.yellow) }
            } else if let image {
                Image(nsImage: image).resizable().scaledToFit()
            } else {
                ProgressView().tint(Theme.yellow)
            }
            if let overlay { Image(nsImage: overlay).resizable().scaledToFit().allowsHitTesting(false) }
        }
        .onChange(of: paused) { _, p in if p { player?.pause() } else { player?.play() } }
        .task {
            if let o = snap.overlay, let cg = SnapMedia.cgImage(o, maxPixel: 2400) {
                overlay = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
            }
            if snap.isVideo {
                guard let asset = try? SnapMedia.asset(snap.source) else { return }
                let item = AVPlayerItem(asset: asset)
                let p = AVPlayer(playerItem: item)
                NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { _ in
                    if loop { p.seek(to: .zero); p.play() } else { onEnd() }
                }
                player = p
                p.play()
            } else if let cg = SnapMedia.cgImage(snap.source, maxPixel: 2400) {
                image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
            }
        }
        .onDisappear { player?.pause(); player = nil }
    }
}

/// A bare video layer (Snapchat shows no playback controls), fitted like the overlay.
struct PlayerLayer: NSViewRepresentable {
    let player: AVPlayer
    func makeNSView(context: Context) -> AVPlayerView {
        let v = AVPlayerView()
        v.controlsStyle = .none
        v.videoGravity = .resizeAspect
        v.player = player
        return v
    }
    func updateNSView(_ v: AVPlayerView, context: Context) { v.player = player }
}
