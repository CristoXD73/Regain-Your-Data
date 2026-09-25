// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "WhatsVault",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "WhatsVault", path: "Sources/WhatsVault")
    ]
)
