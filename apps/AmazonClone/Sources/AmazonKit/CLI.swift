import Foundation

/// `AmazonVault --check <folder>` prints what was recognised (counts only, no contents).
public enum AmazonCLI {
    public static func run() throws {
        guard let i = CommandLine.arguments.firstIndex(of: "--check"), i + 1 < CommandLine.arguments.count else { return }
        let t0 = Date()
        let x = AmazonLoader.load(URL(fileURLWithPath: CommandLine.arguments[i + 1]))
        let watched = x.viewing.filter(\.isWatch)
        let span = watched.map(\.start)
        print("""
        files \(x.files.count) in \(x.groups.count) parts, with descriptions: \(x.files.filter { $0.summary != nil }.count)
        orders \(x.orders.count), items \(x.orders.map(\.items.count).reduce(0, +)), undated \(x.orders.filter { $0.date == .distantPast }.count), without a total \(x.orders.filter { $0.total == 0 }.count)
        refunds \(x.refunds.count), digital \(x.digital.count)
        prime video: playbacks \(x.viewing.count) (watched \(watched.count), promos/trailers \(x.viewing.count - watched.count)), episodes of shows \(watched.filter { $0.show != nil }.count), shows \(Set(watched.compactMap(\.show)).count), films/other \(Set(watched.filter { $0.show == nil }.map(\.title)).count)
          hours watched \(Int(watched.map(\.seconds).reduce(0, +) / 3600)), span \(span.min()?.formatted(date: .abbreviated, time: .omitted) ?? "-") – \(span.max()?.formatted(date: .abbreviated, time: .omitted) ?? "-")
          searches \(x.videoSearches.count), purchases/rentals \(x.videoPurchases.count), devices \(Set(x.viewing.map(\.device)).count)
        loaded in \(String(format: "%.2f", Date().timeIntervalSince(t0)))s
        """)
        exit(0)
    }
}
