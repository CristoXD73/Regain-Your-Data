import SwiftUI

/// One snap in a grid: portrait tile, rounded corners, caption overlay drawn in, video length.
struct Tile: View {
    @Environment(VaultStore.self) private var store
    let snap: Snap
    var width: Double
    var showSender = false
    @State private var image: NSImage?

    var body: some View {
        let selected = store.selected.contains(snap.id)
        let voice = store.isVoiceNote(snap)
        (voice ? AnyView(Theme.voice) : AnyView(Theme.card))
            .frame(width: width, height: width * 16 / 9 * 0.9)
            .overlay {
                if voice {
                    Image(systemName: "waveform").font(.system(size: width * 0.28, weight: .bold)).foregroundStyle(.white.opacity(0.9))
                } else if let image {
                    Image(nsImage: image).resizable().scaledToFill()
                }
            }
            .overlay(alignment: .bottomLeading) {
                HStack(spacing: 3) {
                    if snap.isVideo {
                        Image(systemName: voice ? "mic.fill" : "play.fill").font(.system(size: 9, weight: .black))
                        if let d = store.duration(snap) { Text("\(Int(d.rounded()))s").font(Theme.body(11, .bold)) }
                    }
                    if showSender {
                        Text(snap.sentByMe ? "You" : (snap.sender ?? "")).font(Theme.body(10, .bold)).lineLimit(1)
                    }
                }
                .foregroundStyle(.white).shadow(color: .black.opacity(0.6), radius: 2)
                .padding(6)
            }
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 20)).foregroundStyle(.black, Theme.yellow).padding(6)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.yellow, lineWidth: selected ? 3 : 0))
            .contentShape(Rectangle())
            .task(id: snap.id) {
                if let c = Thumbnails.shared.cached(snap, size: 256) { image = c; return }
                image = await Thumbnails.shared.image(snap, size: 256)
            }
    }
}

/// A grid of snaps under month headers. Click plays; ⌘-click selects.
struct SnapGrid: View {
    @Environment(VaultStore.self) private var store
    let snaps: [Snap]
    var showSender = false
    var header: AnyView? = nil

    var body: some View {
        let w = store.tileWidth
        let months = Dictionary(grouping: snaps, by: { Calendar.current.dateInterval(of: .month, for: $0.date)!.start })
        ScrollView {
            if let header { header }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: w, maximum: w), spacing: 4)], alignment: .leading, spacing: 4, pinnedViews: [.sectionHeaders]) {
                ForEach(months.keys.sorted(by: >), id: \.self) { m in
                    Section {
                        ForEach(months[m]!) { s in
                            Tile(snap: s, width: w, showSender: showSender)
                                .onTapGesture { tap(s) }
                                .contextMenu { menu(s) }
                        }
                    } header: {
                        Text(m.formatted(.dateTime.month(.wide).year()))
                            .font(Theme.title(18)).foregroundStyle(.white)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                            .background(Theme.background)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .overlay {
            if snaps.isEmpty {
                Text(store.searchText.isEmpty ? "Nothing here" : "No results").font(Theme.body(16)).foregroundStyle(Theme.secondary)
            }
        }
    }

    private func tap(_ s: Snap) {
        if NSEvent.modifierFlags.contains(.command) || !store.selected.isEmpty {
            if store.selected.contains(s.id) { store.selected.remove(s.id) } else { store.selected.insert(s.id) }
        } else {
            store.play(snaps, from: snaps.firstIndex(of: s) ?? 0, story: false)
        }
    }

    @ViewBuilder
    private func menu(_ s: Snap) -> some View {
        Button("Play") { store.play(snaps, from: snaps.firstIndex(of: s) ?? 0, story: false) }
        Button("Select") { store.selected.insert(s.id) }
        Divider()
        Button(store.isEyesOnly(s) ? "Remove from My Eyes Only" : "Move to My Eyes Only") { store.toggleEyesOnly([s]) }
        Button("Export…") { Exporter.export([s]) }
        Button("Show in Finder") { store.revealInFinder([s]) }
    }
}

// MARK: Snaps (with Flashbacks)

struct SnapsView: View {
    @Environment(VaultStore.self) private var store
    var body: some View {
        let flash = store.searchText.isEmpty ? store.flashbacks : []
        SnapGrid(snaps: store.memories, header: flash.isEmpty ? nil : AnyView(FlashbackRow(flashbacks: flash)))
    }
}

struct FlashbackRow: View {
    @Environment(VaultStore.self) private var store
    let flashbacks: [Flashback]
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Flashbacks").font(Theme.title(18)).foregroundStyle(.white)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(flashbacks) { f in
                        let snaps = f.snapIDs.map { store.snap($0) }
                        StoryCard(cover: snaps[0], title: f.id == 1 ? "1 year ago" : "\(f.id) years ago",
                                  subtitle: "\(snaps.count) Snap\(snaps.count == 1 ? "" : "s")", width: 150, highlight: true)
                            .onTapGesture { store.play(snaps, story: true, title: "Flashback · \(f.id) year\(f.id == 1 ? "" : "s") ago") }
                    }
                }
            }
        }
        .padding(.horizontal, 20).padding(.bottom, 10)
    }
}

