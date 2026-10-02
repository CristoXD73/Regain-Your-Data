import AppKit
import SwiftUI

/// What the Regain Your Data hub needs to show Tax Desk as one of its tabs.
public enum TaxesModule {
    @MainActor public static func makeView() -> some View {
        RootView().environment(TaxStore.shared)
    }

    /// One line for the hub's home page. Reads only the document count, so it works while locked.
    @MainActor public static var summary: String {
        let docs = TaxStore.shared.library.documents
        guard !docs.isEmpty else { return "No documents yet" }
        let years = Set(docs.compactMap(\.year)).sorted().map(String.init)
        return "\(docs.count) document\(docs.count == 1 ? "" : "s") · \(years.joined(separator: ", ")) · locked with Touch ID"
    }

    /// ⌘O in the hub imports documents.
    @MainActor public static func chooseFolder() { TaxStore.shared.chooseFiles() }

    @MainActor public static func menuItems() -> some View {
        Group {
            ForEach(Array(TaxStore.Tab.allCases.enumerated()), id: \.element) { i, t in
                Button(t.rawValue) { TaxStore.shared.tab = t }
                    .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: [.command, .option])
            }
            Divider()
            Button("Lock Tax Documents") { TaxStore.shared.lock() }.keyboardShortcut("l", modifiers: [.command, .control])
        }
    }
}
