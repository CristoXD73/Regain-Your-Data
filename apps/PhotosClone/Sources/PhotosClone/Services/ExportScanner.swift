import Foundation

/// Everything read from an iCloud Photos "Request a copy of your data" export.
///
/// Layout Apple produces (one folder per downloaded zip):
///   iCloud Photos Part N of M/
///     Photos/                 media + "Photo Details.csv", "Photo Details-1.csv", ...
///                             (imgName,fileChecksum,favorite,hidden,deleted,originalCreationDate,viewCount,importDate)
///     Recently Deleted/       media only
///     Albums/<name>.csv       header "Images" (or "imgName" for Hidden.csv / Favorites.csv)
///     Memories/<name>.csv     header "imageName"
///     iCloud Shared Albums.zip  -> My Albums/<album>/{media, AlbumInfo.json}
///
/// Filenames are NOT unique across parts (two different IMG_0100.MOV can exist), so each file is
/// matched to the Photo Details rows that sit in its own folder first, and to other folders only
/// when that name is unambiguous.
struct ExportLibrary {
    var root: URL
    var assets: [Asset] = []
    var albums: [AlbumRef] = []
    var memories: [AlbumRef] = []
    var sharedAlbums: [AlbumRef] = []
    var parts: [String] = []
    /// The export zips found under the root, opened for reading.
    var zips: [ZipArchive] = []
    var csvRowCount = 0
    var filesWithoutMetadata = 0
    var zippedCount = 0
    /// Apple's empty placeholder files left out because a real copy sits next to them.
    var droppedEmptyFiles = 0
    var scanDuration: TimeInterval = 0
}

/// A file found either on disk or inside a zip.
private struct Node {
    let source: MediaSource
    let name: String
    /// Folder key. Disk: the folder path. Zip: "<zip path>#<folder inside zip>".
    let dir: String
    /// Path as Apple laid it out, e.g. "iCloud Photos Part 3 of 11/Photos/IMG_0100.MOV".
    let relativePath: String
    let size: Int64
    var folderName: String { (dir as NSString).lastPathComponent }
    var ext: String { (name as NSString).pathExtension.lowercased() }
}

/// One row of Photo Details.csv.
struct DetailRow: Hashable {
    let name: String
    let checksum: String
    let favorite: Bool
    let hidden: Bool
    let deleted: Bool
    let created: Date?
    let viewCount: Int
    let imported: Date?
}

enum ExportScanner {
    static let imageExts: Set<String> = ["heic", "heif", "jpg", "jpeg", "png", "gif", "webp", "tif", "tiff", "bmp", "avif", "jp2", "psd", "dng", "raw", "cr2", "nef", "arw"]
    static let videoExts: Set<String> = ["mov", "mp4", "m4v", "avi", "3gp", "mkv", "hevc"]

    static func isMedia(_ url: URL) -> Bool {
        let e = url.pathExtension.lowercased()
        return imageExts.contains(e) || videoExts.contains(e)
    }

    /// Finds export roots automatically on mounted volumes and in the usual folders.
    static func suggestedRoots() -> [URL] {
        let fm = FileManager.default
        var candidates: [URL] = []
        var bases = [fm.homeDirectoryForCurrentUser.appendingPathComponent("Downloads"),
                     fm.homeDirectoryForCurrentUser.appendingPathComponent("Desktop"),
                     fm.homeDirectoryForCurrentUser.appendingPathComponent("Pictures")]
        if let vols = try? fm.contentsOfDirectory(at: URL(fileURLWithPath: "/Volumes"), includingPropertiesForKeys: nil) {
            bases += vols
            for v in vols {
                if let sub = try? fm.contentsOfDirectory(at: v, includingPropertiesForKeys: nil) { bases += sub }
            }
        }
        for base in bases {
            guard let items = try? fm.contentsOfDirectory(atPath: base.path) else { continue }
            if items.contains(where: { $0.hasPrefix("iCloud Photos Part ") }) {
                candidates.append(base)
            }
        }
        var seen = Set<String>()
        return candidates.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }

