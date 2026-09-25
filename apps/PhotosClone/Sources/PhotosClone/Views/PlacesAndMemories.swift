import MapKit
import SwiftUI

// MARK: Map

private struct Cluster: Identifiable {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let assets: [Asset]
}

struct PlacesView: View {
    @Environment(LibraryStore.self) private var store
    @State private var region: MKCoordinateRegion?
    @State private var picked: [Asset] = []
    @State private var position: MapCameraPosition = .automatic

    var body: some View {
        let located = store.assets(for: .library).filter { store.info($0)?.hasLocation == true }
        let clusters = cluster(located)
        VStack(spacing: 0) {
            Map(position: $position) {
                ForEach(clusters) { c in
                    Annotation("", coordinate: c.coordinate) {
                        ClusterPin(cluster: c)
                            .onTapGesture { picked = c.assets }
                    }
                }
            }
            .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
            .onMapCameraChange(frequency: .onEnd) { region = $0.region }
            .overlay(alignment: .topLeading) {
                if store.isIndexing {
                    Label("Still reading locations: \(store.indexed.formatted()) of \(store.indexingTotal.formatted())", systemImage: "location.magnifyingglass")
                        .font(.caption).padding(8)
                        .background(.regularMaterial, in: Capsule())
                        .padding(10)
                } else if located.isEmpty {
                    Text("No photos with locations").padding(8).background(.regularMaterial, in: Capsule()).padding(10)
                }
            }

            if !picked.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("\(picked.count.formatted()) items here").font(.headline)
                        Spacer()
                        Button("Close") { picked = [] }
                    }
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: 2) {
                            ForEach(picked) { a in
                                ThumbCell(asset: a, size: 120)
                                    .frame(width: 120, height: 120)
                                    .onTapGesture { store.open(a, in: picked) }
                            }
                        }
                    }
                    .frame(height: 124)
                }
                .padding(10)
                .background(.bar)
            }
        }
    }

    /// Buckets photos on a grid sized to the visible map so pins merge as you zoom out.
    private func cluster(_ assets: [Asset]) -> [Cluster] {
        let span = region.map { max($0.span.latitudeDelta, $0.span.longitudeDelta) } ?? 180
        let cell = max(0.0005, span / 12)
        var buckets: [String: [Asset]] = [:]
        for a in assets {
            guard let i = store.info(a), let lat = i.latitude, let lon = i.longitude else { continue }
            buckets["\(Int((lat / cell).rounded(.down)))_\(Int((lon / cell).rounded(.down)))", default: []].append(a)
        }
        return buckets.map { k, list in
            var lat = 0.0, lon = 0.0
            for a in list { let i = store.info(a)!; lat += i.latitude!; lon += i.longitude! }
            return Cluster(id: k, coordinate: .init(latitude: lat / Double(list.count), longitude: lon / Double(list.count)),
                           assets: list.sorted { $0.date < $1.date })
        }
    }
}

private struct ClusterPin: View {
    let cluster: Cluster
    @State private var image: NSImage?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.gray
                .frame(width: 54, height: 54)
                .overlay { if let image { Image(nsImage: image).resizable().scaledToFill() } }
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white, lineWidth: 2))
                .shadow(radius: 3)
            if cluster.assets.count > 1 {
                Text(cluster.assets.count.formatted())
                    .font(.caption2.bold()).foregroundStyle(.white)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(.blue, in: Capsule())
                    .offset(x: 8, y: -8)
            }
        }
        .task(id: cluster.assets.last?.id) {
            if let a = cluster.assets.last { image = await ThumbnailLoader.shared.image(for: a, size: 256) }
        }
    }
}

// MARK: Memories & Shared Albums

struct MemoriesView: View {
    @Environment(LibraryStore.self) private var store

    var body: some View {
        let shared = store.selection == .sharedAlbums
        let refs = shared ? store.library.sharedAlbums : filtered(store.library.memories)
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 18)], spacing: 18) {
                ForEach(refs) { m in
                    MemoryCard(ref: m) {
                        store.selection = shared ? .shared(m.id) : .memory(m.id)
                    } play: {
                        store.slideshow = m.assetIDs.map { store.asset($0) }.filter { $0.kind != .video }
                    }
                }
            }
            .padding(18)
        }
        .overlay {
            if refs.isEmpty { ContentUnavailableView("No Memories", systemImage: "memories") }
        }
    }

    private func filtered(_ list: [AlbumRef]) -> [AlbumRef] {
        let q = store.searchText.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? list : list.filter { $0.title.localizedCaseInsensitiveContains(q) }
    }
}

