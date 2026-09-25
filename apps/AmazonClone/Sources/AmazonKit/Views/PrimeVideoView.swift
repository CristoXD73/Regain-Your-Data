import Charts
import RegainCore
import SwiftUI

/// Prime Video, in its own dark style: what you watched, when, and on what.
struct PrimeVideoView: View {
    @Environment(AmazonStore.self) private var store
    @State private var section: Section = .overview
    @State private var showPromos = false
    @State private var filter = ""
    @State private var openWork: String?

    enum Section: String, CaseIterable { case overview = "Overview", history = "History", titles = "Shows & Movies", searches = "Searches", purchases = "Purchases & Rentals" }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 22) {
                HStack(spacing: 0) {
                    Text("prime").font(.system(size: 22, weight: .heavy)).foregroundStyle(.white)
                    Text(" video").font(.system(size: 22, weight: .regular)).foregroundStyle(.white)
                }
                ForEach(Section.allCases, id: \.self) { s in
                    Button { section = s } label: {
                        Text(s.rawValue).font(.system(size: 14, weight: section == s ? .bold : .medium))
                            .foregroundStyle(section == s ? .white : AZ.pvSecondary)
                            .padding(.vertical, 6)
                            .overlay(alignment: .bottom) { if section == s { Rectangle().fill(.white).frame(height: 2).offset(y: 4) } }
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                if section == .history || section == .titles || section == .searches {
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(AZ.pvSecondary)
                        TextField("Filter", text: $filter).textFieldStyle(.plain).foregroundStyle(.white)
                    }
                    .padding(.horizontal, 10).frame(width: 220, height: 30)
                    .background(AZ.pvCard, in: RoundedRectangle(cornerRadius: 6))
                }
            }
            .padding(.horizontal, 26).padding(.vertical, 14)

            if store.export.viewing.isEmpty && store.export.videoPurchases.isEmpty {
                Text("No Prime Video data in this download.").foregroundStyle(AZ.pvSecondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                switch section {
                case .overview: Overview(open: { openWork = $0; section = .titles })
                case .history: History(showPromos: $showPromos, filter: filter)
                case .titles: Titles(filter: filter, open: $openWork)
                case .searches: Searches(filter: filter)
                case .purchases: Purchases()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AZ.pvBackground)
        .environment(\.colorScheme, .dark)
    }
}

private extension Array where Element == Viewing {
    var hours: Double { map(\.seconds).reduce(0, +) / 3600 }
}

private func hoursText(_ h: Double) -> String { h >= 10 ? "\(Int(h.rounded())) h" : String(format: "%.1f h", h) }

private func durationText(_ s: Double) -> String {
    let m = Int(s / 60)
    return m >= 60 ? "\(m / 60) h \(m % 60) min" : m > 0 ? "\(m) min" : "\(Int(s)) s"
}

// MARK: Overview

private struct Overview: View {
    @Environment(AmazonStore.self) private var store
    let open: (String) -> Void

    var body: some View {
        let w = store.export.viewing.filter(\.isWatch)
        let byWork = Dictionary(grouping: w, by: \.work).sorted { $0.value.hours > $1.value.hours }
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 14)], spacing: 14) {
                    PVTile(value: hoursText(w.hours), label: "watched")
                    PVTile(value: "\(Set(w.compactMap(\.show)).count)", label: "shows")
                    PVTile(value: "\(w.filter { $0.show != nil }.count)", label: "episode plays")
                    PVTile(value: "\(Set(w.filter { $0.show == nil }.map(\.title)).count)", label: "films and other titles")
                    PVTile(value: "\(Set(w.map { Calendar.current.startOfDay(for: $0.start) }).count)", label: "days you watched")
                    if let d = Dictionary(grouping: w, by: \.device).max(by: { $0.value.hours < $1.value.hours }), !d.key.isEmpty {
                        PVTile(value: d.key, label: "watched on most")
                    }
                }

                row("Most watched") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            ForEach(byWork.prefix(15), id: \.key) { name, plays in
                                Button { open(name) } label: { Poster(title: name, subtitle: hoursText(plays.hours)) }.buttonStyle(.plain)
                            }
                        }
                    }
                }

                let months = Dictionary(grouping: w, by: { Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: $0.start))! })
                    .map { (month: $0.key, hours: $0.value.hours) }.sorted { $0.month < $1.month }
                row("Hours watched each month") {
                    Chart(months, id: \.month) { m in
                        BarMark(x: .value("Month", m.month, unit: .month), y: .value("Hours", m.hours)).foregroundStyle(AZ.pvBlue)
                    }
                    .chartXAxis { AxisMarks(values: .stride(by: .month, count: max(1, months.count / 10))) { _ in AxisGridLine(); AxisValueLabel(format: .dateTime.month(.abbreviated).year(.twoDigits)) } }
                    .frame(height: 200)
                }

                HStack(alignment: .top, spacing: 26) {
                    let hours = Dictionary(grouping: w, by: { Calendar.current.component(.hour, from: $0.start) }).mapValues(\.hours)
                    row("What time you watch") {
                        Chart((0..<24).map { (h: $0, v: hours[$0] ?? 0) }, id: \.h) { p in
                            BarMark(x: .value("Hour", p.h), y: .value("Hours", p.v)).foregroundStyle(AZ.pvBlue.opacity(0.8))
                        }
                        .chartXAxis { AxisMarks(values: [0, 6, 12, 18, 23]) { v in AxisValueLabel { Text(hourLabel(v.as(Int.self) ?? 0)) } } }
                        .frame(height: 160)
                    }
                    let days = Dictionary(grouping: w, by: { Calendar.current.component(.weekday, from: $0.start) }).mapValues(\.hours)
                    row("Which day") {
                        Chart((1...7).map { (d: $0, v: days[$0] ?? 0) }, id: \.d) { p in
                            BarMark(x: .value("Day", Calendar.current.shortWeekdaySymbols[p.d - 1]), y: .value("Hours", p.v)).foregroundStyle(AZ.pvBlue.opacity(0.8))
                        }
                        .frame(height: 160)
                    }
                }
            }
            .padding(26)
        }
    }

    private func hourLabel(_ h: Int) -> String {
        var c = DateComponents(); c.hour = h
        return Calendar.current.date(from: c)?.formatted(.dateTime.hour()) ?? "\(h)"
    }

    private func row<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
            content()
        }
    }
}

