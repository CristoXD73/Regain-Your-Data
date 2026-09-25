import SwiftUI

struct AssetGridView: View {
    @Environment(LibraryStore.self) private var store
    let item: SidebarItem
    var grouped: Bool
    /// When set, the grid scrolls to this month once it appears (from the Years/Months views).
    var scrollTo: Date? = nil

    @State private var anchor: Int?

    var body: some View {
        let assets = store.assets(for: item)
        let columns = [GridItem(.adaptive(minimum: store.thumbnailSize, maximum: store.thumbnailSize * 1.6), spacing: 2)]
        Group {
            if assets.isEmpty {
                ContentUnavailableView(store.searchText.isEmpty ? "No Items" : "No Results",
                                       systemImage: item.icon,
                                       description: Text(store.searchText.isEmpty ? "" : "Nothing matches “\(store.searchText)”."))
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 2, pinnedViews: grouped ? [.sectionHeaders] : []) {
                            if grouped {
                                ForEach(store.sections(assets)) { section in
                                    Section {
                                        cells(section.assets, all: assets)
                                    } header: {
                                        SectionHeader(title: section.title, count: section.assets.count)
                                            .id(section.id)
                                    }
                                }
                            } else {
                                cells(assets, all: assets)
                            }
                        }
                        .padding(.horizontal, 2)
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .defaultScrollAnchor(grouped && scrollTo == nil ? .bottom : .top)
                    .task {
                        // Wait one layout pass so the lazy grid knows where the target is.
                        try? await Task.sleep(for: .milliseconds(50))
                        if let d = scrollTo { proxy.scrollTo(d, anchor: .top) }
                        else if grouped && store.searchText.isEmpty { proxy.scrollTo("bottom", anchor: .bottom) }
                    }
                    .onChange(of: item) { _, _ in
                        if grouped { proxy.scrollTo("bottom", anchor: .bottom) }
                    }
                }
                .focusable()
                .focusEffectDisabled()
                .onKeyPress(.space) { openSelection(assets) }
                .onKeyPress(.return) { openSelection(assets) }
                .onKeyPress(.escape) { store.selectedIDs = []; return .handled }
                .onKeyPress(characters: .init(charactersIn: "."), phases: .down) { _ in
                    guard !store.selectedIDs.isEmpty else { return .ignored }
                    store.toggleFavorite(store.selectedIDs.sorted()); return .handled
                }
                .onKeyPress(.delete, phases: .down) { press in
                    guard press.modifiers.contains(.command), !store.selectedIDs.isEmpty else { return .ignored }
                    let ids = store.selectedIDs.sorted()
                    if item == .recentlyDeleted { store.confirmDeleteNow = ids } else { store.moveToTrash(ids) }
                    return .handled
                }
                .onKeyPress(.rightArrow) { moveSelection(assets, by: 1) }
                .onKeyPress(.leftArrow) { moveSelection(assets, by: -1) }
                .onKeyPress(characters: .init(charactersIn: "a"), phases: .down) { press in
                    guard press.modifiers.contains(.command) else { return .ignored }
                    store.selectedIDs = Set(assets.map(\.id)); return .handled
                }
            }
        }
    }

    @ViewBuilder
    private func cells(_ list: [Asset], all: [Asset]) -> some View {
        ForEach(list) { a in
            ThumbCell(asset: a, size: store.thumbnailSize, selected: store.selectedIDs.contains(a.id), showDaysLeft: item == .recentlyDeleted)
                .onTapGesture(count: 2) { store.open(a, in: all) }
                .simultaneousGesture(TapGesture().modifiers(.command).onEnded { toggle(a) })
                .simultaneousGesture(TapGesture().modifiers(.shift).onEnded { extend(to: a, in: all) })
                .onTapGesture { store.selectedIDs = [a.id]; anchor = a.id }
                .contextMenu { menu(a, all: all) }
                .modifier(DragOut(url: a.source.fileURL))
        }
    }

    @ViewBuilder
    private func menu(_ a: Asset, all: [Asset]) -> some View {
        let targets = store.selectedIDs.contains(a.id) ? store.selectedIDs.sorted().map { store.asset($0) } : [a]
        let ids = targets.map(\.id)
        Button("Open") { store.open(a, in: all) }
        Button("Get Info") { store.selectedIDs = [a.id]; store.showInfo = true }
        Divider()
        if item == .recentlyDeleted {
            Button("Recover") { store.restore(ids) }
            Button("Delete Now…") { store.confirmDeleteNow = ids }
        } else {
            Button(targets.allSatisfy(\.isFavorite) ? "Unfavorite" : "Favorite") { store.toggleFavorite(ids) }
            Button(a.isHidden ? "Unhide" : "Hide") { store.setHidden(ids, !a.isHidden) }
            Button(targets.count > 1 ? "Delete \(targets.count) Items" : "Delete") { store.moveToTrash(ids) }
        }
        Divider()
        Button(a.isZipped ? "Show Zip in Finder" : "Show in Finder") { store.revealInFinder(targets) }
        Button("Open With Default App") { store.withFile(a) { NSWorkspace.shared.open($0) } }
        Button(targets.count > 1 ? "Export \(targets.count) Originals…" : "Export Original…") { store.export(targets) }
        Divider()
        Button("Copy") {
            Task {
                var urls: [NSURL] = []
                for t in targets { if let u = try? await MediaAccess.fileURL(t.source) { urls.append(u as NSURL) } }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.writeObjects(urls)
            }
        }
    }

    private func toggle(_ a: Asset) {
        if store.selectedIDs.contains(a.id) { store.selectedIDs.remove(a.id) } else { store.selectedIDs.insert(a.id) }
        anchor = a.id
    }

    private func extend(to a: Asset, in list: [Asset]) {
        guard let anchor, let i = list.firstIndex(where: { $0.id == anchor }), let j = list.firstIndex(of: a) else {
            store.selectedIDs = [a.id]; return
        }
        store.selectedIDs = Set(list[min(i, j)...max(i, j)].map(\.id))
    }

    private func openSelection(_ list: [Asset]) -> KeyPress.Result {
        guard let id = store.selectedIDs.first, let a = list.first(where: { $0.id == id }) else { return .ignored }
        store.open(a, in: list)
        return .handled
    }

    private func moveSelection(_ list: [Asset], by d: Int) -> KeyPress.Result {
        guard let id = store.selectedIDs.first, let i = list.firstIndex(where: { $0.id == id }) else { return .ignored }
        let j = max(0, min(list.count - 1, i + d))
        store.selectedIDs = [list[j].id]
        anchor = list[j].id
        return .handled
    }
}

