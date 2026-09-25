import AVKit
import PDFKit
import SwiftUI
import WebKit

/// Browses every file of an export: a sidebar of files grouped by zip and folder, and a preview
/// that shows CSVs as spreadsheets, JSON as a tree, HTML offline, and pictures, video, audio and
/// PDFs as themselves. "Search inside" looks through the text of every file at once.
public struct DataBrowser: View {
    let files: [DataFile]
    @State private var selection: DataFile.ID?
    @State private var nameFilter = ""
    @State private var searchText = ""
    @State private var searching = false
    @State private var hits: [SearchHit] = []
    @State private var searchTask: Task<Void, Never>?
    @State private var searchStatus = ""

    public init(files: [DataFile], initial: DataFile.ID? = nil) {
        self.files = files.sorted { ($0.group, $0.folder, $0.name) < ($1.group, $1.folder, $1.name) }
        _selection = State(initialValue: initial)
    }

    public var body: some View {
        HSplitView {
            sidebar.frame(minWidth: 240, idealWidth: 290, maxWidth: 420)
            Group {
                if let f = files.first(where: { $0.id == selection }) {
                    FilePreview(file: f).id(f.id)
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "doc.text.magnifyingglass").font(.system(size: 44, weight: .light)).foregroundStyle(.secondary)
                        Text("\(files.count) files").font(.title3.weight(.semibold))
                        Text("Pick one on the left, or search inside all of them.").foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            Picker("", selection: $searching) {
                Text("Files").tag(false)
                Text("Search Inside").tag(true)
            }
            .pickerStyle(.segmented).labelsHidden().padding(.horizontal, 10).padding(.top, 10)
            if searching {
                TextField("Words to find in every file", text: $searchText)
                    .textFieldStyle(.roundedBorder).padding(10)
                    .onSubmit(runSearch)
                if !searchStatus.isEmpty { Text(searchStatus).font(.caption).foregroundStyle(.secondary).padding(.bottom, 4) }
                List(selection: $selection) {
                    ForEach(hits) { h in
                        VStack(alignment: .leading, spacing: 3) {
                            Label(h.file.name, systemImage: h.file.symbol).font(.system(size: 12, weight: .semibold))
                            Text(h.snippet).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(3)
                        }
                        .tag(h.file.id)
                    }
                }
            } else {
                TextField("Filter file names", text: $nameFilter).textFieldStyle(.roundedBorder).padding(10)
                List(selection: $selection) {
                    ForEach(groups, id: \.0) { group, items in
                        Section(group) {
                            ForEach(items) { f in
                                HStack(spacing: 6) {
                                    Image(systemName: f.symbol).foregroundStyle(.secondary).frame(width: 16)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(f.name).lineLimit(1).truncationMode(.middle)
                                        if !f.folder.isEmpty {
                                            Text(f.folder).font(.system(size: 10)).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.head)
                                        }
                                    }
                                    Spacer(minLength: 4)
                                    Text(ByteCountFormatter.string(fromByteCount: Int64(f.size), countStyle: .file))
                                        .font(.system(size: 10)).foregroundStyle(.tertiary).monospacedDigit()
                                }
                                .tag(f.id)
                                .help(f.summary ?? f.origin)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    private var groups: [(String, [DataFile])] {
        let f = nameFilter.lowercased()
        let shown = f.isEmpty ? files : files.filter { $0.name.lowercased().contains(f) || $0.folder.lowercased().contains(f) }
        let byGroup = Dictionary(grouping: shown, by: \.group)
        return byGroup.keys.sorted().map { ($0, byGroup[$0]!) }
    }

    private func runSearch() {
        searchTask?.cancel()
        let q = searchText.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { hits = []; searchStatus = ""; return }
        hits = []
        searchStatus = "Searching…"
        let candidates = files.filter { [.table, .json, .html, .text].contains($0.kind) && $0.size < 80_000_000 }
        searchTask = Task {
            let found = await Task.detached(priority: .userInitiated) { Self.search(q, in: candidates) }.value
            guard !Task.isCancelled else { return }
            hits = found
            searchStatus = found.isEmpty ? "Nothing found" : "\(found.count) match\(found.count == 1 ? "" : "es")\(found.count >= 1000 ? " (first 1000)" : "")"
        }
    }

    struct SearchHit: Identifiable {
        let id = UUID()
        let file: DataFile
        let snippet: String
    }

    nonisolated static func search(_ q: String, in files: [DataFile]) -> [SearchHit] {
        var out: [SearchHit] = []
        for f in files {
            if Task.isCancelled || out.count >= 1000 { break }
            guard let d = try? f.read() else { continue }
            let s = String(decoding: d, as: UTF8.self)
            var range = s.startIndex..<s.endIndex
            var n = 0
            while n < 20, let r = s.range(of: q, options: [.caseInsensitive, .diacriticInsensitive], range: range) {
                let lo = s.index(r.lowerBound, offsetBy: -60, limitedBy: s.startIndex) ?? s.startIndex
                let hi = s.index(r.upperBound, offsetBy: 80, limitedBy: s.endIndex) ?? s.endIndex
                let snip = s[lo..<hi].replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
                out.append(SearchHit(file: f, snippet: (lo > s.startIndex ? "…" : "") + snip + (hi < s.endIndex ? "…" : "")))
                n += 1
                range = r.upperBound..<s.endIndex
            }
        }
        return out
    }
}

// MARK: Preview

public struct FilePreview: View {
    let file: DataFile
    @State private var content: Content = .loading
    @State private var rowFilter = ""

    enum Content {
        case loading, table(CSVTable), json(JSONNode), text(String), html(String, URL?), image(NSImage), media(URL), pdf(PDFDocument), none(String)
    }

    public init(file: DataFile) { self.file = file }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            Group {
                switch content {
                case .loading: ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                case .table(let t):
                    VStack(spacing: 0) {
                        HStack {
                            Image(systemName: "line.3.horizontal.decrease.circle").foregroundStyle(.secondary)
                            TextField("Filter rows", text: $rowFilter).textFieldStyle(.plain)
                            Text("\(t.rows.count) rows · \(t.header.count) columns").font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        Divider()
                        DataTable(table: t, filter: rowFilter)
                    }
                case .json(let root):
                    List { OutlineGroup(root.children ?? [], children: \.children) { JSONRow(node: $0) } }
                        .listStyle(.inset)
                case .text(let s):
                    ScrollView { Text(s).font(.system(size: 12, design: .monospaced)).textSelection(.enabled).padding(14).frame(maxWidth: .infinity, alignment: .leading) }
                case .html(let s, let base): OfflineWebView(html: s, baseURL: base)
                case .image(let img): ScrollView([.horizontal, .vertical]) { Image(nsImage: img).resizable().scaledToFit().frame(maxWidth: img.size.width) }.frame(maxWidth: .infinity, maxHeight: .infinity)
                case .media(let u): MediaPlayer(url: u)
                case .pdf(let d): PDFViewer(document: d)
                case .none(let why):
                    VStack(spacing: 12) {
                        Image(systemName: file.symbol).font(.system(size: 44, weight: .light)).foregroundStyle(.secondary)
                        Text(why).foregroundStyle(.secondary)
                        Button("Open With Default App") { openExternally() }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task { content = await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: file.symbol).foregroundStyle(.secondary)
                Text(file.name).font(.system(size: 16, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                Spacer()
                Menu {
                    Button("Open With Default App") { openExternally() }
                    Button("Save a Copy…") { saveCopy() }
                    if case .file(let u) = file.location { Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([u]) } }
                } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            }
            Text("\(file.origin) · \(ByteCountFormatter.string(fromByteCount: Int64(file.size), countStyle: .file))")
                .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            if let s = file.summary, !s.isEmpty {
                Label(s, systemImage: "info.circle").font(.callout).foregroundStyle(.secondary)
                    .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(14)
    }

    private func load() async -> Content {
        let f = file
        return await Task.detached(priority: .userInitiated) { () -> Content in
            do {
                switch f.kind {
                case .table:
                    return .table(f.ext == "tsv" ? CSVTable(tsv: try f.read()) : try f.table())
                case .json:
                    let d = try f.read()
                    guard let obj = try? JSONSerialization.jsonObject(with: d, options: [.fragmentsAllowed]) else {
                        return .text(String(decoding: d.prefix(4_000_000), as: UTF8.self))
                    }
                    return .json(JSONNode(key: f.name, value: obj))
                case .text:
                    return .text(String(decoding: try f.read(limit: 4_000_000), as: UTF8.self))
                case .html:
                    var base: URL? = nil
                    if case .file(let u) = f.location { base = u.deletingLastPathComponent() }
                    return .html(String(decoding: try f.read(), as: UTF8.self), base)
                case .image:
                    guard let img = NSImage(data: try f.read()) else { return .none("This picture can't be shown.") }
                    return .image(img)
                case .video, .audio: return .media(try f.fileURL())
                case .pdf:
                    guard let d = PDFDocument(data: try f.read()) else { return .none("This PDF can't be shown.") }
                    return .pdf(d)
                case .other: return .none("No preview for .\(f.ext.isEmpty ? "?" : f.ext) files.")
                }
            } catch {
                return .none("Couldn't read this file: \(error.localizedDescription)")
            }
        }.value
    }

    private func openExternally() {
        if let u = try? file.fileURL() { NSWorkspace.shared.open(u) }
    }

    private func saveCopy() {
        let p = NSSavePanel()
        p.nameFieldStringValue = file.name
        if p.runModal() == .OK, let dest = p.url, let d = try? file.read() { try? d.write(to: dest) }
    }
}

extension CSVTable {
    init(tsv data: Data) {
        let lines = String(decoding: data, as: UTF8.self).components(separatedBy: .newlines).filter { !$0.isEmpty }
        let split = lines.map { $0.components(separatedBy: "\t") }
        self.init(header: split.first ?? [], rows: Array(split.dropFirst()))
    }
}

// MARK: JSON

final class JSONNode: Identifiable, @unchecked Sendable {
    let id = UUID()
    let key: String
    let value: Any

    init(key: String, value: Any) {
        self.key = key
        self.value = value
    }

    lazy var children: [JSONNode]? = {
        if let d = value as? [String: Any] { return d.keys.sorted().map { JSONNode(key: $0, value: d[$0]!) } }
        if let a = value as? [Any] { return a.enumerated().map { JSONNode(key: "[\($0.offset)]", value: $0.element) } }
        return nil
    }()

    var display: String {
        switch value {
        case let d as [String: Any]: return "{ \(d.count) }"
        case let a as [Any]: return "[ \(a.count) ]"
        case let s as String: return s
        case let n as NSNumber: return CFGetTypeID(n) == CFBooleanGetTypeID() ? (n.boolValue ? "true" : "false") : n.stringValue
        case is NSNull: return "null"
        default: return "\(value)"
        }
    }
}

private struct JSONRow: View {
    let node: JSONNode
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(node.key).font(.system(size: 12, weight: .semibold, design: .monospaced))
            Text(node.display).font(.system(size: 12, design: .monospaced))
                .foregroundStyle(node.children == nil ? .primary : .secondary)
                .textSelection(.enabled).lineLimit(6)
        }
    }
}

// MARK: Web, media, PDF

/// Shows an export's HTML pages without letting them reach the internet: every http(s) load is
/// blocked, so remote images and trackers in the page stay unloaded.
struct OfflineWebView: NSViewRepresentable {
    let html: String
    let baseURL: URL?

    func makeNSView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .nonPersistent()
        let wv = WKWebView(frame: .zero, configuration: cfg)
        let rules = #"[{"trigger":{"url-filter":"^(https?|wss?|ftp)://"},"action":{"type":"block"}}]"#
        WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "offline", encodedContentRuleList: rules) { list, _ in
            if let list { wv.configuration.userContentController.add(list) }
            wv.loadHTMLString(html, baseURL: baseURL)
        }
        return wv
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

struct MediaPlayer: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> AVPlayerView {
        let v = AVPlayerView()
        v.controlsStyle = .inline
        v.player = AVPlayer(url: url)
        return v
    }
    func updateNSView(_ v: AVPlayerView, context: Context) {}
    static func dismantleNSView(_ v: AVPlayerView, coordinator: ()) { v.player?.pause() }
}

struct PDFViewer: NSViewRepresentable {
    let document: PDFDocument
    func makeNSView(context: Context) -> PDFView {
        let v = PDFView()
        v.autoScales = true
        v.document = document
        return v
    }
    func updateNSView(_ v: PDFView, context: Context) {}
}
