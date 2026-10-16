/// Identifies one transport connection (a WebSocket, a nearby peer, an
/// in-memory pipe). The room maps connections to seats.
public struct ConnectionID: Hashable, Sendable, Codable, RawRepresentable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String { rawValue }
}

/// A message the room wants delivered to a specific connection.
public struct Outbound: Sendable, Hashable {
    public let to: ConnectionID
    public let message: ServerMessage

    public init(to: ConnectionID, message: ServerMessage) {
        self.to = to
        self.message = message
    }
}

/// The referee for one table of two to six seats. It owns the only unredacted
/// `MatchState`, validates every client message, and returns the messages to
/// deliver. It is a pure value: the same code runs inside the Hummingbird
/// server and on the hosting device in local play, and tests drive it
/// directly with no transport at all.
///
/// Lifecycle (tdr/0013): the room starts in the lobby. The first player to
/// join is the host. A heads-up table deals as soon as the second player sits
/// down; a bigger table deals when the host sends `startMatch` and the hosting
/// layer calls `beginMatch()` after its grace period. Once the match has begun
/// only seated players may (re)join; knocked-out players stay and watch.
public struct MatchRoom: Sendable {
    public typealias DeckProvider = @Sendable (_ handNumber: Int) -> Deck

    public struct SeatedPlayer: Sendable, Hashable {
        public let identity: PlayerIdentity
        /// `nil` while the player is disconnected but may still reclaim the seat.
        public var connection: ConnectionID?
        public var isReady: Bool
        /// The server verified this player's ranked session token.
        public var isRanked: Bool
    }

    public let code: String
    public let configuration: MatchConfiguration
    /// Whether the authority can rate matches (tdr/0010). Only the internet
    /// server with ranked play configured sets it.
    public let isRankedCapable: Bool
    public private(set) var match: MatchState
    public private(set) var players: [Seat: SeatedPlayer] = [:]
    public private(set) var host: Seat?
    /// The host asked to start; waiting for `beginMatch()`.
    public private(set) var isStarting = false
    /// The first hand has been dealt; the lobby is closed.
    public private(set) var hasBegun = false
    private let deckProvider: DeckProvider

    /// - Parameter deckProvider: supplies the deck for each hand. Defaults to a
    ///   fresh system-shuffled deck; tests inject rigged decks.
    public init(
        code: String,
        configuration: MatchConfiguration = .standard,
        isRankedCapable: Bool = false,
        deckProvider: @escaping DeckProvider = { _ in Deck.shuffled() }
    ) {
        self.code = code
        self.configuration = configuration
        self.isRankedCapable = isRankedCapable
        match = MatchState(configuration: configuration)
        self.deckProvider = deckProvider
    }

    public var maxPlayers: Int { configuration.maxPlayers }
    public var isFull: Bool { players.count == maxPlayers }
    public var isEmpty: Bool { players.isEmpty }
    /// `.lobby` until the first hand is dealt, then the match's phase.
    public var phase: MatchPhase { hasBegun ? match.phase : .lobby }
    public var connectedSeats: [Seat] { players.keys.sorted().filter { players[$0]?.connection != nil } }
    /// Every seated player is ranked, so a finished match changes ratings.
    public var isEloEnabled: Bool {
        isRankedCapable && !players.isEmpty && players.values.allSatisfy(\.isRanked)
    }

    public func seat(of connection: ConnectionID) -> Seat? {
        players.first { $0.value.connection == connection }?.key
    }

    // MARK: - Handling messages

    /// - Parameter verifiedRanked: the server checked the join's session token
    ///   (tdr/0010). The rules never see tokens themselves.
    public mutating func handle(_ message: ClientMessage, from connection: ConnectionID, verifiedRanked: Bool = false) -> [Outbound] {
        switch message {
        case .join(let identity, _):
            return join(identity, from: connection, ranked: verifiedRanked)
        case .ready:
            guard let seat = seat(of: connection) else { return [reject(connection, "Join the room first.")] }
            return ready(seat)
        case .act(let action):
            guard let seat = seat(of: connection) else { return [reject(connection, "Join the room first.")] }
            return act(action, by: seat, connection: connection)
        case .leave:
            guard let seat = seat(of: connection) else { return [] }
            return leave(seat)
        case .startMatch:
            guard let seat = seat(of: connection) else { return [reject(connection, "Join the room first.")] }
            return requestStart(by: seat, connection: connection)
        }
    }