/// Dragging out only works for files on disk; zipped items go through Export instead.
private struct DragOut: ViewModifier {
    let url: URL?
    func body(content: Content) -> some View {
        if let url { content.draggable(url) } else { content }
    }
}

struct SectionHeader: View {
    let title: String
    let count: Int
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.title3.bold())
            Text("\(count.formatted())").font(.callout).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

struct ThumbCell: View {
    @Environment(LibraryStore.self) private var store
    let asset: Asset
    let size: Double
    var selected = false
    var showDaysLeft = false
    @State private var image: NSImage?

    private var pixel: Int { size > 220 ? 512 : 256 }

    var body: some View {
        Color.gray.opacity(0.12)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    Image(nsImage: image).resizable().scaledToFill()
                } else if asset.fileSize == 0 {
                    Image(systemName: "exclamationmark.triangle").font(.title2).foregroundStyle(.secondary)
                        .help("This file is empty in Apple's export")
                } else if asset.kind == .video && asset.isZipped {
                    Image(systemName: "film").font(.title2).foregroundStyle(.secondary)
                }
            }
            .clipped()
            .overlay(alignment: .bottomTrailing) {
                if asset.kind == .video {
                    Text(duration)
                        .font(.caption2.weight(.semibold)).monospacedDigit()
                        .foregroundStyle(.white).shadow(radius: 2)
                        .padding(5)
                }
            }
            .overlay(alignment: .topLeading) {
                if asset.kind == .livePhoto && size > 90 {
                    Image(systemName: "livephoto").font(.caption).foregroundStyle(.white).shadow(radius: 2).padding(5)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if showDaysLeft {
                    Text(daysLeft)
                        .font(.caption2.weight(.semibold)).foregroundStyle(.white).shadow(radius: 2)
                        .padding(5)
                } else if asset.isFavorite {
                    Image(systemName: "heart.fill").font(.caption).foregroundStyle(.white).shadow(radius: 2).padding(5)
                }
            }
            .overlay {
                if selected {
                    Rectangle().strokeBorder(Color.accentColor, lineWidth: 3)
                        .background(Color.accentColor.opacity(0.15))
                }
            }
            .contentShape(Rectangle())
            .task(id: "\(asset.id)-\(pixel)") {
                if let c = ThumbnailLoader.shared.cachedImage(asset, size: pixel) { image = c; return }
                image = await ThumbnailLoader.shared.image(for: asset, size: pixel)
            }
    }

    private var daysLeft: String {
        guard let d = asset.deletedAt else { return "iCloud" }
        let left = max(0, Int(ceil((EditsStore.retention - Date().timeIntervalSince(d)) / 86_400)))
        return left == 1 ? "1 day" : "\(left) days"
    }

    private var duration: String {
        guard let d = store.info(asset)?.duration else { return "" }
        return formatDuration(d)
    }
}

