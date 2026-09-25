import RegainCore
import SwiftUI

/// Amazon's colours.
enum AZ {
    static let navy = Color(hex: 0x131921)          // top bar
    static let navy2 = Color(hex: 0x232F3E)         // nav strip
    static let orange = Color(hex: 0xFF9900)
    static let searchButton = Color(hex: 0xFEBD69)
    static let yellow = Color(hex: 0xFFD814)        // "Buy it again"
    static let yellowBorder = Color(hex: 0xFCD200)
    static let link = Color(hex: 0x007185)
    static let text = Color(hex: 0x0F1111)
    static let secondary = Color(hex: 0x565959)
    static let border = Color(hex: 0xD5D9D9)
    static let cardHeader = Color(hex: 0xF0F2F2)
    static let page = Color.white
    static let homePage = Color(hex: 0xE3E6E6)
    static let price = Color(hex: 0xB12704)
    static let green = Color(hex: 0x067D62)
    // Prime Video
    static let pvBackground = Color(hex: 0x0F171E)
    static let pvCard = Color(hex: 0x1B2530)
    static let pvBlue = Color(hex: 0x1A98FF)
    static let pvSecondary = Color(hex: 0x8197A4)
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

public struct AmazonApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var store = AmazonStore.shared
    public init() {}

    public var body: some Scene {
        WindowGroup("Amazon Clone") {
            RootView().environment(store).frame(minWidth: 960, minHeight: 640).preferredColorScheme(.light)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) { Button("Open Amazon Data…") { chooseFolder(store) }.keyboardShortcut("o") }
            CommandMenu("Go") { AmazonModule.menuItems() }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ n: Notification) { NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true) }
    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ n: Notification) { DataFile.clearPreviewCache() }
}

@MainActor
func chooseFolder(_ store: AmazonStore) {
    let p = NSOpenPanel()
    p.canChooseDirectories = true
    p.canChooseFiles = false
    p.message = "Choose the folder with your Amazon data download (the zips like “Prime Video.zip” and FileDescriptions.csv)."
    if p.runModal() == .OK, let u = p.url { store.open(u) }
}

struct RootView: View {
    @Environment(AmazonStore.self) private var store
    var body: some View {
        switch store.phase {
        case .welcome: WelcomeView()
        case .loading(let m):
            VStack(spacing: 12) {
                ProgressView().controlSize(.large)
                Text(m).foregroundStyle(AZ.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity).background(AZ.page.ignoresSafeArea())
        case .ready:
            VStack(spacing: 0) {
                TopBar()
                Group {
                    switch store.tab {
                    case .home: HomeView()
                    case .orders: OrdersView()
                    case .spending: SpendingView()
                    case .video: PrimeVideoView()
                    case .data:
                        DataBrowser(files: store.export.files, initial: store.dataSelection)
                            .id(store.dataSelection ?? "")
                            .background(AZ.page)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .sheet(item: Binding(get: { store.openOrder }, set: { store.openOrder = $0 })) { OrderDetail(order: $0) }
            // The navy bar runs up under the window's title bar, as on amazon.com.
            .ignoresSafeArea(.container, edges: .top)
        }
    }
}

// MARK: Header

/// The "amazon" wordmark with its orange smile, drawn rather than copied.
struct LogoMark: View {
    var body: some View {
        VStack(spacing: -7) {
            Text("amazon").font(.system(size: 24, weight: .heavy)).foregroundStyle(.white).kerning(-0.8)
            Smile().stroke(AZ.orange, style: StrokeStyle(lineWidth: 2.6, lineCap: .round)).frame(width: 64, height: 12)
                .overlay(alignment: .topTrailing) {
                    Arrowhead().fill(AZ.orange).frame(width: 9, height: 8).offset(x: 2, y: -1)
                }
                .offset(x: 3)
        }
    }

    struct Smile: Shape {
        func path(in r: CGRect) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: r.minX, y: r.minY + 2))
            p.addQuadCurve(to: CGPoint(x: r.maxX - 3, y: r.minY + 3), control: CGPoint(x: r.midX, y: r.maxY + 6))
            return p
        }
    }

    struct Arrowhead: Shape {
        func path(in r: CGRect) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: r.minX, y: r.minY + 1))
            p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX - 1, y: r.maxY))
            p.closeSubpath()
            return p
        }
    }
}

