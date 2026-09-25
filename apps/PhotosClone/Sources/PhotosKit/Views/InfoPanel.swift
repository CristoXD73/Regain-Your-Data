import MapKit
import SwiftUI

struct InfoPanel: View {
    @Environment(LibraryStore.self) private var store
    let asset: Asset?

    var body: some View {
        if let a = asset {
            let info = store.info(a)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(a.date == .distantPast ? "Unknown Date" : a.date.formatted(date: .complete, time: .omitted))
                            .font(.headline)
                        if a.date != .distantPast {
                            Text(a.date.formatted(date: .omitted, time: .shortened)).foregroundStyle(.secondary)
                        }
                    }

                    if a.fileSize == 0 {
                        Label("This file is empty (0 bytes) in the export Apple sent. The photo or video itself isn't in your download.", systemImage: "exclamationmark.triangle")
                            .font(.callout).foregroundStyle(.orange)
                    }
                    if let info {
                        box {
                            if let cam = info.camera { Text(cam).font(.subheadline.weight(.semibold)) }
                            if let lens = info.lens { Text(lens).font(.caption).foregroundStyle(.secondary) }
                            HStack(spacing: 10) {
                                if let w = info.width, let h = info.height {
                                    Text("\(w) × \(h)")
                                    Text(String(format: "%.1f MP", Double(w * h) / 1_000_000))
                                }
                                Text(ByteCountFormatter.string(fromByteCount: a.fileSize, countStyle: .file))
                            }
                            .font(.caption).foregroundStyle(.secondary)
                            let exif = exifLine(info)
                            if !exif.isEmpty { Text(exif).font(.caption.monospacedDigit()) }
                            if let d = info.duration {
                                Text([formatDuration(d), info.codec, info.fps.map { String(format: "%.0f fps", $0) }].compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption.monospacedDigit())
                            }
                        }
                    } else {
                        Text("Reading file details…").font(.caption).foregroundStyle(.secondary)
                    }

                    if let info, let lat = info.latitude, let lon = info.longitude {
                        let c = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                        Map(initialPosition: .region(MKCoordinateRegion(center: c, latitudinalMeters: 3000, longitudinalMeters: 3000))) {
                            Marker("", coordinate: c)
                        }
                        .frame(height: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .id(a.id)
                        Text(String(format: "%.5f, %.5f", lat, lon)).font(.caption.monospaced()).foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }

                    if let an = store.analysis(a) {
                        let top = an.labels.filter { $0.value >= 0.3 }.sorted { $0.value > $1.value }.prefix(8)
                        if !top.isEmpty {
                            section("In This Photo") {
                                Text(top.map { PhotoAnalyzer.displayName($0.key) }.joined(separator: " · "))
                                    .font(.callout)
                            }
                        }
                        if let text = an.text, !text.isEmpty {
                            section("Text") {
                                Text(text.count > 400 ? String(text.prefix(400)) + "…" : text)
                                    .font(.caption).textSelection(.enabled)
                                Button("Copy Text") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(text, forType: .string)
                                }
                                .controlSize(.small)
                            }
                        }
                    }

                    section("iCloud") {
                        row("Kind", kindText(a))
                        row("Favorite", a.isFavorite ? "Yes" : "No")
                        if a.isHidden { row("Hidden", "Yes") }
                        if a.isDeleted { row("Recently Deleted", a.deletedAt.map { "Since " + $0.formatted(date: .abbreviated, time: .omitted) } ?? "In iCloud's export") }
                        if let c = a.csvCreationDate { row("Created", c.formatted(date: .abbreviated, time: .shortened)) }
                        if let i = a.importDate { row("Imported", i.formatted(date: .abbreviated, time: .shortened)) }
                        row("Views", "\(a.viewCount)")
                        if let c = a.checksum, !c.isEmpty { row("Checksum", c) }
                    }

                    let albums = store.albumTitles(for: a)
                    if !albums.isEmpty {
                        section("Albums & Memories") {
                            ForEach(albums, id: \.self) { Text($0).font(.callout) }
                        }
                    }

                    section("File") {
                        row("Name", a.name)
                        if let p = a.pairedSource { row("Motion", p.name) }
                        if let part = a.part { row("From", part) }
                        if case .zip(let e) = a.source {
                            row("Stored in", e.archive.url.lastPathComponent)
                            row("Compressed", ByteCountFormatter.string(fromByteCount: Int64(e.compressedSize), countStyle: .file))
                        }
                        row("Path", a.relativePath)
                        HStack {
                            Button(a.isZipped ? "Show Zip in Finder" : "Show in Finder") { store.revealInFinder([a]) }
                            if a.isZipped { Button("Export Original…") { store.export([a]) } }
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            ContentUnavailableView("No Selection", systemImage: "info.circle", description: Text("Select one photo to see its details."))
        }
    }

    private func kindText(_ a: Asset) -> String {
        switch a.kind {
        case .livePhoto: "Live Photo"
        case .video: a.isScreenRecording ? "Screen Recording" : "Video"
        case .photo: a.isScreenshot ? "Screenshot" : a.ext.uppercased() + " Photo"
        }
    }

    private func exifLine(_ i: MediaInfo) -> String {
        var parts: [String] = []
        if let iso = i.iso { parts.append("ISO \(iso)") }
        if let f = i.focalLength { parts.append(String(format: "%.0f mm", f)) }
        if let n = i.fNumber { parts.append(String(format: "ƒ%.1f", n)) }
        if let e = i.exposure { parts.append(e >= 1 ? String(format: "%.1fs", e) : "1/\(Int((1 / e).rounded()))s") }
        return parts.joined(separator: "   ")
    }

    private func box<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6, content: content)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
            content()
        }
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack(alignment: .top) {
            Text(k).foregroundStyle(.secondary).frame(width: 78, alignment: .leading)
            Text(v).textSelection(.enabled).lineLimit(3).truncationMode(.middle)
        }
        .font(.callout)
    }
}