func formatDuration(_ d: Double) -> String {
    let s = Int(d.rounded())
    return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
}

// MARK: Library with Years / Months / All Photos

struct LibraryView: View {
    @Environment(LibraryStore.self) private var store
    @State private var target: Date?
    @State private var yearTarget: Date?

    var body: some View {
        switch store.libraryZoom {
        case .all:
            AssetGridView(item: .library, grouped: true, scrollTo: target)
                .id(target)
        case .months:
            SummaryGrid(groups: groups(by: .month), minWidth: 260, initial: yearTarget) { d in
                target = d
                store.libraryZoom = .all
            }
        case .years:
            SummaryGrid(groups: groups(by: .year), minWidth: 380) { d in
                yearTarget = d
                store.libraryZoom = .months
            }
        }
    }

    private func groups(by comp: Calendar.Component) -> [SummaryGroup] {
        let cal = Calendar.current
        let fmt = DateFormatter()
        fmt.setLocalizedDateFormatFromTemplate(comp == .year ? "yyyy" : "MMMM yyyy")
        var buckets: [Date: [Asset]] = [:]
        for a in store.assets(for: .library) where a.date != .distantPast {
            buckets[cal.dateInterval(of: comp, for: a.date)!.start, default: []].append(a)
        }
        return buckets.keys.sorted().map { k in
            let list = buckets[k]!
            // Prefer a favorite photo as the cover, like Photos does.
            let cover = list.first { $0.isFavorite && $0.kind != .video } ?? list.filter { $0.kind != .video && !$0.isScreenshot }.dropFirst(list.count / 3).first ?? list[list.count / 2]
            return SummaryGroup(id: k, title: fmt.string(from: k), count: list.count, cover: cover, strip: Array(list.filter { !$0.isScreenshot }.prefix(40).enumerated().filter { $0.offset % 8 == 0 }.map(\.element)))
        }
    }
}

struct SummaryGroup: Identifiable {
    let id: Date
    let title: String
    let count: Int
    let cover: Asset
    let strip: [Asset]
}

struct SummaryGrid: View {
    let groups: [SummaryGroup]
    let minWidth: Double
    var initial: Date? = nil
    let onOpen: (Date) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: minWidth), spacing: 16)], spacing: 16) {
                    ForEach(groups) { g in
                        Button { onOpen(g.id) } label: { SummaryCard(group: g) }
                            .buttonStyle(.plain)
                            .id(g.id)
                    }
                }
                .padding(16)
            }
            .onAppear {
                if let initial, let g = groups.first(where: { $0.id >= initial }) { proxy.scrollTo(g.id, anchor: .top) }
                else if let last = groups.last { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
    }
}

struct SummaryCard: View {
    let group: SummaryGroup
    @State private var image: NSImage?

    var body: some View {
        Color.gray.opacity(0.15)
            .aspectRatio(4 / 3, contentMode: .fit)
            .overlay { if let image { Image(nsImage: image).resizable().scaledToFill() } }
            .overlay(alignment: .topLeading) {
                LinearGradient(colors: [.black.opacity(0.55), .clear], startPoint: .top, endPoint: .center)
            }
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.title).font(.title2.bold())
                    Text("\(group.count.formatted()) items").font(.callout).opacity(0.85)
                }
                .foregroundStyle(.white)
                .padding(14)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
            .contentShape(Rectangle())
            .task { image = await ThumbnailLoader.shared.image(for: group.cover, size: 512) }
    }
}
