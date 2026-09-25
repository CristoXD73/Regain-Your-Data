import AppKit
import AVFoundation
import ImageIO
import ObjectiveC

/// Opens any snap as an AVAsset. Files on disk open directly; zipped clips (all under 40 MB) are
/// unpacked into memory and served to AVFoundation from there, so nothing is written to disk.
enum SnapMedia {
    private static var loaderKey: UInt8 = 0

    static func asset(_ source: MediaSource) throws -> AVURLAsset {
        switch source {
        case .file(let u):
            return AVURLAsset(url: u)
        case .zip(let e):
            let data = try e.archive.data(e)
            let ext = (e.name as NSString).pathExtension.lowercased()
            let url = URL(string: "snapmem://\(stableHash(e.path)).\(ext)")!
            let asset = AVURLAsset(url: url)
            let loader = MemoryLoader(data: data, type: ext == "mov" ? "com.apple.quicktime-movie" : "public.mpeg-4")
            asset.resourceLoader.setDelegate(loader, queue: MemoryLoader.queue)
            // The resource loader holds its delegate weakly; tie the loader's life to the asset.
            objc_setAssociatedObject(asset, &loaderKey, loader, .OBJC_ASSOCIATION_RETAIN)
            return asset
        }
    }

    static func image(_ source: MediaSource) -> CGImageSource? {
        switch source {
        case .file(let u): return CGImageSourceCreateWithURL(u as CFURL, nil)
        case .zip(let e): return (try? e.archive.data(e)).flatMap { CGImageSourceCreateWithData($0 as CFData, nil) }
        }
    }

    static func cgImage(_ source: MediaSource, maxPixel: Int) -> CGImage? {
        guard let src = image(source) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
    }

    static func videoFrame(_ asset: AVAsset, maxPixel: Int, at seconds: Double = 0.5) async -> CGImage? {
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: maxPixel, height: maxPixel)
        gen.requestedTimeToleranceBefore = .positiveInfinity
        gen.requestedTimeToleranceAfter = .positiveInfinity
        if let cg = try? await gen.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image { return cg }
        return try? await gen.image(at: .zero).image
    }

    /// Draws a snap's caption/sticker layer over its picture, the way Snapchat shows it.
    static func composite(_ base: CGImage, overlay: CGImage?) -> CGImage {
        guard let overlay else { return base }
        let w = base.width, h = base.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return base }
        ctx.interpolationQuality = .high
        ctx.draw(base, in: CGRect(x: 0, y: 0, width: w, height: h))
        ctx.draw(overlay, in: aspectFit(CGSize(width: overlay.width, height: overlay.height), in: CGRect(x: 0, y: 0, width: w, height: h)))
        return ctx.makeImage() ?? base
    }

    static func aspectFit(_ size: CGSize, in rect: CGRect) -> CGRect {
        guard size.width > 0, size.height > 0 else { return rect }
        let s = min(rect.width / size.width, rect.height / size.height)
        let w = size.width * s, h = size.height * s
        return CGRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h)
    }
}

/// Serves an in-memory video to AVFoundation, with byte-range support for seeking.
final class MemoryLoader: NSObject, AVAssetResourceLoaderDelegate, @unchecked Sendable {
    static let queue = DispatchQueue(label: "SnapVault.MemoryLoader")
    let data: Data
    let type: String

    init(data: Data, type: String) {
        self.data = data
        self.type = type
    }

    func resourceLoader(_ loader: AVAssetResourceLoader, shouldWaitForLoadingOfRequestedResource request: AVAssetResourceLoadingRequest) -> Bool {
        if let info = request.contentInformationRequest {
            info.contentType = type
            info.contentLength = Int64(data.count)
            info.isByteRangeAccessSupported = true
        }
        if let dr = request.dataRequest {
            let start = Int(dr.requestedOffset)
            let end = dr.requestsAllDataToEndOfResource ? data.count : min(data.count, Int(dr.requestedOffset) + dr.requestedLength)
            if start < end { dr.respond(with: data.subdata(in: start..<end)) }
        }
        request.finishLoading()
        return true
    }
}

/// What a video says about itself: length and when it was recorded.
struct VideoInfo: Codable {
    var duration: Double?
    var recorded: Date?
    /// False for voice notes: chat .mp4 files with only an audio track.
    var hasVideo: Bool?
}

/// Thumbnails (with overlays drawn in) and video info, cached on the Mac's SSD.
final class Thumbnails: @unchecked Sendable {
    static let shared = Thumbnails()
    let dir: URL
    private let memory = NSCache<NSString, NSImage>()
    private let gate = AsyncGate(limit: 6)

    init() {
        dir = Paths.caches.appendingPathComponent("thumbs")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        memory.countLimit = 2500
    }

    private func key(_ s: Snap, _ size: Int) -> String { stableHash(s.cacheKey) + "-\(size)" }

    func cached(_ s: Snap, size: Int) -> NSImage? { memory.object(forKey: key(s, size) as NSString) }

    func isOnDisk(_ s: Snap, size: Int) -> Bool {
        FileManager.default.fileExists(atPath: dir.appendingPathComponent(key(s, size) + ".jpg").path)
    }

    /// Returns the thumbnail, making it if needed. For videos, `info` receives what the clip
    /// recorded about itself (so each clip is only unpacked once).
    func image(_ s: Snap, size: Int, info: ((VideoInfo) -> Void)? = nil) async -> NSImage? {
        let k = key(s, size)
        if let img = memory.object(forKey: k as NSString) { return img }
        let file = dir.appendingPathComponent(k + ".jpg")
        if info == nil, let img = NSImage(contentsOf: file) {
            memory.setObject(img, forKey: k as NSString)
            return img
        }
        await gate.enter()
        defer { Task { await gate.leave() } }
        if Task.isCancelled { return nil }

        var base: CGImage?
        if s.isVideo {
            if let asset = try? SnapMedia.asset(s.source) {
                let hasVideo = !((try? await asset.loadTracks(withMediaType: .video)) ?? []).isEmpty
                if hasVideo { base = await SnapMedia.videoFrame(asset, maxPixel: size * 2) }
                if let info {
                    var v = VideoInfo()
                    v.hasVideo = hasVideo
                    if let d = try? await asset.load(.duration), d.isNumeric { v.duration = d.seconds }
                    if let c = try? await asset.load(.creationDate) { v.recorded = try? await c.load(.dateValue) }
                    info(v)
                }
            }
        } else {
            base = SnapMedia.cgImage(s.source, maxPixel: size * 2)
        }
        guard let base else { return nil }
        let overlay = s.overlay.flatMap { SnapMedia.cgImage($0, maxPixel: size * 2) }
        let cg = SnapMedia.composite(base, overlay: overlay)
        let img = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        memory.setObject(img, forKey: k as NSString)
        if let dest = CGImageDestinationCreateWithURL(file as CFURL, "public.jpeg" as CFString, 1, nil) {
            CGImageDestinationAddImage(dest, cg, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
            CGImageDestinationFinalize(dest)
        }
        return img
    }
}

actor AsyncGate {
    private let limit: Int
    private var running = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []
    init(limit: Int) { self.limit = limit }
    func enter() async {
        if running < limit { running += 1; return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func leave() {
        if waiters.isEmpty { running -= 1 } else { waiters.removeFirst().resume() }
    }
}
