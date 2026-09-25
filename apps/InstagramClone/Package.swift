// swift-tools-version:5.10
import PackageDescription

// InstagramKit holds the app; the InstaVault executable is a thin launcher, so the Regain Your Data hub
// can embed the same code.
let package = Package(
    name: "InstagramClone",
    platforms: [.macOS(.v14)],
    products: [.library(name: "InstagramKit", targets: ["InstagramKit"])],
    targets: [
        .target(name: "InstagramKit", path: "Sources/InstagramKit"),
        .executableTarget(name: "InstaVault", dependencies: ["InstagramKit"], path: "Sources/InstaVault"),
    ]
)
