import PDFKit
import SwiftUI

/// Documents for the year on the left, the selected one in the middle with what was read from it
/// highlighted, and its boxes on the right to check and correct.
struct DocumentsView: View {
    @Environment(TaxStore.self) private var store

    var body: some View {
        HSplitView {
            DocumentList().frame(minWidth: 230, idealWidth: 260, maxWidth: 340)
            if let doc = store.document(store.selection) {
                DocumentCanvas(doc: doc).id(doc.id).frame(minWidth: 380, maxWidth: .infinity)
                Inspector(doc: doc).id(doc.id).frame(minWidth: 320, idealWidth: 360, maxWidth: 440)
            } else {
                EmptyState().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

private struct EmptyState: View {
    @Environment(TaxStore.self) private var store
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "tray.and.arrow.down").font(.system(size: 50, weight: .light)).foregroundStyle(TX.accent)
            Text(store.documents.isEmpty ? "Add your \(String(store.year)) tax documents" : "Pick a document").font(.title2.weight(.semibold))
            if store.documents.isEmpty {
                Text("Drop PDFs or photos here: slips (T4, T5, W-2, 1099…), receipts, last year's return or Notice of Assessment. Paper slips can be scanned with your iPhone. Everything is read on this Mac.")
                    .foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 480)
                Button("Choose Files…") { store.chooseFiles() }.buttonStyle(.borderedProminent).tint(TX.accent).controlSize(.large)
            }
        }
        .padding(30)
    }
}

// MARK: List

private struct DocumentList: View {
    @Environment(TaxStore.self) private var store

