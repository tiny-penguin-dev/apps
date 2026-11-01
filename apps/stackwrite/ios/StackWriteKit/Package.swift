// swift-tools-version: 6.0
import PackageDescription

// StackWrite's code, shared by the app and the keyboard extension (BUILD.md):
// - StackWriteCore: the typing engine, the dictionary, the rules for Free and Pro,
//   and the stores. Foundation only, so `swift test` runs on Linux in CI.
//   The v1 handwriting pieces live in Handwriting/ behind `Flags.handwritingPad`.
// - StackWriteUI: the design system and the keyboard's views (UIKit and SwiftUI).
let package = Package(
    name: "StackWriteKit",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "StackWriteCore", targets: ["StackWriteCore"]),
        .library(name: "StackWriteUI", targets: ["StackWriteUI"]),
    ],
    targets: [
        .target(name: "StackWriteCore", resources: [.copy("Resources/lexicon.tsv")]),
        .target(name: "StackWriteUI", dependencies: ["StackWriteCore"]),
        .testTarget(name: "StackWriteKitTests", dependencies: ["StackWriteCore"], exclude: ["Fixtures"]),
    ]
)
