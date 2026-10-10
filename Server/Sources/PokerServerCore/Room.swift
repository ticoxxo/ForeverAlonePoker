import Foundation
import Logging
import PokerCore

/// One table on the server: the authority plus the delivery queue of every
/// connected WebSocket. Mirrors the remote path of the app's `HostedTable`.
///
/// Ranked play (tdr/0010): a join carrying a session token is verified here,
/// before the rules see it; the seat is remembered as ranked. When a match
/// between two ranked seats finishes, the result is published and both
/// players receive `.rated`.
public actor Room {
    public nonisolated let code: String
    public nonisolated let authority: MatchAuthority
    public nonisolated let createdAt: Date
    private var connections: [ConnectionID: AsyncStream<ServerMessage>.Continuation] = [:]
    private var lastActivity: Date
    private let ranked: RankedServices?
    private var rankedSeats: [Seat: RankedPlayer] = [:]
    /// Guards against publishing the same finished match twice.
    private var publishedCurrentMatch = false
    private let logger = Logger(label: "PokerServer.Room")

    public init(
        code: String,
        configuration: MatchConfiguration = .standard,
        deckProvider: @escaping MatchRoom.DeckProvider = { _ in Deck.shuffled() },
        ranked: RankedServices? = nil
    ) {
        self.code = code
        authority = MatchAuthority(room: MatchRoom(code: code, configuration: configuration, deckProvider: deckProvider))
        createdAt = Date()
        lastActivity = createdAt
        self.ranked = ranked
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

        var rankedPlayer: RankedPlayer?
        if case .join(let identity, let token) = message, let token, let ranked {
            switch await Self.verify(token, for: identity, with: ranked.sessions) {
            case .success(let player):
                rankedPlayer = player
            case .failure(let reason):
                deliver([Outbound(to: id, message: .rejected(reason: reason))])
                return
            }
        }

        let outbound = await authority.handle(message, from: id)
        if case .join = message, let seat = await authority.room.seat(of: id) {
            // A join without a valid token (re)claims the seat unranked.
            rankedSeats[seat] = rankedPlayer
        }
        deliver(outbound)
        await publishIfFinished()
    }

    public func detach(_ id: ConnectionID) async {
        guard let continuation = connections.removeValue(forKey: id) else { return }
        continuation.finish()
        lastActivity = Date()
        deliver(await authority.disconnect(id))
        await publishIfFinished()
    }

    public var connectionCount: Int { connections.count }

    /// Seats whose player proved their identity with a session token.
    public var rankedSeatCount: Int { rankedSeats.count }

    public func isIdle(longerThan interval: TimeInterval, now: Date = Date()) -> Bool {
        connections.isEmpty && now.timeIntervalSince(lastActivity) > interval
    }

    // MARK: - Ranked play

    private enum Verification {
        case success(RankedPlayer)
        case failure(String)
    }

    private static func verify(_ token: String, for identity: PlayerIdentity, with sessions: SessionTokenService) async -> Verification {
        guard let playerID = try? await sessions.verify(token) else {
            return .failure("Your ranked sign-in has expired. Sign in again from your profile.")
        }
        guard playerID == identity.id else {
            return .failure("The signed-in account does not match this player.")
        }
        return .success(RankedPlayer(identity))
    }

    /// Publishes a match that just reached `.finished` when both seats are
    /// ranked. Runs the CloudKit call off the actor so a slow network never
    /// blocks the table; the ratings are delivered when they come back.
    private func publishIfFinished() async {
        let room = await authority.room
        guard case .finished(let winnerSeat) = room.match.phase else {
            publishedCurrentMatch = false
            return
        }
        guard !publishedCurrentMatch else { return }
        publishedCurrentMatch = true

        guard let ranked,
              let winner = rankedSeats[winnerSeat],
              let loser = rankedSeats[winnerSeat.opponent],
              winner.playerID != loser.playerID
        else { return }

        Task { [weak self] in
            do {
                let result = try await ranked.rankings.record(winner: winner, loser: loser)
                await self?.deliverRating(result.winner, to: winnerSeat)
                await self?.deliverRating(result.loser, to: winnerSeat.opponent)
            } catch {
                await self?.logPublishFailure(error)
            }
        }
    }

    private func deliverRating(_ update: RatingUpdate, to seat: Seat) async {
        guard let connection = await authority.room.players[seat]?.connection else { return }
        deliver([Outbound(to: connection, message: .rated(update))])
    }

    private func logPublishFailure(_ error: Error) {
        logger.error("Could not publish ranked result for room \(code): \(error)")
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
    /// `nil` when the server runs without ranked play.
    public nonisolated let ranked: RankedServices?

    public init(
        generateCode: @escaping CodeGenerator = { RoomCode.random() },
        deckProvider: @escaping MatchRoom.DeckProvider = { _ in Deck.shuffled() },
        ranked: RankedServices? = nil
    ) {
        self.generateCode = generateCode
        self.deckProvider = deckProvider
        self.ranked = ranked
    }

    public func create(configuration: MatchConfiguration = .standard) -> Room {
        var code = generateCode()
        while rooms[code] != nil { code = generateCode() }
        let room = Room(code: code, configuration: configuration, deckProvider: deckProvider, ranked: ranked)
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
