import Compression
import Foundation
import zlib

/// Read-only access to a .zip without unpacking it. Supports ZIP64, which Apple's exports need
/// (each part is 40–70 GB with tens of thousands of entries), and the two methods zips use:
/// stored and deflate.
final class ZipArchive: @unchecked Sendable {
    let url: URL
    private let fd: Int32
    private(set) var entries: [ZipEntry] = []

    enum ZipError: Error { case open, notZip, corrupt(String), unsupported(UInt16), crc }

    init(url: URL) throws {
        self.url = url
        fd = Darwin.open(url.path, O_RDONLY)
        guard fd >= 0 else { throw ZipError.open }
        do { try readCentralDirectory() } catch { Darwin.close(fd); throw error }
    }

    deinit { Darwin.close(fd) }

    // MARK: Central directory

    private func read(_ count: Int, at offset: UInt64) throws -> Data {
        var data = Data(count: count)
        let n = data.withUnsafeMutableBytes { pread(fd, $0.baseAddress, count, off_t(offset)) }
        guard n == count else { throw ZipError.corrupt("short read at \(offset)") }
        return data
    }

    private func readCentralDirectory() throws {
        var st = stat()
        guard fstat(fd, &st) == 0 else { throw ZipError.open }
        let fileSize = UInt64(st.st_size)

        // End of central directory: 22 bytes plus a comment of up to 64 KB, at the very end.
        let tailLen = Int(min(fileSize, 65_557))
        let tail = try read(tailLen, at: fileSize - UInt64(tailLen))
        guard let eocd = tail.lastIndex(ofSignature: 0x06054b50) else { throw ZipError.notZip }
        var count = UInt64(tail.u16(eocd + 10))
        var cdSize = UInt64(tail.u32(eocd + 12))
        var cdOffset = UInt64(tail.u32(eocd + 16))

        // ZIP64: the real values live in a separate record, found through a locator.
        if count == 0xFFFF || cdSize == 0xFFFF_FFFF || cdOffset == 0xFFFF_FFFF, eocd >= 20, tail.u32(eocd - 20) == 0x07064b50 {
            let rec = try read(56, at: tail.u64(eocd - 20 + 8))
            guard rec.u32(0) == 0x06064b50 else { throw ZipError.corrupt("zip64 record") }
            count = rec.u64(32)
            cdSize = rec.u64(40)
            cdOffset = rec.u64(48)
        }

        let cd = try read(Int(cdSize), at: cdOffset)
        var p = 0
        entries.reserveCapacity(Int(count))
        while p + 46 <= cd.count, cd.u32(p) == 0x02014b50 {
            let flags = cd.u16(p + 8)
            let method = cd.u16(p + 10)
            let crc = cd.u32(p + 16)
            var comp = UInt64(cd.u32(p + 20))
            var size = UInt64(cd.u32(p + 24))
            let nameLen = Int(cd.u16(p + 28)), extraLen = Int(cd.u16(p + 30)), commentLen = Int(cd.u16(p + 32))
            var local = UInt64(cd.u32(p + 42))
            let nameData = cd.subdata(in: (p + 46)..<(p + 46 + nameLen))

            // ZIP64 extra field (id 1) holds whichever of the three values overflowed, in order.
            var e = p + 46 + nameLen
            let extraEnd = e + extraLen
            while e + 4 <= extraEnd {
                let id = cd.u16(e), len = Int(cd.u16(e + 2))
                if id == 1 {
                    var q = e + 4
                    if size == 0xFFFF_FFFF { size = cd.u64(q); q += 8 }
                    if comp == 0xFFFF_FFFF { comp = cd.u64(q); q += 8 }
                    if local == 0xFFFF_FFFF { local = cd.u64(q) }
                }
                e += 4 + len
            }

            // Bit 11 marks UTF-8 names; Apple sets it inconsistently, so try UTF-8 either way.
            let path = String(data: nameData, encoding: .utf8)
                ?? String(data: nameData, encoding: flags & 0x800 != 0 ? .utf8 : .isoLatin1) ?? ""
            if !path.hasSuffix("/") {
                entries.append(ZipEntry(archive: self, path: path, method: method, crc: crc,
                                        compressedSize: comp, size: size, localHeaderOffset: local))
            }
            p = extraEnd + commentLen
        }
    }

    // MARK: Reading entries

    /// Offset of the entry's data, which follows a variable-length local header.
    private func dataOffset(_ e: ZipEntry) throws -> UInt64 {
        let h = try read(30, at: e.localHeaderOffset)
        guard h.u32(0) == 0x04034b50 else { throw ZipError.corrupt("local header for \(e.path)") }
        return e.localHeaderOffset + 30 + UInt64(h.u16(26)) + UInt64(h.u16(28))
    }

