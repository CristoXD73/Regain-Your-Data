// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "InstaVault",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "InstaVault", path: "Sources/InstaVault")
    ]
)
