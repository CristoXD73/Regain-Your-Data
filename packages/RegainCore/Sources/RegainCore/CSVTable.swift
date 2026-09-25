import Foundation

/// A CSV file read into memory. Handles RFC 4180 quoting, a UTF-8 byte-order mark, CRLF or LF
/// line ends, and the doubled quotes some exports leave inside values (`"\"Full\""`).
public struct CSVTable: Sendable, Identifiable {
    public let id = UUID()
    public var header: [String]
    public var rows: [[String]]

    public init(header: [String], rows: [[String]]) {
        self.header = header
        self.rows = rows
    }

    public init(data: Data) {
        var all = Self.parse(String(decoding: data, as: UTF8.self))
        header = all.isEmpty ? [] : all.removeFirst().map(Self.clean)
        rows = all.filter { !($0.count == 1 && $0[0].isEmpty) }.map { $0.map(Self.clean) }
    }

    /// Index of the first column whose name matches one of `names`, ignoring case, spaces and
    /// punctuation, so "Order ID", "OrderId" and "order-id" are the same column.
    public func column(_ names: String...) -> Int? { column(names) }

    public func column(_ names: [String]) -> Int? {
        let keys = header.map(Self.key)
        for n in names { if let i = keys.firstIndex(of: Self.key(n)) { return i } }
        return nil
    }

    public func has(_ names: String...) -> Bool { names.allSatisfy { column($0) != nil } }

    public static func key(_ s: String) -> String { String(s.lowercased().unicodeScalars.filter(CharacterSet.alphanumerics.contains).map(Character.init)) }

    /// Trims and removes one extra pair of quotes around a whole value.
    static func clean(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.count >= 2, t.hasPrefix("\""), t.hasSuffix("\"") { t = String(t.dropFirst().dropLast()) }
        return t
    }

    static func parse(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = String.UnicodeScalarView()
        var quoted = false
        var it = text.unicodeScalars.makeIterator()
        var pending: Unicode.Scalar? = nil
        var first = true
        while let c = pending ?? it.next() {
            pending = nil
            if first { first = false; if c == "\u{FEFF}" { continue } }
            if quoted {
                if c == "\"" {
                    if let n = it.next() {
                        if n == "\"" { field.append("\"") } else { quoted = false; pending = n }
                    } else { quoted = false }
                } else { field.append(c) }
                continue
            }
            switch c {
            case "\"" where field.isEmpty: quoted = true
            case ",": row.append(String(field)); field = .init()
            case "\r": continue
            case "\n":
                row.append(String(field)); field = .init()
                rows.append(row); row = []
            default: field.append(c)
            }
        }
        if !field.isEmpty || !row.isEmpty { row.append(String(field)); rows.append(row) }
        return rows
    }
}

public extension Array where Element == String {
    /// The value at `i`, or "" when the column is missing or the row is short.
    subscript(safe i: Int?) -> String {
        guard let i, indices.contains(i) else { return "" }
        return self[i]
    }
}

/// Lenient readers for the values data exports put in their CSVs.
public enum Parse {
    /// "", "Not Available", "N/A" … mean there is no value.
    public static func isMissing(_ s: String) -> Bool {
        let k = CSVTable.key(s)
        return k.isEmpty || ["notavailable", "na", "notapplicable", "none", "null", "unknown"].contains(k)
    }

    public static func text(_ s: String) -> String? { isMissing(s) ? nil : s }

    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let iso = ISO8601DateFormatter()
    private static let formatters: [DateFormatter] = [
        "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm:ss 'UTC'", "yyyy-MM-dd",
        "MM/dd/yyyy HH:mm:ss", "MM/dd/yyyy", "M/d/yy", "dd/MM/yyyy", "MMM d, yyyy", "MMMM d, yyyy",
    ].map {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = $0
        return f
    }

    /// ISO 8601 (with or without fractions of a second) and the usual US and European forms.
    public static func date(_ s: String) -> Date? {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard t.count >= 6, !isMissing(t) else { return nil }
        if let d = isoFractional.date(from: t) ?? iso.date(from: t) { return d }
        for f in formatters { if let d = f.date(from: t) { return d } }
        return nil
    }

    /// "$1,234.56", "1.234,56 €", "12,34" and "'12.99'" all read as numbers.
    public static func money(_ s: String) -> Double? {
        var t = String(s.unicodeScalars.filter { CharacterSet.decimalDigits.contains($0) || $0 == "," || $0 == "." || $0 == "-" }.map(Character.init))
        guard t.contains(where: \.isNumber) else { return nil }
        let lastComma = t.lastIndex(of: ","), lastDot = t.lastIndex(of: ".")
        switch (lastComma, lastDot) {
        case let (c?, d?):
            if c > d { t = t.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".") }
            else { t = t.replacingOccurrences(of: ",", with: "") }
        case let (c?, nil):
            // "12,34" is a decimal comma; "1,234" is a thousands separator.
            t = t.distance(from: c, to: t.endIndex) == 3 && t.filter { $0 == "," }.count == 1
                ? t.replacingOccurrences(of: ",", with: ".") : t.replacingOccurrences(of: ",", with: "")
        default: break
        }
        return Double(t)
    }

    public static func number(_ s: String) -> Double? { Double(s.trimmingCharacters(in: .whitespaces)) ?? money(s) }

    public static func bool(_ s: String) -> Bool { ["yes", "true", "1", "y"].contains(s.lowercased()) }
}
