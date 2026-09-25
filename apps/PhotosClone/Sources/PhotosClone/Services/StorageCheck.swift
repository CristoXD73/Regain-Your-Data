import Foundation
import zlib

/// Answers "can I delete the unzipped folders and keep only the zips?".
/// Every file in each top-level folder must exist in one of the zips with the same name and size,
/// and a random sample is also compared byte for byte.
struct FolderReport: Identifiable, Sendable {
    let id: String
    let url: URL
    var files = 0
    var bytes: Int64 = 0
    var missing: [String] = []
    var sampled = 0
    var sampleMismatches: [String] = []
    var safe: Bool { files > 0 && missing.isEmpty && sampleMismatches.isEmpty }
}

enum StorageCheck {
    static func run(root: URL, zips: [ZipArchive], samplesPerFolder: Int = 60,
                    progress: @escaping @Sendable (String) -> Void) -> (zipBytes: Int64, folders: [FolderReport]) {
        func norm(_ s: String) -> String { s.precomposedStringWithCanonicalMapping }
        var inZips: [String: ZipEntry] = [:]
        var bySize: [UInt64: [ZipEntry]] = [:]
        for z in zips { for e in z.entries { inZips["\(norm(e.name))|\(e.size)"] = e; bySize[e.size, default: []].append(e) } }

        /// Renamed copies ("Photo Details-1 copy.csv", "IMG_1 (2).mov") still count when their
        /// contents match a zip entry: same size and same CRC-32.
        func sameContent(_ u: URL, size: Int64) -> ZipEntry? {
            guard let candidates = bySize[UInt64(size)], let h = try? FileHandle(forReadingFrom: u) else { return nil }
            defer { try? h.close() }
            var crc = crc32(0, nil, 0)
            while let chunk = try? h.read(upToCount: 1 << 20), !chunk.isEmpty {
                crc = chunk.withUnsafeBytes { crc32(crc, $0.bindMemory(to: Bytef.self).baseAddress, uInt(chunk.count)) }
            }
            return candidates.first { $0.crc == UInt32(crc) }
        }
        let zipBytes = zips.reduce(Int64(0)) { $0 + Int64((try? $1.url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }

        let fm = FileManager.default
        let top = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        var reports: [FolderReport] = []
        for dir in top.sorted(by: { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }) {
            guard (try? dir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            // Apple's guide PDFs come from a separate download, not the zips; leave them out.
            if dir.lastPathComponent == "icloud-photos" || dir.lastPathComponent.hasPrefix(".") { continue }
            progress("Checking \(dir.lastPathComponent)…")
            var r = FolderReport(id: dir.path, url: dir)
            var covered: [(URL, ZipEntry)] = []
            let walker = fm.enumerator(at: dir, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey])
            while let u = walker?.nextObject() as? URL {
                let name = u.lastPathComponent
                if name.hasPrefix("._") || name == ".DS_Store" { continue }
                let v = try? u.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
                if v?.isDirectory == true { continue }
                let size = Int64(v?.fileSize ?? 0)
                r.files += 1
                r.bytes += size
                // The Shared Albums zip is itself inside Part 1's zip, so it counts like any file.
                if let e = inZips["\(norm(name))|\(size)"] ?? sameContent(u, size: size) { covered.append((u, e)) }
                else { r.missing.append(String(u.path.dropFirst(dir.path.count + 1))) }
            }
            // Spot-check contents: unpack a sample and compare with the file on disk.
            let sample = covered.filter { $0.1.size < 40_000_000 }.shuffled().prefix(samplesPerFolder)
            for (i, (u, e)) in sample.enumerated() {
                if i % 10 == 0 { progress("Comparing \(dir.lastPathComponent) byte for byte (\(i) of \(sample.count))…") }
                let same = (try? e.archive.data(e)) == (try? Data(contentsOf: u))
                r.sampled += 1
                if !same { r.sampleMismatches.append(u.lastPathComponent) }
            }
            reports.append(r)
        }
        return (zipBytes, reports)
    }
}
