// swift-tools-version:5.10
import PackageDescription

// WhatsAppKit holds the app; the WhatsVault executable is a thin launcher, so the Regain Your Data hub
// can embed the same code.
let package = Package(
    name: "WhatsAppClone",
    platforms: [.macOS(.v14)],
    products: [.library(name: "WhatsAppKit", targets: ["WhatsAppKit"])],
    targets: [
        .target(name: "WhatsAppKit", path: "Sources/WhatsAppKit"),
        .executableTarget(name: "WhatsVault", dependencies: ["WhatsAppKit"], path: "Sources/WhatsVault"),
    ]
)
