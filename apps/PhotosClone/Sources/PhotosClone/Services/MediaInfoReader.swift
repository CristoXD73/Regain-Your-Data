import AVFoundation
import Foundation
import ImageIO

/// Reads EXIF / QuickTime metadata. Only headers are read, so this stays fast even on a USB drive.
enum MediaInfoReader {
    private static let exifDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return f
    }()
    private static let lock = NSLock()

    /// Returns nil when the details can't be read cheaply (a zipped video that was never unpacked),
    /// so nothing incomplete gets cached.
    static func read(_ asset: Asset) async -> MediaInfo? {
        if asset.kind == .video {
            guard let url = readableFile(asset.source) else { return nil }
            return await readVideo(url)
        }
        guard var info = readImage(asset.source) else { return MediaInfo() }
        if asset.kind == .livePhoto, let mov = asset.pairedSource.flatMap(readableFile) {
            info.duration = await readVideo(mov).duration
        }
        return info
    }

    /// A file AVFoundation can open without unpacking anything new.
    private static func readableFile(_ s: MediaSource) -> URL? {
        switch s {
        case .file(let u): u
        case .zip(let e): UnpackCache.shared.cachedFile(for: e)
        }
    }

    static func readImage(_ source: MediaSource) -> MediaInfo? {
        let opts = [kCGImageSourceShouldCache: false] as CFDictionary
        switch source {
        case .file(let url):
            guard let src = CGImageSourceCreateWithURL(url as CFURL, opts) else { return nil }
            return readImage(src)
        case .zip(let e):
            // EXIF sits at the start of the file, so unpacking the first 512 KB is usually enough.
            if e.size > 524_288, let head = try? e.archive.data(e, limit: 524_288),
               let src = CGImageSourceCreateWithData(head as CFData, opts),
               let info = readImage(src), info.width != nil {
                return info
            }
            guard let all = try? e.archive.data(e), let src = CGImageSourceCreateWithData(all as CFData, opts) else { return nil }
            return readImage(src)
        }
    }

    private static func readImage(_ src: CGImageSource) -> MediaInfo? {
        var info = MediaInfo()
        let opts = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let props = CGImageSourceCopyPropertiesAtIndex(src, 0, opts) as? [CFString: Any] else { return nil }
        var w = props[kCGImagePropertyPixelWidth] as? Int
        var h = props[kCGImagePropertyPixelHeight] as? Int
        if let o = props[kCGImagePropertyOrientation] as? Int, o >= 5 { swap(&w, &h) }
        info.width = w; info.height = h

        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        let gps = props[kCGImagePropertyGPSDictionary] as? [CFString: Any] ?? [:]

        if let s = exif[kCGImagePropertyExifDateTimeOriginal] as? String ?? tiff[kCGImagePropertyTIFFDateTime] as? String {
            // EXIF times are local wall-clock; use the recorded offset when present.
            var tz = TimeZone.current
            if let off = exif["OffsetTimeOriginal" as CFString] as? String, let z = parseOffset(off) { tz = z }
            lock.lock()
            exifDate.timeZone = tz
            info.captureDate = exifDate.date(from: s)
            lock.unlock()
            // Bursts share a second; the sub-second field keeps them in shooting order.
            if let sub = exif[kCGImagePropertyExifSubsecTimeOriginal] as? String, let frac = Double("0." + sub), let d = info.captureDate {
                info.captureDate = d.addingTimeInterval(frac)
            }
        }
        info.make = (tiff[kCGImagePropertyTIFFMake] as? String)?.trimmingCharacters(in: .whitespaces)
        info.model = (tiff[kCGImagePropertyTIFFModel] as? String)?.trimmingCharacters(in: .whitespaces)
        info.lens = exif[kCGImagePropertyExifLensModel] as? String
        info.iso = (exif[kCGImagePropertyExifISOSpeedRatings] as? [Int])?.first
        info.fNumber = exif[kCGImagePropertyExifFNumber] as? Double
        info.exposure = exif[kCGImagePropertyExifExposureTime] as? Double
        info.focalLength = exif[kCGImagePropertyExifFocalLenIn35mmFilm] as? Double ?? exif[kCGImagePropertyExifFocalLength] as? Double
        if var lat = gps[kCGImagePropertyGPSLatitude] as? Double, var lon = gps[kCGImagePropertyGPSLongitude] as? Double {
            if (gps[kCGImagePropertyGPSLatitudeRef] as? String) == "S" { lat = -lat }
            if (gps[kCGImagePropertyGPSLongitudeRef] as? String) == "W" { lon = -lon }
            if !(lat == 0 && lon == 0) { info.latitude = lat; info.longitude = lon }
        }
        return info
    }

    static func readVideo(_ url: URL) async -> MediaInfo {
        var info = MediaInfo()
        let asset = AVURLAsset(url: url)
        if let d = try? await asset.load(.duration), d.isNumeric { info.duration = d.seconds }
        if let track = try? await asset.loadTracks(withMediaType: .video).first {
            if let (size, transform) = try? await track.load(.naturalSize, .preferredTransform) {
                let r = CGRect(origin: .zero, size: size).applying(transform)
                info.width = Int(abs(r.width)); info.height = Int(abs(r.height))
            }
            info.fps = (try? await track.load(.nominalFrameRate)).map(Double.init)
            if let fmt = try? await track.load(.formatDescriptions).first {
                let sub = CMFormatDescriptionGetMediaSubType(fmt)
                info.codec = sub == kCMVideoCodecType_HEVC ? "HEVC" : sub == kCMVideoCodecType_H264 ? "H.264" : fourCC(sub)
            }
        }
        let items = (try? await asset.load(.metadata)) ?? []
        for item in items {
            guard let key = item.identifier?.rawValue else { continue }
            if key.hasSuffix("location.ISO6709"), let s = try? await item.load(.stringValue) {
                (info.latitude, info.longitude) = parseISO6709(s)
            } else if key.hasSuffix("creationdate"), let d = try? await item.load(.dateValue) {
                info.captureDate = d
            } else if key.hasSuffix("creationdate"), let s = try? await item.load(.stringValue) {
                info.captureDate = ISO8601DateFormatter().date(from: s)
            } else if key.hasSuffix("make"), let s = try? await item.load(.stringValue) {
                info.make = s
            } else if key.hasSuffix("model"), let s = try? await item.load(.stringValue) {
                info.model = s
            }
        }
        return info
    }

    private static func parseOffset(_ s: String) -> TimeZone? {
        let sign: Int = s.hasPrefix("-") ? -1 : 1
        let parts = s.dropFirst().split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        return TimeZone(secondsFromGMT: sign * (parts[0] * 3600 + parts[1] * 60))
    }

    /// "+45.5017-073.5673+020.000/"
    static func parseISO6709(_ s: String) -> (Double?, Double?) {
        let pattern = #"([+-]\d+(?:\.\d+)?)([+-]\d+(?:\.\d+)?)"#
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              let a = Range(m.range(at: 1), in: s), let b = Range(m.range(at: 2), in: s) else { return (nil, nil) }
        return (Double(s[a]), Double(s[b]))
    }

    private static func fourCC(_ v: FourCharCode) -> String {
        let bytes = [24, 16, 8, 0].map { UInt8((v >> $0) & 0xff) }
        return String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .whitespaces)
    }
}

/// Background indexer with an on-disk cache keyed by path + size, so a second launch is instant.
actor MediaInfoStore {
    private var cache: [String: MediaInfo] = [:]
    private let file: URL
    private var dirty = 0

    init(root: URL) {
        file = Paths.support.appendingPathComponent("info-\(stableHash(root.standardizedFileURL.path)).json")
        if let data = try? Data(contentsOf: file),
           let decoded = try? JSONDecoder().decode([String: MediaInfo].self, from: data) {
            cache = decoded
        }
    }

    static func key(_ a: Asset) -> String { a.cacheKey }

    func cached(_ a: Asset) -> MediaInfo? { cache[Self.key(a)] }
    func all() -> [String: MediaInfo] { cache }

    func store(_ info: MediaInfo, for a: Asset) {
        cache[Self.key(a)] = info
        dirty += 1
        if dirty >= 500 { save() }
    }

    func save() {
        guard dirty > 0 else { return }
        dirty = 0
        if let data = try? JSONEncoder().encode(cache) { try? data.write(to: file, options: .atomic) }
    }
}
