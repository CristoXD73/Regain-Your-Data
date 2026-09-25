import Foundation

/// Cross-checks everything in an export: raw CSVs, files, albums, memories, flags, Live Photo
/// pairing, checksums, dates and cached file details. Prints a report; changes nothing.
enum MetadataAudit {
    static func run(root: URL) async {
        func say(_ s: String) { print(s) }
        func head(_ s: String) { print("\n## " + s) }
        func eg(_ list: [String], _ n: Int = 5) -> String { list.isEmpty ? "" : "  e.g. " + list.prefix(n).joined(separator: " | ") }

        let zipsOnly = ExportScanner.scan(root: root, zipsOnly: true) { _ in }
        let mixed = ExportScanner.scan(root: root) { _ in }
        let zips = zipsOnly.zips

        // ---------------------------------------------------------------- raw CSVs
        head("Photo Details CSVs (read from the zips)")
        struct Row { let dir: String; let name: String; let cols: [String: String] }
        var rows: [Row] = []
        var badWidth = 0, badDate: [String] = [], badFlag: [String] = [], badViews: [String] = []
        var csvFiles = 0
        let expected = ["imgName", "fileChecksum", "favorite", "hidden", "deleted", "originalCreationDate", "viewCount", "importDate"]
        var headers = Set<String>()
        for z in zips {
            for e in z.entries where e.name.hasPrefix("Photo Details") && e.name.hasSuffix(".csv") {
                csvFiles += 1
                let table = CSV.rows(.zip(e))
                guard let h = table.first else { continue }
                headers.insert(h.joined(separator: ","))
                for r in table.dropFirst() {
                    if r.count != h.count { badWidth += 1; continue }
                    let cols = Dictionary(uniqueKeysWithValues: zip(h, r))
                    let row = Row(dir: z.url.lastPathComponent + "#" + e.directory, name: cols["imgName"] ?? "", cols: cols)
                    rows.append(row)
                    for k in ["originalCreationDate", "importDate"] where AppleDate.parse(cols[k] ?? "") == nil { badDate.append("\(row.name) \(k)='\(cols[k] ?? "")'") }
                    for k in ["favorite", "hidden", "deleted"] where !["yes", "no"].contains(cols[k] ?? "") { badFlag.append("\(row.name) \(k)='\(cols[k] ?? "")'") }
                    if Int(cols["viewCount"] ?? "") == nil { badViews.append(row.name) }
                }
            }
        }
        say("\(csvFiles) CSV files, \(rows.count) rows")
        say("header variants: \(headers.count) \(headers.first == expected.joined(separator: ",") ? "(all standard)" : "\(headers)")")
        say("rows with wrong column count: \(badWidth)")
        say("unparseable dates: \(badDate.count)" + eg(badDate))
        say("flags other than yes/no: \(badFlag.count)" + eg(badFlag))
        say("non-numeric viewCount: \(badViews.count)" + eg(badViews))
        let emptyNames = rows.filter { $0.name.isEmpty }.count
        say("empty file names: \(emptyNames)")

        let sameDirDupes = Dictionary(grouping: rows, by: { $0.dir + "/" + $0.name }).filter { $0.value.count > 1 }
        say("same name listed twice in one folder: \(sameDirDupes.count)" + eg(sameDirDupes.keys.map { String($0.split(separator: "/").last ?? "") }))
        let exact = Dictionary(grouping: rows, by: { "\($0.name)|\($0.cols["fileChecksum"] ?? "")" }).filter { $0.value.count > 1 }
        say("identical rows (same name + checksum) in different parts: \(exact.count)" + eg(exact.keys.map { String($0.split(separator: "|")[0]) }))

        var createdAfterImport: [String] = [], future: [String] = [], ancient: [String] = []
        for r in rows {
            guard let c = AppleDate.parse(r.cols["originalCreationDate"] ?? "") else { continue }
            if let i = AppleDate.parse(r.cols["importDate"] ?? ""), c.timeIntervalSince(i) > 86_400 { createdAfterImport.append(r.name) }
            if c > Date() { future.append(r.name) }
            if Calendar.current.component(.year, from: c) < 2000 { ancient.append("\(r.name) \(c.formatted(date: .abbreviated, time: .omitted))") }
        }
        say("created more than a day AFTER import (odd): \(createdAfterImport.count)" + eg(createdAfterImport))
        say("created in the future: \(future.count)" + eg(future))
        say("created before 2000: \(ancient.count)" + eg(ancient))

        // ---------------------------------------------------------------- rows vs files
        head("Rows vs files inside the zips")
        var mediaByDir: [String: Set<String>] = [:]
        var allMedia: [String: Int] = [:]
        for z in zips {
            for e in z.entries where ExportScanner.isMedia(name: e.name) && !e.name.hasPrefix("._") {
                mediaByDir[z.url.lastPathComponent + "#" + e.directory, default: []].insert(e.name)
                allMedia[e.name, default: 0] += 1
            }
        }
        let rowsNoFile = rows.filter { !(mediaByDir[$0.dir]?.contains($0.name) ?? false) }
        let rowsNoFileAnywhere = rowsNoFile.filter { allMedia[$0.name] == nil }
        say("rows whose file isn't in the same folder: \(rowsNoFile.count), of which not in any zip: \(rowsNoFileAnywhere.count)" + eg(rowsNoFileAnywhere.map(\.name)))
        let rowNames = Set(rows.map { $0.dir + "/" + $0.name })
        var filesNoRow: [String] = []
        for (dir, names) in mediaByDir where !dir.hasSuffix("Recently Deleted") {
            for n in names where !rowNames.contains(dir + "/" + n) { filesNoRow.append(n) }
        }
        say("media files with no row in their folder's CSV: \(filesNoRow.count)" + eg(filesNoRow.sorted(), 8))
        let rd = mediaByDir.filter { $0.key.hasSuffix("Recently Deleted") }.flatMap(\.value)
        say("files in Recently Deleted folders: \(rd.count)   rows flagged deleted=yes: \(rows.filter { $0.cols["deleted"] == "yes" }.count)")

        // ---------------------------------------------------------------- scanner result
        head("What the app builds from this")
        var lib = zipsOnly
        let infoStore = MediaInfoStore(root: root)
        for i in lib.assets.indices {
            if let rows = lib.assets[i].candidateRows, let fd = await infoStore.cached(lib.assets[i])?.captureDate,
               let best = rows.min(by: { abs(($0.created ?? .distantPast).timeIntervalSince(fd)) < abs(($1.created ?? .distantPast).timeIntervalSince(fd)) }) {
                lib.assets[i].apply(best)
            }
        }
        say("Apple's empty placeholders left out (a real copy exists): \(lib.droppedEmptyFiles)")
        say("items: \(lib.assets.count)  live photos: \(lib.assets.filter { $0.kind == .livePhoto }.count)  without a CSV row: \(lib.filesWithoutMetadata)")
        let mixedKeys = Set(mixed.assets.map(\.cacheKey)), zipKeys = Set(lib.assets.map(\.cacheKey))
        say("zips-only vs folders+zips: \(zipKeys.subtracting(mixedKeys).count) only in zips-only, \(mixedKeys.subtracting(zipKeys).count) only in mixed"
            + eg(Array(zipKeys.symmetricDifference(mixedKeys)).map { String($0.split(separator: "|")[0]) }))
        let dupKeys = Dictionary(grouping: lib.assets, by: \.cacheKey).filter { $0.value.count > 1 }
        say("distinct items sharing a name+size cache key: \(dupKeys.count) (these would share a thumbnail)" + eg(dupKeys.keys.map { String($0) }))

        // Flags vs Hidden.csv / Favorites.csv
        var hiddenList: [String] = [], favList: [String] = []
        for z in zips {
            for e in z.entries where e.directory.hasSuffix("Albums") {
                if e.name == "Hidden.csv" { hiddenList = CSV.rows(.zip(e)).dropFirst().compactMap(\.first) }
                if e.name == "Favorites.csv" { favList = CSV.rows(.zip(e)).dropFirst().compactMap(\.first) }
            }
        }
        let nameIndex = Dictionary(grouping: lib.assets, by: \.name)
        let pairIndex = Dictionary(grouping: lib.assets.filter { $0.pairedSource != nil }, by: { $0.pairedSource!.name })
        let baseIndex = Dictionary(grouping: lib.assets.filter { $0.candidateRows != nil }, by: { $0.candidateRows![0].name })
        func lookup(_ n: String) -> [Asset] { (nameIndex[n] ?? []) + (pairIndex[n] ?? []) + (baseIndex[n] ?? []) }
        let hiddenNotFlagged = hiddenList.filter { n in !lookup(n).contains(where: \.isHidden) }
        let flaggedNotInList = Set(lib.assets.filter(\.isHidden).map { $0.candidateRows?[0].name ?? $0.name }).subtracting(hiddenList)
        say("Hidden.csv: \(hiddenList.count) names; listed but no hidden item: \(hiddenNotFlagged.count)\(eg(hiddenNotFlagged)); hidden items not in Hidden.csv: \(flaggedNotInList.count)" + eg(Array(flaggedNotInList)))
        let favNotFlagged = favList.filter { n in !lookup(n).contains(where: \.isFavorite) }
        let flaggedFavNotInList = Set(lib.assets.filter(\.isFavorite).map { $0.candidateRows?[0].name ?? $0.name }).subtracting(favList)
        say("Favorites.csv: \(favList.count) names; listed but no favorite item: \(favNotFlagged.count)\(eg(favNotFlagged)); favorites not in Favorites.csv: \(flaggedFavNotInList.count)" + eg(Array(flaggedFavNotInList)))
        let hiddenAndDeleted = lib.assets.filter { $0.isHidden && $0.isDeleted }.count
        say("items both hidden and deleted: \(hiddenAndDeleted)")

        // Albums & memories
        head("Albums and memories")
        var unresolved: [String] = [], ambiguous = 0, emptyAlbums: [String] = []
        for z in zips {
            for e in z.entries where e.name.hasSuffix(".csv") && (e.directory.hasSuffix("Albums") || e.directory.hasSuffix("Memories")) {
                let names = CSV.rows(.zip(e)).dropFirst().compactMap(\.first).filter { !$0.isEmpty }
                if names.isEmpty { emptyAlbums.append(e.name) }
                for n in names {
                    let hits = lookup(n)
                    if hits.isEmpty { unresolved.append("\(n) (in \(e.name))") }
                    if hits.count > 1 { ambiguous += 1 }
                }
            }
        }
        say("albums: \(lib.albums.count), memories kept: \(lib.memories.count)")
        say("album/memory entries that match no item: \(unresolved.count)" + eg(unresolved))
        say("entries that match several items (same name in several parts): \(ambiguous)")
        let memAmbiguous = lib.memories.reduce(0) { n, m in n + m.assetIDs.count } - lib.memories.reduce(0) { n, m in n + Set(m.assetIDs.map { lib.assets[$0].name }).count }
        say("memory entries still showing more than one same-name file: \(memAmbiguous)")
        say("empty album/memory CSVs: \(emptyAlbums.count)" + eg(emptyAlbums))
        let undatedMemories = lib.memories.filter { AppleDate.fromTitle($0.title) == nil }.map(\.title)
        say("memories whose title has no readable date: \(undatedMemories.count)" + eg(undatedMemories))

        // Live Photos
        head("Live Photos")
        var rejected: [String] = []
        var unpairedStills: [String] = []
        let dirs = Dictionary(grouping: lib.assets.filter { $0.part != "Shared Album" }, by: { ($0.relativePath as NSString).deletingLastPathComponent })
        for (_, items) in dirs {
            let stills = Dictionary(items.filter { ["heic", "jpg", "jpeg"].contains($0.ext) && $0.kind == .photo }.map { (($0.name as NSString).deletingPathExtension.lowercased(), $0) }, uniquingKeysWith: { a, _ in a })
            for m in items where m.kind == .video && m.ext == "mov" {
                let stem = (m.name as NSString).deletingPathExtension.lowercased()
                if let s = stills[stem] {
                    let gap = abs((s.csvCreationDate ?? .distantPast).timeIntervalSince(m.csvCreationDate ?? .distantPast))
                    rejected.append("\(s.name)+\(m.name) gap \(Int(gap / 86_400))d, mov \(m.fileSize / 1_000_000)MB")
                    unpairedStills.append(s.name)
                }
            }
        }
        if let out = ProcessInfo.processInfo.environment["AUDIT_PAIRED_OUT"] {
            // "still path<TAB>clip path" relative to the export root, for outside checking.
            try? lib.assets.filter { $0.kind == .livePhoto }.map { a in
                let dir = (a.relativePath as NSString).deletingLastPathComponent
                return "\(a.relativePath)\t\(dir)/\(a.pairedSource!.name)"
            }.joined(separator: "\n").write(toFile: out, atomically: true, encoding: .utf8)
        }
        if let out = ProcessInfo.processInfo.environment["AUDIT_UNPAIRED_OUT"] {
            try? unpairedStills.joined(separator: "\n").write(toFile: out, atomically: true, encoding: .utf8)
        }
        say("same-name still + .MOV left unpaired (dates or size say they're unrelated): \(rejected.count)" + eg(rejected, 4))
        let flagMismatch = lib.assets.filter { $0.kind == .livePhoto }.filter { a in
            // With same-name rows, the motion clip's row is the one captured with the still.
            guard let mov = a.pairedSource?.name, let still = a.csvCreationDate,
                  let row = rows.filter({ $0.name == mov || $0.name == mov.replacingOccurrences(of: #"-\d+(\.[^.]+)$"#, with: "$1", options: .regularExpression) })
                    .filter({ $0.dir.hasSuffix((a.relativePath as NSString).deletingLastPathComponent) })
                    .min(by: { abs((AppleDate.parse($0.cols["originalCreationDate"] ?? "") ?? .distantPast).timeIntervalSince(still)) < abs((AppleDate.parse($1.cols["originalCreationDate"] ?? "") ?? .distantPast).timeIntervalSince(still)) })
            else { return false }
            return (row.cols["hidden"] == "yes") != a.isHidden || (row.cols["favorite"] == "yes") != a.isFavorite
        }
        say("Live Photos whose .MOV half has different hidden/favorite flags than the still: \(flagMismatch.count)" + eg(flagMismatch.map(\.name)))

        // Checksums
        head("Checksums")
        let byChecksum = Dictionary(grouping: lib.assets.filter { !($0.checksum ?? "").isEmpty }, by: { $0.checksum! })
        let appDupes = Dictionary(grouping: lib.assets.filter { !($0.checksum ?? "").isEmpty }, by: { "\($0.checksum!)|\($0.fileSize)" }).filter { $0.value.count > 1 }
        say("Duplicates view (same checksum and size): \(appDupes.count) groups, \(appDupes.values.reduce(0) { $0 + $1.count }) items")
        let dupGroups = byChecksum.filter { $0.value.count > 1 }
        let diffSize = dupGroups.filter { Set($0.value.map(\.fileSize)).count > 1 }
        say("checksum groups with more than one item (exact duplicates): \(dupGroups.count) groups, \(dupGroups.values.reduce(0) { $0 + $1.count }) items")
        say("same checksum but different file sizes (shouldn't happen): \(diffSize.count)" + eg(diffSize.values.map { $0.map { "\($0.name) \($0.fileSize)" }.joined(separator: " vs ") }))

        // Cached file details, dates and thumbnails
        head("File details, dates, thumbnails (from the caches)")
        var noInfo = 0, unreadableImages: [String] = [], videosNoDuration = 0, noThumb: [String] = []
        var movedYears: [String] = [], futureResolved: [String] = [], undated: [String] = []
        let thumbDir = ThumbnailLoader.shared.dir
        for a in lib.assets {
            let info = await infoStore.cached(a)
            if info == nil { noInfo += 1 }
            if let info, a.kind != .video, info.width == nil { unreadableImages.append(a.name) }
            if let info, a.kind == .video, info.duration == nil { videosNoDuration += 1 }
            var a = a
            if let rows = a.candidateRows, let fd = info?.captureDate,
               let best = rows.min(by: { abs(($0.created ?? .distantPast).timeIntervalSince(fd)) < abs(($1.created ?? .distantPast).timeIntervalSince(fd)) }) {
                a.apply(best)
            }
            let r = DateResolver.resolve(a, fileDate: info?.captureDate, camera: info?.camera)
            if r == .distantPast { undated.append(a.name) }
            if let c = a.csvCreationDate, abs(r.timeIntervalSince(c)) > 365 * 86_400 {
                movedYears.append("\(a.name) \(c.formatted(date: .numeric, time: .omitted))→\(r.formatted(date: .numeric, time: .omitted))")
            }
            if r > Date() { futureResolved.append(a.name) }
            if !FileManager.default.fileExists(atPath: thumbDir.appendingPathComponent(stableHash(a.cacheKey) + "-256.jpg").path) { noThumb.append(a.name + (a.isZipped ? " (zip)" : "")) }
        }
        say("items with no cached file details: \(noInfo)")
        say("images whose pixels couldn't be read: \(unreadableImages.count)" + eg(unreadableImages))
        say("videos with no known duration: \(videosNoDuration)")
        say("items the date fix moves by more than a year: \(movedYears.count)" + eg(movedYears, 8))
        say("items dated in the future after the fix: \(futureResolved.count)" + eg(futureResolved))
        say("items still without any date: \(undated.count)" + eg(undated, 8))
        let multi = lib.assets.filter { $0.candidateRows != nil }
        say("files sharing a listed name with another file in their folder: \(multi.count)")
        let emptyFiles = lib.assets.filter { $0.fileSize == 0 }.map(\.name)
        say("empty (0-byte) files in Apple's export: \(emptyFiles.count)" + eg(emptyFiles))
        say("items with no saved thumbnail: \(noThumb.count)" + eg(noThumb, 8))
    }
}
