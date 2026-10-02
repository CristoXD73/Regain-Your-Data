import Foundation

/// Works out what a document is and pulls the numbers out of it.
///
/// Fillable government PDFs are read by field name. Everything else is read by position: each
/// box is found by its label ("Employment income") or its number ("14"), and the amount that
/// sits right of it or just below it is taken. Every value keeps where it came from, so the
/// review screen can highlight it and a person can correct it with one click on the page.
enum Extractor {
    // MARK: What is it?

    static func classify(_ r: ReadResult, country: Country?) -> (spec: SlipSpec, score: Double) {
        let text = fold(r.fullText)
        var best: (SlipSpec, Double) = (Specs.other, 0)
        for spec in Specs.all where spec.id != Specs.other.id {
            var score = 0.0
            for (i, k) in spec.keywords.enumerated() {
                let key = fold(k)
                // A bare code like "T4" must stand alone, so it doesn't match "T4A" or "T45".
                if key.count <= 8 && !key.contains(" ") {
                    if text.range(of: #"(?<![a-z0-9])"# + NSRegularExpression.escapedPattern(for: key) + #"(?![a-z0-9(])"#, options: .regularExpression) != nil { score += 1 }
                } else if text.contains(key) {
                    score += i == 0 ? 4 : 2.5
                }
            }
            // Box labels that appear count for a little too.
            let labels = spec.fields.filter { $0.kind == .money }.flatMap { [$0.label] + $0.aliases }
            score += Double(labels.filter { $0.count > 6 && text.contains(fold($0)) }.count) * 0.3
            if let country, spec.country != country { score *= 0.8 }
            if score > best.1 { best = (spec, score) }
        }
        return best.1 >= 2 ? best : (Specs.other, best.1)
    }

    // MARK: Numbers

    static func extract(_ r: ReadResult, spec: SlipSpec) -> [String: FieldValue] {
        var out: [String: FieldValue] = [:]

        // 1. Government fillable PDFs: the field names say which box is which. CRA's T4 has two
        //    slips per page; the first one wins.
        for f in spec.fields {
            guard let name = f.formField else { continue }
            let hits = r.formFields.filter { !$0.value.isEmpty && $0.key.split(separator: ".").contains(Substring(name)) }
            guard let pick = hits.min(by: { ($0.key.contains("Slip2") ? 1 : 0, $0.key) < ($1.key.contains("Slip2") ? 1 : 0, $1.key) }) else { continue }
            let v = f.kind == .money ? (Amounts.parse(pick.value).map(Amounts.plain) ?? pick.value) : pick.value
            out[f.key] = FieldValue(value: v, confidence: 1)
        }

        // A filled-in government form lists every box it has; the empty ones stay empty rather
        // than borrowing a neighbour's amount.
        let fromForm = spec.fields.contains { $0.formField != nil && $0.kind == .money && out[$0.key] != nil }

        // 2. By position.
        var used = Set<Int>()
        var candidates: [(field: String, money: Int, cost: Double, both: Bool)] = []
        for f in spec.fields where f.kind == .money && out[f.key] == nil && !(fromForm && f.formField != nil) {
            let labelAnchors = anchors(for: f, in: r, labelsOnly: true, spec: spec)
            let numberAnchors = anchors(for: f, in: r, labelsOnly: false)
            var bestByMoney: [Int: (Double, Int)] = [:]   // money index -> (cost, how many anchor kinds agree)
            for (kind, list) in [(0, labelAnchors), (1, numberAnchors)] {
                for a in list {
                    var found: [(Int, Double, Bool)] = []   // money, cost, on the anchor's own row
                    for (i, m) in r.money.enumerated() where m.page == a.page {
                        let onLine = a.rect.rect.insetBy(dx: -0.002, dy: -0.002).contains(CGPoint(x: m.rect.rect.midX, y: m.rect.rect.midY))
                        guard var c = onLine ? 0.002 : cost(anchor: a.rect.rect, money: m.rect.rect) else { continue }
                        if kind == 1 { c += 0.015 }   // a lone box number is weaker evidence than a label
                        found.append((i, c, onLine || sameRow(a.rect.rect, m.rect.rect)))
                    }
                    // A label with an amount on its own row doesn't reach for the rows below.
                    if found.contains(where: \.2) { found = found.filter(\.2) }
                    for (i, c, _) in found {
                        if let old = bestByMoney[i] {
                            bestByMoney[i] = (min(old.0, c), old.1 | (1 << kind))
                        } else {
                            bestByMoney[i] = (c, 1 << kind)
                        }
                    }
                }
            }
            for (i, v) in bestByMoney { candidates.append((f.key, i, v.0, v.1 == 3)) }
        }
        // An amount belongs to the box it sits closest to: an empty box doesn't take the amount
        // of the box beside it.
        var nearest: [Int: Double] = [:]
        for c in candidates { nearest[c.money] = min(nearest[c.money] ?? .infinity, c.cost) }
        candidates = candidates.filter { $0.cost <= nearest[$0.money]! * 1.25 + 0.004 }
        // Closest pairs first, each amount used once.
        for c in candidates.sorted(by: { $0.cost < $1.cost }) where out[c.field] == nil && !used.contains(c.money) {
            let m = r.money[c.money]
            let conf = c.both ? 0.92 : c.cost < 0.04 ? 0.8 : c.cost < 0.1 ? 0.6 : 0.35
            out[c.field] = FieldValue(value: Amounts.plain(m.value), confidence: conf, page: m.page, rect: m.rect)
            used.insert(c.money)
        }

        // 3. Text fields: the line under (or after) the label.
        let allLabels = Set(spec.fields.flatMap { [$0.label] + $0.aliases }.map(fold).filter { $0.count >= 4 })
        for f in spec.fields where f.kind == .text || f.kind == .province {
            guard out[f.key] == nil else { continue }
            if f.kind == .province {
                if let v = province(near: [f.label] + f.aliases, in: r) { out[f.key] = v }
            } else if let v = textBelow(labels: [f.label] + f.aliases, in: r, skip: allLabels, digits: f.key == "ein") { out[f.key] = v }
        }

        // 4. The tax year.
        if out["year"] == nil, let y = year(in: r) { out["year"] = y }
        return out
    }

    /// Where a box's label or number is printed.
    static func anchors(for f: FieldSpec, in r: ReadResult, labelsOnly: Bool, spec: SlipSpec? = nil) -> [TextLine] {
        if labelsOnly {
            func longest(_ g: FieldSpec, in t: String) -> Int {
                ([g.label] + g.aliases).map(fold).filter { $0.count >= 4 && t.contains($0) }.map(\.count).max() ?? 0
            }
            let others = (spec?.fields ?? []).filter { $0.key != f.key && $0.kind == .money }
            return r.lines.filter { l in
                let t = fold(l.text)
                let mine = longest(f, in: t)
                // "Total income" also matches "Total income tax deducted"; that line belongs to
                // the field with the longer, more specific label.
                return mine > 0 && !others.contains { longest($0, in: t) > mine }
            }
        }
        // Box numbers: a short line that is exactly the number, or starts with it ("14 Employment income").
        let key = fold(f.key)
        guard key.first?.isNumber == true else { return [] }
        return r.lines.compactMap { l in
            let t = fold(l.text).trimmingCharacters(in: .whitespaces)
            if t == key || t == "box " + key || t == "case " + key { return l }
            if t.hasPrefix(key + " "), !PageReader.isMoney(String(t.dropFirst(key.count + 1)).trimmingCharacters(in: .whitespaces)) {
                // Keep just the number's part of the line as the anchor.
                var line = l
                let frac = Double(key.count + 1) / Double(max(1, t.count))
                line.rect = CGRectCodable(CGRect(x: l.rect.x, y: l.rect.y, width: l.rect.w * frac, height: l.rect.h))
                return line
            }
            return nil
        }
    }

    static func sameRow(_ a: CGRect, _ m: CGRect) -> Bool {
        abs(m.midY - a.midY) < max(a.height, m.height) * 0.7 && m.minX >= a.maxX - 0.01
    }

    /// How far an amount is from a label, if it is in a plausible place: on the same row to the
    /// right, or below within a few lines and roughly the same column.
    static func cost(anchor a: CGRect, money m: CGRect) -> Double? {
        let rowTolerance = max(a.height, m.height) * 0.7
        if abs(m.midY - a.midY) < rowTolerance, m.minX >= a.maxX - 0.01 {
            // Slips print a box's amount on its own row, often far to the right of the label.
            let gap = m.minX - a.maxX
            return gap < 0.65 ? gap * 0.3 + 0.005 : nil
        }
        let drop = a.minY - m.maxY                     // positive when the amount is lower on the page
        if drop > -rowTolerance * 0.5, drop < 0.07 {
            let dx = m.midX < a.minX - 0.03 ? a.minX - m.midX : max(0, m.minX - a.maxX)
            guard dx < 0.2 else { return nil }
            return max(0, drop) * 2 + dx * 0.8 + 0.02
        }
        return nil
    }

    static func textBelow(labels: [String], in r: ReadResult, skip: Set<String> = [], digits: Bool = false) -> FieldValue? {
        let keys = labels.map(fold).filter { $0.count >= 4 }
        guard let label = r.lines.first(where: { l in let t = fold(l.text); return keys.contains { containsWord(t, $0) } }) else { return nil }
        // "Employer's name: Acme Ltd" — only after a colon, so the rest of a long label
        // (", address, and ZIP code") isn't taken for the value.
        for k in labels {
            if let range = label.text.range(of: k + ":", options: [.caseInsensitive, .diacriticInsensitive]) {
                let rest = label.text[range.upperBound...].trimmingCharacters(in: .whitespaces)
                if rest.count >= 2, !skip.contains(where: { fold(rest).contains($0) }) {
                    return FieldValue(value: rest, confidence: 0.7, page: label.page, rect: label.rect)
                }
            }
        }
        let a = label.rect.rect
        let below = r.lines.filter { l in
            let b = l.rect.rect
            guard l.page == label.page, b.maxY <= a.minY + 0.005, a.minY - b.maxY < 0.06, b.maxX > a.minX - 0.02, b.minX < a.maxX + 0.1 else { return false }
            guard !PageReader.isMoney(l.text), !skip.contains(where: { fold(l.text).contains($0) }) else { return false }
            return digits ? l.text.filter(\.isNumber).count >= 6 : l.text.filter(\.isLetter).count >= 3
        }
        guard let pick = below.max(by: { $0.rect.y < $1.rect.y }) else { return nil }
        return FieldValue(value: pick.text, confidence: 0.55, page: pick.page, rect: pick.rect)
    }

    /// Whole words only, so "State" doesn't match "Statement".
    static func containsWord(_ text: String, _ key: String) -> Bool {
        guard key.count < 10 else { return text.contains(key) }
        return text.range(of: #"(?<![a-z0-9])"# + NSRegularExpression.escapedPattern(for: key) + #"(?![a-z0-9])"#, options: .regularExpression) != nil
    }

    static let provinces: Set<String> = ["AB", "BC", "MB", "NB", "NL", "NS", "NT", "NU", "ON", "PE", "QC", "SK", "YT", "ZZ", "US"]

    /// A two-letter province code near the label.
    static func province(near labels: [String], in r: ReadResult) -> FieldValue? {
        let keys = labels.map(fold).filter { $0.count >= 4 }
        guard let label = r.lines.first(where: { l in keys.contains { fold(l.text).contains($0) } }) else { return nil }
        let a = label.rect.rect
        let codes = r.lines.filter { $0.page == label.page && provinces.contains($0.text.trimmingCharacters(in: .whitespaces).uppercased()) }
        guard let pick = codes.min(by: { hypot($0.rect.rect.midX - a.midX, $0.rect.rect.midY - a.midY) < hypot($1.rect.rect.midX - a.midX, $1.rect.rect.midY - a.midY) }),
              hypot(pick.rect.rect.midX - a.midX, pick.rect.rect.midY - a.midY) < 0.12 else { return nil }
        return FieldValue(value: pick.text.trimmingCharacters(in: .whitespaces).uppercased(), confidence: 0.7, page: pick.page, rect: pick.rect)
    }

    static func year(in r: ReadResult) -> FieldValue? {
        let now = Calendar.current.component(.year, from: Date())
        let yearRE = try! NSRegularExpression(pattern: #"(?<!\d)(20\d\d)(?!\d)"#)
        var counts: [Int: (Int, TextLine)] = [:]
        for l in r.lines {
            let ns = l.text as NSString
            for m in yearRE.matches(in: l.text, range: NSRange(location: 0, length: ns.length)) {
                guard let y = Int(ns.substring(with: m.range)), y >= 2000, y <= now + 1 else { continue }
                let near = fold(l.text).contains("year") || fold(l.text).contains("annee")
                counts[y] = ((counts[y]?.0 ?? 0) + (near ? 5 : 1), l)
            }
        }
        guard let best = counts.max(by: { $0.value.0 < $1.value.0 }) else { return nil }
        return FieldValue(value: String(best.key), confidence: best.value.0 >= 5 ? 0.85 : 0.5, page: best.value.1.page, rect: best.value.1.rect)
    }

    /// Lowercased, without accents or curly quotes, for matching labels.
    static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
    }
}
