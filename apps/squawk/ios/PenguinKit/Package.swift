// swift-tools-version: 6.0
import PackageDescription

// Squawk the penguin, drawn from SwiftUI shapes. Nothing in here is specific to the
// Squawk app, so it can move to the repo's packages/ folder when a second app needs it.
let package = Package(
    name: "PenguinKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "PenguinKit", targets: ["PenguinKit"]),
    ],
    targets: [
        .target(name: "PenguinKit"),
        .testTarget(name: "PenguinKitTests", dependencies: ["PenguinKit"]),
    ]
)
