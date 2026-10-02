import Foundation

/// Settings live in their own domain, shared by the standalone app and the Regain Your Data hub.
enum Prefs {
    static let defaults = UserDefaults(suiteName: "com.regainyourdata.shared.taxes") ?? .standard
}