struct PVTile: View {
    let value: String
    let label: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.system(size: 22, weight: .bold)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.5)
            Text(label).font(.system(size: 12)).foregroundStyle(AZ.pvSecondary)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(AZ.pvCard, in: RoundedRectangle(cornerRadius: 8))
    }
}

/// Artwork would have to come from Amazon, so each title gets a gradient card of its own colour.
struct Poster: View {
    let title: String
    var subtitle: String?
    var width: CGFloat = 150

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 8).fill(Self.gradient(title))
                Text(title).font(.system(size: 15, weight: .heavy)).foregroundStyle(.white).lineLimit(4)
                    .shadow(color: .black.opacity(0.5), radius: 4).padding(10)
            }
            .frame(width: width, height: width * 1.33)
            if let subtitle { Text(subtitle).font(.system(size: 12)).foregroundStyle(AZ.pvSecondary) }
        }
        .frame(width: width, alignment: .leading)
    }

    static func gradient(_ s: String) -> LinearGradient {
        let h = Double(Int(stableHash(s).unicodeScalars.map(\.value).reduce(0, +)) % 360) / 360
        return LinearGradient(colors: [Color(hue: h, saturation: 0.55, brightness: 0.55), Color(hue: (h + 0.08).truncatingRemainder(dividingBy: 1), saturation: 0.7, brightness: 0.22)],
                              startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// MARK: History

private struct History: View {
    @Environment(AmazonStore.self) private var store
    @Binding var showPromos: Bool
    let filter: String

    var body: some View {
        let f = filter.lowercased()
        let items = store.export.viewing.filter { (showPromos || $0.isWatch) && (f.isEmpty || $0.title.lowercased().contains(f)) }
        let days = Dictionary(grouping: items, by: { Calendar.current.startOfDay(for: $0.start) }).sorted { $0.key > $1.key }
        VStack(spacing: 0) {
            HStack {
                Text("\(items.count) plays").foregroundStyle(AZ.pvSecondary)
                Spacer()
                Toggle("Include trailers and promos", isOn: $showPromos).toggleStyle(.switch).controlSize(.small).foregroundStyle(AZ.pvSecondary)
            }
            .font(.system(size: 12)).padding(.horizontal, 26).padding(.bottom, 8)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    ForEach(days, id: \.key) { day, plays in
                        SwiftUI.Section {
                            ForEach(plays) { PlayRow(v: $0) }
                        } header: {
                            Text(day.formatted(date: .complete, time: .omitted)).font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                                .padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading).background(AZ.pvBackground)
                        }
                    }
                }
                .padding(.horizontal, 26).padding(.bottom, 20)
            }
        }
    }
}