/// A story-style card: cover image with a title over a dark gradient.
struct StoryCard: View {
    let cover: Snap
    let title: String
    let subtitle: String
    var width: Double = 170
    var highlight = false
    @State private var image: NSImage?

    var body: some View {
        Theme.card
            .frame(width: width, height: width * 1.55)
            .overlay { if let image { Image(nsImage: image).resizable().scaledToFill() } }
            .overlay { LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom) }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Theme.title(15)).lineLimit(2)
                    Text(subtitle).font(Theme.body(11, .medium)).opacity(0.85)
                }
                .foregroundStyle(.white).padding(10)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.yellow, lineWidth: highlight ? 3 : 0))
            .contentShape(Rectangle())
            .task(id: cover.id) { image = await Thumbnails.shared.image(cover, size: 256) }
    }
}

// MARK: Stories

struct StoriesView: View {
    @Environment(VaultStore.self) private var store
    var body: some View {
        let days = store.dayStories
        let years = Dictionary(grouping: days, by: { Calendar.current.component(.year, from: $0.id) })
        let shared = store.sharedStory
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if !shared.isEmpty {
                    section("Shared Story") {
                        StoryCard(cover: shared[0], title: "Shared Story", subtitle: "\(shared.count) Snaps")
                            .onTapGesture { store.play(shared, story: true, title: "Shared Story") }
                    }
                }
                ForEach(years.keys.sorted(by: >), id: \.self) { y in
                    section(String(y)) {
                        ForEach(years[y]!) { d in
                            let snaps = d.snapIDs.map { store.snap($0) }
                            StoryCard(cover: snaps[0], title: d.title, subtitle: "\(snaps.count) Snaps")
                                .onTapGesture { store.play(snaps, story: true, title: d.title) }
                        }
                    }
                }
            }
            .padding(20)
        }
        .overlay { if days.isEmpty && shared.isEmpty { Text("No stories").font(Theme.body(16)).foregroundStyle(Theme.secondary) } }
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(Theme.title(18)).foregroundStyle(.white)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170, maximum: 170), spacing: 10)], alignment: .leading, spacing: 10, content: content)
        }
    }
}

// MARK: My Eyes Only

struct EyesOnlyView: View {
    @Environment(VaultStore.self) private var store
    var body: some View {
        content.onAppear { store.lock.migrateFromKeychainIfNeeded() }
    }

    @ViewBuilder
    private var content: some View {
        switch store.lock.state {
        case .unlocked:
            SnapGrid(snaps: store.eyesOnlySnaps)
                .overlay {
                    if store.eyesOnlySnaps.isEmpty && store.searchText.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "lock.fill").font(.system(size: 34)).foregroundStyle(Theme.yellow)
                            Text("Nothing in My Eyes Only yet").font(Theme.title(18)).foregroundStyle(.white)
                            Text("Right-click a snap, or select some and choose My Eyes Only.").font(Theme.body(13, .medium)).foregroundStyle(Theme.secondary)
                        }
                    }
                }
        case .locked: PasscodePad(mode: .unlock)
        case .needsSetup: PasscodePad(mode: .create)
        }
    }
}