    /// The transport dropped. The seat is kept so the same identity can rejoin;
    /// mid-hand the player is folded, and later hands fold them when the
    /// action reaches them.
    public mutating func disconnect(_ connection: ConnectionID) -> [Outbound] {
        guard let seat = seat(of: connection) else { return [] }
        players[seat]?.connection = nil
        players[seat]?.isReady = false
        var events: [GameEvent] = []
        if hasBegun, match.phase == .inHand {
            events = (try? match.forfeit(seat)) ?? []
            events += foldAbsentActors()
        }
        return broadcast(events) + broadcastStates()
    }

    /// Deals the first hand after the host's grace period. Players still
    /// disconnected lose their seat. Does nothing unless the host asked to start.
    public mutating func beginMatch() -> [Outbound] {
        guard isStarting, !hasBegun else { return [] }
        return begin()
    }

    // MARK: - Views

    public func view(for seat: Seat) -> PlayerView {
        let hand = hasBegun ? match.currentHand : nil
        let inHand = phase == .inHand
        return PlayerView(
            seat: seat,
            me: summary(of: seat, hand: hand) ?? PlayerSummary(
                seat: seat, name: "", stack: match.stack(for: seat), streetCommitted: 0,
                hasFolded: false, isAllIn: false, isReady: false, isConnected: false
            ),
            players: (1..<maxPlayers).compactMap { step in
                summary(of: seat.advanced(by: step, tableSize: maxPlayers), hand: hand)
            },
            table: TableInfo(
                maxPlayers: maxPlayers,
                host: host,
                isStarting: isStarting,
                isRankedCapable: isRankedCapable,
                isEloEnabled: isEloEnabled
            ),
            phase: phase,
            handNumber: hand?.handNumber ?? match.handsPlayed,
            button: hand?.button ?? match.button,
            street: hand?.street,
            holeCards: hand?[seat].holeCards ?? [],
            community: hand?.community ?? [],
            pot: (hand?.isOver == false) ? (hand?.pot ?? 0) : 0,
            actor: inHand ? hand?.actor : nil,
            isMyTurn: inHand && hand?.actor == seat,
            legalActions: inHand ? HandEngine.legalActions(in: hand!, for: seat) : .none,
            lastResult: hand?.result
        )
    }

    private func summary(of seat: Seat, hand: HandState?) -> PlayerSummary? {
        guard let player = players[seat] else { return nil }
        let live = hand.flatMap { $0.isOver ? nil : $0[seat] }
        return PlayerSummary(
            seat: seat,
            playerID: player.identity.id,
            name: player.identity.displayName,
            countryCode: player.identity.countryCode,
            stack: live?.stack ?? (hasBegun ? match.stack(for: seat) : configuration.startingStack),
            streetCommitted: live?.streetCommitted ?? 0,
            hasFolded: hand?[seat].hasFolded ?? false,
            isAllIn: live?.isAllIn ?? false,
            isReady: player.isReady,
            isConnected: player.connection != nil,
            isRanked: player.isRanked,
            isBusted: hasBegun && match.isBusted(seat),
            place: hasBegun ? match.place(of: seat) : nil
        )
    }

    // MARK: - Private handlers