    static func isMedia(name: String) -> Bool {
        let e = (name as NSString).pathExtension.lowercased()
        return imageExts.contains(e) || videoExts.contains(e)
    }

    /// Reads the export whether it is unzipped, still zipped, or a mix. A file present both ways
    /// is taken from disk (faster), matched by name and size.
    /// `zipsOnly` ignores unzipped folders (used to check the zips alone hold everything).
    static func scan(root: URL, zipsOnly: Bool = false, progress: @escaping (String) -> Void) -> ExportLibrary {
        let start = Date()
        var lib = ExportLibrary(root: root)
        let fm = FileManager.default
        let rootPath = root.standardizedFileURL.path

        // 1. Walk the folders on disk.
        var media: [Node] = []
        var csvs: [Node] = []
        var sharedZips: [MediaSource] = []
        var partZips: [URL] = []
        var partNames = Set<String>()

        progress("Looking through folders…")
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey]
        let walker = fm.enumerator(at: root, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true })
        while let url = walker?.nextObject() as? URL {
            let name = url.lastPathComponent
            if name.hasPrefix("._") || name == ".DS_Store" { continue }
            let vals = try? url.resourceValues(forKeys: Set(keys))
            if vals?.isDirectory == true {
                if name.hasSuffix(".photoslibrary") || name == "icloud-photos" || zipsOnly { walker?.skipDescendants() }
                if name.hasPrefix("iCloud Photos Part ") && !zipsOnly { partNames.insert(name) }
                continue
            }
            let node = Node(source: .file(url), name: name, dir: url.deletingLastPathComponent().path,
                            relativePath: relative(url.path, to: rootPath), size: Int64(vals?.fileSize ?? 0))
            switch node.ext {
            case "csv": csvs.append(node)
            case "zip":
                if name == "iCloud Shared Albums.zip" { sharedZips.append(node.source) }
                else if name.hasPrefix("iCloud Photos Part ") { partZips.append(url) }
            default:
                if isMedia(name: name) {
                    media.append(node)
                    if media.count % 2000 == 0 { progress("Found \(media.count) photos and videos…") }
                }
            }
        }

        // 2. Open the zips and add whatever isn't already on disk.
        // Accented names can be composed differently on disk and in the zip; compare normalised.
        func norm(_ s: String) -> String { s.precomposedStringWithCanonicalMapping }
        let onDisk = Set(media.map { "\(norm($0.name))|\($0.size)" })
        let csvOnDisk = Set(csvs.map { norm($0.relativePath) })
        for zipURL in partZips.sorted(by: { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }) {
            progress("Opening \(zipURL.lastPathComponent)…")
            guard let zip = try? ZipArchive(url: zipURL) else { continue }
            lib.zips.append(zip)
            partNames.insert(zipURL.deletingPathExtension().lastPathComponent)
            for e in zip.entries {
                let name = e.name
                if name.hasPrefix("._") || e.path.hasPrefix("__MACOSX") || name == ".DS_Store" { continue }
                let node = Node(source: .zip(e), name: name, dir: zipURL.path + "#" + e.directory,
                                relativePath: e.path, size: Int64(e.size))
                switch node.ext {
                case "csv":
                    if !csvOnDisk.contains(norm(e.path)) { csvs.append(node) }
                case "zip":
                    if name == "iCloud Shared Albums.zip" && sharedZips.isEmpty { sharedZips.append(node.source) }
                default:
                    if isMedia(name: name) && !onDisk.contains("\(norm(name))|\(node.size)") {
                        media.append(node)
                        lib.zippedCount += 1
                    }
                }
            }
        }
        lib.parts = partNames.sorted { $0.localizedStandardCompare($1) == .orderedAscending }

        // 3. Photo Details, keyed by folder then name.
        progress("Reading Photo Details…")
        // A folder can list the same name more than once (two different files); the zip then
        // renames the later ones "IMG_0300-1.MOV", "IMG_0300-2.MOV"… so keep every row.
        var detailsByDir: [String: [String: [DetailRow]]] = [:]
        var detailsByName: [String: [DetailRow]] = [:]
        for csv in csvs where csv.name.hasPrefix("Photo Details") {
            let rows = CSV.rows(csv.source)
            guard let header = rows.first else { continue }
            let idx = Dictionary(header.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
            func col(_ r: [String], _ k: String) -> String { idx[k].flatMap { $0 < r.count ? r[$0] : nil } ?? "" }
            for r in rows.dropFirst() {
                let name = col(r, "imgName")
                guard !name.isEmpty else { continue }
                let row = DetailRow(
                    name: name,
                    checksum: col(r, "fileChecksum"),
                    favorite: col(r, "favorite") == "yes",
                    hidden: col(r, "hidden") == "yes",
                    deleted: col(r, "deleted") == "yes",
                    created: AppleDate.parse(col(r, "originalCreationDate")),
                    viewCount: Int(col(r, "viewCount")) ?? 0,
                    imported: AppleDate.parse(col(r, "importDate")))
                detailsByDir[csv.dir, default: [:]][name, default: []].append(row)
                detailsByName[name, default: []].append(row)
                lib.csvRowCount += 1
            }
        }

        // 4. Build assets folder by folder, pairing Live Photos (still + .MOV with the same stem).
        progress("Pairing Live Photos…")
        let liveIDs = LivePhotoIDs(root: root)
        defer { liveIDs.save() }
        var nextID = 0
        var byName: [String: [Int]] = [:]
        let mediaByDir = Dictionary(grouping: media, by: \.dir)
        for (dir, allFiles) in mediaByDir.sorted(by: { $0.key < $1.key }) {
            // Apple sometimes leaves an empty "X.mp4" and puts the real file at "X-1.mp4".
            let names = Set(allFiles.filter { $0.size > 0 }.map { $0.name.lowercased() })
            let files = allFiles.filter { f in
                guard f.size == 0 else { return true }
                let ns = f.name.lowercased() as NSString
                return !(1...9).contains { names.contains("\(ns.deletingPathExtension)-\($0).\(ns.pathExtension)") }
            }
            lib.droppedEmptyFiles += allFiles.count - files.count
            let dirDetails = detailsByDir[dir] ?? [:]
            let isRecentlyDeleted = (dir as NSString).lastPathComponent == "Recently Deleted"

            /// Rows that may describe this file: its own name's rows, or for "X-1.ext" the rows of
            /// "X.ext" when that name is listed more than once in the folder.
            func candidates(_ name: String) -> (rows: [DetailRow], guess: Int) {
                if let r = dirDetails[name], !r.isEmpty { return (r, 0) }
                let ns = name as NSString
                if let m = ns.deletingPathExtension.range(of: #"-(\d+)$"#, options: .regularExpression) {
                    let stem = String(ns.deletingPathExtension[..<m.lowerBound])
                    let n = Int(ns.deletingPathExtension[m].dropFirst()) ?? 0
                    // Also when the name is listed once: Apple sometimes leaves an empty "X.mp4" and
                    // puts the real file at "X-1.mp4".
                    if let r = dirDetails[stem + "." + ns.pathExtension], !r.isEmpty { return (r, min(n, r.count - 1)) }
                }
                if let all = detailsByName[name], all.count == 1 { return (all, 0) }
                return ([], 0)
            }
            func details(_ name: String) -> DetailRow? {
                let c = candidates(name)
                return c.rows.isEmpty ? nil : c.rows[c.guess]
            }

            // A name can belong to several stills (IMG_0200.HEIC and an unrelated IMG_0200.JPG).
            var stills: [String: [Int]] = [:]
            var movies: [String: [Int]] = [:]
            for (i, f) in files.enumerated() {
                var stem = (f.name as NSString).deletingPathExtension
                if ["heic", "heif", "jpg", "jpeg"].contains(f.ext) { stills[stem.lowercased(), default: []].append(i) }
                guard f.ext == "mov" else { continue }
                // "IMG_0400-1.MOV" is Apple's rename of a second "IMG_0400.MOV"; either may be the
                // Live Photo's motion half.
                if let r = stem.range(of: #"-\d+$"#, options: .regularExpression), dirDetails[String(stem[..<r.lowerBound]) + "." + (f.name as NSString).pathExtension] != nil {
                    stem = String(stem[..<r.lowerBound])
                }
                movies[stem.lowercased(), default: []].append(i)
            }
            var consumed = Set<Int>()
            var pairFor: [Int: Int] = [:]
            for (stem, group) in stills {
            // HEIC first: that's what iPhones save Live Photos as.
            for still in group.sorted(by: { (files[$0].ext == "heic" ? 0 : 1) < (files[$1].ext == "heic" ? 0 : 1) }) {
                // A real Live Photo's two halves were captured together; unrelated files that just
                // share a name (IMG_0100.HEIC from 2018, IMG_0100.MOV from 2019) are left alone.
                let aDates = candidates(files[still].name).rows.compactMap(\.created)
                let sized = (movies[stem] ?? []).filter { files[$0].size <= 60_000_000 && !consumed.contains($0) }
                var options = sized.filter { mov in
                    let bDates = candidates(files[mov].name).rows.compactMap(\.created)
                    return aDates.isEmpty || bDates.isEmpty
                        || aDates.contains(where: { a in bDates.contains { abs(a.timeIntervalSince($0)) <= 120 } })
                }
                // iCloud's dates for the two halves can disagree (one was re-imported later).
                // Apple's Live Photo ID inside both files settles it.
                if options.isEmpty, !sized.isEmpty,
                   let stillID = liveIDs.id(for: files[still].source, size: files[still].size) {
                    options = sized.filter { liveIDs.id(for: files[$0].source, size: files[$0].size) == stillID }
                }
                guard var mov = options.first else { continue }
                if options.count > 1, let stillID = liveIDs.id(for: files[still].source, size: files[still].size),
                   let match = options.first(where: { liveIDs.id(for: files[$0].source, size: files[$0].size) == stillID }) {
                    // Several same-name clips could be it: Apple's Live Photo ID says which.
                    mov = match
                } else if options.count > 1, let target = aDates.first {
                    // No ID to go on: ask each clip for its recorded date.
                    mov = options.min { abs((recordedDate(files[$0].source) ?? .distantPast).timeIntervalSince(target))
                        < abs((recordedDate(files[$1].source) ?? .distantPast).timeIntervalSince(target)) }!
                }
                pairFor[still] = mov
                consumed.insert(mov)
            }
            }

            for (i, f) in files.enumerated() where !consumed.contains(i) {
                let d = details(f.name)
                let paired = pairFor[i].map { files[$0] }
                let kind: MediaKind = paired != nil ? .livePhoto : (videoExts.contains(f.ext) ? .video : .photo)
                var a = Asset(
                    id: nextID, source: f.source, name: f.name,
                    relativePath: f.relativePath,
                    kind: kind, pairedSource: paired?.source,
                    date: .distantPast)
                a.inRecentlyDeletedFolder = isRecentlyDeleted
                if let d { a.apply(d) } else { a.isDeleted = isRecentlyDeleted }
                let cands = candidates(f.name).rows
                if cands.count > 1 { a.candidateRows = cands }
                a.part = partName(for: f.relativePath)
                a.fileSize = f.size + (paired?.size ?? 0)
                a.primarySize = f.size
                if d == nil { lib.filesWithoutMetadata += 1 }
                lib.assets.append(a)
                byName[f.name, default: []].append(nextID)
                if let paired { byName[paired.name, default: []].append(nextID) }
                nextID += 1
            }
        }

        // 5. Albums and Memories reference files by name only.
        progress("Reading albums and memories…")
        func resolve(_ csv: Node) -> [Int] {
            var ids: [Int] = []
            var seen = Set<Int>()
            for r in CSV.rows(csv.source).dropFirst() {
                guard let n = r.first, !n.isEmpty else { continue }
                for id in byName[n] ?? [] where seen.insert(id).inserted { ids.append(id) }
            }
            return ids
        }
        /// Memories cover a short stretch of time, so when a name matches files from several parts,
        /// keep the one closest to the memory's date (from its title, else its other photos).
        func resolveMemory(_ csv: Node, title: String) -> [Int] {
            let groups = CSV.rows(csv.source).dropFirst().compactMap(\.first).filter { !$0.isEmpty }.map { byName[$0] ?? [] }
            let sure = groups.filter { $0.count == 1 }.map { lib.assets[$0[0]].date }.filter { $0 != .distantPast }.sorted()
            let anchor = AppleDate.fromTitle(title) ?? (sure.isEmpty ? nil : sure[sure.count / 2])
            var ids: [Int] = []
            var seen = Set<Int>()
            for g in groups {
                var pick = g
                if g.count > 1, let anchor {
                    pick = [g.min { abs(lib.assets[$0].date.timeIntervalSince(anchor)) < abs(lib.assets[$1].date.timeIntervalSince(anchor)) }!]
                }
                for id in pick where seen.insert(id).inserted { ids.append(id) }
            }
            return ids
        }

        let skipAlbums: Set<String> = ["Hidden", "Favorites"]   // shown as their own smart albums
        for csv in csvs where csv.folderName == "Albums" {
            let title = (csv.name as NSString).deletingPathExtension
            if skipAlbums.contains(title) {
                // Hidden.csv lists hidden items by name; honour it for files without a details row.
                if title == "Hidden" {
                    for id in resolve(csv) where lib.assets[id].checksum == nil { lib.assets[id].isHidden = true }
                }
                continue
            }
            lib.albums.append(AlbumRef(id: "album:" + csv.relativePath, title: title, kind: .album, assetIDs: resolve(csv)))
        }
        lib.albums.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }

        for csv in csvs where csv.folderName == "Memories" {
            let title = (csv.name as NSString).deletingPathExtension
            let ids = resolveMemory(csv, title: title)
            guard !ids.isEmpty else { continue }
            var m = AlbumRef(id: "memory:" + csv.relativePath, title: title, kind: .memory, assetIDs: ids)
            m.sortDate = AppleDate.fromTitle(title) ?? ids.map { lib.assets[$0].date }.min()
            lib.memories.append(m)
        }
        lib.memories.sort { ($0.sortDate ?? .distantPast) > ($1.sortDate ?? .distantPast) }

        // 6. Shared Albums arrive as a nested zip; unpack that small file once into the cache.
        for zip in sharedZips.prefix(1) {
            progress("Opening Shared Albums…")
            guard let dest = SharedAlbums.extract(zip) else { continue }
            for album in SharedAlbums.albums(in: dest) {
                var ids: [Int] = []
                for (file, date) in album.files {
                    var a = Asset(id: nextID, source: .file(file), name: file.lastPathComponent,
                                  relativePath: "Shared Albums/\(album.title)/\(file.lastPathComponent)",
                                  kind: videoExts.contains(file.pathExtension.lowercased()) ? .video : .photo,
                                  date: date ?? .distantPast)
                    a.part = "Shared Album"
                    a.importDate = date
                    a.fileSize = Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                    a.primarySize = a.fileSize
                    lib.assets.append(a)
                    ids.append(nextID)
                    nextID += 1
                }
                lib.sharedAlbums.append(AlbumRef(id: "shared:" + album.title, title: album.title, kind: .shared, assetIDs: ids, sortDate: album.created))
            }
        }

        lib.scanDuration = Date().timeIntervalSince(start)
        return lib
    }

    /// The creation date a video recorded about itself (small clips only; unpacks zipped ones
    /// into the SSD cache). Blocking, for use during a scan off the main thread.
    private static func recordedDate(_ source: MediaSource) -> Date? {
        let sem = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var result: Date?
        Task.detached {
            if let url = try? await MediaAccess.fileURL(source) {
                result = await MediaInfoReader.readVideo(url).captureDate
            }
            sem.signal()
        }
        sem.wait()
        return result
    }

    private static func partName(for path: String) -> String? {
        for comp in (path as NSString).pathComponents.reversed() where comp.hasPrefix("iCloud Photos Part ") {
            return String(comp.dropFirst("iCloud Photos ".count))
        }
        return nil
    }

    private static func relative(_ path: String, to root: String) -> String {
        path.hasPrefix(root + "/") ? String(path.dropFirst(root.count + 1)) : path
    }
}

