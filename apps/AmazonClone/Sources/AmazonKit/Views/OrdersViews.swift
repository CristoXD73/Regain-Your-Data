import Charts
import SwiftUI

/// "Your Orders": one card per order with Amazon's grey summary strip on top.
struct OrdersView: View {
    @Environment(AmazonStore.self) private var store
    var body: some View {
        @Bindable var store = store
        let orders = store.shownOrders
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Your Orders").font(.system(size: 28)).foregroundStyle(AZ.text)
                if store.export.orders.isEmpty {
                    NoOrders()
                } else {
                    HStack(spacing: 8) {
                        Text("\(orders.count) order\(orders.count == 1 ? "" : "s")").bold()
                        Text("placed in")
                        Picker("", selection: $store.year) {
                            Text("all years").tag(Int?.none)
                            ForEach(store.years, id: \.self) { Text(String($0)).tag(Int?.some($0)) }
                        }
                        .labelsHidden().fixedSize()
                        if !store.query.isEmpty {
                            Text("matching “\(store.query)”").foregroundStyle(AZ.secondary)
                            Button("Clear") { store.query = "" }.buttonStyle(.link)
                        }
                    }
                    .font(.system(size: 14)).foregroundStyle(AZ.text)
                    LazyVStack(spacing: 18) {
                        ForEach(orders) { OrderCard(order: $0) }
                    }
                }
            }
            .padding(.horizontal, 24).padding(.vertical, 20)
            .frame(maxWidth: 1000, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(AZ.page)
    }
}

struct NoOrders: View {
    @Environment(AmazonStore.self) private var store
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Your order history hasn't arrived yet", systemImage: "shippingbox").font(.system(size: 17, weight: .semibold)).foregroundStyle(AZ.text)
            Text("Amazon delivers a data request in parts. This download has \(store.export.groups.joined(separator: ", ")). When the part with your orders arrives (it's called “Your Orders” or holds “Order History.csv”), put it in the same folder and open the folder again.")
                .foregroundStyle(AZ.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Open Folder Again") { if let r = store.root { store.open(r) } }
                Button("Browse What's Here") { store.tab = .data }
            }
        }
        .padding(20)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AZ.border))
    }
}

struct OrderCard: View {
    @Environment(AmazonStore.self) private var store
    let order: Order

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 36) {
                field("ORDER PLACED", order.date == .distantPast ? "—" : order.date.formatted(date: .long, time: .omitted))
                field("TOTAL", store.money(order.total, order.currency))
                if !order.recipient.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("SHIP TO").font(.system(size: 11)).foregroundStyle(AZ.secondary)
                        Text(order.recipient).font(.system(size: 13)).foregroundStyle(AZ.link).help(order.shipTo)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("ORDER # \(order.id)").font(.system(size: 11)).foregroundStyle(AZ.secondary).textSelection(.enabled)
                    Button("View order details") { store.openOrder = order }.buttonStyle(.plain).font(.system(size: 13)).foregroundStyle(AZ.link)
                }
            }
            .padding(.horizontal, 18).padding(.vertical, 12)
            .background(AZ.cardHeader)

            VStack(alignment: .leading, spacing: 14) {
                Text(headline).font(.system(size: 17, weight: .bold)).foregroundStyle(order.isCancelled ? AZ.price : AZ.text)
                ForEach(order.items) { item in
                    HStack(alignment: .top, spacing: 16) {
                        ProductImage()
                        VStack(alignment: .leading, spacing: 5) {
                            Button { store.openProduct(item.asin, host: order.host) } label: {
                                Text(item.name.isEmpty ? "Item \(item.asin)" : item.name).multilineTextAlignment(.leading)
                                    .font(.system(size: 14)).foregroundStyle(AZ.link).lineLimit(3)
                            }
                            .buttonStyle(.plain).help("Open this product on Amazon in your browser")
                            HStack(spacing: 10) {
                                if item.quantity > 1 { Text("Qty: \(item.quantity)") }
                                if let p = item.unitPrice { Text(store.money(p, order.currency)).foregroundStyle(AZ.price) }
                                if !item.condition.isEmpty && item.condition.lowercased() != "new" { Text(item.condition) }
                            }
                            .font(.system(size: 12)).foregroundStyle(AZ.secondary)
                            if !item.asin.isEmpty {
                                HStack(spacing: 8) {
                                    Button { store.openProduct(item.asin, host: order.host) } label: {
                                        Label("Buy it again", systemImage: "arrow.clockwise").font(.system(size: 12)).foregroundStyle(AZ.text)
                                            .padding(.horizontal, 12).padding(.vertical, 5)
                                            .background(AZ.yellow, in: Capsule()).overlay(Capsule().stroke(AZ.yellowBorder))
                                    }
                                    Button { store.openProduct(item.asin, host: order.host) } label: {
                                        Text("View your item").font(.system(size: 12)).foregroundStyle(AZ.text)
                                            .padding(.horizontal, 12).padding(.vertical, 5)
                                            .background(.white, in: Capsule()).overlay(Capsule().stroke(AZ.border))
                                    }
                                }
                                .buttonStyle(.plain).padding(.top, 2)
                            }
                        }
                    }
                }
            }
            .padding(18)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AZ.border))
    }

    private var headline: String {
        if order.isCancelled { return "Cancelled" }
        let statuses = Set(order.items.map(\.status).filter { !$0.isEmpty })
        if let ship = order.items.compactMap(\.shipDate).max(), statuses.isEmpty || statuses == ["Shipped"] || statuses == ["Delivered"] {
            return "Shipped \(ship.formatted(date: .abbreviated, time: .omitted))"
        }
        return statuses.first ?? (order.status.isEmpty ? "Ordered" : order.status)
    }

    private func field(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 11)).foregroundStyle(AZ.secondary)
            Text(value).font(.system(size: 13)).foregroundStyle(AZ.text)
        }
    }
}