struct PasscodePad: View {
    enum Mode { case unlock, create }
    @Environment(VaultStore.self) private var store
    let mode: Mode
    @State private var code = ""
    @State private var first: String?
    @State private var shake = 0
    @FocusState private var focused: Bool

    var body: some View {
        let lock = store.lock
        VStack(spacing: 22) {
            Image(systemName: "lock.fill").font(.system(size: 30, weight: .bold)).foregroundStyle(.black)
                .frame(width: 64, height: 64).background(Theme.yellow, in: Circle())
            Text("My Eyes Only").font(Theme.title(24)).foregroundStyle(.white)
            Text(prompt).font(Theme.body(14, .medium)).foregroundStyle(Theme.secondary)
            HStack(spacing: 16) {
                ForEach(0..<4, id: \.self) { i in
                    Circle().fill(i < code.count ? Theme.yellow : Color.clear)
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.6), lineWidth: 2))
                        .frame(width: 16, height: 16)
                }
            }
            .modifier(Shake(amount: CGFloat(shake)))
            if let m = lock.message { Text(m).font(Theme.body(12)).foregroundStyle(.red) }
            VStack(spacing: 12) {
                ForEach([["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], ["bio", "0", "del"]], id: \.self) { row in
                    HStack(spacing: 18) {
                        ForEach(row, id: \.self) { k in key(k) }
                    }
                }
            }
            if mode == .unlock {
                Button("Forgot passcode?") { Task { await lock.resetWithMacPassword() } }
                    .buttonStyle(.plain).font(Theme.body(12)).foregroundStyle(Theme.secondary)
            } else {
                Text("Only a scrambled version of the passcode is kept, in your Mac's Keychain.")
                    .font(Theme.body(11, .medium)).foregroundStyle(Theme.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .focusable().focused($focused).focusEffectDisabled()
        .onAppear { focused = true }
        .onKeyPress(characters: .decimalDigits) { p in type(p.characters); return .handled }
        .onKeyPress(.delete) { if !code.isEmpty { code.removeLast() }; return .handled }
        .task { if mode == .unlock && lock.biometricsAvailable { await lock.unlockWithBiometrics() } }
    }

    private var prompt: String {
        switch mode {
        case .unlock: "Enter your passcode"
        case .create: first == nil ? "Create a 4-digit passcode" : "Enter it again to confirm"
        }
    }

    @ViewBuilder
    private func key(_ k: String) -> some View {
        let label: AnyView = switch k {
        case "bio":
            store.lock.biometricsAvailable && mode == .unlock
                ? AnyView(Image(systemName: "touchid").font(.system(size: 22)))
                : AnyView(Color.clear)
        case "del": AnyView(Image(systemName: "delete.left").font(.system(size: 20)))
        default: AnyView(Text(k).font(Theme.title(24)))
        }
        Button {
            switch k {
            case "bio": if mode == .unlock { Task { await store.lock.unlockWithBiometrics() } }
            case "del": if !code.isEmpty { code.removeLast() }
            default: type(k)
            }
        } label: {
            label.foregroundStyle(.white).frame(width: 64, height: 64)
                .background(k == "bio" || k == "del" ? Color.clear : Theme.card, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private func type(_ digits: String) {
        for ch in digits where ch.isNumber && code.count < 4 { code.append(ch) }
        guard code.count == 4 else { return }
        let entered = code
        code = ""
        switch mode {
        case .unlock:
            if !store.lock.tryPasscode(entered) { withAnimation(.default) { shake += 1 } }
        case .create:
            if let first {
                if first == entered { store.lock.setPasscode(entered) } else {
                    self.first = nil
                    store.lock.message = "Those didn't match. Try again."
                    withAnimation(.default) { shake += 1 }
                }
            } else {
                first = entered
                store.lock.message = nil
            }
        }
    }
}

struct Shake: GeometryEffect {
    var amount: CGFloat
    var animatableData: CGFloat { get { amount } set { amount = newValue } }
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 10 * sin(amount * .pi * 4), y: 0))
    }
}