struct TopBar: View {
    @Environment(AmazonStore.self) private var store
    var body: some View {
        @Bindable var store = store
        VStack(spacing: 0) {
            HStack(spacing: 18) {
                LogoMark()
                VStack(alignment: .leading, spacing: 0) {
                    Text("Your data").font(.system(size: 12)).foregroundStyle(Color(white: 0.8))
                    Text("from Amazon").font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                }
                HStack(spacing: 0) {
                    TextField("Search your orders", text: $store.query)
                        .textFieldStyle(.plain).foregroundStyle(AZ.text)
                        .padding(.horizontal, 10).frame(height: 38).background(.white)
                        .onSubmit { if store.tab != .orders { store.tab = .orders } }
                    Button { store.tab = .orders } label: {
                        Image(systemName: "magnifyingglass").font(.system(size: 17, weight: .semibold)).foregroundStyle(AZ.text)
                            .frame(width: 46, height: 38).background(AZ.searchButton)
                    }
                    .buttonStyle(.plain)
                }
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .frame(maxWidth: 640)
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Returns").font(.system(size: 12)).foregroundStyle(Color(white: 0.8))
                    Text("& Orders").font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                }
                .onTapGesture { store.tab = .orders }
            }
            .padding(.horizontal, 18).padding(.top, 30).padding(.bottom, 10)
            .background(AZ.navy)

            HStack(spacing: 2) {
                ForEach(AmazonStore.Tab.allCases) { t in
                    Button { store.tab = t } label: {
                        Label(t.rawValue, systemImage: t.symbol).labelStyle(.titleAndIcon)
                            .font(.system(size: 13, weight: store.tab == t ? .bold : .regular)).foregroundStyle(.white)
                            .padding(.horizontal, 9).frame(height: 30)
                            .overlay { if store.tab == t { RoundedRectangle(cornerRadius: 2).stroke(.white, lineWidth: 1) } }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Button { chooseFolder(store) } label: {
                    Label("Open another download", systemImage: "folder").font(.system(size: 12)).foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12).frame(height: 38)
            .background(AZ.navy2)
        }
    }
}

// MARK: Welcome

struct WelcomeView: View {
    @Environment(AmazonStore.self) private var store
    @State private var found: [URL] = []
    var body: some View {
        VStack(spacing: 18) {
            Image(nsImage: moduleIcon).resizable().frame(width: 120, height: 120)
            Text("Amazon Clone").font(.system(size: 30, weight: .bold)).foregroundStyle(AZ.text)
            Text("Your orders, spending and Prime Video history from Amazon's “Request Your Data” download, read straight from the zips. Nothing leaves this Mac.")
                .foregroundStyle(AZ.secondary).multilineTextAlignment(.center).frame(maxWidth: 460)
            ForEach(found, id: \.self) { u in
                Button { store.open(u) } label: {
                    HStack {
                        Image(systemName: "folder.fill").foregroundStyle(AZ.orange)
                        Text(u.path).lineLimit(1).truncationMode(.middle).foregroundStyle(AZ.text)
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(AZ.secondary)
                    }
                    .padding(12).frame(width: 480)
                    .background(.white, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(AZ.border))
                }
                .buttonStyle(.plain)
            }
            Button { chooseFolder(store) } label: {
                Text("Choose Folder…").font(.system(size: 14, weight: .medium)).foregroundStyle(AZ.text)
                    .padding(.horizontal, 22).padding(.vertical, 8)
                    .background(AZ.yellow, in: Capsule()).overlay(Capsule().stroke(AZ.yellowBorder))
            }
            .buttonStyle(.plain)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AZ.homePage.ignoresSafeArea())
        .task { found = await Task.detached { AmazonFinder.suggestedRoots() }.value }
    }
}

enum AmazonFinder {
    /// Folders on this Mac that look like an Amazon download: a FileDescriptions.csv, or zips with
    /// Amazon's part names.
    static func suggestedRoots() -> [URL] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        var bases = ["Desktop", "Downloads", "Documents"].map { home.appendingPathComponent($0).resolvingSymlinksInPath() }
        if let vols = try? fm.contentsOfDirectory(at: URL(fileURLWithPath: "/Volumes"), includingPropertiesForKeys: nil) { bases += vols }
        let parts: Set<String> = ["prime video.zip", "your orders.zip", "your amazon orders.zip", "digital content.zip", "kindle.zip", "audible.zip", "alexa.zip"]
        var found = Set<URL>()
        for base in bases {
            let e = fm.enumerator(at: base, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles, .skipsPackageDescendants])
            while let u = e?.nextObject() as? URL {
                if e!.level > 4 { e?.skipDescendants(); continue }
                let n = u.lastPathComponent.lowercased()
                if n == "filedescriptions.csv" || parts.contains(n) || (n.hasPrefix("retail.") && n.hasSuffix(".zip")) {
                    found.insert(u.deletingLastPathComponent())
                }
            }
        }
        return found.sorted { $0.path < $1.path }
    }
}

// MARK: Home

