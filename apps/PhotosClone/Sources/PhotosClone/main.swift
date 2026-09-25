import Foundation

// `PhotosClone --scan <folder>` prints what the scanner found, without opening a window.
if let i = CommandLine.arguments.firstIndex(of: "--scan"), i + 1 < CommandLine.arguments.count {
    let root = URL(fileURLWithPath: CommandLine.arguments[i + 1])
    let lib = ExportScanner.scan(root: root, zipsOnly: CommandLine.arguments.contains("--zips-only")) { _ in }
    let a = lib.assets
    func n(_ f: (Asset) -> Bool) -> Int { a.filter(f).count }
    print("""
    root: \(root.path)
    parts: \(lib.parts.count)  zips opened: \(lib.zips.count)  items read from inside zips: \(lib.zippedCount)
    Photo Details rows: \(lib.csvRowCount)
    assets: \(a.count)  (photos \(n { $0.kind == .photo }), videos \(n { $0.kind == .video }), live \(n { $0.kind == .livePhoto }))
    favorites \(n { $0.isFavorite })  hidden \(n { $0.isHidden })  deleted \(n { $0.isDeleted })  shared-album items \(n { $0.part == "Shared Album" })
    screenshots \(n { $0.isScreenshot })  screen recordings \(n { $0.isScreenRecording })
    files without a details row: \(lib.filesWithoutMetadata)   undated: \(n { $0.date == .distantPast })
    albums: \(lib.albums.count) (empty: \(lib.albums.filter { $0.assetIDs.isEmpty }.map(\.title)))
    memories: \(lib.memories.count), shared albums: \(lib.sharedAlbums.map { "\($0.title) (\($0.assetIDs.count))" })
    date range: \(a.map(\.date).filter { $0 != .distantPast }.min().map { "\($0)" } ?? "-") … \(a.map(\.date).max().map { "\($0)" } ?? "-")
    scan took \(String(format: "%.1f", lib.scanDuration))s
    """)
    exit(0)
}

