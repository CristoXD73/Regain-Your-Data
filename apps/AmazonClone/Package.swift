// swift-tools-version:5.10
import PackageDescription

// AmazonKit holds the app; the AmazonVault executable is a thin launcher, so the Regain Your Data
// hub can embed the same code.
let package = Package(
    name: "AmazonClone",
    platforms: [.macOS(.v14)],
    products: [.library(name: "AmazonKit", targets: ["AmazonKit"])],
    dependencies: [.package(path: "../../packages/RegainCore")],
    targets: [
        .target(name: "AmazonKit", dependencies: ["RegainCore"], path: "Sources/AmazonKit"),
        .executableTarget(name: "AmazonVault", dependencies: ["AmazonKit"], path: "Sources/AmazonVault"),
    ]
)
