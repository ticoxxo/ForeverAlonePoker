import Foundation
import Logging
import PokerServerCore

let environment = ProcessInfo.processInfo.environment
let configuration = ServerConfiguration(
    hostname: environment["HOST"] ?? "0.0.0.0",
    port: Int(environment["PORT"] ?? "") ?? 8080
)

// Ranked play needs SESSION_SECRET and, for a real leaderboard, a CloudKit
// server-to-server key (CLOUDKIT_KEY_ID + CLOUDKIT_PRIVATE_KEY[_PATH]). See
// tdr/0010 for the full list of variables.
var startupLogger = Logger(label: "PokerServer")
startupLogger.logLevel = configuration.logLevel
let ranked = try await RankedServices.fromEnvironment(environment)
switch ranked {
case nil:
    startupLogger.info("Ranked play disabled: set \(RankedServices.EnvironmentKey.sessionSecret) to enable it.")
case (_, usesCloudKit: false)?:
    startupLogger.warning("Ranked play enabled with an in-memory leaderboard (no CloudKit key); ratings are lost on restart.")
case (_, usesCloudKit: true)?:
    startupLogger.info("Ranked play enabled; leaderboard in CloudKit container \(environment[RankedServices.EnvironmentKey.container] ?? RankedServices.defaultContainer).")
}

// Skin store (tdr/0012): SKINS_DIR (default SkinAssets or Server/SkinAssets),
// CATALOG_SIGNING_KEY and CATALOG_KEY_ID.
let store = try StoreConfiguration.fromEnvironment(environment)
switch store {
case nil:
    startupLogger.info("Skin store disabled: no \(StoreConfiguration.EnvironmentKey.skinsDirectory) with a manifest.json.")
case let store? where store.signer == nil:
    startupLogger.warning("Skin store serving \(store.skinsDirectory.path) UNSIGNED; release builds of the app refuse it. Set \(StoreConfiguration.EnvironmentKey.signingKey).")
case let store?:
    startupLogger.info("Skin store serving \(store.skinsDirectory.path), signed with key \(store.signer?.keyID ?? "").")
}

let app = buildApplication(configuration: configuration, registry: RoomRegistry(ranked: ranked?.services), store: store)
try await app.runService()