// `PhotosClone --zip-test <zip> [<extracted root>]` lists a zip and checks entries against disk.
if let i = CommandLine.arguments.firstIndex(of: "--zip-test"), i + 1 < CommandLine.arguments.count {
    let t0 = Date()
    let z = try ZipArchive(url: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
    print("entries: \(z.entries.count) in \(String(format: "%.2f", Date().timeIntervalSince(t0)))s, methods: \(Set(z.entries.map(\.method)))")
    print("largest: \(z.entries.max { $0.size < $1.size }.map { "\($0.path) \($0.size)" } ?? "-")")
    let odd = z.entries.filter { $0.path.unicodeScalars.contains { $0.value > 127 } }.prefix(3).map(\.path)
    print("non-ASCII names: \(odd)")
    if i + 2 < CommandLine.arguments.count {
        let root = CommandLine.arguments[i + 2]
        var checked = 0, same = 0
        for e in z.entries where e.size < 20_000_000 && e.size > 0 {
            let f = root + "/" + e.path
            guard let disk = FileManager.default.contents(atPath: f) else { continue }
            let t = Date()
            let d = try z.data(e)
            checked += 1
            if d == disk { same += 1 } else { print("MISMATCH \(e.path)") }
            if checked == 1 { print("first inflate: \(e.size) bytes in \(String(format: "%.3f", Date().timeIntervalSince(t)))s") }
            if checked >= 40 { break }
        }
        print("byte-identical to extracted file: \(same)/\(checked)")
        if let e = z.entries.first(where: { $0.path.hasSuffix(".HEIC") }) {
            let head = try z.data(e, limit: 262_144)
            print("partial read of \(e.name): \(head.count) bytes")
        }
    }
    exit(0)
}

// `PhotosClone --storage-check <folder>` runs the Free Up Space check and prints the result.
if let i = CommandLine.arguments.firstIndex(of: "--storage-check"), i + 1 < CommandLine.arguments.count {
    let root = URL(fileURLWithPath: CommandLine.arguments[i + 1])
    let lib = ExportScanner.scan(root: root) { _ in }
    let r = StorageCheck.run(root: root, zips: lib.zips, samplesPerFolder: 30) { _ in }
    let f = ByteCountFormatter()
    print("zips: \(f.string(fromByteCount: r.zipBytes))")
    for x in r.folders {
        print("\(x.safe ? "SAFE" : "KEEP")  \(x.url.lastPathComponent): \(x.files) files, \(f.string(fromByteCount: x.bytes)), missing \(x.missing.count), sampled \(x.sampled), mismatched \(x.sampleMismatches.count)")
        for m in x.missing.prefix(5) { print("      not in zips: \(m)") }
    }
    exit(0)
}

// `PhotosClone --unpack-test <zip> <min MB>` unpacks one video through the SSD cache and times it.
if let i = CommandLine.arguments.firstIndex(of: "--unpack-test"), i + 2 < CommandLine.arguments.count {
    let z = try ZipArchive(url: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
    let minSize = UInt64(CommandLine.arguments[i + 2])! * 1_000_000
    guard let e = z.entries.filter({ $0.name.hasSuffix(".MOV") && $0.size >= minSize }).min(by: { $0.size < $1.size }) else { exit(1) }
    let sem = DispatchSemaphore(value: 0)
    Task {
        let t = Date()
        guard let url = try? await MediaAccess.fileURL(.zip(e)) else { print("unpack failed"); exit(1) }
        print("unpacked \(e.name) (\(e.size / 1_000_000) MB) in \(String(format: "%.1f", Date().timeIntervalSince(t)))s -> \(url.path)")
        let t2 = Date()
        _ = try? await MediaAccess.fileURL(.zip(e))
        print("second request (cached): \(String(format: "%.3f", Date().timeIntervalSince(t2)))s")
        let info = await MediaInfoReader.readVideo(url)
        print("playable: duration \(info.duration.map { String(format: "%.1fs", $0) } ?? "?"), \(info.width ?? 0)x\(info.height ?? 0) \(info.codec ?? "")")
        print("cache budget \(UnpackCache.shared.budget / 1_000_000_000) GB, used \(UnpackCache.shared.usage() / 1_000_000) MB")
        await UnpackCache.shared.clear()
        print("cache cleared, used \(UnpackCache.shared.usage()) bytes")
        sem.signal()
    }
    sem.wait()
    exit(0)
}

// `PhotosClone --ai-test <folder> <count>` labels a random sample from cached thumbnails and
// reports label counts and a few searches (text only).
if let i = CommandLine.arguments.firstIndex(of: "--ai-test"), i + 2 < CommandLine.arguments.count {
    let lib = ExportScanner.scan(root: URL(fileURLWithPath: CommandLine.arguments[i + 1])) { _ in }
    let n = Int(CommandLine.arguments[i + 2])!
    let sem = DispatchSemaphore(value: 0)
    Task.detached {
        let sample = lib.assets.filter { $0.kind != .video }.shuffled().prefix(n)
        var labelled: [(Asset, [String: Float])] = []
        let t = Date()
        for a in sample {
            guard let img = await ThumbnailLoader.shared.image(for: a, size: 256),
                  let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }
            labelled.append((a, PhotoAnalyzer.labels(cg)))
        }
        let secs = Date().timeIntervalSince(t)
        print("labelled \(labelled.count) in \(String(format: "%.1f", secs))s (\(String(format: "%.0f", secs / Double(max(1, labelled.count)) * 1000)) ms each)")
        var freq: [String: Int] = [:]
        for (_, l) in labelled { for (k, v) in l where v >= 0.3 { freq[k, default: 0] += 1 } }
        print("top labels:", freq.sorted { $0.value > $1.value }.prefix(25).map { "\($0.key)=\($0.value)" }.joined(separator: " "))
        for q in ["dog", "puppy", "beach", "ocean", "food", "car", "sunset", "people", "document", "text"] {
            let w = SearchQuery(q).words.first!
            let hits = labelled.filter { p in w.labels.contains { (p.1[$0] ?? 0) >= 0.3 } }.count
            print("  \"\(q)\" -> labels \(w.labels.sorted().prefix(6)) -> \(hits) of \(labelled.count)")
        }
        let shots = labelled.filter { PhotoAnalyzer.needsText($0.0, labels: $0.1) }.prefix(3)
        for (a, _) in shots {
            let t2 = Date()
            guard let img = await ThumbnailLoader.displayImage(a.source, maxPixel: 2048),
                  let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }
            let text = PhotoAnalyzer.text(cg)
            print("  text pass on one \(a.isScreenshot ? "screenshot" : "document"): \(text.count) characters, \(text.split(separator: "\n").count) lines, \(String(format: "%.2f", Date().timeIntervalSince(t2)))s")
        }
        sem.signal()
    }
    sem.wait()
    exit(0)
}

