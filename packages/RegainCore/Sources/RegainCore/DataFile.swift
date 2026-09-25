import Foundation
import UniformTypeIdentifiers

/// One file of a data export, either on disk or inside a zip that stays zipped.
public struct DataFile: Identifiable, Hashable, Sendable {
    public enum Location: Hashable, Sendable {
        case file(URL)
        case zip(URL, String)
    }

    public enum Kind: String, Sendable {
        case table, json, html, text, image, video, audio, pdf, other
    }

    public let id: String
    public let location: Location
    /// File name, e.g. "Viewing History.csv".
    public let name: String
    /// The folder it sits in inside its zip or export, e.g. "Your Prime Video Viewing Activity".
    public let folder: String
    /// What the file belongs to: the zip's name ("Prime Video") or the top folder.
    public let group: String
    public let size: UInt64
    /// The export's own explanation of the file, when it ships one (Amazon's FileDescriptions.csv).
    public var summary: String?

    public init(location: Location, name: String, folder: String, group: String, size: UInt64, summary: String? = nil) {
        self.location = location
        self.name = name
        self.folder = folder
        self.group = group
        self.size = size
        self.summary = summary
        switch location {
        case .file(let u): id = u.path
        case .zip(let z, let p): id = z.path + "|" + p
        }
    }

    public var ext: String { (name as NSString).pathExtension.lowercased() }

    public var kind: Kind {
        switch ext {
        case "csv", "tsv": return .table
        case "json", "geojson": return .json
        case "html", "htm": return .html
        case "txt", "md", "xml", "log", "ics", "vcf", "eml", "yaml", "yml": return .text
        case "pdf": return .pdf
        default:
            guard let t = UTType(filenameExtension: ext) else { return .other }
            if t.conforms(to: .image) { return .image }
            if t.conforms(to: .movie) || t.conforms(to: .video) { return .video }
            if t.conforms(to: .audio) { return .audio }
            if t.conforms(to: .text) { return .text }
            return .other
        }
    }

    public var symbol: String {
        switch kind {
        case .table: return "tablecells"
        case .json: return "curlybraces"
        case .html: return "globe"
        case .text: return "doc.text"
        case .image: return "photo"
        case .video: return "film"
        case .audio: return "waveform"
        case .pdf: return "doc.richtext"
        case .other: return "doc"
        }
    }

    public func read(limit: UInt64? = nil) throws -> Data {
        switch location {
        case .file(let u):
            guard let limit else { return try Data(contentsOf: u, options: .mappedIfSafe) }
            let h = try FileHandle(forReadingFrom: u)
            defer { try? h.close() }
            return try h.read(upToCount: Int(limit)) ?? Data()
        case .zip(let z, let p):
            guard let e = ZipCache.shared.entry(p, in: z) else { throw CocoaError(.fileNoSuchFile) }
            return try e.archive.data(e, limit: limit)
        }
    }

    public func table() throws -> CSVTable { CSVTable(data: try read()) }

    /// A real file for things that need one (video, PDF, Quick Look). Zipped files are copied out
    /// to the Mac's caches, never next to the export.
    public func fileURL() throws -> URL {
        switch location {
        case .file(let u): return u
        case .zip(let z, let p):
            guard let e = ZipCache.shared.entry(p, in: z) else { throw CocoaError(.fileNoSuchFile) }
            let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("RegainYourData/Preview", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let dest = dir.appendingPathComponent(stableHash(id) + "-" + name)
            if !FileManager.default.fileExists(atPath: dest.path) { try e.archive.extract(e, to: dest) }
            return dest
        }
    }

    /// Where it came from, for display: "Prime Video.zip › Your Prime Video Viewing Activity".
    public var origin: String {
        switch location {
        case .file(let u): return u.deletingLastPathComponent().path
        case .zip(let z, _): return ([z.lastPathComponent] + (folder.isEmpty ? [] : [folder])).joined(separator: " › ")
        }
    }

    /// Removes files copied out for previewing.
    public static func clearPreviewCache() {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("RegainYourData/Preview")
        try? FileManager.default.removeItem(at: dir)
    }
}

/// Opened zips, so reading many files from one zip parses its directory once.
public final class ZipCache: @unchecked Sendable {
    public static let shared = ZipCache()
    private var zips: [URL: (ZipArchive, [String: ZipEntry])] = [:]
    private let lock = NSLock()

