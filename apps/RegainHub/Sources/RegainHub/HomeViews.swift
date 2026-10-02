import RegainCore
import SwiftUI
import TaxKit

/// The hub's start page: every app with the export it has open, and the companies still to come.
struct HomeView: View {
    @Environment(Hub.self) private var hub

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Regain Your Data").font(.system(size: 38, weight: .heavy, design: .rounded))
                        .foregroundStyle(LinearGradient(colors: [Color(red: 1, green: 0.62, blue: 0.2), Color(red: 0.95, green: 0.25, blue: 0.5), Color(red: 0.45, green: 0.3, blue: 0.95)],
                                                        startPoint: .leading, endPoint: .trailing))
                    Text("The data companies send you, in a form you can actually use. Everything is read on this Mac, straight from the zips — nothing is uploaded, and nothing in your downloads is changed.")
                        .font(.system(size: 15)).foregroundStyle(.secondary).frame(maxWidth: 680, alignment: .leading)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300, maximum: 460), spacing: 16)], alignment: .leading, spacing: 16) {
                    ForEach(Source.apps + [.explorer]) { AppCard(source: $0) }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Coming next").font(.system(size: 22, weight: .bold))
                    Text("These don't have their own view yet. Request your data now; when it arrives, open it in Explorer to browse and search every file.")
                        .foregroundStyle(.secondary)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 250, maximum: 360), spacing: 12)], alignment: .leading, spacing: 12) {
                        ForEach(Upcoming.all) { UpcomingCard(item: $0) }
                    }
                }
            }
            .padding(.horizontal, 36).padding(.top, 48).padding(.bottom, 36)
            .frame(maxWidth: 1300, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(.background)
        .ignoresSafeArea(.container, edges: .top)
    }
}

private struct AppCard: View {
    @Environment(Hub.self) private var hub
    let source: Source
    @State private var hover = false

    var body: some View {
        Button { hub.current = source } label: {
            HStack(alignment: .top, spacing: 14) {
                SourceIcon(source: source, size: 64)
                VStack(alignment: .leading, spacing: 5) {
                    Text(source.appName).font(.system(size: 17, weight: .bold))
                    Text(source.blurb).font(.system(size: 12.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    if source == .taxes {
                        Label(TaxesModule.summary, systemImage: "lock.doc").font(.system(size: 11)).foregroundStyle(.secondary)
                    } else if let folder = source.savedFolder {
                        Label((folder as NSString).abbreviatingWithTildeInPath, systemImage: FileManager.default.fileExists(atPath: folder) ? "checkmark.circle.fill" : "externaldrive.badge.xmark")
                            .font(.system(size: 11)).foregroundStyle(FileManager.default.fileExists(atPath: folder) ? .green : .orange)
                            .lineLimit(1).truncationMode(.middle)
                            .help(FileManager.default.fileExists(atPath: folder) ? folder : "Not found — is the drive connected?")
                    } else {
                        Label("No export opened yet", systemImage: "circle.dashed").font(.system(size: 11)).foregroundStyle(.tertiary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.quaternary.opacity(hover ? 0.9 : 0.5)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(.quaternary))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

private struct UpcomingCard: View {
    @Environment(Hub.self) private var hub
    let item: Upcoming

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(item.name, systemImage: item.symbol).font(.system(size: 15, weight: .semibold))
            Text(item.how).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            HStack {
                Link("Request your data ↗", destination: URL(string: item.request)!).font(.system(size: 12))
                Spacer()
                Button("Open in Explorer…") { hub.chooseExplorerFolder() }.controlSize(.small)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.quaternary, style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
    }
}

// MARK: Explorer

/// Any export at all: pick a folder or zip and browse every file in it.
struct ExplorerView: View {
    @Environment(Hub.self) private var hub

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "doc.text.magnifyingglass").font(.system(size: 18)).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Explorer").font(.system(size: 15, weight: .bold))
                    Text(hub.explorerRoot.map { ($0.path as NSString).abbreviatingWithTildeInPath } ?? "Any export, file by file")
                        .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                if !hub.recents.isEmpty {
                    Menu("Recent") {
                        ForEach(hub.recents, id: \.self) { p in Button((p as NSString).abbreviatingWithTildeInPath) { hub.explore(URL(fileURLWithPath: p)) } }
                    }
                    .fixedSize()
                }
                Button("Open…") { hub.chooseExplorerFolder() }
            }
            .padding(.horizontal, 16).padding(.top, 30).padding(.bottom, 10)
            Divider()
            if hub.explorerLoading {
                ProgressView("Reading the file list…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if hub.explorerRoot == nil || hub.explorerFiles.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "archivebox").font(.system(size: 54, weight: .light)).foregroundStyle(.secondary)
                    Text(hub.explorerRoot == nil ? "Open any data export" : "No files found there").font(.title2.weight(.semibold))
                    Text("A Google Takeout, a Facebook or TikTok download, anything: choose its folder or zip. CSV files open as spreadsheets, JSON as a tree, HTML pages offline, and “Search Inside” looks through every file at once.")
                        .multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 520)
                    Button("Choose Folder or Zip…") { hub.chooseExplorerFolder() }.buttonStyle(.borderedProminent).controlSize(.large)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                DataBrowser(files: hub.explorerFiles, initial: debugPick).id(hub.explorerRoot)
            }
        }
        .background(.background)
        .ignoresSafeArea(.container, edges: .top)
    }
}

extension ExplorerView {
    /// Development: `REGAIN_PICK=<part of a file name>` opens that file first.
    var debugPick: DataFile.ID? {
        #if DEBUG
        if let p = ProcessInfo.processInfo.environment["REGAIN_PICK"] { return hub.explorerFiles.first { $0.name.contains(p) }?.id }
        #endif
        return nil
    }
}
