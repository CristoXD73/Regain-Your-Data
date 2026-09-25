import Foundation

/// Instagram's "Download your information" export, HTML format, messages only:
///
///   instagram-<username>-<date>-<id>.zip
///     your_instagram_activity/messages/inbox/<name>_<id>/message_1.html, message_2.html …
///     your_instagram_activity/messages/inbox/<name>_<id>/photos|videos|audio|gifs/<file>
///     your_instagram_activity/messages/message_requests/<name>_<id>/…   (same layout)
///     your_instagram_activity/messages/ai_conversations/…              (Meta AI chats)
///
/// Each page holds messages newest first:
///   <div class="… _a6-g …">
///     <div class="… _a6-h …">Sender Name</div>
///     <div class="… _a6-p"> text / link / <img|video|audio src="your_instagram_activity/…"> /
///                           <ul class="_a6-q"><li>❤Name</li></ul> (reactions) </div>
///     <div class="… _a6-o">Jan 2, 2023 4:05 pm</div>
///   </div>
/// The conversation's title is in <div class="_a70e">. Times are minute precision, local time.
struct Account: Identifiable, Hashable, Codable {
    let id: String              // username from the zip name
    let zip: URL
    var owner = ""              // the display name the account's own messages use
    var threads: [Thread] = []
    var exportDate: String

    static func == (a: Account, b: Account) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

struct Thread: Identifiable, Hashable, Codable {
    /// `unknown` is never stored: it's where the app files chats with a deleted or deactivated
    /// account ("Instagram User") until you give them a name.
    enum Folder: String, Codable { case inbox, requests, ai, unknown }
    let id: String              // path inside the zip
    let title: String
    let folder: Folder
    var messages: [Message]     // oldest first
    var participants: [String]
    var isGroup: Bool { participants.count > 2 }
    var last: Message? { messages.last }

    static func == (a: Thread, b: Thread) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

/// A photo, video, voice note or GIF, by its path inside the account's zip.
struct Media: Hashable, Codable {
    enum Kind: String, Codable { case photo, video, audio, gif }
    let kind: Kind
    let path: String
}

struct Message: Identifiable, Hashable, Codable {
    let id: Int
    let sender: String
    let time: Date
    let text: String
    let link: String?
    let media: [Media]
    let reactions: [String]     // e.g. "❤️ Ana"
    var mine = false
    /// Instagram left this message out of the export (shared posts, reels, story replies…).
    var isUnavailable: Bool { text.isEmpty && media.isEmpty && link == nil }

    static func == (a: Message, b: Message) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

enum InstagramScanner {
    /// Folders that contain Instagram exports (for the welcome screen).
    static func suggestedRoots() -> [URL] {
        let fm = FileManager.default
        var bases = [fm.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")]
        if let vols = try? fm.contentsOfDirectory(at: URL(fileURLWithPath: "/Volumes"), includingPropertiesForKeys: nil) { bases += vols }
        var found = Set<URL>()
        for base in bases {
            let e = fm.enumerator(at: base, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles, .skipsPackageDescendants])
            while let u = e?.nextObject() as? URL {
                if e!.level > 6 { e?.skipDescendants(); continue }
                if u.lastPathComponent.hasPrefix("instagram-"), u.pathExtension == "zip" {
                    // Suggest the folder that holds all the accounts' zips.
                    found.insert(u.deletingLastPathComponent().deletingLastPathComponent())
                }
            }
        }
        return found.sorted { $0.path < $1.path }
    }

    /// Finds instagram-*.zip files under `root`, one per account (unzipped copies are ignored:
    /// everything is read from the zips).
    static func accounts(under root: URL) -> [URL] {
        let fm = FileManager.default
        var byAccount: [String: URL] = [:]
        let e = fm.enumerator(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles, .skipsPackageDescendants])
        while let u = e?.nextObject() as? URL {
            if e!.level > 4 { e?.skipDescendants(); continue }
            guard u.pathExtension == "zip", u.lastPathComponent.hasPrefix("instagram-") else { continue }
            let name = username(u)
            if byAccount[name] == nil { byAccount[name] = u }
        }
        return byAccount.values.sorted { username($0) < username($1) }
    }