// `PhotosClone --ocr-bench <folder> <count>` times text recognition on screenshots.
if let i = CommandLine.arguments.firstIndex(of: "--ocr-bench"), i + 2 < CommandLine.arguments.count {
    let lib = ExportScanner.scan(root: URL(fileURLWithPath: CommandLine.arguments[i + 1])) { _ in }
    let n = Int(CommandLine.arguments[i + 2])!
    let sem = DispatchSemaphore(value: 0)
    Task.detached {
        for a in lib.assets.filter(\.isScreenshot).shuffled().prefix(n) {
            let t0 = Date()
            guard let img = await ThumbnailLoader.displayImage(a.source, maxPixel: 2048),
                  let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }
            let t1 = Date()
            let text = PhotoAnalyzer.text(cg)
            let t2 = Date()
            print(String(format: "load %.2fs  ocr %.2fs  %dx%d  %d chars  %@", t1.timeIntervalSince(t0), t2.timeIntervalSince(t1), cg.width, cg.height, text.count, a.isZipped ? "zip" : "file"))
        }
        sem.signal()
    }
    sem.wait()
    exit(0)
}

// `PhotosClone --date-audit <folder>` compares iCloud's creation date with the date in each file.
if let i = CommandLine.arguments.firstIndex(of: "--date-audit"), i + 1 < CommandLine.arguments.count {
    let root = URL(fileURLWithPath: CommandLine.arguments[i + 1])
    let lib = ExportScanner.scan(root: root) { _ in }
    let sem = DispatchSemaphore(value: 0)
    Task.detached {
        let store = MediaInfoStore(root: root)
        var withFileDate = 0, same = 0, sameDay = 0, fileEarlier = 0, fileLater = 0, noFileDate = 0
        var csvEqualsImport = 0, csvEqualsImportAndFileEarlier = 0
        var buckets: [String: Int] = [:]
        var examples: [String] = []
        var tzHours: [Int: Int] = [:]
        var tzExamples: [String] = []
        for a in lib.assets where a.part != "Shared Album" {
            guard let csv = a.csvCreationDate else { continue }
            if csv == a.importDate { csvEqualsImport += 1 }
            guard let info = await store.cached(a), let file = info.captureDate else { noFileDate += 1; continue }
            withFileDate += 1
            let d = file.timeIntervalSince(csv)
            if abs(d) >= 120 && abs(d) < 86_400 { tzHours[Int((d / 3600).rounded()), default: 0] += 1; if tzExamples.count < 4 { tzExamples.append("\(a.name) \(a.kind) iCloud \(csv) file \(file)") } }
            if abs(d) < 120 { same += 1 } else if abs(d) < 86_400 { sameDay += 1 } else if d < 0 {
                fileEarlier += 1
                if csv == a.importDate { csvEqualsImportAndFileEarlier += 1 }
                let years = Int(-d / (365 * 86_400))
                buckets[years == 0 ? "<1y" : "\(years)y+", default: 0] += 1
                if examples.count < 8 { examples.append("\(a.name): iCloud \(csv.formatted(date: .abbreviated, time: .omitted)), file \(file.formatted(date: .abbreviated, time: .omitted)), \(a.kind)") }
            } else { fileLater += 1 }
        }
        print("items with a date inside the file: \(withFileDate), without: \(noFileDate)")
        print("  agree within 2 min: \(same)   within a day (time zone): \(sameDay)")
        print("  file date EARLIER than iCloud's by >1 day: \(fileEarlier) (of which iCloud date == import date: \(csvEqualsImportAndFileEarlier)) by \(buckets.sorted { $0.key < $1.key })")
        print("  file date LATER than iCloud's by >1 day: \(fileLater)")
        print("iCloud 'created' equals 'imported' for \(csvEqualsImport) of \(lib.assets.count) items")
        examples.forEach { print("  e.g. " + $0) }
        // Effect of DateResolver on the whole library.
        var usedFile = 0, tzFixed = 0, moved = 0, keptCSV = 0, fileOnly = 0, none = 0
        var tiesBefore = 0, tiesAfter = 0
        var resolved: [(Date, String)] = [], before: [(Date, String)] = []
        for a in lib.assets where a.part != "Shared Album" {
            let fd = await store.cached(a)?.captureDate
            let r = DateResolver.resolve(a, fileDate: fd)
            let old = a.csvCreationDate ?? a.importDate ?? .distantPast
            if a.csvCreationDate == nil { if fd != nil && r != .distantPast { fileOnly += 1 } else { none += 1 } }
            else if r == fd { if abs(r.timeIntervalSince(old)) > 86_400 { moved += 1 } else { usedFile += 1 } }
            else if r != old { tzFixed += 1 } else { keptCSV += 1 }
            resolved.append((r, a.name)); before.append((old, a.name))
        }
        tiesBefore = Dictionary(grouping: before, by: \.0).values.filter { $0.count > 1 }.reduce(0) { $0 + $1.count }
        tiesAfter = Dictionary(grouping: resolved, by: \.0).values.filter { $0.count > 1 }.reduce(0) { $0 + $1.count }
        print("RESOLVED: precise file time \(usedFile), time-zone fixed (iCloud minute + file seconds) \(tzFixed), moved to file date (>1 day) \(moved), kept iCloud \(keptCSV), no iCloud row but file date \(fileOnly), still undated \(none)")
        print("items sharing an identical timestamp with another item: before \(tiesBefore), after \(tiesAfter)")
        print("hour offsets (file minus iCloud) for the within-a-day group:", tzHours.sorted { $0.key < $1.key })
        tzExamples.forEach { print("  tz e.g. " + $0) }
        sem.signal()
    }
    sem.wait()
    exit(0)
}

