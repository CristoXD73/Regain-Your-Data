import SwiftUI
import UniformTypeIdentifiers

enum TX {
    static let accent = Color(red: 0.12, green: 0.55, blue: 0.40)
    static let accent2 = Color(red: 0.08, green: 0.40, blue: 0.55)
    static func confidence(_ c: Double, confirmed: Bool) -> Color {
        confirmed ? .green : c >= 0.8 ? Color(red: 0.35, green: 0.7, blue: 0.35) : c >= 0.55 ? .orange : .red
    }
}

public struct TaxDeskApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var store = TaxStore.shared
    public init() {}

    public var body: some Scene {
        WindowGroup("Tax Desk") {
            RootView().environment(store).frame(minWidth: 1100, minHeight: 700)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Import Documents…") { store.chooseFiles() }.keyboardShortcut("o")
            }
            CommandMenu("Taxes") { TaxesModule.menuItems() }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ n: Notification) { NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true) }
    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { true }
}

struct RootView: View {
    @Environment(TaxStore.self) private var store
    @State private var dropping = false

    var body: some View {
        Group {
            if store.locked {
                LockView()
            } else {
                VStack(spacing: 0) {
                    TopBar()
                    Divider()
                    switch store.tab {
                    case .documents: DocumentsView()
                    case .draft: DraftView()
                    case .file: EnginesView()
                    case .packet: PacketView()
                    }
                }
                .onDrop(of: [.fileURL], isTargeted: $dropping) { providers in
                    for p in providers {
                        _ = p.loadObject(ofClass: URL.self) { url, _ in
                            if let url { Task { @MainActor in TaxStore.shared.importFiles([url]) } }
                        }
                    }
                    return true
                }
                .overlay {
                    if dropping {
                        RoundedRectangle(cornerRadius: 16).strokeBorder(TX.accent, style: StrokeStyle(lineWidth: 3, dash: [10, 6]))
                            .background(TX.accent.opacity(0.08)).padding(10)
                            .overlay(Label("Drop to import", systemImage: "square.and.arrow.down").font(.title2.weight(.semibold)).foregroundStyle(TX.accent))
                    }
                }
            }
        }
        .onAppear { store.warmUp() }
        .alert("Tax Desk", isPresented: Binding(get: { store.message != nil }, set: { if !$0 { store.message = nil } })) {
            Button("OK") { store.message = nil }
        } message: { Text(store.message ?? "") }
    }
}

struct LockView: View {
    @Environment(TaxStore.self) private var store
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.doc").font(.system(size: 60, weight: .light)).foregroundStyle(TX.accent)
            Text("Your tax documents are locked").font(.title2.weight(.semibold))
            Text("They hold your SIN or SSN and income, so they open with Touch ID, your Apple Watch or your password.")
                .foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 420)
            Button("Unlock") { store.unlock() }.buttonStyle(.borderedProminent).tint(TX.accent).controlSize(.large).keyboardShortcut(.defaultAction)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { store.unlock() }
    }
}

struct TopBar: View {
    @Environment(TaxStore.self) private var store

    var body: some View {
        @Bindable var store = store
        HStack(spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "doc.text.magnifyingglass").font(.system(size: 20, weight: .semibold)).foregroundStyle(TX.accent)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Tax Desk").font(.system(size: 16, weight: .bold))
                    Text("Drafts for your tax preparer").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            Picker("Tax year", selection: Binding(get: { store.year }, set: { store.setYear($0) })) {
                ForEach(store.years, id: \.self) { Text(String($0)).tag($0) }
            }
            .labelsHidden().fixedSize()
            Text(store.info.country.flag + " " + (store.info.country == .canada ? store.info.province : "US")).font(.system(size: 12)).foregroundStyle(.secondary)
                .help("Change the country and province in Draft Return")
            Spacer()
            Picker("", selection: $store.tab) {
                ForEach(TaxStore.Tab.allCases) { Label($0.rawValue, systemImage: $0.symbol).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()
            Spacer()
            ScanButton { data, ext in store.importData(data, ext: ext, name: "Scan \(Date().formatted(date: .abbreviated, time: .shortened)).\(ext)") }
                .frame(width: 140, height: 24)
                .help("Scan paper slips with your iPhone or iPad (Continuity Camera)")
            Button { store.chooseFiles() } label: { Label("Import", systemImage: "plus") }
                .buttonStyle(.borderedProminent).tint(TX.accent)
            if store.library.requireUnlock {
                Button { store.lock() } label: { Image(systemName: "lock") }.help("Lock")
            }
        }
        .padding(.horizontal, 16).padding(.top, 30).padding(.bottom, 10)
    }
}

/// "Scan with iPhone": shows the system's Continuity Camera menu (Take Photo, Scan Documents),
/// and receives what the phone sends back.
struct ScanButton: NSViewRepresentable {
    let onImport: (Data, String) -> Void

    func makeNSView(context: Context) -> ScanButtonView {
        let b = ScanButtonView(title: "Scan with iPhone", target: nil, action: nil)
        b.bezelStyle = .rounded
        b.image = NSImage(systemSymbolName: "iphone.gen3", accessibilityDescription: nil)
        b.imagePosition = .imageLeading
        b.target = b
        b.action = #selector(ScanButtonView.showMenu)
        b.onImport = onImport
        return b
    }

    func updateNSView(_ v: ScanButtonView, context: Context) { v.onImport = onImport }

    final class ScanButtonView: NSButton, NSServicesMenuRequestor {
        var onImport: ((Data, String) -> Void)?
        override var acceptsFirstResponder: Bool { true }

        @objc func showMenu() {
            window?.makeFirstResponder(self)
            let menu = NSMenu()
            let item = NSMenuItem(title: "Import from iPhone or iPad", action: nil, keyEquivalent: "")
            item.identifier = NSMenuItem.importFromDeviceIdentifier
            menu.addItem(item)
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: bounds.height + 4), in: self)
        }

        override func validRequestor(forSendType sendType: NSPasteboard.PasteboardType?, returnType: NSPasteboard.PasteboardType?) -> Any? {
            if let returnType, returnType == .pdf || NSImage.imageTypes.contains(returnType.rawValue) { return self }
            return super.validRequestor(forSendType: sendType, returnType: returnType)
        }

        func readSelection(from pb: NSPasteboard) -> Bool {
            if let pdf = pb.data(forType: .pdf) { onImport?(pdf, "pdf"); return true }
            if let img = NSImage(pasteboard: pb), let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
               let jpg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.9]) {
                onImport?(jpg, "jpg")
                return true
            }
            return false
        }

        func writeSelection(to pboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) -> Bool { false }
    }
}
