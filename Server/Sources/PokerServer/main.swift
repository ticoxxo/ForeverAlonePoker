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

let app = buildApplication(configuration: configuration, registry: RoomRegistry(ranked: ranked?.services))
try await app.runService()
