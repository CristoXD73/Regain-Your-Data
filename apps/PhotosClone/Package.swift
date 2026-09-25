// swift-tools-version:5.10
import PackageDescription

// PhotosKit holds the app; the PhotosClone executable is a thin launcher, so the Regain Your Data hub
// can embed the same code.
let package = Package(
    name: "PhotosClone",
    platforms: [.macOS(.v14)],
    products: [.library(name: "PhotosKit", targets: ["PhotosKit"])],
    targets: [
        .target(name: "PhotosKit", path: "Sources/PhotosKit"),
        .executableTarget(name: "PhotosClone", dependencies: ["PhotosKit"], path: "Sources/PhotosClone"),
    ]
)
