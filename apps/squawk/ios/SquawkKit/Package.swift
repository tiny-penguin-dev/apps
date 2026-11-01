// swift-tools-version: 6.0
import PackageDescription

// Squawk's alarm model, storage and planning. No UI and no AlarmKit, so it runs and
// tests anywhere. The app turns its plans into AlarmKit alarms.
let package = Package(
    name: "SquawkKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "SquawkKit", targets: ["SquawkKit"]),
    ],
    targets: [
        .target(name: "SquawkKit"),
        .testTarget(name: "SquawkKitTests", dependencies: ["SquawkKit"]),
    ]
)
