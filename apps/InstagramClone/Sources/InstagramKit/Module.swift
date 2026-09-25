import SwiftUI

/// What the Regain Your Data hub needs to show Instagram Clone as one of its tabs.
public enum InstagramModule {
    @MainActor public static func makeView() -> some View {
        RootView().environment(InstaStore.shared).preferredColorScheme(.dark)
    }

    @MainActor public static func chooseFolder() { InstagramKit.chooseFolder(InstaStore.shared) }

    /// Items for the hub's menu while this module is showing.
    @MainActor public static func menuItems() -> some View {
        Toggle("Gradient Background", isOn: Binding(get: { InstaStore.shared.gradientBackground },
                                                     set: { InstaStore.shared.gradientBackground = $0 }))
    }
}

/// The hub ships each app's icon under its own name; on its own the app uses its bundle icon.
@MainActor var moduleIcon: NSImage { NSImage(named: "InstagramIcon") ?? NSApp.applicationIconImage }
