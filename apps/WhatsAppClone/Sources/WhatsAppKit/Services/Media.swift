import AppKit
import AVFoundation
import ImageIO
import ObjectiveC

/// Opened zips, so media can be read by path.
final class ZipLibrary: @unchecked Sendable {
    static let shared = ZipLibrary()
    private var zips: [URL: (ZipArchive, [String: ZipEntry])] = [:]
    private let lock = NSLock()

    /// WhatsApp exports keep attachments at the top of the zip, so look them up by file name.
    func entry(byName name: String, in zip: URL) -> ZipEntry? {
        lock.lock()
        if zips[zip] == nil, let z = try? ZipArchive(url: zip) {
            zips[zip] = (z, Dictionary(z.entries.map { ($0.path, $0) }, uniquingKeysWith: { a, _ in a }))
        }
        let found = zips[zip]?.0.entries.first { $0.name == name }
        lock.unlock()
        return found
    }

    func entry(_ path: String, in zip: URL) -> ZipEntry? {
        lock.lock(); defer { lock.unlock() }
        if zips[zip] == nil, let z = try? ZipArchive(url: zip) {
            zips[zip] = (z, Dictionary(z.entries.map { ($0.path, $0) }, uniquingKeysWith: { a, _ in a }))
        }
        return zips[zip]?.1[path]
    }
}

// MARK: Media loading

enum MediaLoader {
    private static var loaderKey: UInt8 = 0

    static func asset(_ e: ZipEntry) throws -> AVURLAsset {
        let data = try e.archive.data(e)
        let ext = (e.name as NSString).pathExtension.lowercased()
        let asset = AVURLAsset(url: URL(string: "wamem://\(stableHash(e.path)).\(ext)")!)
        let type = ext == "opus" ? "org.xiph.ogg-audio" : ext == "aac" ? "public.aac-audio" : ext == "m4a" ? "com.apple.m4a-audio" : ext == "mov" ? "com.apple.quicktime-movie" : "public.mpeg-4"
        let loader = MemoryLoader(data: data, type: type)
        asset.resourceLoader.setDelegate(loader, queue: MemoryLoader.queue)
        objc_setAssociatedObject(asset, &loaderKey, loader, .OBJC_ASSOCIATION_RETAIN)
        return asset
    }

    static func image(_ e: ZipEntry, maxPixel: Int) -> CGImage? {
        guard let d = try? e.archive.data(e), let src = CGImageSourceCreateWithData(d as CFData, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(src, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ] as CFDictionary)
    }
}

/// Thumbnails for chat photos and videos, cached on the Mac's SSD.
final class Thumbs: @unchecked Sendable {
    static let shared = Thumbs()
    private let dir: URL
    private let memory = NSCache<NSString, NSImage>()
    private let gate = AsyncGate(limit: 6)

    init() {
        dir = Paths.caches.appendingPathComponent("thumbs")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        memory.countLimit = 1500
    }

    func image(_ e: ZipEntry, video: Bool, size: Int = 512) async -> NSImage? {
        let key = stableHash("\(e.archive.url.lastPathComponent)|\(e.path)|\(e.size)") + "-\(size)"
        if let m = memory.object(forKey: key as NSString) { return m }
        let file = dir.appendingPathComponent(key + ".jpg")
        if let img = NSImage(contentsOf: file) { memory.setObject(img, forKey: key as NSString); return img }
        await gate.enter()
        defer { Task { await gate.leave() } }
        var cg: CGImage?
        if video {
            if let asset = try? MediaLoader.asset(e) {
                let gen = AVAssetImageGenerator(asset: asset)
                gen.appliesPreferredTrackTransform = true
                gen.maximumSize = CGSize(width: size, height: size)
                cg = try? await gen.image(at: CMTime(seconds: 0.3, preferredTimescale: 600)).image
            }
        } else {
            cg = MediaLoader.image(e, maxPixel: size)
        }
        guard let cg else { return nil }
        let img = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        memory.setObject(img, forKey: key as NSString)
        if let d = CGImageDestinationCreateWithURL(file as CFURL, "public.jpeg" as CFString, 1, nil) {
            CGImageDestinationAddImage(d, cg, [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary)
            CGImageDestinationFinalize(d)
        }
        return img
    }
}
