// swift-tools-version: 6.0
import PackageDescription

// SkinKit is the pure model of cosmetic skins: which skin each slot (card
// front, card back, later mat and chips) shows, what the store sells, and the
// fallback rules. It reads PokerCore's `Card` but PokerCore never knows skins
// exist. No UI, networking or StoreKit here, so the app, the server and the
// catalog publisher share it. See tdr/0011 and tdr/0012.
let package = Package(
    name: "SkinKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "SkinKit", targets: ["SkinKit"]),
        // Catalog and loadout builders for every test target (tdr/0002).
        .library(name: "SkinKitTestSupport", targets: ["SkinKitTestSupport"]),
    ],
    dependencies: [
        .package(path: "../PokerCore"),
    ],
    targets: [
        .target(
            name: "SkinKit",
            dependencies: [.product(name: "PokerCore", package: "PokerCore")]
        ),
        .target(
            name: "SkinKitTestSupport",
            dependencies: ["SkinKit", .product(name: "PokerCore", package: "PokerCore")]
        ),
        .testTarget(
            name: "SkinKitTests",
            dependencies: [
                "SkinKit",
                "SkinKitTestSupport",
                .product(name: "PokerCoreTestSupport", package: "PokerCore"),
            ]
        ),
    ]
)