private struct PlayRow: View {
    let v: Viewing
    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 5).fill(Poster.gradient(v.work)).frame(width: 64, height: 36)
                .overlay(Image(systemName: v.isWatch ? "play.fill" : "film").font(.system(size: 12)).foregroundStyle(.white.opacity(0.8)))
            VStack(alignment: .leading, spacing: 2) {
                Text(v.show ?? v.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                HStack(spacing: 6) {
                    if let s = v.season { Text("S\(s)") }
                    if let e = v.episode { Text(e).lineLimit(1) }
                    if !v.isWatch { Text(v.kind.rawValue).padding(.horizontal, 5).background(AZ.pvCard, in: Capsule()) }
                    if v.deleted { Text("removed from history").italic() }
                }
                .font(.system(size: 12)).foregroundStyle(AZ.pvSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(durationText(v.seconds)).font(.system(size: 12, weight: .medium)).foregroundStyle(.white).monospacedDigit()
                Text("\(v.start.formatted(date: .omitted, time: .shortened))\(v.device.isEmpty ? "" : " · \(v.device)")")
                    .font(.system(size: 11)).foregroundStyle(AZ.pvSecondary).lineLimit(1)
            }
        }
        .padding(.vertical, 7)
    }
}

// MARK: Shows & Movies

private struct Titles: View {
    @Environment(AmazonStore.self) private var store
    let filter: String
    @Binding var open: String?

    var body: some View {
        let f = filter.lowercased()
        let works = Dictionary(grouping: store.export.viewing.filter(\.isWatch), by: \.work)
            .filter { f.isEmpty || $0.key.lowercased().contains(f) }
            .sorted { ($0.value.map(\.start).max() ?? .distantPast) > ($1.value.map(\.start).max() ?? .distantPast) }
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 170), spacing: 18)], alignment: .leading, spacing: 22) {
                ForEach(works, id: \.key) { name, plays in
                    Button { open = name } label: {
                        Poster(title: name, subtitle: "\(hoursText(plays.hours)) · last \(plays.map(\.start).max()!.formatted(.dateTime.month(.abbreviated).year()))")
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(26)
        }
        .sheet(item: Binding(get: { open.map { WorkID(name: $0) } }, set: { open = $0?.name })) { w in
            WorkDetail(name: w.name, plays: store.export.viewing.filter { $0.isWatch && $0.work == w.name })
        }
    }

    struct WorkID: Identifiable { let name: String; var id: String { name } }
}

private struct WorkDetail: View {
    @Environment(\.dismiss) private var dismiss
    let name: String
    let plays: [Viewing]

