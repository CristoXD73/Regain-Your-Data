import AppKit
import AVFoundation
import QuartzCore

/// Copies snaps out of the export with readable names ("Snap 2019-06-15 14.30.00.mp4") and the
/// right file dates. Optionally burns the caption/sticker layer into photos and videos.
@MainActor
enum Exporter {
    static func export(_ snaps: [Snap]) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Export \(snaps.count) Snap\(snaps.count == 1 ? "" : "s")"
        let burn = NSButton(checkboxWithTitle: "Include captions and stickers", target: nil, action: nil)
        burn.state = .on
        panel.accessoryView = burn
        panel.isAccessoryViewDisclosed = true
        guard panel.runModal() == .OK, let dest = panel.url else { return }
        let withOverlay = burn.state == .on
        Task.detached {
            for s in snaps { await write(s, to: dest, withOverlay: withOverlay) }
            await MainActor.run { NSWorkspace.shared.open(dest) }
        }
    }

    nonisolated private static func write(_ s: Snap, to dir: URL, withOverlay: Bool) async {
        let ext = s.isVideo ? "mp4" : ((s.name as NSString).pathExtension.lowercased() == "png" ? "png" : "jpg")
        let f = DateFormatter()
        f.dateFormat = s.time == nil ? "yyyy-MM-dd" : "yyyy-MM-dd HH.mm.ss"
        let base = "Snap \(f.string(from: s.date))"
        var url = dir.appendingPathComponent("\(base).\(ext)")
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) { url = dir.appendingPathComponent("\(base) \(n).\(ext)"); n += 1 }

        let overlay = withOverlay ? s.overlay.flatMap { SnapMedia.cgImage($0, maxPixel: 4096) } : nil
        if s.isVideo {
            if let overlay, await burnVideo(s, overlay: overlay, to: url) {} else { copy(s.source, to: url) }
        } else if let overlay, let base = SnapMedia.cgImage(s.source, maxPixel: 8192),
                  let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil) {
            CGImageDestinationAddImage(dest, SnapMedia.composite(base, overlay: overlay), [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary)
            CGImageDestinationFinalize(dest)
        } else {
            copy(s.source, to: url)
        }
        try? FileManager.default.setAttributes([.creationDate: s.date, .modificationDate: s.date], ofItemAtPath: url.path)
    }

    nonisolated private static func copy(_ source: MediaSource, to url: URL) {
        switch source {
        case .file(let u): try? FileManager.default.copyItem(at: u, to: url)
        case .zip(let e): try? e.archive.extract(e, to: url)
        }
    }

    /// Re-encodes the clip with the overlay drawn on every frame.
    nonisolated private static func burnVideo(_ s: Snap, overlay: CGImage, to url: URL) async -> Bool {
        guard let file = try? await MediaAccess.fileURL(s.source) else { return false }
        let asset = AVURLAsset(url: file)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let (natural, transform) = try? await track.load(.naturalSize, .preferredTransform),
              let composition = try? await AVMutableVideoComposition.videoComposition(withPropertiesOf: asset) else { return false }
        let r = CGRect(origin: .zero, size: natural).applying(transform)
        let size = CGSize(width: abs(r.width), height: abs(r.height))
        let parent = CALayer(), video = CALayer(), top = CALayer()
        parent.frame = CGRect(origin: .zero, size: size)
        video.frame = parent.frame
        top.frame = SnapMedia.aspectFit(CGSize(width: overlay.width, height: overlay.height), in: parent.frame)
        top.contents = overlay
        parent.addSublayer(video)
        parent.addSublayer(top)
        composition.renderSize = size
        composition.animationTool = AVVideoCompositionCoreAnimationTool(postProcessingAsVideoLayer: video, in: parent)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else { return false }
        session.videoComposition = composition
        do {
            try await session.export(to: url, as: .mp4)
            return true
        } catch {
            try? FileManager.default.removeItem(at: url)
            return false
        }
    }
}