/// Product photos would have to come from Amazon's servers, so a plain box stands in.
struct ProductImage: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 4).fill(Color(hex: 0xF7F8F8))
            .frame(width: 90, height: 90)
            .overlay(Image(systemName: "shippingbox").font(.system(size: 30, weight: .light)).foregroundStyle(Color(hex: 0xC7CBCB)))
    }
}

struct OrderDetail: View {
    @Environment(AmazonStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let order: Order

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Order Details").font(.system(size: 22, weight: .bold))
                    Text("Ordered on \(order.date.formatted(date: .long, time: .shortened))  |  Order# \(order.id)").font(.system(size: 13)).foregroundStyle(AZ.secondary).textSelection(.enabled)
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(20)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top, spacing: 30) {
                        block("Shipping Address", order.shipTo)
                        block("Payment Method", order.payment)
                        block("Billing Address", order.billing)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Order Summary").font(.system(size: 14, weight: .bold))
                            HStack { Text("Items:"); Spacer(); Text("\(order.itemCount)") }
                            HStack { Text("Grand Total:").bold(); Spacer(); Text(store.money(order.total, order.currency)).bold().foregroundStyle(AZ.price) }
                            if !order.shippingOption.isEmpty { Text(order.shippingOption).foregroundStyle(AZ.secondary) }
                        }
                        .font(.system(size: 13)).frame(width: 200)
                    }
                    .padding(16).overlay(RoundedRectangle(cornerRadius: 8).stroke(AZ.border))

                    ForEach(order.items) { item in
                        HStack(alignment: .top, spacing: 14) {
                            ProductImage()
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.name).font(.system(size: 14)).foregroundStyle(AZ.link).textSelection(.enabled)
                                Group {
                                    if !item.asin.isEmpty { Text("ASIN: \(item.asin)") }
                                    Text("Quantity: \(item.quantity)")
                                    if let p = item.unitPrice { Text("Price: \(store.money(p, order.currency))") }
                                    if let t = item.total { Text("Item total, with tax: \(store.money(t, order.currency))") }
                                    if !item.status.isEmpty { Text("Status: \(item.status)") }
                                    if let d = item.shipDate { Text("Shipped: \(d.formatted(date: .long, time: .omitted))") }
                                    if !item.carrier.isEmpty { Text("Carrier: \(item.carrier)").textSelection(.enabled) }
                                    if !item.giftMessage.isEmpty { Text("Gift message: \(item.giftMessage)") }
                                }
                                .font(.system(size: 12)).foregroundStyle(AZ.secondary)
                            }
                        }
                        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AZ.border))
                    }
                }
                .padding(20)
            }
        }
        .foregroundStyle(AZ.text)
        .frame(width: 860, height: 620)
        .background(.white)
    }

    private func block(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 14, weight: .bold))
            Text(value.isEmpty ? "—" : value).font(.system(size: 13)).foregroundStyle(AZ.secondary).textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: Spending

struct SpendingView: View {
    @Environment(AmazonStore.self) private var store
    @State private var year: Int?

