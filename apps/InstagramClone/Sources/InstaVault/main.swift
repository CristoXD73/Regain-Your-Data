import Foundation

// `InstaVault --check <folder>` loads every account and prints counts (no message content).
if let i = CommandLine.arguments.firstIndex(of: "--check"), i + 1 < CommandLine.arguments.count {
    let t0 = Date()
    for (n, zip) in InstagramScanner.accounts(under: URL(fileURLWithPath: CommandLine.arguments[i + 1])).enumerated() {
        let a = try InstagramScanner.loadCached(zip, idBase: n * 10_000_000)
        let msgs = a.threads.flatMap(\.messages)
        let media = msgs.flatMap(\.media)
        func count(_ k: Media.Kind) -> Int { media.filter { $0.kind == k }.count }
        print("""
        \(a.id) (\(a.exportDate)): threads \(a.threads.count) [inbox \(a.threads.filter { $0.folder == .inbox }.count), requests \(a.threads.filter { $0.folder == .requests }.count), ai \(a.threads.filter { $0.folder == .ai }.count), groups \(a.threads.filter(\.isGroup).count)]
          "Instagram User" chats: \(a.threads.filter { t in t.title == "Instagram User" || (!t.isGroup && !t.participants.isEmpty && t.participants.filter { $0 != a.owner }.allSatisfy { $0 == "Instagram User" }) }.count)
          owner found: \(!a.owner.isEmpty), messages \(msgs.count), mine \(msgs.filter(\.mine).count), undated \(msgs.filter { $0.time == .distantPast }.count), not in export \(msgs.filter(\.isUnavailable).count), group members listed \(a.threads.filter(\.isGroup).map(\.participants.count))
          media: photos \(count(.photo)), videos \(count(.video)), audio \(count(.audio)), gifs \(count(.gif)); links \(msgs.filter { $0.link != nil }.count); with reactions \(msgs.filter { !$0.reactions.isEmpty }.count)
          date range: \(msgs.map(\.time).filter { $0 != .distantPast }.min().map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "-") – \(msgs.map(\.time).max().map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "-")
          media files in zip not referenced by any message: \(try ZipArchive(url: zip).entries.filter { e in ["photos", "videos", "audio", "gifs"].contains((e.directory as NSString).lastPathComponent) }.count - Set(media.map(\.path)).count)
        """)
    }
    print(String(format: "loaded in %.1fs", Date().timeIntervalSince(t0)))
    exit(0)
}

// `InstaVault --media-test <folder>` loads one photo, video and voice note from each zip.
if let i = CommandLine.arguments.firstIndex(of: "--media-test"), i + 1 < CommandLine.arguments.count {
    let sem = DispatchSemaphore(value: 0)
    Task.detached {
        for zip in InstagramScanner.accounts(under: URL(fileURLWithPath: CommandLine.arguments[i + 1])) {
            guard let a = try? InstagramScanner.loadCached(zip, idBase: 0) else { continue }
            let media = a.threads.flatMap(\.messages).flatMap(\.media)
            for kind in [Media.Kind.photo, .video, .audio] {
                guard let m = media.first(where: { $0.kind == kind }), let e = ZipLibrary.shared.entry(m.path, in: zip) else { print("\(a.id) \(kind): none"); continue }
                let t = Date()
                if kind == .audio {
                    let d = try? await MediaLoader.asset(e).load(.duration)
                    print(String(format: "%@ audio: %.1fs long (%.2fs)", a.id, d?.seconds ?? -1, Date().timeIntervalSince(t)))
                } else {
                    let img = await Thumbs.shared.image(e, kind: kind)
                    print(String(format: "%@ %@: thumbnail %@ (%.2fs, %.1f MB)", a.id, "\(kind)", img.map { "\(Int($0.size.width))x\(Int($0.size.height))" } ?? "FAILED", Date().timeIntervalSince(t), Double(e.size) / 1e6))
                }
            }
        }
        sem.signal()
    }
    sem.wait()
    exit(0)
}

InstaApp.main()
