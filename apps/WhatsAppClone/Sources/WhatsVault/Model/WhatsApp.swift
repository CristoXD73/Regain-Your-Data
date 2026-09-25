import Foundation

/// A WhatsApp "Export Chat" (with media) zip:
///
///   WhatsApp Chat - <name>.zip
///     _chat.txt                                    the transcript
///     00000012-PHOTO-2023-01-02-14-05-00.jpg       attachments (PHOTO, STICKER, GIF, VIDEO,
///                                                  AUDIO, and documents by their own name)
///
/// Transcript lines from iPhone exports look like
///   [2023-01-02, 2:05:00 PM] Name: text
///   ‎[2023-01-02, 2:05:06 PM] Name: ‎<attached: 00000012-PHOTO-2023-01-02-14-05-00.jpg>
/// A leading U+200E marks attachments and system notices. Lines without a "[date]" prefix
/// continue the previous message. The time format follows the phone's settings, so a few
/// common ones are accepted.
struct Chat: Identifiable, Hashable {
    let id: String
    let zip: URL
    let title: String
    var messages: [Message]
    var participants: [String]
    var me: String
    var isGroup: Bool { participants.count > 2 }

    static func == (a: Chat, b: Chat) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

struct Message: Identifiable, Hashable {
    enum Kind { case text, photo, sticker, gif, video, audio, document, system, deleted, omitted }
    let id: Int
    let time: Date
    let sender: String
    var text: String
    var kind: Kind
    /// File name inside the zip, for attachments.
    var file: String?
    var mine = false

    var isMedia: Bool { [.photo, .sticker, .gif, .video].contains(kind) }
}

enum WhatsAppScanner {
    /// "WhatsApp Chat - Alex.zip" files under `root`; unzipped copies are ignored.
    static func chats(under root: URL) -> [URL] {
        let fm = FileManager.default
        var out: [URL] = []
        let e = fm.enumerator(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles, .skipsPackageDescendants])
        while let u = e?.nextObject() as? URL {
            if e!.level > 5 { e?.skipDescendants(); continue }
            if u.pathExtension == "zip", u.lastPathComponent.hasPrefix("WhatsApp Chat") { out.append(u) }
        }
        return out.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    static func suggestedRoots() -> [URL] {
        let fm = FileManager.default
        var bases = [fm.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")]
        if let vols = try? fm.contentsOfDirectory(at: URL(fileURLWithPath: "/Volumes"), includingPropertiesForKeys: nil) { bases += vols }
        var found = Set<URL>()
        for base in bases {
            let e = fm.enumerator(at: base, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles, .skipsPackageDescendants])
            while let u = e?.nextObject() as? URL {
                if e!.level > 6 { e?.skipDescendants(); continue }
                if u.pathExtension == "zip", u.lastPathComponent.hasPrefix("WhatsApp Chat") { found.insert(u.deletingLastPathComponent()) }
            }
        }
        return found.sorted { $0.path < $1.path }
    }

    private static let line = try! NSRegularExpression(pattern: #"^‎?\[([^\]]+)\] ([^:]+): (.*)$"#)
    private static let formats = ["yyyy-MM-dd, h:mm:ss a", "yyyy-MM-dd, HH:mm:ss", "M/d/yy, h:mm:ss a", "d/M/yy, HH:mm:ss",
                                  "dd/MM/yyyy, HH:mm:ss", "M/d/yy, h:mm a", "dd.MM.yy, HH:mm:ss"]
    private static let formatters: [DateFormatter] = formats.map {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = $0
        return f
    }

    static func parseDate(_ s: String) -> Date? {
        // Newer iOS puts a narrow no-break space before AM/PM.
        let t = s.replacingOccurrences(of: "\u{202F}", with: " ").replacingOccurrences(of: "\u{00A0}", with: " ")
        for f in formatters { if let d = f.date(from: t) { return d } }
        return nil
    }

    static func load(_ zipURL: URL, idBase: Int = 0) throws -> Chat {
        let zip = try ZipArchive(url: zipURL)
        guard let txt = zip.entries.first(where: { $0.name == "_chat.txt" || $0.name.hasSuffix(".txt") }) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let files = Set(zip.entries.map(\.name))
        let text = String(decoding: try zip.data(txt), as: UTF8.self).replacingOccurrences(of: "\r", with: "")
        var msgs: [Message] = []
        var id = idBase
        for raw in text.components(separatedBy: "\n") {
            let ns = raw as NSString
            guard let m = line.firstMatch(in: raw, range: NSRange(location: 0, length: ns.length)),
                  let date = parseDate(ns.substring(with: m.range(at: 1))) else {
                // A continuation line of the previous message.
                if !raw.isEmpty, var last = msgs.popLast() {
                    last.text += "\n" + raw
                    msgs.append(last)
                }
                continue
            }
            let sender = ns.substring(with: m.range(at: 2)).trimmingCharacters(in: .whitespaces)
            var body = ns.substring(with: m.range(at: 3))
            let marked = raw.hasPrefix("\u{200E}") || body.hasPrefix("\u{200E}")
            body = body.replacingOccurrences(of: "\u{200E}", with: "")
            var msg = Message(id: id, time: date, sender: sender, text: body, kind: .text)
            if let r = body.range(of: #"<attached: ([^>]+)>"#, options: .regularExpression) {
                let file = String(body[r].dropFirst("<attached: ".count).dropLast())
                msg.file = files.contains(file) ? file : nil
                msg.kind = msg.file == nil ? .omitted : kind(of: file)
                msg.text = body.replacingingRange(r).trimmingCharacters(in: .whitespacesAndNewlines)
            } else if marked && (body.hasSuffix(" omitted") || body == "This message was deleted." || body.contains("end-to-end encrypted")) {
                msg.kind = body.contains("deleted") ? .deleted : body.hasSuffix(" omitted") ? .omitted : .system
            } else if body == "This message was deleted." || body == "You deleted this message." {
                msg.kind = .deleted
            }
            msgs.append(msg)
            id += 1
        }

        let title = zipURL.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "WhatsApp Chat - ", with: "").replacingOccurrences(of: "WhatsApp Chat with ", with: "")
        // The first message is often the chat's own encryption notice, sent "by" the chat title.
        let people = Array(Set(msgs.filter { $0.kind != .system }.map(\.sender))).sorted()
        // The exporter is the person who isn't the chat title (1:1 chats); in groups, whoever
        // writes most is a fair guess, and can be changed in the app.
        let me = people.first { $0 != title } ?? people.first ?? ""
        for i in msgs.indices { msgs[i].mine = msgs[i].sender == me }
        return Chat(id: zipURL.path, zip: zipURL, title: title, messages: msgs, participants: people, me: me)
    }

    static func kind(of file: String) -> Message.Kind {
        let up = file.uppercased()
        if up.contains("-STICKER-") { return .sticker }
        if up.contains("-GIF-") { return .gif }
        if up.contains("-VIDEO-") { return .video }
        if up.contains("-AUDIO-") || up.hasSuffix(".OPUS") || up.hasSuffix(".M4A") { return .audio }
        if up.contains("-PHOTO-") || ["JPG", "JPEG", "PNG", "HEIC", "WEBP"].contains((file as NSString).pathExtension.uppercased()) { return .photo }
        return .document
    }
}

private extension String {
    func replacingingRange(_ r: Range<String.Index>) -> String {
        var s = self
        s.removeSubrange(r)
        return s
    }
}