    var body: some View {
        let orders = store.export.orders.filter { !$0.isCancelled && $0.date != .distantPast }
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Spending").font(.system(size: 28)).foregroundStyle(AZ.text)
                if orders.isEmpty {
                    NoOrders()
                } else {
                    let total = orders.map(\.total).reduce(0, +)
                    let refunded = store.export.refunds.compactMap(\.amount).reduce(0, +)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 14)], spacing: 14) {
                        Tile(value: store.money(total), label: "Spent")
                        Tile(value: "\(orders.count)", label: "Orders")
                        Tile(value: "\(orders.map(\.itemCount).reduce(0, +))", label: "Items")
                        Tile(value: store.money(total / Double(max(1, orders.count))), label: "Average order")
                        if let big = orders.max(by: { $0.total < $1.total }) { Tile(value: store.money(big.total), label: "Biggest order") }
                        if refunded > 0 { Tile(value: store.money(refunded), label: "Refunded") }
                    }

                    let byYear = Dictionary(grouping: orders, by: { Calendar.current.component(.year, from: $0.date) })
                        .map { (year: $0.key, total: $0.value.map(\.total).reduce(0, +)) }.sorted { $0.year < $1.year }
                    Panel("By year") {
                        Chart(byYear, id: \.year) { y in
                            BarMark(x: .value("Year", String(y.year)), y: .value("Spent", y.total))
                                .foregroundStyle(y.year == year ? AZ.orange : AZ.navy2)
                                .annotation(position: .top) { Text(store.money(y.total)).font(.system(size: 10)).foregroundStyle(AZ.secondary) }
                        }
                        .frame(height: 220)
                        Picker("Months of", selection: $year) {
                            ForEach(byYear.map(\.year).reversed(), id: \.self) { Text(String($0)).tag(Int?.some($0)) }
                        }
                        .pickerStyle(.segmented).frame(maxWidth: 600)
                    }
                    .onAppear { if year == nil { year = byYear.last?.year } }

                    if let y = year ?? byYear.last?.year {
                        let months = Dictionary(grouping: orders.filter { Calendar.current.component(.year, from: $0.date) == y },
                                                by: { Calendar.current.component(.month, from: $0.date) }).mapValues { $0.map(\.total).reduce(0, +) }
                        Panel("Month by month in \(String(y))") {
                            Chart((1...12).map { (m: $0, v: months[$0] ?? 0) }, id: \.m) { p in
                                BarMark(x: .value("Month", Calendar.current.shortMonthSymbols[p.m - 1]), y: .value("Spent", p.v))
                                    .foregroundStyle(AZ.orange)
                            }
                            .frame(height: 200)
                        }
                    }

                    let items = orders.flatMap { o in o.items.map { (item: $0, order: o) } }
                    Panel("Most expensive purchases") {
                        ForEach(Array(items.sorted { ($0.item.total ?? 0) > ($1.item.total ?? 0) }.prefix(10).enumerated()), id: \.offset) { _, p in
                            row(p.item.name, store.money(p.item.total, p.order.currency), p.order.date)
                        }
                    }
                    let repeats = Dictionary(grouping: items, by: \.item.name).filter { $0.value.count > 1 && !$0.key.isEmpty }
                        .sorted { $0.value.count > $1.value.count }.prefix(10)
                    if !repeats.isEmpty {
                        Panel("Bought again and again") {
                            ForEach(Array(repeats), id: \.key) { name, list in
                                row(name, "\(list.count) times", list.map(\.order.date).max() ?? .distantPast)
                            }
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 1000, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(AZ.page)
    }

    private func row(_ name: String, _ value: String, _ date: Date) -> some View {
        HStack {
            Text(name).foregroundStyle(AZ.link).lineLimit(1)
            Spacer()
            Text(date.formatted(date: .abbreviated, time: .omitted)).foregroundStyle(AZ.secondary)
            Text(value).foregroundStyle(AZ.text).monospacedDigit().frame(width: 110, alignment: .trailing)
        }
        .font(.system(size: 13))
    }
}

struct Panel<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    init(_ title: String, @ViewBuilder content: () -> Content) { self.title = title; self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 18, weight: .bold)).foregroundStyle(AZ.text)
            content
        }
        .padding(18)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AZ.border))
    }
}

struct Tile: View {
    let value: String
    let label: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 12)).foregroundStyle(AZ.secondary)
            Text(value).font(.system(size: 22, weight: .semibold)).foregroundStyle(AZ.text).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(AZ.cardHeader, in: RoundedRectangle(cornerRadius: 8))
    }
}
