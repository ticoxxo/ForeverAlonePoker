import Foundation
import Hummingbird
import HummingbirdWebSocket
import Logging
import NIOCore
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
    public let maxPlayers: Int

    public init(code: String, seatsTaken: Int, connected: Int, maxPlayers: Int) {
        self.code = code
        self.seatsTaken = seatsTaken
        self.connected = connected
        self.maxPlayers = maxPlayers
    }
}

/// Optional body of `POST /rooms` (tdr/0013). No body means heads-up.
public struct CreateRoomRequest: Codable, Sendable, Equatable {
    public let maxPlayers: Int?

    public init(maxPlayers: Int?) {
        self.maxPlayers = maxPlayers
    }

    /// The table size asked for, or `nil` when the body is not acceptable.
    static func maxPlayers(from body: ByteBuffer) -> Int? {
        guard body.readableBytes > 0 else { return TableSize.minPlayers }
        guard let request = try? JSONDecoder().decode(CreateRoomRequest.self, from: Data(body.readableBytesView)) else {
            return nil
        }
        let size = request.maxPlayers ?? TableSize.minPlayers
        return TableSize.range.contains(size) ? size : nil
    }
}

/// Body of `POST /auth/apple`.
public struct AppleSignInRequest: Codable, Sendable, Equatable {
    public let identityToken: String

    public init(identityToken: String) {
        self.identityToken = identityToken
    }
}

/// Reply of `POST /auth/apple`: the session token to send on ranked joins and
/// the player id the app must use as its `PlayerIdentity.id`.
public struct SessionIssued: ResponseCodable, Sendable, Equatable {
    public let token: String
    public let playerID: String

    public init(token: String, playerID: String) {
        self.token = token
        self.playerID = playerID
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
///
/// - Parameter store: the skin store's files and signing key (tdr/0012);
///   `nil` answers 503 on `/store/catalog` and serves no skin files.
public func buildApplication(
    configuration: ServerConfiguration = ServerConfiguration(),
    registry: RoomRegistry = RoomRegistry(),
    store: StoreConfiguration? = nil
) -> some ApplicationProtocol {
    var logger = Logger(label: "PokerServer")
    logger.logLevel = configuration.logLevel

    let router = Router(context: BasicWebSocketRequestContext.self)
    router.middlewares.add(LogRequestsMiddleware(.debug))
    if let store {
        // Skin artwork. In production the manifest's assetBaseURL points at a
        // CDN instead and this only serves development.
        router.middlewares.add(FileMiddleware(
            store.skinsDirectory.path,
            urlBasePath: "/skins",
            cacheControl: .init([(MediaType(type: .image), [.maxAge(60 * 60 * 24 * 30)])])
        ))
    }
    let catalogs = store.map { CatalogService(manifestURL: $0.manifestURL, signer: $0.signer) }

    router.get("health") { _, _ in
        "OK"
    }

    // Sign in with Apple exchange (tdr/0010): the app sends Apple's identity
    // token once; we verify it and hand back our own long-lived session token.
    router.post("auth/apple") { request, context in
        guard let ranked = registry.ranked else {
            throw HTTPError(.serviceUnavailable, message: "Ranked play is not enabled on this server.")
        }
        let body = try await request.decode(as: AppleSignInRequest.self, context: context)
        let playerID: String
        do {
            playerID = try await ranked.verifier.verify(identityToken: body.identityToken)
        } catch {
            context.logger.info("Rejected Apple identity token: \(error)")
            throw HTTPError(.unauthorized, message: "Apple could not verify this sign-in.")
        }
        return SessionIssued(token: try await ranked.sessions.issue(playerID: playerID), playerID: playerID)
    }

    // Skin catalog (tdr/0012): the manifest as signed bytes. Clients revalidate
    // with If-None-Match; publishing a new manifest needs no restart.
    router.get("store/catalog") { request, context -> Response in
        guard let catalogs else {
            throw HTTPError(.serviceUnavailable, message: "The skin store is not configured on this server.")
        }
        let published = try await catalogs.current()
        return try await request.ifNoneMatch(
            headers: [.cacheControl: "no-cache"],
            eTag: published.etag,
            context: context
        ) {
            published.catalog
        }
    }

    router.post("rooms") { request, _ in
        let body = try await request.body.collect(upTo: 1024)
        guard let maxPlayers = CreateRoomRequest.maxPlayers(from: body) else {
            throw HTTPError(.badRequest, message: "maxPlayers must be between \(TableSize.minPlayers) and \(TableSize.maxPlayers).")
        }
        let room = await registry.create(configuration: MatchConfiguration(maxPlayers: maxPlayers))
        return RoomCreated(code: room.code)
    }

    router.get("rooms/{code}") { _, context in
        let code = RoomCode.normalize(try context.parameters.require("code"))
        guard let room = await registry.room(code) else { throw HTTPError(.notFound) }
        let snapshot = await room.authority.room
        return RoomInfo(
            code: code,
            seatsTaken: snapshot.players.count,
            connected: await room.connectionCount,
            maxPlayers: snapshot.maxPlayers
        )
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
        // Ping every 10 s so a phone that vanished from the network is noticed
        // soon; its seat is then held for a reconnect (tdr/0016).
        server: .http1WebSocketUpgrade(
            webSocketRouter: router,
            configuration: WebSocketServerConfiguration(autoPing: .enabled(timePeriod: .seconds(10)))
        ),
        configuration: .init(address: .hostname(configuration.hostname, port: configuration.port)),
        logger: logger
    )
}
