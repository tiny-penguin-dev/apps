// swift-tools-version: 6.0
import PackageDescription

// Recognition code shared by the app and, later, the keyboard extension:
// the sample format, featurize, the word decoder and the Core ML wrapper.
let package = Package(
    name: "StackWriteKit",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "StackWriteKit", targets: ["StackWriteKit"]),
    ],
    targets: [
        .target(name: "StackWriteKit"),
        .testTarget(name: "StackWriteKitTests", dependencies: ["StackWriteKit"]),
    ]
)
