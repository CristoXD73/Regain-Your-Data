import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Asks Apple Intelligence's on-device model to fill boxes the position rules couldn't find.
/// It runs only when you press the button, entirely on this Mac, and its answers are marked as
/// suggestions to check against the document.
enum AIAssist {
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
        #endif
        return false
    }

    static var unavailableReason: String {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            switch SystemLanguageModel.default.availability {
            case .available: return ""
            case .unavailable(let why): return "Apple Intelligence isn't available (\(why))."
            }
        }
        #endif
        return "Needs macOS 26 or later with Apple Intelligence turned on."
    }

    /// Returns suggested values for the given fields, keyed by field key.
    static func suggest(text: String, spec: SlipSpec, missing: [FieldSpec]) async throws -> [String: String] {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            let list = missing.map { "\"\($0.key)\": \($0.label)" + ($0.kind == .money ? " (amount)" : "") }.joined(separator: "\n")
            let session = LanguageModelSession(instructions: """
                You read text copied from a scanned tax document and find the values of specific boxes. \
                Answer with one JSON object only, mapping each box key to its value exactly as printed. \
                Use null when a box is empty or not in the text. Never guess or calculate.
                """)
            // Keep the prompt within the on-device model's context.
            let excerpt = String(text.prefix(9000))
            let prompt = """
                Document type: \(spec.title)
                Boxes to find:
                \(list)

                Document text:
                \(excerpt)
                """
            let reply = try await session.respond(to: prompt).content
            guard let start = reply.firstIndex(of: "{"), let end = reply.lastIndex(of: "}"),
                  let obj = try? JSONSerialization.jsonObject(with: Data(reply[start...end].utf8)) as? [String: Any] else { return [:] }
            var out: [String: String] = [:]
            for f in missing {
                if let s = obj[f.key] as? String, !s.isEmpty { out[f.key] = s }
                else if let n = obj[f.key] as? NSNumber { out[f.key] = n.stringValue }
            }
            return out
        }
        #endif
        return [:]
    }
}
