import SwiftUI

/// What the Regain Your Data hub needs to show Photos Clone as one of its tabs.
public enum PhotosModule {
    @MainActor static let store = LibraryStore()

    @MainActor public static func makeView() -> some View {
        RootView().environment(store)
    }

    @MainActor public static func chooseFolder() { PhotosKit.chooseFolder(store) }

    @MainActor public static func settingsView() -> some View { SettingsView().environment(store) }

    /// Photos Clone's Image and View menus, for the hub's menu while this module is showing.
    @MainActor public static func menuItems() -> some View {
        Group {
            Button("Free Up Space…") { store.showStorage = true }.disabled(store.phase != .ready)
            Divider()
            Button("Favorite / Unfavorite") { store.toggleFavorite(store.targetIDs) }.disabled(store.targetIDs.isEmpty)
            Button("Hide") { store.setHidden(store.targetIDs, true) }.keyboardShortcut("l").disabled(store.targetIDs.isEmpty)
            Button("Delete") { store.moveToTrash(store.targetIDs) }
                .disabled(store.targetIDs.isEmpty || store.selection == .recentlyDeleted)
            Divider()
            Button("Zoom In") { store.thumbnailSize = min(400, store.thumbnailSize + 40) }.keyboardShortcut("+")
            Button("Zoom Out") { store.thumbnailSize = max(70, store.thumbnailSize - 40) }.keyboardShortcut("-")
            Button(store.showInfo ? "Hide Info" : "Show Info") { store.showInfo.toggle() }.keyboardShortcut("i")
            Divider()
            Button("Lock Hidden Album") { store.lock() }.keyboardShortcut("l", modifiers: [.command, .control])
        }
    }
}
