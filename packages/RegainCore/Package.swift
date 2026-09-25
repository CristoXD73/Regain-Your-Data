// swift-tools-version:5.10
import PackageDescription

// Shared by the newer modules and the Regain Your Data hub: reading zips in place, CSVs, and a
// browser for any export's files.
let package = Package(
    name: "RegainCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "RegainCore", targets: ["RegainCore"])],
    targets: [.target(name: "RegainCore", path: "Sources/RegainCore")]
)
