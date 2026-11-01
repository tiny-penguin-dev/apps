// swift-tools-version: 6.0
import PackageDescription

// Astrotype's code, shared by the app and the keyboard extension (BUILD.md):
// - AstrotypeCore: the typing engine, the dictionary, the rules for Free and Pro,
//   and the stores. Foundation only, so `swift test` runs on Linux in CI.
//   The v1 handwriting pieces live in Handwriting/ behind `Flags.handwritingPad`.
// - AstrotypeUI: the design system and the keyboard's views (UIKit and SwiftUI).
let package = Package(
    name: "AstrotypeKit",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "AstrotypeCore", targets: ["AstrotypeCore"]),
        .library(name: "AstrotypeUI", targets: ["AstrotypeUI"]),
    ],
    targets: [
        .target(name: "AstrotypeCore", resources: [.copy("Resources/lexicon.tsv")]),
        .target(name: "AstrotypeUI", dependencies: ["AstrotypeCore"]),
        .testTarget(name: "AstrotypeKitTests", dependencies: ["AstrotypeCore"], exclude: ["Fixtures"]),
    ]
)