// `PhotosClone --audit <folder>` cross-checks every piece of metadata and prints a report.
if let i = CommandLine.arguments.firstIndex(of: "--audit"), i + 1 < CommandLine.arguments.count {
    let sem = DispatchSemaphore(value: 0)
    Task.detached {
        await MetadataAudit.run(root: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
        sem.signal()
    }
    sem.wait()
    exit(0)
}

// `PhotosClone --prebuild <folder>` saves every missing thumbnail (unpacking zipped videos once)
// and the details of zipped videos, like Free Up Space step 1.
if let i = CommandLine.arguments.firstIndex(of: "--prebuild"), i + 1 < CommandLine.arguments.count {
    let root = URL(fileURLWithPath: CommandLine.arguments[i + 1])
    let lib = ExportScanner.scan(root: root) { _ in }
    let sem = DispatchSemaphore(value: 0)
    Task.detached {
        let store = MediaInfoStore(root: root)
        let dir = ThumbnailLoader.shared.dir
        let missing = lib.assets.filter { $0.fileSize > 0 && !FileManager.default.fileExists(atPath: dir.appendingPathComponent(stableHash($0.cacheKey) + "-256.jpg").path) }
        print("missing thumbnails: \(missing.count)")
        var made = 0, failed: [String] = []
        for a in missing {
            if await ThumbnailLoader.shared.image(for: a, size: 256, keepInMemory: false, allowUnpack: true) != nil { made += 1 } else { failed.append(a.name) }
        }
        var infos = 0
        for a in lib.assets where await store.cached(a) == nil {
            if let info = await MediaInfoReader.read(a) { await store.store(info, for: a); infos += 1 }
        }
        await store.save()
        print("thumbnails made: \(made), failed: \(failed.count) \(failed.prefix(8))")
        print("file details added: \(infos)")
        print("unpacked-video cache now: \(UnpackCache.shared.usage() / 1_000_000) MB of \(UnpackCache.shared.budget / 1_000_000_000) GB")
        sem.signal()
    }
    sem.wait()
    exit(0)
}

PhotosCloneApp.main()
