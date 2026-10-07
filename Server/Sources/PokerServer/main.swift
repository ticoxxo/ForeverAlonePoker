import Foundation
import PokerServerCore

let environment = ProcessInfo.processInfo.environment
let configuration = ServerConfiguration(
    hostname: environment["HOST"] ?? "0.0.0.0",
    port: Int(environment["PORT"] ?? "") ?? 8080
)
let app = buildApplication(configuration: configuration)
try await app.runService()
