import AppKit
import SwiftUI

/// What the Regain Your Data hub needs to show Amazon Clone as one of its tabs.
public enum AmazonModule {
    @MainActor public static func makeView() -> some View {
        RootView().environment(AmazonStore.shared).preferredColorScheme(.light)
    }

    @MainActor public static func chooseFolder() { AmazonKit.chooseFolder(AmazonStore.shared) }

    @MainActor public static func menuItems() -> some View {
        ForEach(Array(AmazonStore.Tab.allCases.enumerated()), id: \.element) { i, t in
            Button(t.rawValue) { AmazonStore.shared.tab = t }
                .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: [.command, .option])
        }
    }
}

/// The hub ships each app's icon under its own name; on its own the app uses its bundle icon.
@MainActor var moduleIcon: NSImage { NSImage(named: "AmazonIcon") ?? NSApp.applicationIconImage }

enum NSWorkspaceOpen {
    static func open(_ u: URL) { NSWorkspace.shared.open(u) }
}