    public func archive(_ url: URL) -> (ZipArchive, [String: ZipEntry])? {
        lock.lock(); defer { lock.unlock() }
        if let z = zips[url] { return z }
        guard let a = try? ZipArchive(url: url) else { return nil }
        let z = (a, Dictionary(a.entries.map { ($0.path, $0) }, uniquingKeysWith: { a, _ in a }))
        zips[url] = z
        return z
    }

    public func entry(_ path: String, in zip: URL) -> ZipEntry? { archive(zip)?.1[path] }
}

public enum DataScanner {
    /// Every file under `root`, looking inside zips without unpacking them. Hidden files, macOS
    /// resource forks and folders inside apps are skipped. A zip's files are grouped under the
    /// zip's name; loose files under their top folder.
    public static func scan(_ root: URL, maxDepth: Int = 8) -> [DataFile] {
        let fm = FileManager.default
        let root = root.resolvingSymlinksInPath()
        var out: [DataFile] = []
        func add(zip u: URL) {
            guard let (a, _) = ZipCache.shared.archive(u) else { return }
            let group = u.deletingPathExtension().lastPathComponent
            for e in a.entries where !e.path.hasSuffix("/") && !e.path.hasPrefix("__MACOSX") && !e.name.hasPrefix("._") && e.name != ".DS_Store" {
                out.append(DataFile(location: .zip(u, e.path), name: e.name, folder: e.directory, group: group, size: e.size))
            }
        }
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: root.path, isDirectory: &isDir) else { return [] }
        if !isDir.boolValue {
            if root.pathExtension.lowercased() == "zip" { add(zip: root) }
            else { out.append(DataFile(location: .file(root), name: root.lastPathComponent, folder: "", group: root.deletingLastPathComponent().lastPathComponent, size: fileSize(root))) }
            return out
        }
        let rootComponents = root.pathComponents
        let e = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey], options: [.skipsHiddenFiles, .skipsPackageDescendants])
        while let u = e?.nextObject() as? URL {
            if e!.level > maxDepth { e?.skipDescendants(); continue }
            guard (try? u.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            if u.pathExtension.lowercased() == "zip" { add(zip: u); continue }
            // Relative to the root by path components, since the enumerator may report the
            // root with or without symlinks resolved (/tmp vs /private/tmp, ~/Desktop links).
            let comps = u.resolvingSymlinksInPath().pathComponents
            let rel = Array(comps.dropFirst(rootComponents.count))
            let group = rel.count > 1 ? rel[0] : "Other files"
            out.append(DataFile(location: .file(u), name: u.lastPathComponent, folder: rel.dropLast().dropFirst(rel.count > 1 ? 1 : 0).joined(separator: "/"),
                                group: group, size: fileSize(u)))
        }
        applyDescriptions(&out)
        return out
    }

    static func fileSize(_ u: URL) -> UInt64 { UInt64((try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }

    /// Amazon (and others) ship a FileDescriptions.csv: "File name,Description". Attach each
    /// description to the files with that name.
    static func applyDescriptions(_ files: inout [DataFile]) {
        var map: [String: String] = [:]
        for f in files where f.name.lowercased().hasPrefix("filedescription") && f.kind == .table {
            guard let t = try? f.table(), let n = t.column("File name", "File", "Name"), let d = t.column("Description") else { continue }
            for r in t.rows where !r[safe: n].isEmpty { map[r[safe: n].lowercased()] = r[safe: d] }
        }
        guard !map.isEmpty else { return }
        for i in files.indices { files[i].summary = map[files[i].name.lowercased()] }
    }
}

/// FNV-1a, so cache file names stay the same between launches (String.hashValue is seeded per run).
public func stableHash(_ s: String) -> String {
    var h: UInt64 = 0xcbf29ce484222325
    for b in s.utf8 { h ^= UInt64(b); h = h &* 0x100000001b3 }
    return String(h, radix: 36)
}
