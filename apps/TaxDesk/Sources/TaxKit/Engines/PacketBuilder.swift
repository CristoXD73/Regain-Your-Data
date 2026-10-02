import AppKit
import PDFKit
import SwiftUI

/// One PDF to hand to a tax preparer: a cover, the draft's lines with where each amount came
/// from, an index of documents, questions and anything to refile, then the completed forms and
/// every original document.
@MainActor
enum PacketBuilder {
    static let pageSize = CGSize(width: 612, height: 792)   // US Letter, which CRA forms use too

    struct Options {
        var includeOriginals = true
        var includeForms = true
    }

    static func build(store: TaxStore, options: Options, to url: URL) throws -> Int {
        let info = store.info
        let country = info.country
        let docs = store.documents
        let draft = store.draft()
        let filed = store.asFiled()

        var pages: [AnyView] = []
        pages.append(AnyView(Cover(year: store.year, info: info, docs: docs)))

        // The draft's lines, a dozen or so per page.
        var rows: [Row] = []
        for section in ReturnLine.Section.allCases where section != .totals {
            let lines = draft.filter { $0.line.section == section }
            guard !lines.isEmpty else { continue }
            rows.append(.heading(section.rawValue))
            for l in lines {
                rows.append(.line(l.line.code, l.line.title, Amounts.format(l.total, country), l.line.note))
                for p in l.parts { rows.append(.source("\(p.source) — \(p.detail)", Amounts.format(p.amount, country), p.reviewed)) }
            }
        }
        pages += paginate(rows, title: "Draft return — \(store.year)")

        // Documents.
        var docRows: [Row] = []
        for d in docs {
            let amounts = d.spec.fields.filter { $0.kind == .money }.compactMap { f -> String? in
                guard let v = d.fields[f.key]?.amount else { return nil }
                return "\(f.key == "amount" ? "" : "box \(f.key) ")\(Amounts.format(v, country))"
            }.joined(separator: " · ")
            docRows.append(.document(d.spec.code, d.payer.isEmpty ? d.fileName : d.payer, amounts, d.status == .reviewed, d.notes))
        }
        if !docRows.isEmpty { pages += paginate(docRows, title: "Documents (\(docs.count))") }

        // Questions, missing slips, refiling.
        var notes: [Row] = []
        if !info.questions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { notes.append(.heading("Questions for you")); notes.append(.text(info.questions)) }
        let missing = store.missingFromLastYear()
        if !missing.isEmpty {
            notes.append(.heading("Had last year, not found this year"))
            for d in missing { notes.append(.text("• \(d.spec.code) from \(d.payer.isEmpty ? d.fileName : d.payer)")) }
        }
        if info.amending {
            notes.append(.heading("Refiling: changes to the return as filed"))
            if !info.amendReason.isEmpty { notes.append(.text(info.amendReason)) }
            let totals = Dictionary(uniqueKeysWithValues: draft.map { ($0.line.id, $0.total) })
            for line in ReturnLine.lines(country) where filed[line.id] != nil || totals[line.id] != nil {
                let before = filed[line.id], after = totals[line.id]
                guard before != after else { continue }
                notes.append(.change(line.code, line.title, before.map { Amounts.format($0, country) } ?? "—", after.map { Amounts.format($0, country) } ?? "—"))
            }
        }
        if !notes.isEmpty { pages += paginate(notes, title: "Notes for the preparer") }

        // Render the pages we drew.
        var box = CGRect(origin: .zero, size: pageSize)
        guard let ctx = CGContext(url as CFURL, mediaBox: &box, nil) else { throw CocoaError(.fileWriteUnknown) }
        for (i, p) in pages.enumerated() {
            let view = p.overlay(alignment: .bottom) { Footer(page: i + 1, year: store.year) }
                .frame(width: pageSize.width, height: pageSize.height)
                .background(Color.white)
                .environment(\.colorScheme, .light)
            let r = ImageRenderer(content: view)
            r.render { _, draw in
                ctx.beginPDFPage(nil)
                draw(ctx)
                ctx.endPDFPage()
            }
        }
        ctx.closePDF()

        // Append completed forms and the originals.
        guard let out = PDFDocument(url: url) else { throw CocoaError(.fileWriteUnknown) }
        if options.includeForms {
            let completed = CanadaEngine.folder(province: info.province, year: store.year).appendingPathComponent("Completed")
            let files = ((try? FileManager.default.contentsOfDirectory(at: completed, includingPropertiesForKeys: nil)) ?? []).filter { $0.pathExtension == "pdf" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
            for f in files { append(PDFDocument(url: f), to: out) }
        }
        if options.includeOriginals {
            for d in docs {
                let u = store.fileURL(d)
                if u.pathExtension.lowercased() == "pdf" { append(PDFDocument(url: u), to: out) }
                else if let img = NSImage(contentsOf: u), let page = PDFPage(image: img) { out.insert(page, at: out.pageCount) }
            }
        }
        out.write(to: url)
        return out.pageCount
    }

    private static func append(_ doc: PDFDocument?, to out: PDFDocument) {
        guard let doc else { return }
        for i in 0..<doc.pageCount { if let p = doc.page(at: i)?.copy() as? PDFPage { out.insert(p, at: out.pageCount) } }
    }

    // MARK: Pages

    enum Row: Hashable {
        case heading(String)
        case line(String, String, String, String?)
        case source(String, String, Bool)
        case document(String, String, String, Bool, String)
        case text(String)
        case change(String, String, String, String)

        /// Rough height, for splitting into pages.
        var height: CGFloat {
            switch self {
            case .heading: return 34
            case .line(_, _, _, let note): return note == nil ? 22 : 36
            case .source: return 16
            case .document(_, _, _, _, let notes): return notes.isEmpty ? 40 : 56
            case .text(let s): return CGFloat(max(1, s.count / 95 + s.filter { $0 == "\n" }.count + 1)) * 15 + 6
            case .change: return 20
            }
        }
    }

    static func paginate(_ rows: [Row], title: String) -> [AnyView] {
        var pages: [[Row]] = [[]]
        var used: CGFloat = 0
        for r in rows {
            if used + r.height > 640, !pages[pages.count - 1].isEmpty { pages.append([]); used = 0 }
            pages[pages.count - 1].append(r)
            used += r.height
        }
        return pages.enumerated().map { i, rows in AnyView(RowsPage(title: i == 0 ? title : title + " (continued)", rows: rows)) }
    }

    struct Cover: View {
        let year: Int
        let info: TaxYearInfo
        let docs: [TaxDocument]
        var body: some View {
            VStack(alignment: .leading, spacing: 18) {
                Text("DRAFT — FOR REVIEW BY A TAX PROFESSIONAL").font(.system(size: 10, weight: .bold)).foregroundStyle(.red).kerning(1)
                Text("\(String(year)) tax return").font(.system(size: 34, weight: .bold))
                Text(info.country == .canada ? "Canada · \(info.province)" : "United States\(info.usState.isEmpty ? "" : " · \(info.usState)")")
                    .font(.system(size: 16)).foregroundStyle(.secondary)
                if info.amending { Text("Refiling a return already filed").font(.system(size: 14, weight: .semibold)).foregroundStyle(.orange) }
                Divider()
                Group {
                    Text("Prepared \(Date().formatted(date: .long, time: .omitted)) with Tax Desk (Regain Your Data).")
                    Text("\(docs.count) documents, \(docs.filter { $0.status == .reviewed }.count) checked by hand against the originals.")
                    Text("Amounts were read from the documents that follow. Values marked “not checked” were read automatically and should be verified against the original.")
                    Text("This is not a filed return and has not been checked by \(info.country == .canada ? "the CRA" : "the IRS"). Please review, complete and file it.")
                }
                .font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                Spacer()
            }
            .padding(54)
            .frame(width: pageSize.width, height: pageSize.height, alignment: .topLeading)
        }
    }

    struct RowsPage: View {
        let title: String
        let rows: [Row]
        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 18, weight: .bold)).padding(.bottom, 8)
                ForEach(Array(rows.enumerated()), id: \.offset) { _, r in row(r) }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 48).padding(.top, 44).padding(.bottom, 60)
            .frame(width: pageSize.width, height: pageSize.height, alignment: .topLeading)
            .foregroundStyle(.black)
        }

        @ViewBuilder func row(_ r: Row) -> some View {
            switch r {
            case .heading(let s):
                Text(s).font(.system(size: 13, weight: .bold)).padding(.top, 12)
                Rectangle().fill(Color.black.opacity(0.2)).frame(height: 0.5)
            case .line(let code, let title, let amount, let note):
                VStack(alignment: .leading, spacing: 1) {
                    HStack {
                        Text(code).font(.system(size: 10, design: .monospaced)).frame(width: 96, alignment: .leading)
                        Text(title).font(.system(size: 11, weight: .semibold))
                        Spacer()
                        Text(amount).font(.system(size: 11, weight: .semibold)).monospacedDigit()
                    }
                    if let note { Text(note).font(.system(size: 9)).foregroundStyle(.gray).padding(.leading, 96) }
                }
            case .source(let s, let amount, let reviewed):
                HStack {
                    Text(s).font(.system(size: 9)).foregroundStyle(.gray).lineLimit(1)
                    if !reviewed { Text("not checked").font(.system(size: 8, weight: .bold)).foregroundStyle(.orange) }
                    Spacer()
                    Text(amount).font(.system(size: 9)).foregroundStyle(.gray).monospacedDigit()
                }
                .padding(.leading, 96)
            case .document(let code, let name, let amounts, let reviewed, let notes):
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(code).font(.system(size: 11, weight: .bold)).frame(width: 70, alignment: .leading)
                        Text(name).font(.system(size: 11))
                        Spacer()
                        Text(reviewed ? "checked" : "not checked").font(.system(size: 8, weight: .bold)).foregroundStyle(reviewed ? .green : .orange)
                    }
                    Text(amounts).font(.system(size: 9)).foregroundStyle(.gray).padding(.leading, 70).lineLimit(2)
                    if !notes.isEmpty { Text("Note: " + notes).font(.system(size: 9)).italic().padding(.leading, 70).lineLimit(2) }
                }
                .padding(.vertical, 3)
            case .text(let s):
                Text(s).font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
            case .change(let code, let title, let before, let after):
                HStack {
                    Text(code).font(.system(size: 10, design: .monospaced)).frame(width: 96, alignment: .leading)
                    Text(title).font(.system(size: 11))
                    Spacer()
                    Text(before).font(.system(size: 11)).strikethrough().foregroundStyle(.gray).monospacedDigit()
                    Image(systemName: "arrow.right").font(.system(size: 9))
                    Text(after).font(.system(size: 11, weight: .semibold)).monospacedDigit()
                }
            }
        }
    }

    struct Footer: View {
        let page: Int
        let year: Int
        var body: some View {
            HStack {
                Text("Draft \(String(year)) return — not filed")
                Spacer()
                Text("Page \(page)")
            }
            .font(.system(size: 8)).foregroundStyle(.gray)
            .padding(.horizontal, 48).padding(.bottom, 24)
        }
    }
}
