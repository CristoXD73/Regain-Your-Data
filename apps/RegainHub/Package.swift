// swift-tools-version:5.10
import PackageDescription

// Regain Your Data: one app that holds all the others. Each app lives in its own package as a
// library ("kit"), so it builds on its own too; the hub just switches between them.
let package = Package(
    name: "RegainHub",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../PhotosClone"),
        .package(path: "../SnapchatClone"),
        .package(path: "../InstagramClone"),
        .package(path: "../WhatsAppClone"),
        .package(path: "../AmazonClone"),
        .package(path: "../../packages/RegainCore"),
    ],
    targets: [
        .executableTarget(
            name: "RegainHub",
            dependencies: [
                .product(name: "PhotosKit", package: "PhotosClone"),
                .product(name: "SnapchatKit", package: "SnapchatClone"),
                .product(name: "InstagramKit", package: "InstagramClone"),
                .product(name: "WhatsAppKit", package: "WhatsAppClone"),
                .product(name: "AmazonKit", package: "AmazonClone"),
                .product(name: "RegainCore", package: "RegainCore"),
            ],
            path: "Sources/RegainHub"
        )
    ]
)
