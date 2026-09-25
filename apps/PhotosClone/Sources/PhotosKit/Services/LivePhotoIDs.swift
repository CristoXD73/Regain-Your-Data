import AVFoundation
import Foundation
import ImageIO

/// Apple's Live Photo ID: the still stores it in its Apple maker notes, the clip in its QuickTime
/// metadata, and the two halves of one Live Photo share it. Used when iCloud's dates for the two
/// halves disagree. Results are kept on disk (keyed by name + size) so later scans, including
/// ones that read from the zips, don't have to open the files again.
final class LivePhotoIDs: @unchecked Sendable {
    private var cache: [String: String]
    private let file: URL
    private var dirty = false
    private let lock = NSLock()

    init(root: URL) {
        file = Paths.support.appendingPathComponent("livephoto-ids-\(stableHash(root.standardizedFileURL.path)).json")
        cache = (try? JSONDecoder().decode([String: String].self, from: Data(contentsOf: file))) ?? [:]
    }

    /// The ID, or nil when the file has none. Blocking; call off the main thread.
    func id(for source: MediaSource, size: Int64) -> String? {
        let key = "\(source.name)|\(size)"
        lock.lock()
        if let hit = cache[key] { lock.unlock(); return hit.isEmpty ? nil : hit }
        lock.unlock()
        let ext = (source.name as NSString).pathExtension.lowercased()
        let found = ext == "mov" ? Self.clipID(source) : Self.stillID(source)
        lock.lock()
        cache[key] = found ?? ""
        dirty = true
        lock.unlock()
        return found
    }

    func save() {
        lock.lock(); defer { lock.unlock() }
        guard dirty, let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: file, options: .atomic)
        dirty = false
    }

    private static func stillID(_ source: MediaSource) -> String? {
        func read(_ data: Data) -> String? {
            guard let src = CGImageSourceCreateWithData(data as CFData, nil),
                  let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
                  let maker = props["{MakerApple}" as CFString] as? NSDictionary else { return nil }
            // Tag 17 is the Live Photo ID; ImageIO keys the maker notes by number.
            return (maker[NSNumber(value: 17)] ?? maker["17"]) as? String
        }
        // Maker notes sit near the start of the file.
        if let head = try? MediaAccess.data(source, limit: 524_288), let id = read(head) { return id }
        return (try? MediaAccess.data(source)).flatMap(read)
    }

    /// Clips are small (a few MB); zipped ones are unpacked into the SSD cache to be read.
    private static func clipID(_ source: MediaSource) -> String? {
        let sem = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var result: String?
        Task.detached {
            if let url = try? await MediaAccess.fileURL(source) {
                for item in (try? await AVURLAsset(url: url).load(.metadata)) ?? []
                where (item.identifier?.rawValue ?? "").hasSuffix("content.identifier") {
                    result = try? await item.load(.stringValue)
                }
            }
            sem.signal()
        }
        sem.wait()
        return result
    }
}