    /// "instagram-your.username-2024-01-31-AbCdEfGh.zip" -> "your.username"
    static func username(_ zip: URL) -> String {
        var s = zip.deletingPathExtension().lastPathComponent
        s = String(s.dropFirst("instagram-".count))
        if let r = s.range(of: #"-\d{4}-\d{2}-\d{2}-[A-Za-z0-9]+$"#, options: .regularExpression) { s = String(s[..<r.lowerBound]) }
        return s
    }

    /// Loads an account, from the saved copy when the zip hasn't changed since it was parsed.
    static func loadCached(_ zipURL: URL, idBase: Int) throws -> Account {
        let v = try zipURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let key = stableHash("\(zipURL.path)|\(v.fileSize ?? 0)|\(v.contentModificationDate?.timeIntervalSince1970 ?? 0)|\(parserVersion)")
        let file = Paths.support.appendingPathComponent("account-\(key).json")
        if let data = try? Data(contentsOf: file), let a = try? JSONDecoder().decode(Account.self, from: data) { return a }
        let a = try load(zipURL, idBase: idBase)
        if let data = try? JSONEncoder().encode(a) { try? data.write(to: file, options: .atomic) }
        return a
    }

    /// Bump when parsing changes so saved copies are rebuilt.
    static let parserVersion = 1

    static func load(_ zipURL: URL, idBase: Int = 0) throws -> Account {
        let zip = try ZipArchive(url: zipURL)
        let date = zipURL.deletingPathExtension().lastPathComponent.range(of: #"\d{4}-\d{2}-\d{2}"#, options: .regularExpression)
            .map { String(zipURL.deletingPathExtension().lastPathComponent[$0]) } ?? ""
        var account = Account(id: username(zipURL), zip: zipURL, exportDate: date)
        let entries = Dictionary(zip.entries.map { ($0.path, $0) }, uniquingKeysWith: { a, _ in a })

        // Pages grouped by conversation folder.
        var pages: [String: [ZipEntry]] = [:]
        for e in zip.entries where e.name.hasPrefix("message_") && e.name.hasSuffix(".html") {
            pages[e.directory, default: []].append(e)
        }
        var nextID = idBase
        for (dir, list) in pages {
            let folder: Thread.Folder = dir.contains("/message_requests/") ? .requests : dir.contains("/ai_conversations/") ? .ai : .inbox
            var title = ""
            var msgs: [Message] = []
            var listed: [String] = []
            // Pages and the messages in them run newest first; read oldest page last so the
            // reversed list comes out oldest first.
            for page in list.sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) {
                guard let data = try? zip.data(page) else { continue }
                let html = String(decoding: data, as: UTF8.self)
                if title.isEmpty { title = HTML.text(HTML.first(#"<div class="_a70e">(.*?)</div>"#, in: html) ?? "") }
                if listed.isEmpty, let p = HTML.first(#"<div class="_a6-h">Participants: (.*?)</div>"#, in: html) {
                    listed = HTML.text(p).components(separatedBy: ", ").map { $0.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{200E}\u{200F}"))) }.filter { !$0.isEmpty }
                }
                for m in parseMessages(html, entries: entries, nextID: &nextID) { msgs.append(m) }
            }
            msgs.reverse()
            // Same-minute messages keep their page order, which the reverse above preserved.
            msgs = msgs.enumerated().sorted { $0.element.time == $1.element.time ? $0.offset < $1.offset : $0.element.time < $1.element.time }.map(\.element)
            // The page header lists members; fall back to whoever wrote.
            let people = listed.isEmpty ? Array(Set(msgs.map(\.sender))).sorted() : listed
            if title.isEmpty { title = (dir as NSString).lastPathComponent }
            account.threads.append(Thread(id: dir, title: title, folder: folder, messages: msgs, participants: people))
        }

        // The owner writes in (nearly) every conversation.
        var seen: [String: Int] = [:]
        for t in account.threads where t.folder == .inbox { for p in Set(t.messages.map(\.sender)) { seen[p, default: 0] += 1 } }
        account.owner = seen.max { $0.value < $1.value }?.key ?? ""
        for i in account.threads.indices {
            for j in account.threads[i].messages.indices { account.threads[i].messages[j].mine = account.threads[i].messages[j].sender == account.owner }
        }
        account.threads.sort { ($0.last?.time ?? .distantPast) > ($1.last?.time ?? .distantPast) }
        return account
    }

    private static let timeFormat: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMM d, yyyy h:mm a"
        return f
    }()

    private static func parseMessages(_ html: String, entries: [String: ZipEntry], nextID: inout Int) -> [Message] {
        var out: [Message] = []
        let blocks = html.components(separatedBy: #"<div class="pam _3-95 _2ph- _a6-g uiBoxWhite noborder">"#).dropFirst()
        for b in blocks {
            // The first block on a page lists participants and has no timestamp: not a message.
            guard b.contains("_a6-o") else { continue }
            let sender = HTML.text(HTML.first(#"<div class="_3-95 _2pim _a6-h _a6-i">(.*?)</div>"#, in: b) ?? "")
            let stamp = HTML.text(HTML.first(#"<div class="_3-94 _a6-o">(.*?)</div>"#, in: b) ?? "")
            let time = timeFormat.date(from: stamp) ?? .distantPast
            // Content: everything between the sender and the timestamp.
            var content = HTML.first(#"<div class="_3-95 _a6-p">(.*)<div class="_3-94 _a6-o">"#, in: b) ?? ""
            let reactions = HTML.all(#"<li>(.*?)</li>"#, in: content).map(HTML.text)
            if let r = content.range(of: #"<ul class="_a6-q">"#) { content = String(content[..<r.lowerBound]) }
            var media: [Media] = []
            for src in HTML.all(#"(?:<img|<video|<audio)[^>]*src="([^"]+)""#, in: content) {
                let path = HTML.text(src)
                guard entries[path] != nil else { continue }
                let kind: Media.Kind = src.contains("/videos/") ? .video : src.contains("/audio/") ? .audio : src.contains("/gifs/") ? .gif : .photo
                if !media.contains(where: { $0.path == path }) { media.append(Media(kind: kind, path: path)) }
            }
            let link = HTML.all(#"<a target="_blank" href="(http[^"]+)""#, in: content).first.map(HTML.text)
            // Plain text: the content without media and link markup.
            var textHTML = content
            for pattern in [#"<video.*?</video>"#, #"<audio.*?</audio>"#, #"<a [^>]*>.*?</a>"#, #"<img[^>]*>"#] {
                textHTML = textHTML.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
            }
            var text = HTML.text(textHTML)
            if let link, text == link { text = "" }
            out.append(Message(id: nextID, sender: sender, time: time, text: text, link: link, media: media, reactions: reactions))
            nextID += 1
        }
        return out
    }
}

/// Just enough HTML handling for Instagram's regular export pages.
enum HTML {
    static func first(_ pattern: String, in s: String) -> String? { all(pattern, in: s).first }

    static func all(_ pattern: String, in s: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return [] }
        return re.matches(in: s, range: NSRange(s.startIndex..., in: s)).compactMap { m in
            Range(m.range(at: 1), in: s).map { String(s[$0]) }
        }
    }

    /// Strips tags, turns <br> and block ends into newlines, decodes entities, tidies spaces.
    static func text(_ html: String) -> String {
        var s = html.replacingOccurrences(of: #"<br\s*/?>"#, with: "\n", options: .regularExpression)
        s = s.replacingOccurrences(of: #"</div>"#, with: "\n")
        s = s.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        s = decodeEntities(s)
        let lines = s.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return lines.joined(separator: "\n")
    }

    static func decodeEntities(_ s: String) -> String {
        guard s.contains("&") else { return s }
        var out = ""
        var i = s.startIndex
        let named = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " "]
        while i < s.endIndex {
            if s[i] == "&", let semi = s[i...].firstIndex(of: ";"), s.distance(from: i, to: semi) <= 10 {
                let name = String(s[s.index(after: i)..<semi])
                var decoded: String?
                if name.hasPrefix("#x") || name.hasPrefix("#X") { decoded = UInt32(name.dropFirst(2), radix: 16).flatMap(Unicode.Scalar.init).map { String(Character($0)) } }
                else if name.hasPrefix("#") { decoded = UInt32(name.dropFirst()).flatMap(Unicode.Scalar.init).map { String(Character($0)) } }
                else { decoded = named[name] }
                if let decoded { out += decoded; i = s.index(after: semi); continue }
            }
            out.append(s[i])
            i = s.index(after: i)
        }
        return out
    }
}
