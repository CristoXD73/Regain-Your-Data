import SwiftUI

/// What the Regain Your Data hub needs to show Snapchat Clone as one of its tabs.
public enum SnapchatModule {
    @MainActor public static func makeView() -> some View {
        RootView().environment(VaultStore.shared).preferredColorScheme(.dark)
    }

    @MainActor public static func chooseFolder() { SnapchatKit.chooseFolder(VaultStore.shared) }

    /// Items for the hub's menu while this module is showing.
    @MainActor public static func menuItems() -> some View {
        Group {
            ForEach(Array(Tab.allCases.enumerated()), id: \.element) { i, t in
                Button(t.rawValue) { VaultStore.shared.tab = t }
                    .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: [.command, .option])
            }
            Divider()
            Button("Lock My Eyes Only") { VaultStore.shared.lockEyesOnly() }.keyboardShortcut("l", modifiers: [.command, .control])
        }
    }
}

/// The hub ships each app's icon under its own name; on its own the app uses its bundle icon.
@MainActor var moduleIcon: NSImage { NSImage(named: "SnapchatIcon") ?? NSApp.applicationIconImage }
