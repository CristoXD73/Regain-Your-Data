import AppKit
import PDFKit
import Vision

/// Text found on a page, with where it is. Rectangles are 0…1 with the origin at the bottom left,
/// whichever way the text was read.
struct TextLine: Codable, Hashable {
    var text: String
    var rect: CGRectCodable
    var page: Int
}

/// A dollar amount found on a page.
struct MoneyToken: Codable, Hashable {
    var text: String
    var value: Double
    var rect: CGRectCodable
    var page: Int
}

/// Everything read from one document, cached so a document is only read once.
struct ReadResult: Codable {
    var lines: [TextLine] = []
    var money: [MoneyToken] = []
    /// Values of a fillable PDF's fields, by name without the "[0]" indexes.
    var formFields: [String: String] = [:]
    var pageCount = 0
    var method = ""

    var fullText: String { lines.map(\.text).joined(separator: "\n") }
}

enum PageReader {
    /// Money as printed on slips: "52,345.67", "52345.67", "$1,234.00", and in French "52 345,67".
    /// A space only separates thousands when the decimals follow a comma, so "14 123.45" stays
    /// box 14 and 123.45.
    static let moneyPattern = try! NSRegularExpression(pattern: #"(?<![\d.,])-?\$? ?(?:\d{1,3}(?:,\d{3})+\.\d{2}|\d{1,3}(?:[ \u00A0\u202F]\d{3})+,\d{2}|\d{1,3}(?:\.\d{3})+,\d{2}|\d+[.,]\d{2})(?!\d)"#)
    /// Paper slips print dollars and cents in separate boxes, which OCR reads as "52345 67".
    static let splitCentsPattern = try! NSRegularExpression(pattern: #"(?<![\d.,])\d{2,7} \d{2}(?![\d.,])"#)

    static func read(_ url: URL) -> ReadResult {
        if url.pathExtension.lowercased() == "pdf", let doc = PDFDocument(url: url) { return read(pdf: doc) }
        guard let img = NSImage(contentsOf: url), let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return ReadResult(method: "unreadable") }
        var r = ReadResult(pageCount: 1, method: "on-device OCR")
        ocr(cg, page: 0, into: &r)
        return r
    }

    static func read(pdf doc: PDFDocument) -> ReadResult {
        var r = ReadResult(pageCount: doc.pageCount)
        var methods = Set<String>()
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            // A fillable form's own fields: exact values, placed where the widgets are.
            for a in page.annotations where a.type == "Widget" {
                guard let name = a.fieldName else { continue }
                let v = (a.widgetStringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !v.isEmpty else { continue }
                r.formFields[strip(name)] = v
                let rect = normalize(a.bounds, in: bounds)
                // Amount fields only: a SIN or account number is digits too, but has no cents and
                // more than seven digits.
                let digitsOnly = v.allSatisfy { $0.isNumber }
                let looksLikeMoney = isMoney(v) || (digitsOnly && v.count <= 7 && (name.contains("Box") || name.contains("Amount")))
                if looksLikeMoney, let m = Amounts.parse(v) {
                    r.money.append(MoneyToken(text: v, value: m, rect: CGRectCodable(rect), page: i))
                }
                r.lines.append(TextLine(text: v, rect: CGRectCodable(rect), page: i))
                methods.insert("form fields")
            }
            // The page's own text, when it has some; otherwise it's a scan and needs OCR.
            let text = page.string ?? ""
            if text.filter({ !$0.isWhitespace }).count > 40 {
                textLayer(page, pageIndex: i, bounds: bounds, into: &r)
                methods.insert("text layer")
            } else if let cg = render(page, bounds: bounds) {
                ocr(cg, page: i, into: &r)
                methods.insert("on-device OCR")
            }
        }
        r.method = methods.sorted().joined(separator: " + ")
        return r
    }

    static func strip(_ name: String) -> String { name.replacingOccurrences(of: #"\[\d+\]"#, with: "", options: .regularExpression) }

    private static func normalize(_ r: CGRect, in b: CGRect) -> CGRect {
        CGRect(x: (r.minX - b.minX) / b.width, y: (r.minY - b.minY) / b.height, width: r.width / b.width, height: r.height / b.height)
    }

    // MARK: Text layer

    private static func textLayer(_ page: PDFPage, pageIndex: Int, bounds: CGRect, into r: inout ReadResult) {
        guard let all = page.selection(for: bounds) else { return }
        for line in all.selectionsByLine() {
            let s = (line.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !s.isEmpty else { continue }
            r.lines.append(TextLine(text: s, rect: CGRectCodable(normalize(line.bounds(for: page), in: bounds)), page: pageIndex))
        }
        // Amounts, each with the exact rectangle of its characters.
        let full = page.string ?? ""
        let ns = full as NSString
        for m in moneyPattern.matches(in: full, range: NSRange(location: 0, length: ns.length)) {
            let t = ns.substring(with: m.range)
            guard let v = Amounts.parse(t), let sel = page.selection(for: m.range) else { continue }
            r.money.append(MoneyToken(text: t, value: v, rect: CGRectCodable(normalize(sel.bounds(for: page), in: bounds)), page: pageIndex))
        }
    }

    static func isMoney(_ s: String) -> Bool {
        let ns = s as NSString
        return moneyPattern.firstMatch(in: s, range: NSRange(location: 0, length: ns.length))?.range.length == ns.length
    }

    // MARK: OCR

    static func render(_ page: PDFPage, bounds: CGRect, dpi: CGFloat = 300) -> CGImage? {
        let scale = dpi / 72
        let w = Int(bounds.width * scale), h = Int(bounds.height * scale)
        guard w > 0, h > 0, w * h < 120_000_000,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.setFillColor(CGColor(gray: 1, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: -bounds.minX, y: -bounds.minY)
        page.draw(with: .mediaBox, to: ctx)
        return ctx.makeImage()
    }

    /// Apple's on-device text recognition. Nothing leaves the Mac.
    static func ocr(_ image: CGImage, page: Int, into r: inout ReadResult) {
        let req = VNRecognizeTextRequest()
        req.recognitionLevel = .accurate
        req.usesLanguageCorrection = true
        req.recognitionLanguages = ["en-US", "fr-CA"]
        req.customWords = ["T4", "T4A", "T5", "T3", "RRSP", "CPP", "QPP", "EI", "W-2", "1099", "1098"]
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        // The first recognition after a restart loads a model through a system service, which
        // now and then stalls; give up after a few minutes rather than wait forever.
        let done = DispatchSemaphore(value: 0)
        var ok = false
        DispatchQueue.global(qos: .userInitiated).async {
            ok = (try? handler.perform([req])) != nil
            done.signal()
        }
        if done.wait(timeout: .now() + 180) == .timedOut {
            req.cancel()
            r.method = "text recognition didn't respond (try Read Again)"
            return
        }
        guard ok, let obs = req.results else { return }
        for o in obs {
            guard let cand = o.topCandidates(1).first else { continue }
            let s = cand.string
            r.lines.append(TextLine(text: s, rect: CGRectCodable(o.boundingBox), page: page))
            let ns = s as NSString
            let whole = NSRange(location: 0, length: ns.length)
            let strict = moneyPattern.matches(in: s, range: whole)
            let split = splitCentsPattern.matches(in: s, range: whole).filter { m in !strict.contains { NSIntersectionRange($0.range, m.range).length > 0 } }
            for m in strict + split {
                let t = ns.substring(with: m.range)
                guard let v = Amounts.parse(t), let range = Range(m.range, in: s) else { continue }
                let box = (try? cand.boundingBox(for: range))?.boundingBox ?? o.boundingBox
                r.money.append(MoneyToken(text: t, value: v, rect: CGRectCodable(box), page: page))
            }
        }
    }
}
