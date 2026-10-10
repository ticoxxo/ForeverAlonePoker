/// Identifies one transport connection (a WebSocket, a Multipeer peer, an
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

/// The referee for one two-player table. It owns the only unredacted
/// `MatchState`, validates every client message, and returns the messages to
/// deliver. It is a pure value: the same code runs inside the Hummingbird
/// server and on the hosting device in local play, and tests drive it
/// directly with no transport at all.
public struct MatchRoom: Sendable {
    public typealias DeckProvider = @Sendable (_ handNumber: Int) -> Deck

    public struct SeatedPlayer: Sendable, Hashable {
        public let identity: PlayerIdentity
        /// `nil` while the player is disconnected but may still reclaim the seat.
        public var connection: ConnectionID?
        public var isReady: Bool
    }

    public let code: String
    public private(set) var match: MatchState
    public private(set) var players: [Seat: SeatedPlayer] = [:]
    private let deckProvider: DeckProvider

    /// - Parameter deckProvider: supplies the deck for each hand. Defaults to a
    ///   fresh system-shuffled deck; tests inject rigged decks.
    public init(
        code: String,
        configuration: MatchConfiguration = .standard,
        deckProvider: @escaping DeckProvider = { _ in Deck.shuffled() }
    ) {
        self.code = code
        match = MatchState(configuration: configuration)
        self.deckProvider = deckProvider
    }

    public var isFull: Bool { players.count == Seat.allCases.count }
    public var isEmpty: Bool { players.isEmpty }
    public var connectedSeats: [Seat] { Seat.allCases.filter { players[$0]?.connection != nil } }

    public func seat(of connection: ConnectionID) -> Seat? {
        players.first { $0.value.connection == connection }?.key
    }

    // MARK: - Handling messages

    public mutating func handle(_ message: ClientMessage, from connection: ConnectionID) -> [Outbound] {
        switch message {
        case .join(let identity, _):
            // Session tokens are verified by the server before the message
            // reaches the room; the rules never see them.
            return join(identity, from: connection)
        case .ready:
            guard let seat = seat(of: connection) else { return [reject(connection, "Join the room first.")] }
            return ready(seat)
        case .act(let action):
            guard let seat = seat(of: connection) else { return [reject(connection, "Join the room first.")] }
            return act(action, by: seat, connection: connection)
        case .leave:
            guard let seat = seat(of: connection) else { return [] }
            return leave(seat, keepSeat: false)
        }
    }

    /// The transport dropped. The seat is kept so the same identity can rejoin.
    public mutating func disconnect(_ connection: ConnectionID) -> [Outbound] {
        guard let seat = seat(of: connection) else { return [] }
        return leave(seat, keepSeat: true)
    }

    // MARK: - Views

    public func view(for seat: Seat) -> PlayerView {
        let hand = match.currentHand
        let inHand = match.phase == .inHand
        return PlayerView(
            seat: seat,
            me: summary(of: seat, hand: hand) ?? PlayerSummary(
                name: "", stack: match.stack(for: seat), streetCommitted: 0,
                hasFolded: false, isAllIn: false, isReady: false, isConnected: false
            ),
            opponent: summary(of: seat.opponent, hand: hand),
            phase: match.phase,
            handNumber: hand?.handNumber ?? match.handsPlayed,
            button: hand?.button ?? match.button,
            street: hand?.street,
            holeCards: hand?[seat].holeCards ?? [],
            community: hand?.community ?? [],
            pot: (hand?.isOver == false) ? (hand?.pot ?? 0) : 0,
            isMyTurn: inHand && hand?.actor == seat,
            legalActions: inHand ? HandEngine.legalActions(in: hand!, for: seat) : .none,
            lastResult: hand?.result
        )
    }

    private func summary(of seat: Seat, hand: HandState?) -> PlayerSummary? {
        guard let player = players[seat] else { return nil }
        let seatState = hand?[seat]
        return PlayerSummary(
            name: player.identity.displayName,
            stack: seatState?.stack ?? match.stack(for: seat),
            streetCommitted: seatState?.streetCommitted ?? 0,
            hasFolded: seatState?.hasFolded ?? false,
            isAllIn: seatState?.isAllIn ?? false,
            isReady: player.isReady,
            isConnected: player.connection != nil
        )
    }

    // MARK: - Private handlers

    private mutating func join(_ identity: PlayerIdentity, from connection: ConnectionID) -> [Outbound] {
        if seat(of: connection) != nil {
            return [reject(connection, "Already seated.")]
        }
        // Reclaim a seat held for this identity (reconnect).
        if let seat = players.first(where: { $0.value.identity.id == identity.id && $0.value.connection == nil })?.key {
            players[seat]?.connection = connection
            return [Outbound(to: connection, message: .welcome(seat: seat, roomCode: code))] + broadcastStates()
        }
        guard let seat = Seat.allCases.first(where: { players[$0] == nil }) else {
            return [reject(connection, "Room is full.")]
        }
        players[seat] = SeatedPlayer(identity: identity, connection: connection, isReady: false)
        var out = [Outbound(to: connection, message: .welcome(seat: seat, roomCode: code))]
        if isFull {
            out += broadcastStates()
        } else {
            out.append(Outbound(to: connection, message: .waitingForOpponent))
        }
        return out
    }

    private mutating func ready(_ seat: Seat) -> [Outbound] {
        guard isFull else { return [] }
        players[seat]?.isReady = true
        guard Seat.allCases.allSatisfy({ players[$0]?.isReady == true }) else {
            return broadcastStates()
        }
        for each in Seat.allCases { players[each]?.isReady = false }
        do {
            if case .finished = match.phase {
                try match.rematch()
            }
            let events = try match.startHand(deck: deckProvider(match.nextHandNumber))
            return broadcast(events) + broadcastStates()
        } catch {
            return connectedSeats.compactMap { reject(seat: $0, "\(error)") }
        }
    }

    private mutating func act(_ action: PlayerAction, by seat: Seat, connection: ConnectionID) -> [Outbound] {
        do {
            let events = try match.apply(action, by: seat)
            return broadcast(events) + broadcastStates()
        } catch {
            return [reject(connection, describe(error))]
        }
    }

    private mutating func leave(_ seat: Seat, keepSeat: Bool) -> [Outbound] {
        var events: [GameEvent] = []
        if match.phase == .inHand, let forfeited = try? match.forfeit(seat) {
            events = forfeited
        }
        if keepSeat {
            players[seat]?.connection = nil
            players[seat]?.isReady = false
        } else {
            players[seat] = nil
        }
        var out = broadcast(events)
        if let opponent = players[seat.opponent], let connection = opponent.connection {
            out.append(Outbound(to: connection, message: .opponentLeft))
            out.append(Outbound(to: connection, message: .state(view(for: seat.opponent))))
        }
        return out
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
/// keeps one per room; the Multipeer host keeps one for its table.
public actor MatchAuthority {
    public private(set) var room: MatchRoom

    public init(room: MatchRoom) {
        self.room = room
    }

    public func handle(_ message: ClientMessage, from connection: ConnectionID) -> [Outbound] {
        room.handle(message, from: connection)
    }

    public func disconnect(_ connection: ConnectionID) -> [Outbound] {
        room.disconnect(connection)
    }

    public func view(for seat: Seat) -> PlayerView {
        room.view(for: seat)
    }
}
