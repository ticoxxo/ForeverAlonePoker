// swift-tools-version: 6.0
import PackageDescription

// The internet referee: a Hummingbird server that runs PokerCore's
// MatchAuthority per room and speaks the same wire protocol as the app.
// See tdr/0003 and tdr/0008.
let package = Package(
    name: "PokerServer",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "PokerServer", targets: ["PokerServer"]),
        .library(name: "PokerServerCore", targets: ["PokerServerCore"]),
    ],
    dependencies: [
        .package(path: "../Packages/PokerCore"),
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.0.0"),
        .package(url: "https://github.com/hummingbird-project/hummingbird-websocket.git", from: "2.0.0"),
    ],
    targets: [
        .target(
            name: "PokerServerCore",
            dependencies: [
                .product(name: "PokerCore", package: "PokerCore"),
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "HummingbirdWebSocket", package: "hummingbird-websocket"),
            ]
        ),
        .executableTarget(
            name: "PokerServer",
            dependencies: ["PokerServerCore"]
        ),
        // Development opponent for testing online play from one device.
        .executableTarget(
            name: "PokerBot",
            dependencies: [
                "PokerServerCore",
                .product(name: "PokerCore", package: "PokerCore"),
            ]
        ),
        .testTarget(
            name: "PokerServerTests",
            dependencies: [
                "PokerServerCore",
                .product(name: "PokerCoreTestSupport", package: "PokerCore"),
                .product(name: "HummingbirdTesting", package: "hummingbird"),
                .product(name: "HummingbirdWSTesting", package: "hummingbird-websocket"),
            ]
        ),
    ]
)