    var body: some View {
        @Bindable var store = store
        List(selection: $store.selection) {
            let docs = store.documents
            ForEach(["Slips", "Receipts", "Past returns", "Other"], id: \.self) { group in
                let items = docs.filter { kind($0) == group }
                if !items.isEmpty {
                    Section(group) {
                        ForEach(items) { d in Row(doc: d).tag(d.id).contextMenu { menu(d) } }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .overlay(alignment: .bottom) {
            let open = store.documents.filter { $0.status != .reviewed }.count
            if !store.documents.isEmpty {
                Text(open == 0 ? "All documents checked" : "\(open) to check")
                    .font(.caption).foregroundStyle(open == 0 ? .green : .secondary).padding(8)
            }
        }
    }

    private func kind(_ d: TaxDocument) -> String {
        if d.spec.isReturn { return "Past returns" }
        if d.spec.id == Specs.other.id { return "Other" }
        if ["CA.RRSP", "CA.Donation", "CA.Medical", "CA.Rent", "CA.T2202", "US.1098", "US.1098E", "US.1098T"].contains(d.specID) { return "Receipts" }
        return "Slips"
    }

    @ViewBuilder private func menu(_ d: TaxDocument) -> some View {
        Button("Read Again") { store.digitize(d.id, force: true) }
        Button("Show Original in Finder") { NSWorkspace.shared.activateFileViewerSelecting([store.fileURL(d)]) }
        Divider()
        Button("Remove", role: .destructive) { store.delete(d.id) }
    }

    struct Row: View {
        @Environment(TaxStore.self) private var store
        let doc: TaxDocument
        var body: some View {
            HStack(spacing: 8) {
                Text(doc.spec.code).font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(doc.spec.country == .canada ? Color.red.opacity(0.8) : Color.blue.opacity(0.8), in: RoundedRectangle(cornerRadius: 4))
                    .frame(width: 70, alignment: .leading)
                VStack(alignment: .leading, spacing: 1) {
                    Text(doc.payer.isEmpty ? doc.fileName : doc.payer).lineLimit(1)
                    Text(summary).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                if let b = store.busy[doc.id] { ProgressView().controlSize(.small).help(b) }
                else if doc.status == .reviewed { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                else if doc.status == .failed { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
                else { Circle().fill(.orange).frame(width: 7, height: 7).help("Needs checking") }
            }
        }
        var summary: String {
            guard let main = doc.spec.fields.first(where: { $0.kind == .money && doc.fields[$0.key]?.amount != nil }),
                  let v = doc.fields[main.key]?.amount else { return doc.fileName }
            return "\(main.label): \(Amounts.format(v, doc.spec.country))"
        }
    }
}

// MARK: Canvas

/// The document's pages as pictures, with every amount read from them outlined. While a box is
/// being corrected, clicking any amount (or line of text) puts it in that box.
struct DocumentCanvas: View {
    @Environment(TaxStore.self) private var store
    let doc: TaxDocument
    @State private var pages: [NSImage] = []
    @State private var zoom: CGFloat = 1

    var body: some View {
        let read = store.readResult(doc.id)
        VStack(spacing: 0) {
            HStack {
                Text(doc.fileName).font(.system(size: 12, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                Spacer()
                if let key = store.picking, let f = doc.spec.field(key) {
                    Label("Click the value for “\(f.label)” on the page", systemImage: "hand.point.up.left.fill")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 4).background(TX.accent, in: Capsule())
                    Button("Cancel") { store.picking = nil }.controlSize(.small)
                }
                Slider(value: $zoom, in: 0.6...2.5).frame(width: 110).controlSize(.small)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            Divider()
            GeometryReader { geo in
                ScrollView([.vertical, .horizontal]) {
                    VStack(spacing: 14) {
                        ForEach(Array(pages.enumerated()), id: \.offset) { i, img in
                            let width = max(200, (geo.size.width - 32) * zoom)
                            let height = width * img.size.height / max(1, img.size.width)
                            ZStack(alignment: .topLeading) {
                                Image(nsImage: img).resizable().interpolation(.high).frame(width: width, height: height)
                                if let read { overlays(read, page: i, size: CGSize(width: width, height: height)) }
                            }
                            .frame(width: width, height: height)
                            .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                        }
                    }
                    .padding(16)
                }
            }
            .background(Color(white: 0.5).opacity(0.15))
        }
        .task(id: doc.id) { pages = await Self.renderPages(store.fileURL(doc)) }
    }

    @ViewBuilder private func overlays(_ r: ReadResult, page: Int, size: CGSize) -> some View {
        let picking = store.picking
        let selectedKey = picking
        // Amounts read from the page.
        ForEach(Array(r.money.enumerated()).filter { $0.element.page == page }, id: \.offset) { _, m in
            let rect = frame(m.rect.rect, size)
            let used = doc.fields.values.contains { $0.page == page && $0.rect == m.rect }
            Rectangle()
                .strokeBorder(used ? TX.accent : Color.blue.opacity(picking == nil ? 0.25 : 0.8), lineWidth: used ? 2 : 1)
                .background((used ? TX.accent : Color.blue).opacity(picking == nil ? 0.08 : 0.15))
                .frame(width: rect.width + 4, height: rect.height + 4)
                .offset(x: rect.minX - 2, y: rect.minY - 2)
                .onTapGesture { if let k = picking { store.setField(doc.id, k, Amounts.plain(m.value), page: page, rect: m.rect); store.picking = nil } }
                .help(m.text)
        }
        // Lines of text, clickable when filling a text box (a payer's name).
        if let k = picking, doc.spec.field(k)?.kind != .money {
            ForEach(Array(r.lines.enumerated()).filter { $0.element.page == page }, id: \.offset) { _, l in
                let rect = frame(l.rect.rect, size)
                Rectangle().fill(Color.purple.opacity(0.08)).overlay(Rectangle().stroke(Color.purple.opacity(0.4)))
                    .frame(width: rect.width, height: rect.height).offset(x: rect.minX, y: rect.minY)
                    .onTapGesture { store.setField(doc.id, k, l.text, page: page, rect: l.rect); store.picking = nil }
            }
        }
        // The field selected in the inspector.
        if let key = selectedKey ?? store.focusField, let f = doc.fields[key], f.page == page, let fr = f.rect {
            let rect = frame(fr.rect, size)
            RoundedRectangle(cornerRadius: 3).stroke(Color.orange, lineWidth: 3)
                .frame(width: rect.width + 10, height: rect.height + 10).offset(x: rect.minX - 5, y: rect.minY - 5)
                .allowsHitTesting(false)
        }
    }

    /// 0…1 bottom-left rectangles to top-left points.
    private func frame(_ r: CGRect, _ s: CGSize) -> CGRect {
        CGRect(x: r.minX * s.width, y: (1 - r.maxY) * s.height, width: r.width * s.width, height: r.height * s.height)
    }

    static func renderPages(_ url: URL) async -> [NSImage] {
        await Task.detached(priority: .userInitiated) { () -> [NSImage] in
            if url.pathExtension.lowercased() == "pdf", let doc = PDFDocument(url: url) {
                return (0..<min(doc.pageCount, 30)).compactMap { i in
                    guard let p = doc.page(at: i), let cg = PageReader.render(p, bounds: p.bounds(for: .mediaBox), dpi: 144) else { return nil }
                    return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
                }
            }
            return NSImage(contentsOf: url).map { [$0] } ?? []
        }.value
    }
}

// MARK: Inspector

private struct Inspector: View {
    @Environment(TaxStore.self) private var store
    let doc: TaxDocument
    @State private var aiBusy = false
    @State private var aiNote: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Menu {
                        ForEach(Country.allCases) { c in
                            Section(c.name) {
                                ForEach((c == .canada ? Specs.canada : Specs.us)) { s in Button(s.title) { store.setSpec(doc.id, s.id) } }
                            }
                        }
                        Button(Specs.other.title) { store.setSpec(doc.id, Specs.other.id) }
                    } label: {
                        Text(doc.spec.title).font(.system(size: 14, weight: .semibold)).lineLimit(2)
                    }
                    .menuStyle(.borderlessButton).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                }
                Text("Read with \(doc.method.isEmpty ? "…" : doc.method) · \(doc.pageCount) page\(doc.pageCount == 1 ? "" : "s")")
                    .font(.caption).foregroundStyle(.secondary)

                if store.busy[doc.id] != nil {
                    HStack { ProgressView().controlSize(.small); Text("Reading the document…").foregroundStyle(.secondary) }
                }

                VStack(spacing: 6) {
                    ForEach(doc.spec.fields, id: \.key) { f in FieldRow(doc: doc, spec: f) }
                }

                HStack {
                    Button(doc.status == .reviewed ? "Checked ✓" : "Mark All as Checked") { store.markReviewed(doc.id, doc.status != .reviewed) }
                        .buttonStyle(.borderedProminent).tint(doc.status == .reviewed ? .green : TX.accent)
                    Button("Read Again") { store.digitize(doc.id, force: true) }
                }

                let missing = doc.spec.fields.filter { doc.fields[$0.key] == nil }
                if !missing.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Button {
                            aiBusy = true
                            let text = store.readResult(doc.id)?.fullText ?? ""
                            Task {
                                do {
                                    let got = try await AIAssist.suggest(text: text, spec: doc.spec, missing: missing)
                                    for (k, v) in got {
                                        var d = store.document(doc.id)!
                                        d.fields[k] = FieldValue(value: v, confidence: 0.5)
                                        store.update(d)
                                    }
                                    aiNote = got.isEmpty ? "Nothing more found." : "Filled \(got.count) box\(got.count == 1 ? "" : "es") — check them against the page."
                                } catch { aiNote = error.localizedDescription }
                                aiBusy = false
                            }
                        } label: {
                            Label(aiBusy ? "Asking…" : "Find Missing Boxes with Apple Intelligence", systemImage: "sparkles")
                        }
                        .disabled(!AIAssist.isAvailable || aiBusy)
                        Text(AIAssist.isAvailable ? (aiNote ?? "Runs on this Mac only when you press it.") : AIAssist.unavailableReason)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Notes for the preparer").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    TextEditor(text: Binding(get: { doc.notes }, set: { var d = doc; d.notes = $0; store.update(d) }))
                        .font(.system(size: 12)).frame(height: 70)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
                }
            }
            .padding(14)
        }
        .background(.background)
    }
}

private struct FieldRow: View {
    @Environment(TaxStore.self) private var store
    let doc: TaxDocument
    let spec: FieldSpec
    @State private var text = ""

    var body: some View {
        let v = doc.fields[spec.key]
        HStack(spacing: 8) {
            Circle().fill(v.map { TX.confidence($0.confidence, confirmed: $0.confirmed) } ?? Color.gray.opacity(0.3)).frame(width: 8, height: 8)
                .help(v.map { $0.confirmed ? "Checked" : "Read automatically, \(Int($0.confidence * 100))% sure" } ?? "Not found")
            VStack(alignment: .leading, spacing: 0) {
                Text(spec.label).font(.system(size: 11)).lineLimit(1)
                HStack(spacing: 4) {
                    if spec.key.first?.isNumber == true { Text("Box \(spec.key)").font(.system(size: 9)).foregroundStyle(.secondary) }
                    if let line = spec.lines.first, let l = ReturnLine.lines(doc.spec.country).first(where: { $0.id == line }) {
                        Text("→ \(l.code)").font(.system(size: 9)).foregroundStyle(TX.accent)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            TextField("—", text: $text)
                .textFieldStyle(.roundedBorder).multilineTextAlignment(spec.kind == .money ? .trailing : .leading)
                .frame(width: spec.kind == .money ? 110 : 150)
                .onSubmit { store.setField(doc.id, spec.key, text) }
                .onChange(of: text) { _, new in
                    if new != (doc.fields[spec.key]?.value ?? "") { store.setField(doc.id, spec.key, new) }
                }
            Button { store.picking = store.picking == spec.key ? nil : spec.key } label: {
                Image(systemName: "scope").foregroundStyle(store.picking == spec.key ? TX.accent : .secondary)
            }
            .buttonStyle(.plain).help("Pick the value on the page")
        }
        .padding(.vertical, 3).padding(.horizontal, 6)
        .background(store.focusField == spec.key ? TX.accent.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture { store.focusField = spec.key }
        .onAppear { text = v?.value ?? "" }
        .onChange(of: doc.fields[spec.key]?.value) { _, new in text = new ?? "" }
    }
}