private struct MemoryCard: View {
    @Environment(LibraryStore.self) private var store
    let ref: AlbumRef
    let open: () -> Void
    let play: () -> Void
    @State private var image: NSImage?
    @State private var hovering = false

    var body: some View {
        Button(action: open) {
            Color.gray.opacity(0.2)
                .aspectRatio(16 / 10, contentMode: .fit)
                .overlay { if let image { Image(nsImage: image).resizable().scaledToFill().scaleEffect(hovering ? 1.05 : 1) } }
                .overlay { LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .center, endPoint: .bottom) }
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(cleanTitle).font(.title3.bold()).lineLimit(2)
                        Text(subtitle).font(.caption).opacity(0.85)
                    }
                    .foregroundStyle(.white)
                    .padding(14)
                }
                .overlay(alignment: .topTrailing) {
                    Button(action: play) {
                        Image(systemName: "play.fill").padding(10).background(.ultraThinMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .padding(10)
                    .opacity(hovering ? 1 : 0)
                }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeOut(duration: 0.25)) { hovering = h } }
        .task {
            let assets = ref.assetIDs.map { store.asset($0) }
            if let cover = assets.first(where: { $0.isFavorite && $0.kind != .video }) ?? assets.first(where: { $0.kind != .video }) ?? assets.first {
                image = await ThumbnailLoader.shared.image(for: cover, size: 512)
            }
        }
    }

    /// Apple de-duplicates memory file names by appending digits ("…Nov 4, 20201").
    private var cleanTitle: String {
        ref.title.replacingOccurrences(of: #"(\d{4})\d+$"#, with: "$1", options: .regularExpression)
    }

    private var subtitle: String {
        var s = "\(ref.assetIDs.count) items"
        if let d = ref.sortDate, ref.kind == .shared { s += " · created " + d.formatted(date: .abbreviated, time: .omitted) }
        return s
    }
}

// MARK: Slideshow

struct SlideshowView: View {
    @Environment(LibraryStore.self) private var store
    let assets: [Asset]
    @State private var index = 0
    @State private var image: NSImage?
    @State private var paused = false
    @State private var zoomed = false
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(zoomed ? 1.08 : 1.0)
                    .animation(.linear(duration: 4.5), value: zoomed)
                    .id(index)
                    .transition(.opacity)
            }
            VStack {
                HStack {
                    Spacer()
                    Button { store.slideshow = nil } label: {
                        Image(systemName: "xmark").padding(10).background(.ultraThinMaterial, in: Circle())
                    }
                    .buttonStyle(.plain).foregroundStyle(.white)
                    .keyboardShortcut(.cancelAction)
                }
                Spacer()
                Text("\(index + 1) / \(assets.count)\(paused ? "  ·  Paused" : "")")
                    .font(.caption).foregroundStyle(.white.opacity(0.6))
            }
            .padding(16)
        }
        .focusable().focused($focused).focusEffectDisabled()
        .onAppear { focused = true }
        .onKeyPress(.space) { paused.toggle(); return .handled }
        .onKeyPress(.rightArrow) { index = min(assets.count - 1, index + 1); return .handled }
        .onKeyPress(.leftArrow) { index = max(0, index - 1); return .handled }
        .task(id: index) {
            guard !assets.isEmpty else { store.slideshow = nil; return }
            let img = await ThumbnailLoader.displayImage(assets[index].source, maxPixel: 2560)
            zoomed = false
            withAnimation(.easeInOut(duration: 0.8)) { image = img }
            zoomed = true
            try? await Task.sleep(for: .seconds(4))
            while paused { try? await Task.sleep(for: .milliseconds(200)) }
            if Task.isCancelled { return }
            if index < assets.count - 1 { index += 1 } else { store.slideshow = nil }
        }
    }
}
