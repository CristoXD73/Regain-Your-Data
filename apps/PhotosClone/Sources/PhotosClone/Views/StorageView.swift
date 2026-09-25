import SwiftUI

/// "Free Up Space": proves the zips hold everything before the user deletes the unzipped folders.
struct StorageView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var thumbBytes: Int64 = 0
    @State private var unpackedBytes: Int64 = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Free Up Space").font(.title2.bold())
            Text("Photos Clone can read your photos straight from the zips Apple gave you, so the unzipped folders are a second copy you don't need. This checks that every file in them is also inside the zips. Photos Clone never deletes anything: when a folder is marked safe, delete it yourself in Finder.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            GroupBox("1. Save thumbnails while the folders are still here") {
                VStack(alignment: .leading, spacing: 6) {
                    if store.thumbsTotal > 0 {
                        ProgressView(value: Double(store.thumbsDone), total: Double(store.thumbsTotal))
                        Text(store.thumbsRunning
                             ? "\(store.thumbsDone.formatted()) of \(store.thumbsTotal.formatted()) thumbnails…"
                             : "All \(store.thumbsTotal.formatted()) thumbnails saved.")
                            .font(.caption).monospacedDigit()
                    }
                    Text("Without this, a zipped video has to be unpacked before its thumbnail can appear.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            }

            GroupBox("2. Check the zips hold everything") {
                VStack(alignment: .leading, spacing: 8) {
                    if let status = store.storageStatus {
                        HStack { ProgressView().controlSize(.small); Text(status).font(.callout) }
                    } else if let r = store.storageReport {
                        let folderBytes = r.folders.reduce(Int64(0)) { $0 + $1.bytes }
                        let safeBytes = r.folders.filter(\.safe).reduce(Int64(0)) { $0 + $1.bytes }
                        Text("Zips: \(bytes(r.zipBytes)) · Unzipped folders: \(bytes(folderBytes))")
                            .font(.callout.weight(.medium))
                        ScrollView {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(r.folders) { f in folderRow(f) }
                            }
                        }
                        .frame(height: min(CGFloat(r.folders.count) * 46, 260))
                        if safeBytes > 0 {
                            Text("Deleting the folders marked safe frees \(bytes(safeBytes)). Empty the Trash afterwards, or the space isn't freed.")
                                .font(.callout)
                                .fixedSize(horizontal: false, vertical: true)
                            Button("Show Safe Folders in Finder") {
                                NSWorkspace.shared.activateFileViewerSelecting(r.folders.filter(\.safe).map(\.url))
                            }
                        }
                    } else {
                        Text("Reads the file list of every folder and zip, and compares a sample of files byte for byte.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Button(store.storageReport == nil ? "Check Now" : "Check Again") { store.runStorageCheck() }
                        .disabled(store.storageStatus != nil)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            }

            let purged = store.purgedStats
            if purged.count > 0 {
                GroupBox("Deleted in Photos Clone") {
                    Text("\(purged.count.formatted()) deleted item\(purged.count == 1 ? " is" : "s are") still inside the zips (\(bytes(purged.bytes))). Removing them from the zips to free that space is coming in a later version.")
                        .font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(4)
                }
            }

            GroupBox("Cache on this Mac's SSD") {
                VStack(alignment: .leading, spacing: 6) {
                    LabeledContent("Thumbnails", value: bytes(thumbBytes))
                    LabeledContent("Unpacked videos", value: "\(bytes(unpackedBytes)) of \(bytes(UnpackCache.shared.budget)) allowed")
                    Text("Kept in ~/Library/Caches/PhotosClone. Videos are unpacked only when played, and the oldest are removed automatically once the limit (10% of free space) is reached. The external drive is only ever read.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Clear Unpacked Videos") {
                        Task { await UnpackCache.shared.clear(); refreshSizes() }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            }

            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 560)
        .task {
            refreshSizes()
            store.prebuildThumbnails()
            if store.storageReport == nil { store.runStorageCheck() }
        }
        .onChange(of: store.thumbsDone) { _, n in if n % 500 == 0 { refreshSizes() } }
    }

    @ViewBuilder
    private func folderRow(_ f: FolderReport) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Image(systemName: f.safe ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(f.safe ? .green : .orange)
                Text(f.url.lastPathComponent).fontWeight(.medium)
                Spacer()
                Text(bytes(f.bytes)).foregroundStyle(.secondary).monospacedDigit()
            }
            Group {
                if f.safe {
                    Text("Safe to delete: all \(f.files.formatted()) files are in the zips (\(f.sampled) compared byte for byte).")
                } else if f.files == 0 {
                    Text("Empty.")
                } else {
                    Text("Keep: \(f.missing.count) file\(f.missing.count == 1 ? " isn't" : "s aren't") in any zip\(f.sampleMismatches.isEmpty ? "" : ", \(f.sampleMismatches.count) differ"), e.g. \((f.missing + f.sampleMismatches).prefix(3).joined(separator: ", ")).")
                }
            }
            .font(.caption).foregroundStyle(.secondary)
            .padding(.leading, 24)
        }
    }

    private func bytes(_ n: Int64) -> String { ByteCountFormatter.string(fromByteCount: n, countStyle: .file) }

    private func refreshSizes() {
        let dir = ThumbnailLoader.shared.dir
        Task.detached {
            let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey])) ?? []
            let t = files.reduce(Int64(0)) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
            let u = UnpackCache.shared.usage()
            await MainActor.run { thumbBytes = t; unpackedBytes = u }
        }
    }
}
