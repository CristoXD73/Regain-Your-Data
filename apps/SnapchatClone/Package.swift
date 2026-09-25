// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "SnapVault",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "SnapVault", path: "Sources/SnapVault")
    ]
)
