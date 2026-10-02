import Foundation

/// A value read off a document: what it says, where on the page it came from, and whether a
/// person has checked it.
struct FieldValue: Codable, Hashable {
    var value: String
    /// 0…1. Values read from a fillable form's own fields are 1; values found by position on a
    /// scan are lower, and anything under about 0.6 deserves a look.
    var confidence: Double
    /// Page and rectangle (0…1, origin bottom-left) of the text the value came from.
    var page: Int?
    var rect: CGRectCodable?
    var confirmed = false
    var edited = false

    var amount: Double? { Amounts.parse(value) }
}

struct CGRectCodable: Codable, Hashable {
    var x, y, w, h: Double
    init(_ r: CGRect) { x = r.minX; y = r.minY; w = r.width; h = r.height }
    var rect: CGRect { CGRect(x: x, y: y, width: w, height: h) }
}

/// One imported document. The file itself is copied into the app's vault.
struct TaxDocument: Codable, Identifiable, Hashable {
    enum Status: String, Codable { case new, reading, needsReview, reviewed, failed }
    let id: UUID
    var fileName: String
    /// Name of the copy in the vault.
    var storedName: String
    var imported: Date
    var year: Int?
    var specID: String
    var fields: [String: FieldValue] = [:]
    var status: Status = .new
    var notes = ""
    var pageCount = 0
    /// How the text was read: "text layer", "form fields", "on-device OCR".
    var method = ""
    var classifyScore = 0.0

    var spec: SlipSpec { Specs.spec(specID) }
    var payer: String { fields["payer"]?.value ?? "" }
    var title: String { payer.isEmpty ? fileName : "\(spec.code) · \(payer)" }
}

/// Something that isn't on a slip: RRSP contributions without a receipt yet, medical costs,
/// a correction for the preparer…
struct ManualEntry: Codable, Identifiable, Hashable {
    var id = UUID()
    var line: String
    var description: String
    var amount: String
}

/// Per-year settings and notes.
struct TaxYearInfo: Codable, Hashable {
    var country: Country = Locale.current.region?.identifier == "US" ? .us : .canada
    var province = "ON"
    var usState = ""
    /// Only used to fill the T1 birth date, which affects age credits.
    var birthDate = ""
    var filingStatus = "S"
    var questions = ""
    var entries: [ManualEntry] = []
    /// Refiling: fix a return already filed rather than draft a new one.
    var amending = false
    var amendReason = ""
}

struct TaxLibrary: Codable {
    var documents: [TaxDocument] = []
    var years: [Int: TaxYearInfo] = [:]
    var requireUnlock = true
}

enum Amounts {
    /// "$52,345.67", "52 345,67", "52345 67" (dollars and cents boxes) and "(12.00)" all read.
    static func parse(_ s: String) -> Double? {
        var t = s.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        let negative = t.hasPrefix("-") || (t.hasPrefix("(") && t.hasSuffix(")"))
        t = t.filter { $0.isNumber || $0 == "," || $0 == "." || $0 == " " }
        // Dollars and cents in separate boxes: "52345 67".
        if let r = t.range(of: #"^(\d+) (\d{2})$"#, options: .regularExpression) { t = String(t[r]).replacingOccurrences(of: " ", with: ".") }
        t = t.replacingOccurrences(of: " ", with: "")
        let comma = t.lastIndex(of: ","), dot = t.lastIndex(of: ".")
        switch (comma, dot) {
        case let (c?, d?): t = c > d ? t.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".") : t.replacingOccurrences(of: ",", with: "")
        case let (c?, nil): t = t.distance(from: c, to: t.endIndex) == 3 ? t.replacingOccurrences(of: ",", with: ".") : t.replacingOccurrences(of: ",", with: "")
        default: break
        }
        guard let v = Double(t) else { return nil }
        return negative ? -v : v
    }

    static func format(_ v: Double, _ c: Country) -> String {
        v.formatted(.currency(code: c == .canada ? "CAD" : "USD").locale(Locale(identifier: c == .canada ? "en_CA" : "en_US")))
    }

    /// For form fields: "52345.67".
    static func plain(_ v: Double) -> String { String(format: "%.2f", v) }
}

enum TaxPaths {
    static var support: URL {
        // TAXDESK_HOME points everything at another folder, for trying the app with sample data.
        let u = ProcessInfo.processInfo.environment["TAXDESK_HOME"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("TaxDesk")
        make(u)
        return u
    }
    /// Copies of imported documents. Only this user can open the folder.
    static var vault: URL { let u = support.appendingPathComponent("Vault"); make(u); return u }
    static var cache: URL { let u = support.appendingPathComponent("Read"); make(u); return u }
    static var forms: URL { let u = support.appendingPathComponent("CRA forms"); make(u); return u }
    static var library: URL { support.appendingPathComponent("library.json") }

    static func make(_ u: URL) {
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }
}