    private mutating func join(_ identity: PlayerIdentity, from connection: ConnectionID, ranked: Bool) -> [Outbound] {
        if seat(of: connection) != nil {
            return [reject(connection, "Already seated.")]
        }
        // Reclaim a seat held for this identity (reconnect).
        if let seat = players.first(where: { $0.value.identity.id == identity.id && $0.value.connection == nil })?.key {
            players[seat]?.connection = connection
            players[seat]?.isRanked = ranked
            return [Outbound(to: connection, message: .welcome(seat: seat, roomCode: code))] + broadcastStates()
        }
        // A finished match nobody can rematch reopens the lobby for newcomers.
        if hasBegun, case .finished = match.phase, connectedSeats.count < TableSize.minPlayers {
            reopenLobby()
        }
        if hasBegun {
            return [reject(connection, "The game has already started.")]
        }
        guard let seat = Seat.all(count: maxPlayers).first(where: { players[$0] == nil }) else {
            return [reject(connection, "Room is full.")]
        }
        players[seat] = SeatedPlayer(identity: identity, connection: connection, isReady: false, isRanked: ranked)
        if host == nil { host = seat }
        let out = [Outbound(to: connection, message: .welcome(seat: seat, roomCode: code))]
        // Heads-up starts by itself as soon as both seats are taken.
        if maxPlayers == TableSize.minPlayers, isFull {
            isStarting = true
            return out + begin()
        }
        return out + broadcastStates()
    }

    private mutating func requestStart(by seat: Seat, connection: ConnectionID) -> [Outbound] {
        guard seat == host else { return [reject(connection, "Only the host can start the game.")] }
        guard !hasBegun else { return [reject(connection, "The game has already started.")] }
        guard connectedSeats.count >= TableSize.minPlayers else {
            return [reject(connection, "Wait for at least one more player.")]
        }
        isStarting = true
        return broadcastStates()
    }

    private mutating func begin() -> [Outbound] {
        for seat in players.keys where players[seat]?.connection == nil {
            players[seat] = nil
        }
        reassignHostIfNeeded()
        let seats = players.keys.sorted()
        guard seats.count >= TableSize.minPlayers else {
            isStarting = false
            return broadcastStates()
        }
        match = MatchState(configuration: configuration, players: seats, firstButton: seats[0])
        hasBegun = true
        isStarting = false
        return deal()
    }

    private mutating func reopenLobby() {
        for seat in players.keys where players[seat]?.connection == nil {
            players[seat] = nil
        }
        reassignHostIfNeeded()
        match = MatchState(configuration: configuration)
        hasBegun = false
        isStarting = false
        for seat in players.keys { players[seat]?.isReady = false }
    }

    private mutating func reassignHostIfNeeded() {
        if let host, players[host] != nil { return }
        host = players.keys.min()
    }

    private mutating func ready(_ seat: Seat) -> [Outbound] {
        guard hasBegun else { return [] }
        switch match.phase {
        case .inHand, .lobby:
            return []
        case .waitingForHand:
            players[seat]?.isReady = true
            // Everyone still in with a live connection must be ready; absent
            // players are dealt in and folded when the action reaches them.
            let needed = connectedSeats.filter { match.stack(for: $0) > 0 }
            guard needed.count >= TableSize.minPlayers, needed.allSatisfy({ players[$0]?.isReady == true }) else {
                return broadcastStates()
            }
            return deal()
        case .finished:
            players[seat]?.isReady = true
            let needed = connectedSeats
            guard needed.count >= TableSize.minPlayers, needed.allSatisfy({ players[$0]?.isReady == true }) else {
                return broadcastStates()
            }
            for each in players.keys where players[each]?.connection == nil {
                players[each] = nil
            }
            reassignHostIfNeeded()
            let seats = players.keys.sorted()
            if seats == match.players {
                try? match.rematch()
            } else {
                let previous = match.button
                let button = HandEngine.nextSeat(after: previous, in: maxPlayers) { seats.contains($0) }
                match = MatchState(configuration: configuration, players: seats, firstButton: button)
            }
            return deal()
        }
    }

    private mutating func deal() -> [Outbound] {
        for each in players.keys { players[each]?.isReady = false }
        do {
            var events = try match.startHand(deck: deckProvider(match.nextHandNumber))
            events += foldAbsentActors()
            return broadcast(events) + broadcastStates()
        } catch {
            return connectedSeats.compactMap { reject(seat: $0, "\(error)") }
        }
    }

