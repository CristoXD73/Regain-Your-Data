import AppKit
import NaturalLanguage
import Vision

/// What on-device analysis found in one photo.
struct Analysis: Codable {
    /// Vision scene/object labels with confidence, e.g. ["dog": 0.92, "beach": 0.81].
    var labels: [String: Float] = [:]
    /// Text recognised in the image (screenshots, documents, signs). nil = not run yet.
    var text: String?
    var version = PhotoAnalyzer.version
}

/// Everything here runs on the Mac (Vision on the Neural Engine); nothing leaves the machine.
enum PhotoAnalyzer {
    static let version = 1
    static let minConfidence: Float = 0.15

    /// Labels that suggest the picture has text worth reading.
    static let textyLabels: Set<String> = ["document", "handwriting", "receipt", "screenshot", "sign", "street_sign",
                                           "sticky_note", "whiteboard", "newspaper", "ticket", "book", "map",
                                           "credit_card", "gift_card", "checkbook"]

    static func labels(_ cg: CGImage) -> [String: Float] {
        let req = VNClassifyImageRequest()
        try? VNImageRequestHandler(cgImage: cg).perform([req])
        var out: [String: Float] = [:]
        for o in req.results ?? [] where o.confidence >= minConfidence { out[o.identifier] = o.confidence }
        return out
    }

    static func text(_ cg: CGImage) -> String {
        let req = VNRecognizeTextRequest()
        req.recognitionLevel = .accurate
        req.usesLanguageCorrection = true
        req.automaticallyDetectsLanguage = true
        try? VNImageRequestHandler(cgImage: cg).perform([req])
        return (req.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }

    static func needsText(_ a: Asset, labels: [String: Float]) -> Bool {
        guard a.kind != .video else { return false }
        return a.isScreenshot || labels.contains { textyLabels.contains($0.key) && $0.value >= 0.3 }
    }

    // MARK: Query understanding

    static let vocabulary: Set<String> = Set((try? VNClassifyImageRequest().supportedIdentifiers()) ?? [])
    private static let embedding = NLEmbedding.wordEmbedding(for: .english)

    /// Everyday words that aren't Vision labels, mapped to ones that are.
    static let synonyms: [String: [String]] = [
        "puppy": ["dog"], "puppies": ["dog"], "doggo": ["dog"], "kitten": ["cat"], "kitty": ["cat"],
        "ocean": ["beach", "water", "shore"], "sea": ["beach", "water", "shore"], "lake": ["water", "lake"],
        "sunset": ["sunset_sunrise"], "sunrise": ["sunset_sunrise"], "sky": ["sky"],
        "birthday": ["birthday_cake", "celebration", "cake"], "party": ["celebration", "party"],
        "selfie": ["people", "portrait"], "person": ["people", "adult"], "friends": ["people"], "kids": ["child"],
        "meal": ["food"], "dinner": ["food"], "lunch": ["food"], "breakfast": ["food"],
        "auto": ["car"], "automobile": ["car"], "vehicle": ["car", "vehicle"],
        "christmas": ["christmas_tree", "christmas_decoration"], "xmas": ["christmas_tree", "christmas_decoration"],
        "gym": ["gym"], "workout": ["gym", "sport"], "concert": ["concert", "stage"], "snowy": ["snow"],
        "mountains": ["mountain"], "trees": ["tree"], "flowers": ["flower"], "documents": ["document"],
    ]

    /// Labels a query word can mean: exact label, label containing the word, curated synonyms,
    /// then the single closest label from the word embedding if it is a strong match.
    static func labels(for word: String) -> Set<String> {
        let w = word.lowercased()
        var out = Set<String>()
        let singular = w.hasSuffix("s") && w.count > 3 ? String(w.dropLast()) : w
        for cand in [w, singular] where vocabulary.contains(cand) { out.insert(cand) }
        for id in vocabulary where id.split(separator: "_").contains(where: { $0 == w || $0 == singular }) { out.insert(id) }
        for s in synonyms[w] ?? synonyms[singular] ?? [] where vocabulary.contains(s) { out.insert(s) }
        if out.isEmpty, let emb = embedding {
            if let best = emb.neighbors(for: singular, maximumCount: 20).first(where: { vocabulary.contains($0.0) }), best.1 < 0.8 {
                out.insert(best.0)
            }
        }
        return out
    }

    static func displayName(_ label: String) -> String {
        label == "sunset_sunrise" ? "sunset" : label.replacingOccurrences(of: "_", with: " ")
    }
}

/// Cached analysis, keyed like thumbnails (name + size), so it survives moving between folders and zips.
actor AnalysisStore {
    private var cache: [String: Analysis] = [:]
    private let file: URL
    private var dirty = 0

    init(root: URL) {
        file = Paths.support.appendingPathComponent("analysis-\(stableHash(root.standardizedFileURL.path)).json")
        if let data = try? Data(contentsOf: file), let d = try? JSONDecoder().decode([String: Analysis].self, from: data) {
            cache = d.filter { $0.value.version == PhotoAnalyzer.version }
        }
    }

    func cached(_ key: String) -> Analysis? { cache[key] }

    func store(_ a: Analysis, key: String) {
        cache[key] = a
        dirty += 1
        if dirty >= 300 { save() }
    }

    func save() {
        guard dirty > 0 else { return }
        dirty = 0
        if let data = try? JSONEncoder().encode(cache) { try? data.write(to: file, options: .atomic) }
    }
}