enum SharedAlbums {
    struct Album { let title: String; let created: Date?; let files: [(URL, Date?)] }

    static func extract(_ zip: MediaSource) -> URL? {
        let fm = FileManager.default
        let dest = Paths.caches.appendingPathComponent("shared-\(stableHash(zip.name + "|" + zip.containerURL.path))")
        if fm.fileExists(atPath: dest.path) { return dest }
        try? fm.createDirectory(at: dest, withIntermediateDirectories: true)
        var file = zip.fileURL
        if case .zip(let e) = zip {
            let tmp = dest.appendingPathComponent("shared.zip")
            guard (try? e.archive.extract(e, to: tmp)) != nil else { return nil }
            file = tmp
        }
        guard let file else { return nil }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        p.arguments = ["-x", "-k", file.path, dest.path]
        do { try p.run(); p.waitUntilExit() } catch { return nil }
        if zip.isZipped { try? fm.removeItem(at: file) }
        return p.terminationStatus == 0 ? dest : nil
    }

    static func albums(in dir: URL) -> [Album] {
        let fm = FileManager.default
        var result: [Album] = []
        guard let e = fm.enumerator(at: dir, includingPropertiesForKeys: nil) else { return [] }
        var infoFiles: [URL] = []
        while let u = e.nextObject() as? URL {
            if u.lastPathComponent == "AlbumInfo.json" { infoFiles.append(u) }
        }
        for info in infoFiles {
            let folder = info.deletingLastPathComponent()
            var title = folder.lastPathComponent
            var created: Date?
            var dates: [String: Date] = [:]
            if let data = try? Data(contentsOf: info),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                title = json["albumName"] as? String ?? title
                created = (json["creationDate"] as? String).flatMap(AppleDate.parse)
                for p in json["photos"] as? [[String: Any]] ?? [] {
                    if let n = p["name"] as? String, let d = (p["dateCreated"] as? String).flatMap(AppleDate.parse) { dates[n] = d }
                }
            }
            let files = ((try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
                .filter { ExportScanner.isMedia($0) && !$0.lastPathComponent.hasPrefix("._") }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
                .map { ($0, dates[$0.lastPathComponent]) }
            result.append(Album(title: title, created: created, files: files))
        }
        return result.sorted { $0.title < $1.title }
    }
}

enum Paths {
    static var support: URL {
        let u = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("PhotosClone")
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
    static var caches: URL {
        let u = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("PhotosClone")
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
}

/// FNV-1a, so cache file names stay the same between launches (String.hashValue is seeded per run).
func stableHash(_ s: String) -> String {
    var h: UInt64 = 0xcbf29ce484222325
    for b in s.utf8 { h ^= UInt64(b); h = h &* 0x100000001b3 }
    return String(h, radix: 36)
}
