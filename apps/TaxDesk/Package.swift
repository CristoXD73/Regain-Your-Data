// swift-tools-version:5.10
import PackageDescription

// TaxKit holds the app; the TaxDesk executable is a thin launcher, so the Regain Your Data hub
// can embed the same code.
let package = Package(
    name: "TaxDesk",
    platforms: [.macOS(.v14)],
    products: [.library(name: "TaxKit", targets: ["TaxKit"])],
    targets: [
        .target(name: "TaxKit", path: "Sources/TaxKit"),
        .executableTarget(name: "TaxDesk", dependencies: ["TaxKit"], path: "Sources/TaxDesk"),
    ]
)
