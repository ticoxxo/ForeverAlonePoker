// swift-tools-version: 6.0
import PackageDescription

// PokerCore is the pure, platform-agnostic game engine shared by the iOS app
// and the Hummingbird server. It must never depend on UIKit, SwiftUI or any
// networking framework. See tdr/0001-core-package-and-feature-folders.md.
let package = Package(
    name: "PokerCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "PokerCore", targets: ["PokerCore"]),
        // Test builders shared by every test target (app, core, server) so test
        // scaffolding is written once. See tdr/0002-tdd-with-shared-builders.md.
        .library(name: "PokerCoreTestSupport", targets: ["PokerCoreTestSupport"]),
    ],
    targets: [
        .target(
            name: "PokerCore"
        ),
        .target(
            name: "PokerCoreTestSupport",
            dependencies: ["PokerCore"]
        ),
        .testTarget(
            name: "PokerCoreTests",
            dependencies: ["PokerCore", "PokerCoreTestSupport"]
        ),
    ]
)
