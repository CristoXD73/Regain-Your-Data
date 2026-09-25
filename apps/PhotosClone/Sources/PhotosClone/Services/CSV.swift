import Foundation

/// Minimal RFC 4180 reader. Apple's export quotes dates ("Monday January 2,2023 4:05 PM GMT")
/// because they contain commas, and album names can contain emoji.
enum CSV {
    static func rows(_ source: MediaSource) -> [[String]] {
        guard let data = try? MediaAccess.data(source) else { return [] }
        let text = String(decoding: data, as: UTF8.self)
        return parse(text)
    }

    static func parse(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var chars = text.unicodeScalars.makeIterator()
        var pending: Unicode.Scalar? = nil

        func next() -> Unicode.Scalar? {
            if let p = pending { pending = nil; return p }
            return chars.next()
        }

        while let c = next() {
            if inQuotes {
                if c == "\"" {
                    if let n = next() {
                        if n == "\"" { field.unicodeScalars.append("\"") } else { inQuotes = false; pending = n }
                    } else { inQuotes = false }
                } else {
                    field.unicodeScalars.append(c)
                }
                continue
            }
            switch c {
            case "\"": inQuotes = true
            case ",": row.append(field); field = ""
            case "\r": break
            case "\n":
                row.append(field); field = ""
                rows.append(row); row = []
            case "\u{FEFF}": break
            default: field.unicodeScalars.append(c)
            }
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows.filter { !($0.count == 1 && $0[0].isEmpty) }
    }
}

enum AppleDate {
    // "Monday January 2,2023 4:05 PM GMT"
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "GMT")
        f.dateFormat = "EEEE MMMM d,yyyy h:mm a zzz"
        return f
    }()
    private static let lock = NSLock()

    static func parse(_ s: String) -> Date? {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        lock.lock(); defer { lock.unlock() }
        return formatter.date(from: t)
    }

    // Memory titles end in dates like "Nov 4, 2020", "Aug 17, 2020", "April 9 2020" or just "2018".
    private static let titleFormats = ["MMM d, yyyy", "MMMM d, yyyy", "MMMM d yyyy", "MMM d yyyy", "MMMM yyyy", "MMM yyyy", "yyyy"]
    private static let titleFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    static func fromTitle(_ title: String) -> Date? {
        // Strip Apple's de-dup suffix ("Around the Table Nov 4, 20201" -> "... 2020").
        let words = title.split(separator: " ").map(String.init)
        lock.lock(); defer { lock.unlock() }
        for take in stride(from: min(3, words.count), through: 1, by: -1) {
            var tail = words.suffix(take).joined(separator: " ")
            if let r = tail.range(of: #"(\d{4})\d+$"#, options: .regularExpression) {
                tail = String(tail[..<r.lowerBound]) + String(tail[r].prefix(4))
            }
            for fmt in titleFormats {
                titleFormatter.dateFormat = fmt
                if let d = titleFormatter.date(from: tail) { return d }
            }
        }
        return nil
    }
}
