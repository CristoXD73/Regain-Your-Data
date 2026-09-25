import Foundation
import RegainCore

/// Amazon's "Request Your Data" download. Amazon sends it in parts, one zip per area, each with
/// "Your …" folders of CSVs and a FileDescriptions.csv that explains every file:
///
///   Prime Video.zip
///     Your Prime Video Viewing Activity/Viewing History.csv   one row per playback
///     Your Prime Video Viewing Activity/Search History.csv
///     Your Prime Video Library & Purchases/Purchases and Rentals.csv
///   Your Orders.zip (older exports: Retail.OrderHistory.1/Retail.OrderHistory.1.csv)
///     Order History.csv          one row per item shipped: Order ID, Order Date, Product Name,
///                                ASIN, Quantity, Unit Price, Total Owed / Total Amount …
///     Refund Details.csv, Digital Content Orders.csv …
///
/// Column names moved between versions ("Total Owed" became "Total Amount", "Quantity" became
/// "Original Quantity"), so columns are looked up by any of their known names. Whatever isn't
/// recognised is still shown in All Data.
struct AmazonExport: Sendable {
    var files: [DataFile] = []
    var orders: [Order] = []
    var refunds: [Refund] = []
    var digital: [DigitalPurchase] = []
    var viewing: [Viewing] = []
    var videoSearches: [VideoSearch] = []
    var videoPurchases: [VideoPurchase] = []

    var groups: [String] { Array(Set(files.map(\.group))).sorted() }
    var currency: String {
        let all = orders.map(\.currency).filter { !$0.isEmpty }
        return Dictionary(grouping: all, by: { $0 }).max { $0.value.count < $1.value.count }?.key ?? "USD"
    }
}

struct OrderItem: Identifiable, Hashable, Sendable {
    let id: Int
    var name: String
    var asin: String
    var quantity: Int
    var unitPrice: Double?
    var total: Double?
    var status: String
    var shipDate: Date?
    var carrier: String
    var condition: String
    var giftMessage: String
}

struct Order: Identifiable, Hashable, Sendable {
    let id: String
    var date: Date
    var currency: String
    var website: String
    var status: String
    var shipTo: String
    var billing: String
    var payment: String
    var shippingOption: String
    var items: [OrderItem]

    var total: Double { items.compactMap { i in i.total ?? i.unitPrice.map { $0 * Double(i.quantity) } }.reduce(0, +) }
    var itemCount: Int { items.map(\.quantity).reduce(0, +) }
    /// The first line of the shipping address, which is the recipient's name.
    var recipient: String { shipTo.components(separatedBy: CharacterSet(charactersIn: "\n,")).first?.trimmingCharacters(in: .whitespaces) ?? "" }
    var isCancelled: Bool { status.lowercased().contains("cancel") }
    /// amazon.com, amazon.co.uk … from the Website column, for links to a product page.
    var host: String {
        let w = website.lowercased()
        if let r = w.range(of: #"amazon\.[a-z.]+"#, options: .regularExpression) { return "www." + w[r] }
        return "www.amazon.com"
    }
}

struct Refund: Identifiable, Hashable, Sendable {
    let id: Int
    var orderID: String
    var date: Date?
    var amount: Double?
    var currency: String
    var reason: String
    var status: String
}

struct DigitalPurchase: Identifiable, Hashable, Sendable {
    let id: Int
    var title: String
    var orderID: String
    var date: Date?
    var price: Double?
    var currency: String
    var kind: String
}

struct Viewing: Identifiable, Hashable, Sendable {
    enum Kind: String, Sendable { case full = "Full", live = "Live", promo = "Promo", trailer = "Trailer", other = "Other" }
    let id: Int
    var title: String
    var show: String?
    var season: Int?
    var episode: String?
    var start: Date
    var end: Date?
    var seconds: Double
    var device: String
    var kind: Kind
    var deleted: Bool

