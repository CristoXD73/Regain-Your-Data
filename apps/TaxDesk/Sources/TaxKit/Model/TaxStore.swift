import AppKit
import LocalAuthentication
import Observation
import UniformTypeIdentifiers

@MainActor @Observable
final class TaxStore {
    static let shared = TaxStore()

    enum Tab: String, CaseIterable, Identifiable {
        case documents = "Documents", draft = "Draft Return", file = "Forms & Engines", packet = "Preparer Package"
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .documents: return "doc.on.doc"
            case .draft: return "list.bullet.rectangle"
            case .file: return "gearshape.2"
            case .packet: return "shippingbox"
            }
        }
    }

    var library: TaxLibrary
    var year: Int
    var tab: Tab = .documents
    var selection: TaxDocument.ID?
    /// The field being corrected by clicking a number on the page.
    var picking: String?
    /// The field selected in the inspector, outlined on the page.
    var focusField: String?
    var locked: Bool
    var busy: [TaxDocument.ID: String] = [:]
    var message: String?
    private var reads: [TaxDocument.ID: ReadResult] = [:]

    init() {
        var lib = TaxLibrary()
        if let d = try? Data(contentsOf: TaxPaths.library), let l = try? JSONDecoder().decode(TaxLibrary.self, from: d) { lib = l }
        library = lib
        year = Prefs.defaults.object(forKey: "year") as? Int ?? Calendar.current.component(.year, from: Date()) - 1
        locked = lib.requireUnlock && !lib.documents.isEmpty
        #if DEBUG
        // Development with sample data (TAXDESK_HOME): open a tab and a document directly.
        let env = ProcessInfo.processInfo.environment
        if env["TAXDESK_HOME"] != nil {
            if let t = env["TAXDESK_TAB"].flatMap(Tab.init(rawValue:)) { tab = t }
            if let code = env["TAXDESK_PICK"] { selection = lib.documents.first { $0.spec.code == code }?.id }
            if let f = env["TAXDESK_FOCUS"] { focusField = f }
        }
        #endif
    }

    func save() {
        guard let d = try? JSONEncoder().encode(library) else { return }
        try? d.write(to: TaxPaths.library, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: TaxPaths.library.path)
    }

    func setYear(_ y: Int) { year = y; Prefs.defaults.set(y, forKey: "year"); selection = nil }

    var info: TaxYearInfo {
        get { library.years[year] ?? TaxYearInfo() }
        set { library.years[year] = newValue; save() }
    }

    var years: [Int] {
        let current = Calendar.current.component(.year, from: Date())
        return Array(Set(library.documents.compactMap(\.year) + Array(library.years.keys) + [current - 1, year])).sorted(by: >)
    }

    var documents: [TaxDocument] { library.documents.filter { ($0.year ?? year) == year }.sorted { ($0.spec.code, $0.payer) < ($1.spec.code, $1.payer) } }
    var unsorted: [TaxDocument] { library.documents.filter { $0.year == nil } }

    func document(_ id: TaxDocument.ID?) -> TaxDocument? { library.documents.first { $0.id == id } }

    func update(_ doc: TaxDocument) {
        guard let i = library.documents.firstIndex(where: { $0.id == doc.id }) else { return }
        library.documents[i] = doc
        save()
    }

    func fileURL(_ doc: TaxDocument) -> URL { TaxPaths.vault.appendingPathComponent(doc.storedName) }

    // MARK: Lock

    func unlock() {
        let ctx = LAContext()
        ctx.localizedFallbackTitle = "Use Password"
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else { locked = false; return }
        ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "open your tax documents") { ok, _ in
            Task { @MainActor in if ok { self.locked = false } }
        }
    }

    func lock() { if library.requireUnlock { locked = true; selection = nil } }

    // MARK: Import

    static let importTypes: [UTType] = [.pdf, .png, .jpeg, .heic, .tiff, .image]

    func chooseFiles() {
        let p = NSOpenPanel()
        p.allowsMultipleSelection = true
        p.canChooseDirectories = true
        p.allowedContentTypes = Self.importTypes + [.folder]
        p.message = "Choose tax slips, receipts or past returns: PDFs, photos or scans. Folders are searched too."
        if p.runModal() == .OK { importFiles(p.urls) }
    }

    func importFiles(_ urls: [URL]) {
        var files: [URL] = []
        for u in urls {
            var dir: ObjCBool = false
            if FileManager.default.fileExists(atPath: u.path, isDirectory: &dir), dir.boolValue {
                let e = FileManager.default.enumerator(at: u, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles, .skipsPackageDescendants])
                while let f = e?.nextObject() as? URL { if isImportable(f) { files.append(f) } }
            } else if isImportable(u) { files.append(u) }
        }
        for f in files { importFile(f) }
    }

    private func isImportable(_ u: URL) -> Bool {
        guard let t = UTType(filenameExtension: u.pathExtension.lowercased()) else { return false }
        return t.conforms(to: .pdf) || t.conforms(to: .image)
    }

    /// Copies a file into the vault and reads it. The original isn't touched.
    func importFile(_ url: URL) {
        let id = UUID()
        let stored = id.uuidString + "." + url.pathExtension.lowercased()
        do { try FileManager.default.copyItem(at: url, to: TaxPaths.vault.appendingPathComponent(stored)) } catch { message = "Couldn't import \(url.lastPathComponent): \(error.localizedDescription)"; return }
        add(TaxDocument(id: id, fileName: url.lastPathComponent, storedName: stored, imported: Date(), year: nil, specID: Specs.other.id))
    }

    /// A scan from an iPhone (Continuity Camera) or a pasted picture.
    func importData(_ data: Data, ext: String, name: String) {
        let id = UUID()
        let stored = id.uuidString + "." + ext
        do { try data.write(to: TaxPaths.vault.appendingPathComponent(stored)) } catch { message = error.localizedDescription; return }
        add(TaxDocument(id: id, fileName: name, storedName: stored, imported: Date(), year: nil, specID: Specs.other.id))
    }

    private func add(_ doc: TaxDocument) {
        library.documents.append(doc)
        save()
        selection = doc.id
        tab = .documents
        digitize(doc.id)
    }

    func delete(_ id: TaxDocument.ID) {
        guard let doc = document(id) else { return }
        try? FileManager.default.removeItem(at: fileURL(doc))
        try? FileManager.default.removeItem(at: TaxPaths.cache.appendingPathComponent(doc.id.uuidString + ".json"))
        library.documents.removeAll { $0.id == id }
        if selection == id { selection = nil }
        save()
    }

    // MARK: Digitize

    /// Reads a document (text layer, form fields or OCR), works out what it is and fills its
    /// fields. Runs off the main thread; the read text is cached next to the vault.
    func digitize(_ id: TaxDocument.ID, force: Bool = false) {
        guard var doc = document(id) else { return }
        busy[id] = "Reading…"
        let url = fileURL(doc)
        let cacheURL = TaxPaths.cache.appendingPathComponent(id.uuidString + ".json")
        let country = info.country
        Task {
            let r: ReadResult = await Task.detached(priority: .userInitiated) {
                if !force, let d = try? Data(contentsOf: cacheURL), let r = try? JSONDecoder().decode(ReadResult.self, from: d) { return r }
                let r = PageReader.read(url)
                if let d = try? JSONEncoder().encode(r) { try? d.write(to: cacheURL, options: .atomic) }
                return r
            }.value
            reads[id] = r
            let (spec, score) = Extractor.classify(r, country: country)
            doc.specID = spec.id
            doc.classifyScore = score
            doc.fields = Extractor.extract(r, spec: spec)
            doc.pageCount = r.pageCount
            doc.method = r.method
            doc.year = doc.fields["year"].flatMap { Int($0.value) } ?? doc.year ?? year
            doc.status = r.lines.isEmpty ? .failed : .needsReview
            update(doc)
            busy[id] = nil
        }
    }

    func readResult(_ id: TaxDocument.ID) -> ReadResult? {
        if let r = reads[id] { return r }
        let u = TaxPaths.cache.appendingPathComponent(id.uuidString + ".json")
        guard let d = try? Data(contentsOf: u), let r = try? JSONDecoder().decode(ReadResult.self, from: d) else { return nil }
        reads[id] = r
        return r
    }

    /// Changing what a document is re-reads its fields for the new kind.
    func setSpec(_ id: TaxDocument.ID, _ specID: String) {
        guard var doc = document(id) else { return }
        doc.specID = specID
        if let r = readResult(id) {
            let kept = doc.fields.filter { $0.value.edited }
            doc.fields = Extractor.extract(r, spec: doc.spec).merging(kept) { _, k in k }
        }
        update(doc)
    }

    func setField(_ id: TaxDocument.ID, _ key: String, _ value: String, page: Int? = nil, rect: CGRectCodable? = nil) {
        guard var doc = document(id) else { return }
        var f = doc.fields[key] ?? FieldValue(value: "", confidence: 1)
        f.value = value
        f.edited = true
        f.confirmed = true
        f.confidence = 1
        if let page { f.page = page; f.rect = rect }
        doc.fields[key] = f
        if key == "year", let y = Int(value) { doc.year = y }
        update(doc)
    }

    func markReviewed(_ id: TaxDocument.ID, _ on: Bool = true) {
        guard var doc = document(id) else { return }
        doc.status = on ? .reviewed : .needsReview
        for k in doc.fields.keys { doc.fields[k]?.confirmed = on }
        update(doc)
    }

    /// Warms up text recognition in the background: its first use in a session loads a model,
    /// which can take a while.
    func warmUp() {
        Task.detached(priority: .background) {
            let ctx = CGContext(data: nil, width: 64, height: 32, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
            ctx?.setFillColor(CGColor(gray: 1, alpha: 1)); ctx?.fill(CGRect(x: 0, y: 0, width: 64, height: 32))
            if let img = ctx?.makeImage() { var r = ReadResult(); PageReader.ocr(img, page: 0, into: &r) }
        }
    }

    // MARK: Draft

    struct Contribution: Identifiable, Hashable {
        let id: String
        let source: String
        let detail: String
        let amount: Double
        let documentID: TaxDocument.ID?
        let reviewed: Bool
    }

    /// Every return line with the slips and entries that add up to it.
    func draft() -> [(line: ReturnLine, total: Double, parts: [Contribution])] {
        let country = info.country
        var parts: [String: [Contribution]] = [:]
        for doc in documents where doc.spec.country == country && !doc.spec.isReturn {
            for f in doc.spec.fields where f.kind == .money {
                guard let amount = doc.fields[f.key]?.amount, amount != 0 else { continue }
                for line in f.lines {
                    parts[line, default: []].append(Contribution(id: "\(doc.id)-\(f.key)-\(line)", source: doc.title,
                                                                 detail: "\(doc.spec.code) box \(f.key): \(f.label)", amount: amount,
                                                                 documentID: doc.id, reviewed: doc.status == .reviewed))
                }
            }
        }
        for e in info.entries {
            guard let a = Amounts.parse(e.amount) else { continue }
            parts[e.line, default: []].append(Contribution(id: e.id.uuidString, source: "Entered by you", detail: e.description, amount: a, documentID: nil, reviewed: true))
        }
        return ReturnLine.lines(country).filter { $0.section != .totals }.compactMap { line in
            guard let p = parts[line.id], !p.isEmpty else { return nil }
            return (line, p.map(\.amount).reduce(0, +), p)
        }
    }

    /// The amounts of the return as filed (from a past return or a Notice of Assessment in
    /// this year), for refiling.
    func asFiled() -> [String: Double] {
        var out: [String: Double] = [:]
        for doc in documents where doc.spec.isReturn && doc.spec.country == info.country {
            for f in doc.spec.fields where f.kind == .money {
                if let a = doc.fields[f.key]?.amount, let line = f.lines.first { out[line] = a }
            }
        }
        return out
    }

    /// Slips from last year whose payer has nothing this year, so nothing is forgotten.
    func missingFromLastYear() -> [TaxDocument] {
        let now = Set(documents.map { "\($0.specID)|\(Extractor.fold($0.payer))" })
        return library.documents.filter { $0.year == year - 1 && !$0.spec.isReturn && $0.spec.id != Specs.other.id }
            .filter { !now.contains("\($0.specID)|\(Extractor.fold($0.payer))") }
    }
}