    private mutating func act(_ action: PlayerAction, by seat: Seat, connection: ConnectionID) -> [Outbound] {
        do {
            var events = try match.apply(action, by: seat)
            events += foldAbsentActors()
            return broadcast(events) + broadcastStates()
        } catch {
            return [reject(connection, describe(error))]
        }
    }

    /// Folds for players who are not connected whenever the action reaches them.
    private mutating func foldAbsentActors() -> [GameEvent] {
        var events: [GameEvent] = []
        while match.phase == .inHand,
              let actor = match.currentHand?.actor,
              players[actor]?.connection == nil,
              let folded = try? match.forfeit(actor),
              !folded.isEmpty {
            events += folded
        }
        return events
    }

    private mutating func leave(_ seat: Seat) -> [Outbound] {
        guard let player = players.removeValue(forKey: seat) else { return [] }
        var events: [GameEvent] = []
        if hasBegun {
            events = (try? match.retire(seat)) ?? []
            events += foldAbsentActors()
        }
        reassignHostIfNeeded()
        if !hasBegun, players.count < TableSize.minPlayers {
            isStarting = false
        }
        var out = broadcast(events)
        for other in connectedSeats {
            out.append(Outbound(to: players[other]!.connection!, message: .playerLeft(seat: seat, name: player.identity.displayName)))
        }
        return out + broadcastStates()
    }

    // MARK: - Delivery helpers

    private func broadcast(_ events: [GameEvent]) -> [Outbound] {
        connectedSeats.flatMap { seat in
            events.map { Outbound(to: players[seat]!.connection!, message: .event($0)) }
        }
    }

    private func broadcastStates() -> [Outbound] {
        connectedSeats.map { Outbound(to: players[$0]!.connection!, message: .state(view(for: $0))) }
    }

    private func reject(_ connection: ConnectionID, _ reason: String) -> Outbound {
        Outbound(to: connection, message: .rejected(reason: reason))
    }

    private func reject(seat: Seat, _ reason: String) -> Outbound? {
        guard let connection = players[seat]?.connection else { return nil }
        return reject(connection, reason)
    }

    private func describe(_ error: Error) -> String {
        switch error {
        case HandError.notYourTurn: "It is not your turn."
        case HandError.cannotCheckFacingBet(let toCall): "You must call \(toCall), raise or fold."
        case HandError.amountOutOfRange(let min, let max): "Amount must be between \(min) and \(max)."
        case HandError.handIsOver, MatchError.noHandInProgress: "No hand is in progress."
        case HandError.betNotAllowed: "There is already a bet; raise instead."
        case HandError.raiseNotAllowed: "There is no bet to raise; bet instead."
        case HandError.nothingToCall: "There is nothing to call."
        default: "Illegal action."
        }
    }
}

/// Serialises access to a `MatchRoom` for concurrent transports. The server
/// keeps one per room; the local host keeps one for its table.
public actor MatchAuthority {
    public private(set) var room: MatchRoom

    public init(room: MatchRoom) {
        self.room = room
    }

    public func handle(_ message: ClientMessage, from connection: ConnectionID, verifiedRanked: Bool = false) -> [Outbound] {
        room.handle(message, from: connection, verifiedRanked: verifiedRanked)
    }

    /// Waits until no connection in `pending()` is still unseated, or `grace`
    /// passes, then deals the first hand (tdr/0013). Returns what to deliver;
    /// empty when the start was cancelled meanwhile.
    public func beginAfterGrace(
        grace: Duration,
        pending: @Sendable () async -> Set<ConnectionID>,
        clock: ContinuousClock = ContinuousClock()
    ) async -> [Outbound] {
        let deadline = clock.now.advanced(by: grace)
        while clock.now < deadline {
            let waiting = await pending().filter { room.seat(of: $0) == nil }
            if waiting.isEmpty { break }
            try? await clock.sleep(for: .milliseconds(100))
        }
        return room.beginMatch()
    }

    public var isStarting: Bool { room.isStarting }

    public func disconnect(_ connection: ConnectionID) -> [Outbound] {
        room.disconnect(connection)
    }

    public func view(for seat: Seat) -> PlayerView {
        room.view(for: seat)
    }
}