struct HomeView: View {
    @Environment(AmazonStore.self) private var store
    var body: some View {
        let x = store.export
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Hello — here's what Amazon sent you").font(.system(size: 26, weight: .bold)).foregroundStyle(AZ.text)
                    .padding(.top, 8)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280, maximum: 420), spacing: 18, alignment: .top)], alignment: .leading, spacing: 18) {
                    Card(title: "Your Orders", link: x.orders.isEmpty ? nil : "See all orders", tab: .orders) {
                        if x.orders.isEmpty {
                            Missing(text: "Your order history isn't in this download yet. Amazon sends a data request in several parts; put each part in the same folder as it arrives and reopen it.")
                        } else {
                            Stat(value: "\(x.orders.count)", label: "orders")
                            Stat(value: store.money(x.orders.filter { !$0.isCancelled }.map(\.total).reduce(0, +)), label: "spent in total")
                            if let first = x.orders.last?.date { Stat(value: first.formatted(.dateTime.year()), label: "first order") }
                            Divider()
                            ForEach(x.orders.prefix(4)) { o in
                                Text(o.items.first?.name ?? o.id).font(.system(size: 13)).foregroundStyle(AZ.link).lineLimit(1)
                            }
                        }
                    }
                    Card(title: "Prime Video", link: x.viewing.isEmpty ? nil : "See your watching", tab: .video) {
                        let w = x.viewing.filter(\.isWatch)
                        if w.isEmpty {
                            Missing(text: "No Prime Video history in this download.")
                        } else {
                            Stat(value: "\(Int(w.map(\.seconds).reduce(0, +) / 3600)) h", label: "watched")
                            Stat(value: "\(Set(w.compactMap(\.show)).count)", label: "shows")
                            Stat(value: "\(Set(w.filter { $0.show == nil }.map(\.title)).count)", label: "films and other titles")
                            if let top = Dictionary(grouping: w, by: \.work).max(by: { $0.value.map(\.seconds).reduce(0, +) < $1.value.map(\.seconds).reduce(0, +) }) {
                                Divider()
                                Text("Most watched").font(.system(size: 12)).foregroundStyle(AZ.secondary)
                                Text(top.key).font(.system(size: 15, weight: .semibold)).foregroundStyle(AZ.text).lineLimit(2)
                            }
                        }
                    }
                    Card(title: "Spending", link: x.orders.isEmpty ? nil : "See spending", tab: .spending) {
                        if x.orders.isEmpty {
                            Missing(text: "Spending appears once your order history arrives.")
                        } else {
                            let byYear = Dictionary(grouping: x.orders.filter { !$0.isCancelled }, by: { Calendar.current.component(.year, from: $0.date) }).mapValues { $0.map(\.total).reduce(0, +) }
                            ForEach(byYear.keys.sorted(by: >).prefix(5), id: \.self) { y in
                                HStack { Text(String(y)).foregroundStyle(AZ.secondary); Spacer(); Text(store.money(byYear[y])).foregroundStyle(AZ.text).monospacedDigit() }
                                    .font(.system(size: 14))
                            }
                            if !x.refunds.isEmpty {
                                Divider()
                                Stat(value: store.money(x.refunds.compactMap(\.amount).reduce(0, +)), label: "refunded")
                            }
                        }
                    }
                    Card(title: "Everything in your download", link: "Browse all files", tab: .data) {
                        Stat(value: "\(x.files.count)", label: "files in \(x.groups.count) part\(x.groups.count == 1 ? "" : "s")")
                        Divider()
                        ForEach(x.groups, id: \.self) { g in
                            HStack {
                                Image(systemName: "archivebox").foregroundStyle(AZ.secondary)
                                Text(g).foregroundStyle(AZ.text)
                                Spacer()
                                Text(filesText(x.files.filter { $0.group == g }.count)).foregroundStyle(AZ.secondary)
                            }
                            .font(.system(size: 13))
                        }
                    }
                    if !x.digital.isEmpty {
                        Card(title: "Digital purchases", link: "Browse the files", tab: .data) {
                            Stat(value: "\(x.digital.count)", label: "Kindle books, apps, music and video")
                            ForEach(x.digital.prefix(4)) { d in Text(d.title).font(.system(size: 13)).foregroundStyle(AZ.link).lineLimit(1) }
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 1400, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(
            VStack(spacing: 0) {
                LinearGradient(colors: [Color(hex: 0xA8DADC).opacity(0.55), AZ.homePage], startPoint: .top, endPoint: .bottom).frame(height: 260)
                AZ.homePage
            }
        )
    }
}

/// A white homepage card with a bold title and a "See more"-style link at the bottom.
struct Card<Content: View>: View {
    @Environment(AmazonStore.self) private var store
    let title: String
    var link: String?
    var tab: AmazonStore.Tab = .home
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 20, weight: .bold)).foregroundStyle(AZ.text)
            content
            Spacer(minLength: 0)
            if let link {
                Button(link) { store.tab = tab }.buttonStyle(.plain).font(.system(size: 13)).foregroundStyle(AZ.link)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 300, alignment: .topLeading)
        .background(.white)
    }
}

struct Stat: View {
    let value: String
    let label: String
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(value).font(.system(size: 22, weight: .semibold)).foregroundStyle(AZ.text).monospacedDigit()
            Text(label).font(.system(size: 13)).foregroundStyle(AZ.secondary)
        }
    }
}

struct Missing: View {
    let text: String
    var body: some View {
        Label(text, systemImage: "clock.arrow.circlepath").font(.system(size: 13)).foregroundStyle(AZ.secondary)
    }
}

func filesText(_ n: Int) -> String { n == 1 ? "1 file" : "\(n) files" }