    var body: some View {
        let seasons = Dictionary(grouping: plays, by: { $0.season ?? 0 }).sorted { $0.key < $1.key }
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 18) {
                Poster(title: name, width: 110)
                VStack(alignment: .leading, spacing: 6) {
                    Text(name).font(.system(size: 24, weight: .bold)).foregroundStyle(.white)
                    Text("\(hoursText(plays.hours)) over \(plays.count) plays").foregroundStyle(AZ.pvSecondary)
                    if let a = plays.map(\.start).min(), let b = plays.map(\.start).max() {
                        Text("\(a.formatted(date: .abbreviated, time: .omitted)) – \(b.formatted(date: .abbreviated, time: .omitted))").foregroundStyle(AZ.pvSecondary)
                    }
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(22)
            List {
                ForEach(seasons, id: \.key) { season, ps in
                    SwiftUI.Section(season == 0 ? "Plays" : "Season \(season)") {
                        let eps = Dictionary(grouping: ps, by: { $0.episode ?? $0.title }).sorted { ($0.value.map(\.start).min()!) < ($1.value.map(\.start).min()!) }
                        ForEach(eps, id: \.key) { ep, epPlays in
                            HStack {
                                Text(ep).lineLimit(1)
                                Spacer()
                                Text("\(epPlays.count)×").foregroundStyle(.secondary)
                                Text(durationText(epPlays.map(\.seconds).reduce(0, +))).monospacedDigit().frame(width: 90, alignment: .trailing)
                                Text(epPlays.map(\.start).max()!.formatted(date: .abbreviated, time: .omitted)).foregroundStyle(.secondary).frame(width: 110, alignment: .trailing)
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .frame(width: 720, height: 560)
        .background(AZ.pvBackground)
        .environment(\.colorScheme, .dark)
    }
}

// MARK: Searches & purchases

private struct Searches: View {
    @Environment(AmazonStore.self) private var store
    let filter: String
    var body: some View {
        let f = filter.lowercased()
        let items = store.export.videoSearches.filter { f.isEmpty || $0.query.lowercased().contains(f) }
        List(items) { s in
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(AZ.pvSecondary)
                Text(s.query).foregroundStyle(.white)
                Spacer()
                Text(s.device).foregroundStyle(AZ.pvSecondary).lineLimit(1)
                Text(s.date?.formatted(date: .abbreviated, time: .shortened) ?? "").foregroundStyle(AZ.pvSecondary).frame(width: 170, alignment: .trailing)
            }
            .font(.system(size: 13))
            .listRowBackground(Color.clear)
        }
        .scrollContentBackground(.hidden)
        .padding(.horizontal, 12)
    }
}

private struct Purchases: View {
    @Environment(AmazonStore.self) private var store
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(store.export.videoPurchases) { p in
                    HStack(spacing: 14) {
                        RoundedRectangle(cornerRadius: 5).fill(Poster.gradient(p.title)).frame(width: 64, height: 36)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(p.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                            HStack(spacing: 6) {
                                Text(p.offer).font(.system(size: 11, weight: .bold)).foregroundStyle(.black)
                                    .padding(.horizontal, 6).padding(.vertical, 1)
                                    .background(p.offer.lowercased() == "rental" ? AZ.pvSecondary : AZ.pvBlue, in: Capsule())
                                if !p.quality.isEmpty { Text(p.quality).font(.system(size: 11)).foregroundStyle(AZ.pvSecondary) }
                                if let e = p.expires, p.offer.lowercased() == "rental" {
                                    Text("rental ended \(e.formatted(date: .abbreviated, time: .omitted))").font(.system(size: 11)).foregroundStyle(AZ.pvSecondary)
                                }
                            }
                        }
                        Spacer()
                        Text(p.date?.formatted(date: .long, time: .omitted) ?? "").font(.system(size: 12)).foregroundStyle(AZ.pvSecondary)
                    }
                    .padding(12).background(AZ.pvCard, in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(26)
        }
    }
}
