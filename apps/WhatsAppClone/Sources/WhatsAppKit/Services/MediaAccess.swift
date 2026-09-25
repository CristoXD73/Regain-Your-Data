import AppKit
import Foundation

/// Where an item's bytes live: a plain file, or an entry inside one of the export zips.
enum MediaSource: Hashable, @unchecked Sendable {
    case file(URL)
    case zip(ZipEntry)

    var name: String {
        switch self {
        case .file(let u): u.lastPathComponent
        case .zip(let e): e.name
        }
    }
    var fileURL: URL? { if case .file(let u) = self { u } else { nil } }
    var isZipped: Bool { if case .zip = self { true } else { false } }
    /// The file to show in Finder: the file itself, or the zip that contains it.
    var containerURL: URL {
        switch self {
        case .file(let u): u
        case .zip(let e): e.archive.url
        }
    }
}

/// Reads bytes for either kind of source. Zipped videos (and anything that needs a real file,
/// like sharing) are unpacked into a cache on the internal SSD, so the external drive is only
/// ever read. The cache sizes itself to the free space and drops the least recently used files.
enum MediaAccess {
    static func data(_ s: MediaSource, limit: UInt64? = nil) throws -> Data {
        switch s {
        case .file(let u):
            guard let limit else { return try Data(contentsOf: u, options: .mappedIfSafe) }
            let h = try FileHandle(forReadingFrom: u)
            defer { try? h.close() }
            return try h.read(upToCount: Int(limit)) ?? Data()
        case .zip(let e):
            return try e.archive.data(e, limit: limit)
        }
    }

    /// A real file for this source; unpacks zipped entries into the SSD cache first.
    static func fileURL(_ s: MediaSource) async throws -> URL {
        switch s {
        case .file(let u): return u
        case .zip(let e): return try await UnpackCache.shared.file(for: e)
        }
    }

    /// Whether a zipped item would need unpacking first (large videos take a few seconds).
    static func isReady(_ s: MediaSource) -> Bool {
        switch s {
        case .file: true
        case .zip(let e): UnpackCache.shared.cachedFile(for: e) != nil
        }
    }
}

actor UnpackCache {
    static let shared = UnpackCache()

    nonisolated let dir: URL = {
        let d = Paths.caches.appendingPathComponent("unpacked")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()
    private var inFlight: [String: Task<URL, Error>] = [:]

    nonisolated func key(_ e: ZipEntry) -> String {
        stableHash("\(e.archive.url.lastPathComponent)|\(e.path)|\(e.size)")
    }

    nonisolated func cachedFile(for e: ZipEntry) -> URL? {
        let u = dir.appendingPathComponent(key(e)).appendingPathExtension((e.name as NSString).pathExtension)
        guard let size = (try? u.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, UInt64(size) == e.size else { return nil }
        // Touch it so eviction treats it as recently used.
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: u.path)
        return u
    }

    func file(for e: ZipEntry) async throws -> URL {
        if let u = cachedFile(for: e) { return u }
        let k = key(e)
        if let t = inFlight[k] { return try await t.value }
        let dest = dir.appendingPathComponent(k).appendingPathExtension((e.name as NSString).pathExtension)
        let t = Task.detached(priority: .userInitiated) { () throws -> URL in
            try e.archive.extract(e, to: dest)
            return dest
        }
        inFlight[k] = t
        defer { inFlight[k] = nil }
        let url = try await t.value
        trim(keeping: url)
        return url
    }

    /// Budget: 10% of the SSD's free space, between 2 GB and 20 GB.
    nonisolated var budget: Int64 {
        let free = (try? dir.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?.volumeAvailableCapacityForImportantUsage ?? 0
        return min(20_000_000_000, max(2_000_000_000, free / 10))
    }

    nonisolated func usage() -> Int64 {
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return files.reduce(0) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }

    func trim(keeping: URL? = nil) {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        var files = ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys)) ?? [])
            .map { u -> (URL, Int64, Date) in
                let v = try? u.resourceValues(forKeys: Set(keys))
                return (u, Int64(v?.fileSize ?? 0), v?.contentModificationDate ?? .distantPast)
            }
            .sorted { $0.2 < $1.2 }
        var total = files.reduce(0) { $0 + $1.1 }
        let limit = budget
        while total > limit, let oldest = files.first {
            files.removeFirst()
            if oldest.0 == keeping { continue }
            try? FileManager.default.removeItem(at: oldest.0)
            total -= oldest.1
        }
    }

    func clear() {
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
}
