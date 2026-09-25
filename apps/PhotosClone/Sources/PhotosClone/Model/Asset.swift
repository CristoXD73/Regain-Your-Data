import Foundation

enum MediaKind: String, Codable {
    case photo, video, livePhoto
}

/// One item as it appears in the grid. A Live Photo is a single asset whose
/// still image is `source` and whose motion part is `pairedSource`.
struct Asset: Identifiable, Hashable {
    let id: Int
    let source: MediaSource
    let name: String
    /// Path relative to the export root, e.g. "iCloud Photos Part 3 of 11/Photos/IMG_0100.MOV".
    let relativePath: String
    let kind: MediaKind
    var pairedSource: MediaSource?

    // From Photo Details.csv (nil when the export has no row for this file).
    var checksum: String?
    var isFavorite = false
    var isHidden = false
    var isDeleted = false
    /// When the item was deleted in Photos Clone (nil for items iCloud's own export marked deleted).
    var deletedAt: Date?
    /// Deleted for good in Photos Clone: gone from every view, still inside its zip until compacted.
    var isPurged = false
    var inRecentlyDeletedFolder = false
    /// When several Photo Details rows share this file's name, all of them; the right one is
    /// picked once the file's own capture date is known (see LibraryStore.apply).
    var candidateRows: [DetailRow]?
    var viewCount = 0
    var csvCreationDate: Date?
    var importDate: Date?

    /// Which part of the export the file came from, e.g. "Part 3 of 11".
    var part: String?
    /// Size of the main file plus a Live Photo's clip, for display.
    var fileSize: Int64 = 0
    /// Size of the main file alone.
    var primarySize: Int64 = 0

    /// Best known capture date. Filled from the CSV, then refined by EXIF when indexed.
    var date: Date

    var ext: String { (name as NSString).pathExtension.lowercased() }
    var isZipped: Bool { source.isZipped }
    /// Cache key shared by thumbnails and metadata. Deliberately independent of the folder or zip
    /// the file sits in, so caches built from unzipped folders keep working from the zips.
    /// Uses the main file's size only, so pairing a Live Photo's clip never changes the key.
    var cacheKey: String { "\(name)|\(primarySize)" }
    var isScreenshot: Bool {
        ext == "png" && (name.hasPrefix("IMG_") || name.localizedCaseInsensitiveContains("screenshot"))
    }
    var isScreenRecording: Bool {
        name.hasPrefix("ScreenRecording") || name.hasPrefix("RPReplay")
    }
    var isAnimated: Bool { ext == "gif" }
    var isVideo: Bool { kind == .video }

    /// Takes iCloud's metadata from one Photo Details row.
    mutating func apply(_ r: DetailRow) {
        checksum = r.checksum
        isFavorite = r.favorite
        isHidden = r.hidden
        isDeleted = inRecentlyDeletedFolder || r.deleted
        viewCount = r.viewCount
        csvCreationDate = r.created
        importDate = r.imported
        date = DateResolver.resolve(self, fileDate: nil)
    }

    static func == (lhs: Asset, rhs: Asset) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct AlbumRef: Identifiable, Hashable {
    enum Kind { case album, memory, shared }
    let id: String
    let title: String
    let kind: Kind
    var assetIDs: [Int]
    /// For memories: the date in the title ("Around the Table Nov 4, 2020"), if any.
    var sortDate: Date?
}

/// Metadata read from the file itself (EXIF / QuickTime). Cached on disk.
struct MediaInfo: Codable, Hashable {
    var width: Int?
    var height: Int?
    var captureDate: Date?
    var latitude: Double?
    var longitude: Double?
    var make: String?
    var model: String?
    var lens: String?
    var iso: Int?
    var fNumber: Double?
    var exposure: Double?
    var focalLength: Double?
    var duration: Double?
    var fps: Double?
    var codec: String?

    var hasLocation: Bool { latitude != nil && longitude != nil }
    var camera: String? {
        switch (make, model) {
        case let (mk?, md?) where md.hasPrefix(mk): return md
        case let (mk?, md?): return "\(mk) \(md)"
        case let (nil, md?): return md
        case let (mk?, nil): return mk
        default: return nil
        }
    }
}
