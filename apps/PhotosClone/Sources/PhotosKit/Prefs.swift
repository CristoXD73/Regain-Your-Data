import Foundation

/// Settings live in their own domain, shared by the standalone app and the Regain Your Data hub,
/// so both open the same export and neither clashes with the other apps' keys.
enum Prefs {
    static let defaults = UserDefaults(suiteName: "com.regainyourdata.shared.photos") ?? .standard
}
