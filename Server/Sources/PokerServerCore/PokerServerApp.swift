import Foundation
import Hummingbird
import HummingbirdWebSocket
import Logging
import PokerCore

/// Response bodies for the small REST surface.
public struct RoomCreated: ResponseCodable, Sendable, Equatable {
    public let code: String

    public init(code: String) {
        self.code = code
    }
}

public struct RoomInfo: ResponseCodable, Sendable, Equatable {
    public let code: String
    public let seatsTaken: Int
    public let connected: Int

    public init(code: String, seatsTaken: Int, connected: Int) {
        self.code = code
        self.seatsTaken = seatsTaken
        self.connected = connected
    }
}

public struct ServerConfiguration: Sendable {
    public var hostname: String
    public var port: Int
    public var logLevel: Logger.Level

    public init(hostname: String = "0.0.0.0", port: Int = 8080, logLevel: Logger.Level = .info) {
        self.hostname = hostname
        self.port = port
        self.logLevel = logLevel
    }
}

/// Builds the Hummingbird application. Separate from `main` so tests can run
/// it in-process.
public func buildApplication(
    configuration: ServerConfiguration = ServerConfiguration(),
    registry: RoomRegistry = RoomRegistry()
) -> some ApplicationProtocol {
    var logger = Logger(label: "PokerServer")
    logger.logLevel = configuration.logLevel

    let router = Router(context: BasicWebSocketRequestContext.self)
    router.middlewares.add(LogRequestsMiddleware(.debug))

    router.get("health") { _, _ in
        "OK"
    }

    router.post("rooms") { _, _ in
        let room = await registry.create()
        return RoomCreated(code: room.code)
    }

    router.get("rooms/{code}") { _, context in
        let code = RoomCode.normalize(try context.parameters.require("code"))
        guard let room = await registry.room(code) else { throw HTTPError(.notFound) }
        let snapshot = await room.authority.room
        return RoomInfo(code: code, seatsTaken: snapshot.players.count, connected: await room.connectionCount)
    }

    router.ws("rooms/{code}/ws") { _, context in
        let code = RoomCode.normalize(context.parameters.get("code") ?? "")
        guard await registry.room(code) != nil else { return .dontUpgrade }
        return .upgrade([:])
    } onUpgrade: { inbound, outbound, context in
        let code = RoomCode.normalize(context.requestContext.parameters.get("code") ?? "")
        guard let room = await registry.room(code) else { return }
        let connection = ConnectionID(UUID().uuidString)
        let deliveries = await room.attach(connection)

        // Writer: drains the room's per-connection queue in order.
        let writer = Task {
            for await message in deliveries {
                guard let text = try? ServerWire.encode(message) else { continue }
                try await outbound.write(.text(text))
            }
        }
        defer { writer.cancel() }

        // Reader: the socket's inbound frames.
        do {
            for try await frame in inbound.messages(maxSize: 64 * 1024) {
                guard case .text(let text) = frame else { continue }
                do {
                    let message = try ServerWire.decode(ClientMessage.self, from: text)
                    await room.receive(message, from: connection)
                } catch ServerWireError.versionMismatch(let received, let expected) {
                    let reason = "Incompatible app version (\(received), server expects \(expected))."
                    try await outbound.write(.text(try ServerWire.encode(ServerMessage.rejected(reason: reason))))
                } catch {
                    context.logger.debug("Ignoring non-protocol frame")
                }
            }
        } catch {
            context.logger.debug("WebSocket closed with error: \(error)")
        }
        await room.detach(connection)
    }

    return Application(
        router: router,
        server: .http1WebSocketUpgrade(webSocketRouter: router),
        configuration: .init(address: .hostname(configuration.hostname, port: configuration.port)),
        logger: logger
    )
}
