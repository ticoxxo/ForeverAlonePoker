import Foundation
import PokerCore

/// One table on the server: the authority plus the delivery queue of every
/// connected WebSocket. Mirrors the remote path of the app's `HostedTable`.
public actor Room {
    public nonisolated let code: String
    public nonisolated let authority: MatchAuthority
    public nonisolated let createdAt: Date
    private var connections: [ConnectionID: AsyncStream<ServerMessage>.Continuation] = [:]
    private var lastActivity: Date

    public init(
        code: String,
        configuration: MatchConfiguration = .standard,
        deckProvider: @escaping MatchRoom.DeckProvider = { _ in Deck.shuffled() }
    ) {
        self.code = code
        authority = MatchAuthority(room: MatchRoom(code: code, configuration: configuration, deckProvider: deckProvider))
        createdAt = Date()
        lastActivity = createdAt
    }

    /// Registers a connection and returns the stream its socket should drain.
    public func attach(_ id: ConnectionID) -> AsyncStream<ServerMessage> {
        let (stream, continuation) = AsyncStream<ServerMessage>.makeStream()
        connections[id] = continuation
        lastActivity = Date()
        return stream
    }

    public func receive(_ message: ClientMessage, from id: ConnectionID) async {
        guard connections[id] != nil else { return }
        lastActivity = Date()
        deliver(await authority.handle(message, from: id))
    }

    public func detach(_ id: ConnectionID) async {
        guard let continuation = connections.removeValue(forKey: id) else { return }
        continuation.finish()
        lastActivity = Date()
        deliver(await authority.disconnect(id))
    }

    public var connectionCount: Int { connections.count }

    public func isIdle(longerThan interval: TimeInterval, now: Date = Date()) -> Bool {
        connections.isEmpty && now.timeIntervalSince(lastActivity) > interval
    }

    private func deliver(_ outbound: [Outbound]) {
        for item in outbound {
            connections[item.to]?.yield(item.message)
        }
    }
}

/// All rooms on this server instance. In memory by design (tdr/0003).
public actor RoomRegistry {
    public typealias CodeGenerator = @Sendable () -> String

    private var rooms: [String: Room] = [:]
    private let generateCode: CodeGenerator
    private let deckProvider: MatchRoom.DeckProvider

    public init(
        generateCode: @escaping CodeGenerator = { RoomCode.random() },
        deckProvider: @escaping MatchRoom.DeckProvider = { _ in Deck.shuffled() }
    ) {
        self.generateCode = generateCode
        self.deckProvider = deckProvider
    }

    public func create(configuration: MatchConfiguration = .standard) -> Room {
        var code = generateCode()
        while rooms[code] != nil { code = generateCode() }
        let room = Room(code: code, configuration: configuration, deckProvider: deckProvider)
        rooms[code] = room
        return room
    }

    public func room(_ code: String) -> Room? {
        rooms[code]
    }

    public var count: Int { rooms.count }

    /// Drops rooms nobody has touched for a while. Returns how many were removed.
    public func sweep(idleLongerThan interval: TimeInterval, now: Date = Date()) async -> Int {
        var removed = 0
        for (code, room) in rooms where await room.isIdle(longerThan: interval, now: now) {
            rooms[code] = nil
            removed += 1
        }
        return removed
    }
}
