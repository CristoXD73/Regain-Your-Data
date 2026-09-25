// swift-tools-version:5.10
import PackageDescription

// SnapchatKit holds the app; the SnapVault executable is a thin launcher, so the Regain Your Data hub
// can embed the same code.
let package = Package(
    name: "SnapchatClone",
    platforms: [.macOS(.v14)],
    products: [.library(name: "SnapchatKit", targets: ["SnapchatKit"])],
    targets: [
        .target(name: "SnapchatKit", path: "Sources/SnapchatKit"),
        .executableTarget(name: "SnapVault", dependencies: ["SnapchatKit"], path: "Sources/SnapVault"),
    ]
)
