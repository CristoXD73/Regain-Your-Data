import SwiftUI

/// What the Regain Your Data hub needs to show WhatsApp Clone as one of its tabs.
public enum WhatsAppModule {
    @MainActor public static func makeView() -> some View {
        RootView().environment(WAStore.shared).preferredColorScheme(.dark)
    }

    @MainActor public static func chooseFolder() { WhatsAppKit.chooseFolder(WAStore.shared) }

    @MainActor public static func menuItems() -> some View { EmptyView() }
}

/// The hub ships each app's icon under its own name; on its own the app uses its bundle icon.
@MainActor var moduleIcon: NSImage { NSImage(named: "WhatsAppIcon") ?? NSApp.applicationIconImage }