    var isWatch: Bool { kind == .full || kind == .live }
    /// What to group by: the show for episodes, the title for films.
    var work: String { show ?? title }
}

struct VideoSearch: Identifiable, Hashable, Sendable {
    let id: Int
    var query: String
    var date: Date?
    var device: String
}

struct VideoPurchase: Identifiable, Hashable, Sendable {
    let id: Int
    var title: String
    var offer: String
    var quality: String
    var date: Date?
    var expires: Date?
}

enum AmazonLoader {
    static func load(_ root: URL, progress: @Sendable (String) -> Void = { _ in }) -> AmazonExport {
        progress("Finding your Amazon files…")
        var x = AmazonExport()
        x.files = DataScanner.scan(root)
        var n = 0
        func next() -> Int { n += 1; return n }

        // Rows repeated in several parts (Retail.OrderHistory.1, .2 …) are counted once.
        var orderRows: [String: (count: Int, row: [String], table: Int)] = [:]
        var orderTables: [CSVTable] = []
        for f in x.files where f.kind == .table {
            let lower = f.name.lowercased()
            let isOrders = lower == "order history.csv" || lower.hasPrefix("retail.orderhistory")
            let isRefunds = lower == "refund details.csv" || lower.hasPrefix("retail.ordersreturned") || lower.hasPrefix("retail.customerreturns")
            let isDigital = lower == "digital content orders.csv" || lower == "digital items.csv" || lower.hasPrefix("digital orders")
            let isVideo = f.group.lowercased().contains("video") || f.folder.lowercased().contains("prime video")
            let isViewing = lower == "viewing history.csv" && isVideo
            let isVideoSearch = lower == "search history.csv" && isVideo
            let isVideoBuys = lower == "purchases and rentals.csv" && isVideo
            guard isOrders || isRefunds || isDigital || isViewing || isVideoSearch || isVideoBuys else { continue }
            progress("Reading \(f.name)…")
            guard let t = try? f.table() else { continue }

            if isOrders, t.column("Order ID") != nil {
                var seen: [String: Int] = [:]
                for r in t.rows {
                    let key = r.joined(separator: "\u{1F}")
                    seen[key, default: 0] += 1
                    let c = seen[key]!
                    if (orderRows[key]?.count ?? 0) < c { orderRows[key] = (c, r, orderTables.count) }
                }
                orderTables.append(t)
            } else if isRefunds {
                let oid = t.column("Order ID", "OrderID"), date = t.column("Refund Date", "RefundCompletionDate", "Return Date", "Creation Date", "Date")
                let amt = t.column("Refund Amount", "AmountRefunded", "Amount"), cur = t.column("Currency", "Base Currency Code")
                let reason = t.column("Reversal Reason", "Return Reason", "Reason", "Disbursement Type"), status = t.column("Status", "Payment Status", "Refund Status")
                for r in t.rows {
                    x.refunds.append(Refund(id: next(), orderID: r[safe: oid], date: Parse.date(r[safe: date]), amount: Parse.money(r[safe: amt]),
                                            currency: r[safe: cur], reason: Parse.text(r[safe: reason]) ?? "", status: r[safe: status]))
                }
            } else if isDigital {
                let title = t.column("Title", "Product Name", "Item Name"), oid = t.column("Order ID", "OrderId")
                let date = t.column("Order Date", "OrderDate", "Fulfilled Date"), price = t.column("Our Price", "OurPrice", "Transaction Amount", "Price", "List Price")
                let cur = t.column("Currency", "Our Price Currency Code", "OurPriceCurrencyCode", "Base Currency Code"), kind = t.column("Product Name", "Digital Order Item Type", "Order Type", "Marketplace")
                guard title != nil else { continue }
                for r in t.rows where !r[safe: title].isEmpty {
                    x.digital.append(DigitalPurchase(id: next(), title: r[safe: title], orderID: r[safe: oid], date: Parse.date(r[safe: date]),
                                                     price: Parse.money(r[safe: price]), currency: r[safe: cur], kind: kind == title ? "" : r[safe: kind]))
                }
            } else if isViewing {
                let title = t.column("Title"), start = t.column("Playback Start Datetime (UTC)", "Playback Start Datetime"), end = t.column("Playback End Datetime (UTC)")
                let secs = t.column("Seconds Viewed"), type = t.column("Material Type Description"), del = t.column("Is Deleted")
                let make = t.column("Device Manufacturer Name"), model = t.column("Device Model"), amz = t.column("Amazon Device Model Name")
                for r in t.rows {
                    guard let s = Parse.date(r[safe: start]) else { continue }
                    let device = Parse.text(r[safe: amz]) ?? [r[safe: make], r[safe: model]].compactMap(Parse.text).joined(separator: " ")
                    x.viewing.append(Viewing(id: next(), title: r[safe: title], show: nil, season: nil, episode: nil,
                                             start: s, end: Parse.date(r[safe: end]), seconds: Parse.number(r[safe: secs]) ?? 0, device: device,
                                             kind: Viewing.Kind(rawValue: r[safe: type]) ?? .other, deleted: Parse.bool(r[safe: del])))
                }
            } else if isVideoSearch {
                let q = t.column("Search Query from Customer", "Search Query"), d = t.column("Search Request Date"), dev = t.column("Device Name", "Device App Group")
                for r in t.rows where !r[safe: q].isEmpty {
                    x.videoSearches.append(VideoSearch(id: next(), query: r[safe: q], date: Parse.date(r[safe: d]), device: r[safe: dev]))
                }
            } else if isVideoBuys {
                let title = t.column("Title"), offer = t.column("Offer Type"), q = t.column("Quality"), d = t.column("Grant Time", "Origin Time"), exp = t.column("Rental Expiry Time")
                for r in t.rows {
                    x.videoPurchases.append(VideoPurchase(id: next(), title: r[safe: title], offer: r[safe: offer].capitalized, quality: r[safe: q],
                                                          date: Parse.date(r[safe: d]), expires: Parse.date(r[safe: exp])))
                }
            }
        }

        // Orders: one row per item, grouped by Order ID. Each row is read with its own file's
        // columns, since older and newer parts name them differently.
        if !orderTables.isEmpty {
            let columns = orderTables.map(OrderColumns.init)
            var byID: [String: Order] = [:]
            for (count, r, ti) in orderRows.values { for _ in 0..<count {
                let c = columns[ti]
                let id = r[safe: c.id]
                guard !id.isEmpty else { continue }
                let item = OrderItem(id: next(), name: r[safe: c.name], asin: r[safe: c.asin],
                                     quantity: Int(Parse.number(r[safe: c.qty]) ?? 1), unitPrice: Parse.money(r[safe: c.unit]),
                                     total: Parse.money(r[safe: c.total]), status: Parse.text(r[safe: c.shipStatus]) ?? "",
                                     shipDate: Parse.date(r[safe: c.shipDate]), carrier: Parse.text(r[safe: c.carrier]) ?? "",
                                     condition: Parse.text(r[safe: c.condition]) ?? "", giftMessage: Parse.text(r[safe: c.gift]) ?? "")
                let date = Parse.date(r[safe: c.date]) ?? .distantPast
                if var o = byID[id] {
                    o.items.append(item)
                    o.date = min(o.date, date)
                    byID[id] = o
                } else {
                    byID[id] = Order(id: id, date: date, currency: r[safe: c.currency], website: r[safe: c.website], status: r[safe: c.status],
                                     shipTo: Parse.text(r[safe: c.shipTo]) ?? "", billing: Parse.text(r[safe: c.billing]) ?? "",
                                     payment: Parse.text(r[safe: c.payment]) ?? "", shippingOption: Parse.text(r[safe: c.option]) ?? "", items: [item])
                }
            } }
            x.orders = byID.values.sorted { ($0.date, $0.id) > ($1.date, $1.id) }
        }
        assignShows(&x.viewing)
        x.viewing.sort { $0.start > $1.start }
        x.videoSearches.sort { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        x.videoPurchases.sort { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        x.refunds.sort { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        x.digital.sort { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        return x
    }

    struct OrderColumns {
        let id, date, name, asin, qty, unit, total, currency, website, status, shipStatus, shipDate, carrier, shipTo, billing, payment, option, condition, gift: Int?
        init(_ t: CSVTable) {
            id = t.column("Order ID"); date = t.column("Order Date"); name = t.column("Product Name", "Title")
            asin = t.column("ASIN", "ASIN/ISBN"); qty = t.column("Original Quantity", "Quantity")
            unit = t.column("Unit Price", "Purchase Price Per Unit"); total = t.column("Total Owed", "Total Amount", "Item Total")
            currency = t.column("Currency"); website = t.column("Website"); status = t.column("Order Status")
            shipStatus = t.column("Shipment Status"); shipDate = t.column("Ship Date", "Shipment Date")
            carrier = t.column("Carrier Name & Tracking Number", "Carrier Name And Tracking Number")
            shipTo = t.column("Shipping Address", "Shipping Address Name"); billing = t.column("Billing Address")
            payment = t.column("Payment Instrument Type", "Payment Method Type", "Payment Method"); option = t.column("Shipping Option")
            condition = t.column("Product Condition", "Condition"); gift = t.column("Gift Message")
        }
    }

    /// Prime Video names an episode "<episode>-<show> - Season 2" (the joint is sometimes " - ",
    /// " – " or ": "), and a film by its title alone. Film titles have hyphens and colons too, so
    /// a split only counts when the part after it is shared by several different titles: that
    /// part is a show. Titles ending in "Season N" with no shared part are the show themselves.
    static func assignShows(_ plays: inout [Viewing]) {
        let seasonSuffix = try! NSRegularExpression(pattern: #"\s*[-:–]?\s*Season (\d+)\s*$"#)
        let joint = try! NSRegularExpression(pattern: #"(?<=\w)-(?=\w)| - | – |: "#)
        func split(_ t: String) -> (base: String, season: Int?, cuts: [(episode: String, show: String)]) {
            let ns = t as NSString
            var base = t, season: Int?
            if let m = seasonSuffix.firstMatch(in: t, range: NSRange(location: 0, length: ns.length)) {
                base = ns.substring(to: m.range.location)
                season = Int(ns.substring(with: m.range(at: 1)))
            }
            let nb = base as NSString
            let cuts = joint.matches(in: base, range: NSRange(location: 0, length: nb.length)).map {
                (nb.substring(to: $0.range.location).trimmingCharacters(in: .whitespaces),
                 nb.substring(from: $0.range.location + $0.range.length).trimmingCharacters(in: .whitespaces))
            }.filter { !$0.1.isEmpty && !$0.0.isEmpty }
            return (base, season, cuts)
        }
        let titles = Set(plays.map(\.title))
        let parts = Dictionary(uniqueKeysWithValues: titles.map { ($0, split($0)) })
        var shared: [String: Int] = [:]
        for (_, p) in parts { for show in Set(p.cuts.map(\.show)) { shared[show, default: 0] += 1 } }
        var result: [String: (show: String?, season: Int?, episode: String?)] = [:]
        for (t, p) in parts {
            if let best = p.cuts.max(by: { shared[$0.show, default: 0] < shared[$1.show, default: 0] }), shared[best.show, default: 0] >= 2 {
                result[t] = (best.show, p.season, best.episode)
            } else if p.season != nil {
                result[t] = (p.base.trimmingCharacters(in: .whitespaces), p.season, nil)
            } else {
                result[t] = (nil, nil, nil)
            }
        }
        for i in plays.indices {
            let r = result[plays[i].title]!
            plays[i].show = r.show
            plays[i].season = r.season
            plays[i].episode = r.episode
        }
    }
}
