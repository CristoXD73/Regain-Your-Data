import Foundation
import PDFKit

/// Works with blamario/canadian-income-tax (GPL-3.0), an open-source program that completes the
/// CRA's own fillable PDF forms: it takes a T1 with your amounts and your T4 slips, and fills in
/// every calculated line of the T1, the provincial 428 and 479, and the federal schedules.
///
/// This app prepares its inputs: it downloads the blank forms from canada.ca, fills a T4 form
/// for each T4 you imported and writes the other slips' amounts onto the T1, then runs
/// `complete-canadian-taxes` if it is installed. Nothing is filed; the completed forms are a draft
/// for a tax preparer.
enum CanadaEngine {
    /// CRA form numbers of the T1 package for the provinces the engine completes a 428/479 for.
    static let t1Package: [String: String] = ["ON": "5006", "BC": "5010", "AB": "5009", "MB": "5007"]
    static let with479: Set<String> = ["ON", "BC"]

    struct Forms {
        var t1: URL
        var p428: URL?
        var p479: URL?
        var t4: URL
    }

    static func formURLs(province: String, year: Int) -> [(name: String, url: URL)]? {
        guard let pkg = t1Package[province] else { return nil }
        let yy = String(format: "%02d", year % 100)
        let base = "https://www.canada.ca/content/dam/cra-arc/formspubs/pbg/"
        var list = [("T1", "\(pkg)-r/\(pkg)-r-fill-\(yy)e.pdf"), ("428", "\(pkg)-c/\(pkg)-c-fill-\(yy)e.pdf"), ("T4", "t4/t4-fill-\(yy)e.pdf")]
        if with479.contains(province) { list.append(("479", "\(pkg)-tc/\(pkg)-tc-fill-\(yy)e.pdf")) }
        return list.map { ($0.0, URL(string: base + $0.1)!) }
    }

    static func folder(province: String, year: Int) -> URL {
        let u = TaxPaths.forms.appendingPathComponent("\(year) \(province)")
        TaxPaths.make(u)
        return u
    }

    static func localForms(province: String, year: Int) -> Forms? {
        guard let list = formURLs(province: province, year: year) else { return nil }
        let dir = folder(province: province, year: year)
        func local(_ n: String) -> URL? {
            guard let u = list.first(where: { $0.name == n })?.url else { return nil }
            let f = dir.appendingPathComponent(u.lastPathComponent)
            return FileManager.default.fileExists(atPath: f.path) ? f : nil
        }
        guard let t1 = local("T1"), let t4 = local("T4") else { return nil }
        return Forms(t1: t1, p428: local("428"), p479: local("479"), t4: t4)
    }

