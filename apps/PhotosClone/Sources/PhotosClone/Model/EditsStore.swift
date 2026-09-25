import Foundation

/// What the user changed in Photos Clone: favorites, hiding and deleting. The export itself is
/// never written to; these live in a small file on the Mac and are applied on top of it.
struct AssetEdit: Codable, Equatable {
    var favorite: Bool?
    var hidden: Bool?
    var deletedAt: Date?
    /// Taken back out of Recently Deleted (including items iCloud's export had marked deleted).
    var restored: Bool?
    var purged: Bool?

    var isEmpty: Bool { self == AssetEdit() }
}

final class EditsStore {
    /// Items stay in Recently Deleted this long, like in Photos.
    static let retention: TimeInterval = 30 * 24 * 3600

    private(set) var edits: [String: AssetEdit] = [:]
    private let file: URL

    init(root: URL) {
        file = Paths.support.appendingPathComponent("edits-\(stableHash(root.standardizedFileURL.path)).json")
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: file), let e = try? dec.decode([String: AssetEdit].self, from: data) {
            edits = e
        }
    }

    subscript(_ a: Asset) -> AssetEdit? { edits[a.cacheKey] }

    func update(_ a: Asset, _ change: (inout AssetEdit) -> Void) {
        var e = edits[a.cacheKey] ?? AssetEdit()
        change(&e)
        edits[a.cacheKey] = e.isEmpty ? nil : e
    }

    func save() {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(edits) { try? data.write(to: file, options: .atomic) }
    }

    /// Applies the saved edits to a freshly scanned asset.
    func apply(to a: inout Asset, now: Date = Date()) {
        guard let e = edits[a.cacheKey] else { return }
        if let f = e.favorite { a.isFavorite = f }
        if let h = e.hidden { a.isHidden = h }
        if e.restored == true { a.isDeleted = false }
        if let d = e.deletedAt {
            a.isDeleted = true
            a.deletedAt = d
            // Past the 30 days, Recently Deleted empties itself, as in Photos.
            if now.timeIntervalSince(d) > Self.retention { a.isPurged = true }
        }
        if e.purged == true { a.isPurged = true }
    }
}
