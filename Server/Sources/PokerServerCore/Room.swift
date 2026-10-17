import Foundation
import Logging
import PokerCore

/// One table on the server: the authority plus the delivery queue of every
/// connected WebSocket. Mirrors the remote path of the app's `HostedTable`.
///
/// Ranked play (tdr/0010, tdr/0013): a join carrying a session token is
/// verified here, before the rules see it; the seat is remembered as ranked.
/// When a match in which every player is ranked finishes, the winner gains,
/// every loser drops, and each player still connected receives `.rated`.
///
/// Starting a table of three or more (tdr/0013): after the host's
/// `startMatch` the room waits up to `graceInterval` for sockets that are
/// open but not yet seated, then deals.
///
/// Between hands (tdr/0014) the room deals the next hand `nextHandPause`
/// after the last one ends, and a player whose socket dropped is knocked out
/// if they have not rejoined within `absenceTimeout`.
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
    private let graceInterval: Duration
    private var graceTask: Task<Void, Never>?
    private let nextHandPause: Duration
    private var nextHandTask: Task<Void, Never>?
    private let absenceTimeout: Duration
    private var absenceTasks: [MatchRoom.Absence: Task<Void, Never>] = [:]
    private let logger = Logger(label: "PokerServer.Room")

    public static let defaultGraceInterval: Duration = .seconds(5)
    public static let defaultNextHandPause: Duration = .seconds(4)
    public static let defaultAbsenceTimeout: Duration = .seconds(60)

    public init(
        code: String,
        configuration: MatchConfiguration = .standard,
        deckProvider: @escaping MatchRoom.DeckProvider = { _ in Deck.shuffled() },
        ranked: RankedServices? = nil,
        graceInterval: Duration = Room.defaultGraceInterval,
        nextHandPause: Duration = Room.defaultNextHandPause,
        absenceTimeout: Duration = Room.defaultAbsenceTimeout
    ) {
        self.code = code
        authority = MatchAuthority(room: MatchRoom(
            code: code,
            configuration: configuration,
            isRankedCapable: ranked != nil,
            deckProvider: deckProvider
        ))
        createdAt = Date()
        lastActivity = createdAt
        self.ranked = ranked
        self.graceInterval = graceInterval
        self.nextHandPause = nextHandPause
        self.absenceTimeout = absenceTimeout
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

        let (outbound, absence) = await authority.receive(message, from: id, verifiedRanked: rankedPlayer != nil)
        if case .join = message, let seat = await authority.room.seat(of: id) {
            // A join without a valid token (re)claims the seat unranked.
            rankedSeats[seat] = rankedPlayer
        }
        deliver(outbound)
        // Leaving a match in play holds the seat like a drop (tdr/0016).
        if let absence { scheduleExpiry(of: absence) }
        if case .startMatch = message {
            await scheduleBegin()
        }
        await publishIfFinished()
        await scheduleNextHand()
    }

    /// Deals once every open socket has taken a seat or the grace period ends.
    private func scheduleBegin() async {
        guard graceTask == nil, await authority.isStarting else { return }
        let grace = graceInterval
        graceTask = Task { [weak self] in
            guard let self else { return }
            let outbound = await self.authority.beginAfterGrace(grace: grace) { [weak self] in
                await self?.openConnections() ?? []
            }
            await self.finishBegin(outbound)
        }
    }

    private func openConnections() -> Set<ConnectionID> {
        Set(connections.keys)
    }

    private func finishBegin(_ outbound: [Outbound]) async {
        graceTask = nil
        deliver(outbound)
        await publishIfFinished()
        await scheduleNextHand()
    }

    /// Waits for a pending start to deal. For tests.
    public func waitForStart() async {
        await graceTask?.value
    }

    /// Deals the next hand after the pause whenever one is due.
    private func scheduleNextHand() async {
        guard nextHandTask == nil, let ticket = await authority.nextHandTicket else { return }
        let pause = nextHandPause
        nextHandTask = Task { [weak self] in
            guard let self else { return }
            let outbound = await self.authority.dealNextHand(ticket: ticket, after: pause)
            await self.finishNextHand(outbound)
        }
    }

    private func finishNextHand(_ outbound: [Outbound]) async {
        nextHandTask = nil
        deliver(outbound)
        await publishIfFinished()
        await scheduleNextHand()
    }

    /// Waits for a scheduled next hand. For tests.
    public func waitForNextHand() async {
        await nextHandTask?.value
    }

    public func detach(_ id: ConnectionID) async {
        guard let continuation = connections.removeValue(forKey: id) else { return }
        continuation.finish()
        lastActivity = Date()
        let (outbound, absence) = await authority.disconnect(id)
        deliver(outbound)
        if let absence { scheduleExpiry(of: absence) }
        await publishIfFinished()
        await scheduleNextHand()
    }

    /// Knocks the player out if they are still away after the timeout.
    private func scheduleExpiry(of absence: MatchRoom.Absence) {
        let timeout = absenceTimeout
        absenceTasks[absence] = Task { [weak self] in
            guard let self else { return }
            let outbound = await self.authority.expire(absence, after: timeout)
            await self.finishExpiry(absence, outbound)
        }
    }

    private func finishExpiry(_ absence: MatchRoom.Absence, _ outbound: [Outbound]) async {
        absenceTasks[absence] = nil
        deliver(outbound)
        await publishIfFinished()
        await scheduleNextHand()
    }

    /// Waits for every pending absence to expire or lapse. For tests.
    public func waitForAbsences() async {
        for task in absenceTasks.values { await task.value }
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

        // Every player who took part must be ranked, and all distinct.
        let loserSeats = room.match.players.filter { $0 != winnerSeat }
        guard let ranked,
              let winner = rankedSeats[winnerSeat],
              case let losers = loserSeats.compactMap({ rankedSeats[$0] }),
              losers.count == loserSeats.count,
              Set(([winner] + losers).map(\.playerID)).count == losers.count + 1
        else { return }

        Task { [weak self] in
            do {
                let result = try await ranked.rankings.record(winner: winner, losers: losers)
                await self?.deliverRating(result.winner, to: winnerSeat)
                for (seat, update) in zip(loserSeats, result.losers) {
                    await self?.deliverRating(update, to: seat)
                }
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
