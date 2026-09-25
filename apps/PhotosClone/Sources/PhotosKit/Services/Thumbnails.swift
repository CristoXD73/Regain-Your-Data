import AppKit
import AVFoundation
import ImageIO
import QuickLookThumbnailing

/// Thumbnails come from the embedded preview when the file has one (HEIC and iPhone JPEGs do),
/// otherwise from a decode, a video frame or Quick Look. Results are kept in memory and as JPEGs
/// under ~/Library/Caches/PhotosClone/thumbs so scrolling stays smooth on later launches.
final class ThumbnailLoader: @unchecked Sendable {
    static let shared = ThumbnailLoader()

    private let memory = NSCache<NSString, NSImage>()
    let dir: URL
    private let gate = AsyncGate(limit: 8)

    init() {
        memory.countLimit = 3000
        dir = Paths.caches.appendingPathComponent("thumbs")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    func cachedImage(_ asset: Asset, size: Int) -> NSImage? {
        memory.object(forKey: key(asset, size) as NSString)
    }

    /// `keepInMemory: false` is for bulk pre-building: write the disk cache, skip the memory one.
    /// `allowUnpack` lets a zipped video be unpacked to get its frame (used by the one-time
    /// pre-build; normal scrolling never unpacks).
    func image(for asset: Asset, size: Int, keepInMemory: Bool = true, allowUnpack: Bool = false) async -> NSImage? {
        let k = key(asset, size)
        if let img = memory.object(forKey: k as NSString) { return img }
        let file = dir.appendingPathComponent(k + ".jpg")
        if !keepInMemory && FileManager.default.fileExists(atPath: file.path) { return nil }
        if let img = NSImage(contentsOf: file) {
            memory.setObject(img, forKey: k as NSString)
            return img
        }
        await gate.enter()
        defer { Task { await gate.leave() } }
        if Task.isCancelled { return nil }

        guard let cg = await Self.make(asset, maxPixel: size, allowUnpack: allowUnpack) else { return nil }
        let img = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        if keepInMemory { memory.setObject(img, forKey: k as NSString) }
        Self.writeJPEG(cg, to: file)
        return img
    }

    private func key(_ a: Asset, _ size: Int) -> String {
        stableHash(a.cacheKey) + "-\(size)"
    }

    static func make(_ asset: Asset, maxPixel: Int, allowUnpack: Bool = false) async -> CGImage? {
        if asset.kind == .video {
            // Zipped videos only get a frame once they've been unpacked (by playing them, or the
            // one-time pre-build); unpacking while scrolling would thrash the drive.
            var file: URL? = switch asset.source {
            case .file(let u): u
            case .zip(let e): UnpackCache.shared.cachedFile(for: e)
            }
            if file == nil, allowUnpack { file = try? await MediaAccess.fileURL(asset.source) }
            guard let file else { return nil }
            if let cg = await videoFrame(file, maxPixel: maxPixel) { return cg }
            return await quickLook(file, maxPixel: maxPixel)
        }
        switch asset.source {
        case .file(let url):
            if let cg = imageSource(.file(url)).flatMap({ thumb($0, maxPixel: maxPixel) }) { return cg }
            return await quickLook(url, maxPixel: maxPixel)
        case .zip:
            return imageSource(asset.source).flatMap { thumb($0, maxPixel: maxPixel) }
        }
    }

    static func imageSource(_ s: MediaSource) -> CGImageSource? {
        let opts = [kCGImageSourceShouldCache: false] as CFDictionary
        switch s {
        case .file(let u): return CGImageSourceCreateWithURL(u as CFURL, opts)
        case .zip(let e):
            guard let d = try? e.archive.data(e) else { return nil }
            return CGImageSourceCreateWithData(d as CFData, opts)
        }
    }

    static func thumb(_ src: CGImageSource, maxPixel: Int) -> CGImage? {
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
    }

    static func videoFrame(_ url: URL, maxPixel: Int) async -> CGImage? {
        let gen = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: maxPixel, height: maxPixel)
        gen.requestedTimeToleranceBefore = .positiveInfinity
        gen.requestedTimeToleranceAfter = .positiveInfinity
        // The first frames are often black (fade-ins, screen recordings), so aim a second in.
        if let cg = try? await gen.image(at: CMTime(seconds: 1, preferredTimescale: 600)).image { return cg }
        return try? await gen.image(at: .zero).image
    }

    static func quickLook(_ url: URL, maxPixel: Int) async -> CGImage? {
        let req = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: maxPixel, height: maxPixel), scale: 1, representationTypes: .thumbnail)
        return try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: req).cgImage
    }

    private static func writeJPEG(_ cg: CGImage, to url: URL) {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, cg, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        CGImageDestinationFinalize(dest)
    }

    /// Full-size display image, downsampled to the screen so 48 MP HEICs open instantly.
    static func displayImage(_ source: MediaSource, maxPixel: Int = 4096) async -> NSImage? {
        await Task.detached(priority: .userInitiated) {
            if let src = imageSource(source), let cg = fullImage(src, maxPixel: maxPixel) {
                return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
            }
            return source.fileURL.flatMap { NSImage(contentsOf: $0) }
        }.value
    }

    private static func fullImage(_ src: CGImageSource, maxPixel: Int) -> CGImage? {
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
    }
}

/// Caps how many thumbnails decode at once so a fast scroll doesn't queue thousands of decodes.
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
