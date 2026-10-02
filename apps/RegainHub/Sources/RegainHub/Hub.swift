import AppKit
import Observation
import RegainCore

/// Everything the hub can show. Each app keeps its own look; the hub only switches between them.
enum Source: String, CaseIterable, Identifiable {
    case home, photos, snapchat, instagram, whatsapp, amazon, taxes, explorer

    var id: String { rawValue }

    var name: String {
        switch self {
        case .home: return "Home"
        case .photos: return "Photos"
        case .snapchat: return "Snapchat"
        case .instagram: return "Instagram"
        case .whatsapp: return "WhatsApp"
        case .amazon: return "Amazon"
        case .taxes: return "Taxes"
        case .explorer: return "Explorer"
        }
    }

    /// The app's own name, as it is when downloaded on its own.
    var appName: String {
        switch self {
        case .home, .explorer: return name
        case .taxes: return "Tax Desk"
        default: return name + " Clone"
        }
    }

    var blurb: String {
        switch self {
        case .home: return ""
        case .photos: return "Your iCloud Photos download from privacy.apple.com: library, albums, memories, hidden photos and Live Photos."
        case .snapchat: return "Snapchat's My Data: Memories, My Eyes Only, and your chats with their snaps and voice notes."
        case .instagram: return "Instagram's HTML download: your direct messages with photos, videos, reactions and voice notes."
        case .whatsapp: return "WhatsApp's “Export Chat” zips, with photos, stickers, voice notes and documents."
        case .amazon: return "Amazon's “Request Your Data”: orders, spending, Prime Video history and every other file they sent."
        case .taxes: return "Import slips, receipts and past returns (PDFs, photos or iPhone scans), read them on this Mac, add them up and fill the CRA forms or a UsTaxes file: a draft for your tax preparer."
        case .explorer: return "Any other export — Google, Facebook, TikTok, Spotify… Browse its CSV, JSON and HTML files, and search inside all of them."
        }
    }

    /// Name of the icon resource the hub bundles for this app.
    var iconName: String? {
        switch self {
        case .photos: return "PhotosIcon"
        case .snapchat: return "SnapchatIcon"
        case .instagram: return "InstagramIcon"
        case .whatsapp: return "WhatsAppIcon"
        case .amazon: return "AmazonIcon"
        case .taxes: return "TaxesIcon"
        default: return nil
        }
    }

    var symbol: String {
        switch self {
        case .home: return "square.grid.2x2.fill"
        case .photos: return "photo.on.rectangle"
        case .snapchat: return "bolt.fill"
        case .instagram: return "camera"
        case .whatsapp: return "phone.bubble"
        case .amazon: return "shippingbox"
        case .taxes: return "doc.text.magnifyingglass"
        case .explorer: return "doc.text.magnifyingglass"
        }
    }

    /// The folder the app last opened, read from its settings (shared with the standalone app).
    @MainActor var savedFolder: String? {
        let (suite, key): (String, String)
        switch self {
        case .photos: (suite, key) = ("com.regainyourdata.shared.photos", "exportRoot")
        case .snapchat: (suite, key) = ("com.regainyourdata.shared.snapchat", "root")
        case .instagram: (suite, key) = ("com.regainyourdata.shared.instagram", "root")
        case .whatsapp: (suite, key) = ("com.regainyourdata.shared.whatsapp", "root")
        case .amazon: (suite, key) = ("com.regainyourdata.shared.amazon", "root")
        case .taxes: return nil
        case .explorer: return Hub.shared.explorerRoot?.path
        case .home: return nil
        }
        return UserDefaults(suiteName: suite)?.string(forKey: key)
    }

    static let apps: [Source] = [.photos, .snapchat, .instagram, .whatsapp, .amazon, .taxes]
}

/// Companies whose exports don't have their own view yet. Explorer opens them meanwhile.
struct Upcoming: Identifiable {
    let name: String
    let symbol: String
    let request: String
    let how: String
    var id: String { name }

    static let all: [Upcoming] = [
        Upcoming(name: "Facebook", symbol: "person.2.fill", request: "https://accounts.facebook.com/download_your_information", how: "Accounts Center › Your information › Download your information"),
        Upcoming(name: "Google", symbol: "g.circle.fill", request: "https://takeout.google.com", how: "Google Takeout: pick the products, choose .zip"),
        Upcoming(name: "TikTok", symbol: "music.note", request: "https://www.tiktok.com/setting/download-your-data", how: "Settings › Account › Download your data (choose JSON)"),
        Upcoming(name: "X / Twitter", symbol: "xmark", request: "https://x.com/settings/download_your_data", how: "Settings › Your account › Download an archive"),
        Upcoming(name: "Spotify", symbol: "waveform", request: "https://www.spotify.com/account/privacy/", how: "Account › Privacy › Download your data"),
        Upcoming(name: "Netflix", symbol: "tv", request: "https://www.netflix.com/account/getmyinfo", how: "Account › Security & privacy › Personal information"),
        Upcoming(name: "Discord", symbol: "bubble.left.and.bubble.right.fill", request: "https://support.discord.com/hc/articles/360004027692", how: "Settings › Data & Privacy › Request all of my data"),
        Upcoming(name: "LinkedIn", symbol: "briefcase.fill", request: "https://www.linkedin.com/mypreferences/d/download-my-data", how: "Settings › Data privacy › Get a copy of your data"),
    ]
}

@MainActor @Observable
final class Hub {
    static let shared = Hub()

    var current: Source = Source(rawValue: UserDefaults.standard.string(forKey: "current") ?? "") ?? .home {
        didSet { UserDefaults.standard.set(current.rawValue, forKey: "current") }
    }

    // Explorer
    var explorerRoot: URL? = UserDefaults.standard.string(forKey: "explorerRoot").map { URL(fileURLWithPath: $0) }
    var explorerFiles: [DataFile] = []
    var explorerLoading = false
    var recents: [String] = UserDefaults.standard.stringArray(forKey: "explorerRecents") ?? []

    init() {
        if let r = explorerRoot, FileManager.default.fileExists(atPath: r.path) { explore(r) }
    }

    func explore(_ url: URL) {
        explorerRoot = url
        explorerLoading = true
        UserDefaults.standard.set(url.path, forKey: "explorerRoot")
        recents = ([url.path] + recents.filter { $0 != url.path }).prefix(8).map { $0 }
        UserDefaults.standard.set(recents, forKey: "explorerRecents")
        Task {
            explorerFiles = await Task.detached(priority: .userInitiated) { DataScanner.scan(url) }.value
            explorerLoading = false
        }
    }

    func chooseExplorerFolder() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true
        p.canChooseFiles = true
        p.allowedContentTypes = [.zip, .folder]
        p.message = "Choose an export: a folder or a .zip. Nothing is unpacked or changed."
        if p.runModal() == .OK, let u = p.url {
            explore(u)
            current = .explorer
        }
    }

    static func icon(_ s: Source) -> NSImage? { s.iconName.flatMap { NSImage(named: $0) } }
}
