import AVKit
import SwiftUI

/// Full-window photo/video viewer for a chat's media, with arrow-key navigation.
struct MediaViewer: View {
    @Environment(InstaStore.self) private var store
    @FocusState private var focused: Bool

    var body: some View {
        if let v = store.viewer {
            ZStack {
                Color.black.opacity(0.96).ignoresSafeArea()
                Stage(media: v.current).id(v.current.path).padding(.vertical, 56).padding(.horizontal, 70)
                HStack {
                    arrow("chevron.left", v.index > 0) { step(-1) }
                    Spacer()
                    arrow("chevron.right", v.index < v.items.count - 1) { step(1) }
                }
                .padding(.horizontal, 14)
                VStack {
                    HStack {
                        Text("\(v.index + 1) of \(v.items.count)").font(.system(size: 13, weight: .semibold)).foregroundStyle(IG.secondary)
                        Spacer()
                        Button { store.viewer = nil } label: {
                            Image(systemName: "xmark").font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
                        }
                        .buttonStyle(.plain).keyboardShortcut(.cancelAction)
                    }
                    Spacer()
                }
                .padding(.horizontal, 22).padding(.top, 32)
            }
            .focusable().focused($focused).focusEffectDisabled()
            .onAppear { focused = true }
            .onKeyPress(.leftArrow) { step(-1); return .handled }
            .onKeyPress(.rightArrow) { step(1); return .handled }
            .onKeyPress(.escape) { store.viewer = nil; return .handled }
        }
    }

    private func step(_ d: Int) {
        guard var v = store.viewer, v.items.indices.contains(v.index + d) else { return }
        v.index += d
        store.viewer = v
    }

    private func arrow(_ icon: String, _ on: Bool, _ f: @escaping () -> Void) -> some View {
        Button(action: f) {
            Image(systemName: icon).font(.system(size: 18, weight: .bold)).foregroundStyle(.black)
                .frame(width: 34, height: 34).background(Color.white.opacity(0.85), in: Circle())
        }
        .buttonStyle(.plain).opacity(on ? 1 : 0).disabled(!on)
    }
}

private struct Stage: View {
    @Environment(InstaStore.self) private var store
    let media: Media
    @State private var image: NSImage?
    @State private var player: AVPlayer?

    var body: some View {
        ZStack {
            if media.kind == .video {
                if let player { PlayerLayer(player: player) } else { ProgressView() }
            } else if let image {
                Image(nsImage: image).resizable().scaledToFit()
            } else {
                ProgressView()
            }
        }
        .task {
            guard let e = store.entry(media) else { return }
            if media.kind == .video {
                if let a = try? MediaLoader.asset(e) { let p = AVPlayer(playerItem: AVPlayerItem(asset: a)); player = p; p.play() }
            } else if let cg = await Task.detached(operation: { MediaLoader.image(e, maxPixel: 2400) }).value {
                image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
            }
        }
        .onDisappear { player?.pause() }
    }
}

struct PlayerLayer: NSViewRepresentable {
    let player: AVPlayer
    func makeNSView(context: Context) -> AVPlayerView {
        let v = AVPlayerView()
        v.controlsStyle = .floating
        v.videoGravity = .resizeAspect
        v.player = player
        return v
    }
    func updateNSView(_ v: AVPlayerView, context: Context) { v.player = player }
}
