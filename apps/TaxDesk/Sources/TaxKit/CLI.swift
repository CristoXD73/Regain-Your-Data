import Foundation

/// `TaxDesk --read <file>` digitizes one document and prints what it found. Meant for sample
/// documents while developing: it prints the values it reads.
public enum TaxCLI {
    public static func run() throws {
        if let i = CommandLine.arguments.firstIndex(of: "--demo"), i + 1 < CommandLine.arguments.count {
            MainActor.assumeIsolated { demo(URL(fileURLWithPath: CommandLine.arguments[i + 1])) }
            exit(0)
        }
        guard let i = CommandLine.arguments.firstIndex(of: "--read"), i + 1 < CommandLine.arguments.count else { return }
        let url = URL(fileURLWithPath: CommandLine.arguments[i + 1])
        let t0 = Date()
        let r = PageReader.read(url)
        let (spec, score) = Extractor.classify(r, country: nil)
        let fields = Extractor.extract(r, spec: spec)
        print("method: \(r.method); pages \(r.pageCount); lines \(r.lines.count); amounts \(r.money.count); form fields \(r.formFields.count)")
        print("looks like: \(spec.title) (score \(String(format: "%.1f", score)))")
        for f in spec.fields {
            guard let v = fields[f.key] else { print("  \(f.key.padding(toLength: 6, withPad: " ", startingAt: 0)) \(f.label): —"); continue }
            print("  \(f.key.padding(toLength: 6, withPad: " ", startingAt: 0)) \(f.label): \(v.value)  [\(Int(v.confidence * 100))%]")
        }
        if CommandLine.arguments.contains("--dump") {
            for l in r.lines { print("  line “\(l.text)” at", l.rect.rect.debugDescription) }
            for m in r.money { print("  amount \(m.text) at", m.rect.rect.debugDescription) }
        }
        if let j = CommandLine.arguments.firstIndex(of: "--explain"), j + 1 < CommandLine.arguments.count, let f = spec.field(CommandLine.arguments[j + 1]) {
            for (kind, list) in [("label", Extractor.anchors(for: f, in: r, labelsOnly: true, spec: spec)), ("number", Extractor.anchors(for: f, in: r, labelsOnly: false))] {
                for a in list {
                    print("  \(kind) anchor “\(a.text)” at", a.rect.rect.debugDescription)
                    for m in r.money where m.page == a.page {
                        if let c = Extractor.cost(anchor: a.rect.rect, money: m.rect.rect) { print(String(format: "     %.3f → %@ at %@", c, m.text, m.rect.rect.debugDescription)) }
                    }
                }
            }
        }
        print(String(format: "read in %.2fs", Date().timeIntervalSince(t0)))
        exit(0)
    }
}

extension TaxCLI {
    /// `TAXDESK_HOME=<empty folder> TaxDesk --demo <folder of sample documents>`: imports them,
    /// reads them, prints the draft, fills the CRA forms (put the blank ones in
    /// <home>/CRA forms/<year> ON first) and builds a preparer package. Refuses to run on the
    /// real library.
    @MainActor static func demo(_ folder: URL) {
        guard ProcessInfo.processInfo.environment["TAXDESK_HOME"] != nil else { print("Set TAXDESK_HOME to an empty folder first."); return }
        let store = TaxStore.shared
        let files = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []).filter { !$0.lastPathComponent.hasPrefix(".") }.sorted { $0.path < $1.path }
        for f in files {
            let id = UUID()
            let stored = id.uuidString + "." + f.pathExtension.lowercased()
            try? FileManager.default.copyItem(at: f, to: TaxPaths.vault.appendingPathComponent(stored))
            let r = PageReader.read(TaxPaths.vault.appendingPathComponent(stored))
            if let d = try? JSONEncoder().encode(r) { try? d.write(to: TaxPaths.cache.appendingPathComponent(id.uuidString + ".json")) }
            let (spec, _) = Extractor.classify(r, country: .canada)
            var doc = TaxDocument(id: id, fileName: f.lastPathComponent, storedName: stored, imported: Date(), year: nil, specID: spec.id)
            doc.fields = Extractor.extract(r, spec: spec)
            doc.year = doc.fields["year"].flatMap { Int($0.value) } ?? 2025
            doc.pageCount = r.pageCount; doc.method = r.method; doc.status = .needsReview
            store.library.documents.append(doc)
            print("\(f.lastPathComponent): \(spec.code) \(doc.payer) year \(doc.year ?? 0), \(doc.fields.count) fields, \(r.method)")
        }
        store.save()
        store.setYear(2025)
        print("\nDraft:")
        for l in store.draft() { print("  \(l.line.code.padding(toLength: 12, withPad: " ", startingAt: 0)) \(l.line.title.padding(toLength: 42, withPad: " ", startingAt: 0)) \(Amounts.plain(l.total))  (\(l.parts.count) source\(l.parts.count == 1 ? "" : "s"))") }
        print("As filed:", store.asFiled())
        if let forms = CanadaEngine.localForms(province: "ON", year: 2025) {
            let out = CanadaEngine.folder(province: "ON", year: 2025).appendingPathComponent("Inputs")
            do {
                let r = try CanadaEngine.prepare(store: store, forms: forms, into: out)
                for f in [r.t1] + r.t4s {
                    let back = PageReader.read(f)
                    let filled = back.formFields.filter { !$0.value.isEmpty }
                    print("\(f.lastPathComponent): \(filled.count) filled fields:", filled.keys.sorted().map { "\($0.split(separator: ".").last!)=\(filled[$0]!)" }.prefix(14).joined(separator: " "))
                }
            } catch { print("fill failed:", error) }
        } else { print("(no blank CRA forms in \(TaxPaths.forms.path); skipped filling)") }
        let packet = TaxPaths.support.appendingPathComponent("packet.pdf")
        do { print("packet pages:", try PacketBuilder.build(store: store, options: .init(), to: packet), packet.path) } catch { print("packet failed:", error) }
    }
}