    /// Downloads the blank fillable forms from canada.ca (only when asked).
    static func download(province: String, year: Int) async throws -> Forms {
        guard let list = formURLs(province: province, year: year) else { throw EngineError.province(province) }
        let dir = folder(province: province, year: year)
        for (_, u) in list {
            let dest = dir.appendingPathComponent(u.lastPathComponent)
            if FileManager.default.fileExists(atPath: dest.path) { continue }
            let (tmp, resp) = try await URLSession.shared.download(from: u)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw EngineError.download(u.lastPathComponent, (resp as? HTTPURLResponse)?.statusCode ?? 0) }
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: tmp, to: dest)
        }
        guard let f = localForms(province: province, year: year) else { throw EngineError.download("forms", 0) }
        return f
    }

    enum EngineError: LocalizedError {
        case province(String), download(String, Int), noT4Form, engine(String)
        var errorDescription: String? {
            switch self {
            case .province(let p): return "The engine completes provincial forms for ON, BC, AB and MB; \(p) needs the forms filled by hand."
            case .download(let n, let c): return "Couldn't download \(n) from canada.ca (\(c)). The forms for this year may not be published yet."
            case .noT4Form: return "The blank T4 form is missing."
            case .engine(let s): return s
            }
        }
    }

    // MARK: Filling

    /// Fills a copy of the T4 form for each pair of T4 slips, and a copy of the T1 with every
    /// other amount the draft has a T1 field for. Returns the files to give the engine.
    @MainActor
    static func prepare(store: TaxStore, forms: Forms, into out: URL) throws -> (t1: URL, t4s: [URL]) {
        TaxPaths.make(out)
        let t4Docs = store.documents.filter { $0.specID == "CA.T4" }
        var t4Files: [URL] = []
        for (n, pair) in stride(from: 0, to: t4Docs.count, by: 2).map({ Array(t4Docs[$0..<min($0 + 2, t4Docs.count)]) }).enumerated() {
            guard let doc = PDFDocument(url: forms.t4) else { throw EngineError.noT4Form }
            var values: [String: String] = [:]
            for (slip, t4) in pair.enumerated() {
                let prefix = "form1.Page1.Slip\(slip + 1)."
                for f in t4.spec.fields {
                    guard let name = f.formField, let v = t4.fields[f.key]?.value, !v.isEmpty else { continue }
                    let value = f.kind == .money ? (Amounts.parse(v).map(Amounts.plain) ?? v) : v
                    values[prefix + name + ".Slip1" + name] = value
                }
                if let y = t4.year { values[prefix + "Year.Slip1Year"] = String(y) }
            }
            fill(doc, values)
            let dest = out.appendingPathComponent("T4 slips \(n + 1).pdf")
            try write(doc, to: dest)
            t4Files.append(dest)
        }

        guard let t1 = PDFDocument(url: forms.t1) else { throw EngineError.noT4Form }
        var values: [String: String] = [:]
        // T4 amounts come in through the T4 forms; everything else goes straight on the T1.
        for (line, _, parts) in store.draft() {
            guard let field = line.t1Field else { continue }
            let other = parts.filter { p in !(p.documentID.flatMap { store.document($0) }?.specID == "CA.T4") }
            let sum = other.map(\.amount).reduce(0, +)
            if sum != 0 { values["form1." + field] = Amounts.plain(sum) }
        }
        let info = store.info
        let digits = info.birthDate.filter(\.isNumber)
        if digits.count == 8 { values["form1.Page1.Identification.DateBirth_Comb_BordersAll.DateBirth_Comb"] = digits }
        fill(t1, values)
        let t1Out = out.appendingPathComponent("T1 inputs.pdf")
        try write(t1, to: t1Out)
        return (t1Out, t4Files)
    }

    static func fill(_ doc: PDFDocument, _ values: [String: String]) {
        for i in 0..<doc.pageCount {
            for a in doc.page(at: i)?.annotations ?? [] where a.type == "Widget" {
                guard let n = a.fieldName, let v = values[PageReader.strip(n)] else { continue }
                a.widgetStringValue = v
            }
        }
    }

    /// Saves a filled form. CRA forms also carry an XFA copy of the form that Acrobat prefers
    /// over the filled fields; renaming its key (same length, so nothing moves) makes every
    /// viewer show the filled values.
    static func write(_ doc: PDFDocument, to url: URL) throws {
        guard var data = doc.dataRepresentation() else { throw EngineError.engine("Couldn't save \(url.lastPathComponent)") }
        let from = Data("/XFA".utf8), to = Data("/XFX".utf8)
        var search = data.startIndex..<data.endIndex
        while let r = data.range(of: from, in: search) {
            let next = r.upperBound < data.endIndex ? data[r.upperBound] : 0
            if next == 0x20 || next == 0x5B || next == 0x0A || next == 0x0D || next == 0x2F { data.replaceSubrange(r, with: to) }
            search = r.upperBound..<data.endIndex
        }
        try data.write(to: url, options: .atomic)
    }

    // MARK: Running the engine

    struct Setup {
        var engine: URL?
        var pdftk: URL?
        var ready: Bool { engine != nil && pdftk != nil }
    }

    /// Apps don't inherit the shell's PATH, so look where cabal, ghcup and Homebrew install.
    static func findTools() -> Setup {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let dirs = ["\(home)/.cabal/bin", "\(home)/.local/bin", "\(home)/.ghcup/bin", "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"]
        func find(_ n: String) -> URL? {
            dirs.map { URL(fileURLWithPath: $0).appendingPathComponent(n) }.first { FileManager.default.isExecutableFile(atPath: $0.path) }
        }
        return Setup(engine: find("complete-canadian-taxes"), pdftk: find("pdftk"))
    }

    static let installCommands = [
        "brew install pdftk-java",
        "curl --proto '=https' --tlsv1.2 -sSf https://get-ghcup.haskell.org | sh",
        "cabal update && cabal install canadian-income-tax",
    ]

    /// Runs `complete-canadian-taxes <province> --t1 … --t4 … -o <dir>` and returns its output.
    static func run(setup: Setup, province: String, t1: URL, t4s: [URL], p428: URL?, p479: URL?, out: URL) async throws -> String {
        guard let engine = setup.engine, let pdftk = setup.pdftk else { throw EngineError.engine("The engine isn't installed yet.") }
        var args = [province, "--t1", t1.path]
        for t in t4s { args += ["--t4", t.path] }
        if let p428 { args += ["--428", p428.path] }
        if let p479 { args += ["--479", p479.path] }
        args += ["-o", out.path]
        let p = Process()
        p.executableURL = engine
        p.arguments = args
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = [pdftk.deletingLastPathComponent().path, engine.deletingLastPathComponent().path, env["PATH"] ?? "/usr/bin:/bin"].joined(separator: ":")
        p.environment = env
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        try p.run()
        let data = await Task.detached { pipe.fileHandleForReading.readDataToEndOfFile() }.value
        p.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self)
        guard p.terminationStatus == 0 else { throw EngineError.engine("The engine stopped with an error:\n" + text) }
        return text
    }
}