    /// Streams the entry's bytes to `sink` in chunks. Stops early (without error) once `limit`
    /// bytes were produced, which is enough to read EXIF from the start of a photo.
    func stream(_ e: ZipEntry, limit: UInt64? = nil, sink: (UnsafeRawBufferPointer) throws -> Void) throws {
        let start = try dataOffset(e)
        let chunk = 1 << 20
        var readPos: UInt64 = 0
        var produced: UInt64 = 0
        let want = min(limit ?? e.size, e.size)
        var crc = crc32(0, nil, 0)
        let checkCRC = limit == nil

        switch e.method {
        case 0:
            while produced < want {
                let n = Int(min(UInt64(chunk), want - produced))
                let d = try read(n, at: start + produced)
                try d.withUnsafeBytes { buf in
                    if checkCRC { crc = crc32(crc, buf.bindMemory(to: Bytef.self).baseAddress, uInt(n)) }
                    try sink(buf)
                }
                produced += UInt64(n)
            }
        case 8:
            // Compression's ZLIB algorithm is raw DEFLATE, which is exactly what zip stores.
            var s = compression_stream(dst_ptr: UnsafeMutablePointer(bitPattern: 1)!, dst_size: 0,
                                       src_ptr: UnsafePointer(bitPattern: 1)!, src_size: 0, state: nil)
            guard compression_stream_init(&s, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK else {
                throw ZipError.corrupt("inflate init")
            }
            defer { compression_stream_destroy(&s) }
            let out = UnsafeMutablePointer<UInt8>.allocate(capacity: chunk)
            defer { out.deallocate() }
            var src = Data()
            var srcOffset = 0
            while produced < want {
                if srcOffset == src.count && readPos < e.compressedSize {
                    let n = Int(min(UInt64(chunk), e.compressedSize - readPos))
                    src = try read(n, at: start + readPos)
                    srcOffset = 0
                    readPos += UInt64(n)
                }
                let isLast = readPos >= e.compressedSize
                var consumed = 0
                let status: compression_status = src.withUnsafeBytes { raw in
                    let base = raw.bindMemory(to: UInt8.self).baseAddress ?? UnsafePointer(out)
                    let avail = src.count - srcOffset
                    s.src_ptr = base.advanced(by: srcOffset)
                    s.src_size = avail
                    s.dst_ptr = out
                    s.dst_size = chunk
                    let st = compression_stream_process(&s, isLast ? Int32(COMPRESSION_STREAM_FINALIZE.rawValue) : 0)
                    consumed = avail - s.src_size
                    return st
                }
                srcOffset += consumed
                if status == COMPRESSION_STATUS_ERROR { throw ZipError.corrupt("inflate \(e.path)") }
                let made = chunk - s.dst_size
                let n = Int(min(UInt64(made), want - produced))
                if n > 0 {
                    if checkCRC { crc = crc32(crc, out, uInt(n)) }
                    try sink(UnsafeRawBufferPointer(start: out, count: n))
                    produced += UInt64(n)
                }
                if status == COMPRESSION_STATUS_END { break }
                if made == 0 && consumed == 0 && isLast { throw ZipError.corrupt("truncated \(e.path)") }
            }
        default:
            throw ZipError.unsupported(e.method)
        }
        if checkCRC && produced == e.size && UInt32(crc) != e.crc { throw ZipError.crc }
    }

    func data(_ e: ZipEntry, limit: UInt64? = nil) throws -> Data {
        var d = Data()
        d.reserveCapacity(Int(min(limit ?? e.size, e.size)))
        try stream(e, limit: limit) { d.append(contentsOf: $0) }
        return d
    }

    func extract(_ e: ZipEntry, to dest: URL) throws {
        let tmp = dest.appendingPathExtension("partial")
        FileManager.default.createFile(atPath: tmp.path, contents: nil)
        let h = try FileHandle(forWritingTo: tmp)
        do {
            try stream(e) { h.write(Data($0)) }
            try h.close()
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: tmp, to: dest)
        } catch {
            try? h.close()
            try? FileManager.default.removeItem(at: tmp)
            throw error
        }
    }
}

/// One file inside a zip. Class so assets can share it without copying the path around.
final class ZipEntry: Hashable, @unchecked Sendable {
    unowned let archive: ZipArchive
    let path: String
    let method: UInt16
    let crc: UInt32
    let compressedSize: UInt64
    let size: UInt64
    let localHeaderOffset: UInt64

    init(archive: ZipArchive, path: String, method: UInt16, crc: UInt32, compressedSize: UInt64, size: UInt64, localHeaderOffset: UInt64) {
        self.archive = archive; self.path = path; self.method = method; self.crc = crc
        self.compressedSize = compressedSize; self.size = size; self.localHeaderOffset = localHeaderOffset
    }

    var name: String { (path as NSString).lastPathComponent }
    var directory: String { (path as NSString).deletingLastPathComponent }

    static func == (a: ZipEntry, b: ZipEntry) -> Bool { a === b }
    func hash(into h: inout Hasher) { h.combine(ObjectIdentifier(self)) }
}

private extension Data {
    func u16(_ i: Int) -> UInt16 { UInt16(self[startIndex + i]) | UInt16(self[startIndex + i + 1]) << 8 }
    func u32(_ i: Int) -> UInt32 { UInt32(u16(i)) | UInt32(u16(i + 2)) << 16 }
    func u64(_ i: Int) -> UInt64 { UInt64(u32(i)) | UInt64(u32(i + 4)) << 32 }

    func lastIndex(ofSignature sig: UInt32) -> Int? {
        var i = count - 22
        while i >= 0 {
            if u32(i) == sig { return i }
            i -= 1
        }
        return nil
    }
}
