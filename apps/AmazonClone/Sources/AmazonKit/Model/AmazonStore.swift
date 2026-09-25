import Foundation
import Observation
import RegainCore

@MainActor @Observable
final class AmazonStore {
    static let shared = AmazonStore()

    enum Phase: Equatable { case welcome, loading(String), ready }
    enum Tab: String, CaseIterable, Identifiable {
        case home = "Home", orders = "Your Orders", spending = "Spending", video = "Prime Video", data = "All Data"
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .home: return "house"
            case .orders: return "shippingbox"
            case .spending: return "chart.bar"
            case .video: return "play.tv"
            case .data: return "tablecells"
            }
        }
    }

    var phase: Phase = .welcome
    var export = AmazonExport()
    var tab: Tab = .home
    var query = ""
    /// Year shown in Your Orders; nil is every year.
    var year: Int?
    var openOrder: Order?
    /// A file to show in All Data, when another tab links to it.
    var dataSelection: DataFile.ID?

    var root: URL? {
        get { Prefs.defaults.string(forKey: "root").map { URL(fileURLWithPath: $0) } }
        set { Prefs.defaults.set(newValue?.path, forKey: "root") }
    }

    init() {
        #if DEBUG
        // Development: open a sample export without touching the saved folder.
        if let t = ProcessInfo.processInfo.environment["AMAZON_TAB"].flatMap(Tab.init(rawValue:)) { tab = t }
        if let sample = ProcessInfo.processInfo.environment["AMAZON_ROOT"] { open(URL(fileURLWithPath: sample), remember: false); return }
        #endif
        if let r = root, FileManager.default.fileExists(atPath: r.path) { open(r) }
    }

    func open(_ url: URL, remember: Bool = true) {
        if remember { root = url }
        phase = .loading("Opening your Amazon data…")
        Task {
            let x = await Task.detached(priority: .userInitiated) {
                AmazonLoader.load(url) { msg in Task { @MainActor in AmazonStore.shared.progress(msg) } }
            }.value
            export = x
            if year == nil || !years.contains(year!) { year = nil }
            phase = .ready
        }
    }

    private func progress(_ m: String) { if case .loading = phase { phase = .loading(m) } }

    var years: [Int] {
        Array(Set(export.orders.map { Calendar.current.component(.year, from: $0.date) })).filter { $0 > 1990 }.sorted(by: >)
    }

    var shownOrders: [Order] {
        let q = query.lowercased()
        return export.orders.filter { o in
            (year == nil || Calendar.current.component(.year, from: o.date) == year) &&
            (q.isEmpty || o.id.lowercased().contains(q) || o.items.contains { $0.name.lowercased().contains(q) || $0.asin.lowercased() == q })
        }
    }

    func money(_ v: Double?, _ currency: String? = nil) -> String {
        guard let v else { return "—" }
        return v.formatted(.currency(code: (currency?.isEmpty == false ? currency! : export.currency)))
    }

    /// Opens a product page on Amazon in the browser; nothing is fetched by the app itself.
    func openProduct(_ asin: String, host: String = "www.amazon.com") {
        guard !asin.isEmpty, let u = URL(string: "https://\(host)/dp/\(asin)") else { return }
        NSWorkspaceOpen.open(u)
    }
}
