public struct MatchConfiguration: Codable, Sendable, Hashable {
    public var startingStack: Chips
    public var blinds: Blinds
    /// Seats at the table, `TableSize.range` (tdr/0013). Two is heads-up.
    public var maxPlayers: Int

    public init(startingStack: Chips = 1500, blinds: Blinds = Blinds(small: 10, big: 20), maxPlayers: Int = TableSize.minPlayers) {
        precondition(startingStack > 0)
        precondition(TableSize.range.contains(maxPlayers), "A table seats 2 to 6 players")
        self.startingStack = startingStack
        self.blinds = blinds
        self.maxPlayers = maxPlayers
    }

    public static let standard = MatchConfiguration()
}

public enum MatchPhase: Codable, Sendable, Hashable {
    /// The room is still gathering players; no match has begun (tdr/0013).
    /// Only `MatchRoom` reports this; a `MatchState` never is in it.
    case lobby
    /// Before the first hand or between hands.
    case waitingForHand
    case inHand
    /// Every player but `winner` has lost all their chips.
    case finished(winner: Seat)
}

public enum MatchError: Error, Equatable, Sendable {
    case handInProgress
    case noHandInProgress
    case matchFinished
    case matchNotFinished
    case notEnoughPlayers
}

/// A match between two to six players: a sequence of hands with stacks carried
/// over, the button moving clockwise to the next seat with chips, busted
/// players sitting out, and the match ending when one player holds every chip.
public struct MatchState: Codable, Sendable, Hashable {
    public let configuration: MatchConfiguration
    /// Seats taking part, in clockwise order. Other seats always have 0 chips.
    public let players: [Seat]
    /// One entry per seat of the table (`configuration.maxPlayers`).
    public private(set) var stacks: [Chips]
    public private(set) var button: Seat
    public private(set) var handsPlayed: Int
    /// The hand in progress, or the last finished hand until the next one starts.
    public private(set) var currentHand: HandState?
    public private(set) var phase: MatchPhase
    /// Seats in the order they were knocked out (first out first).
    public private(set) var eliminations: [Seat]
    /// Players who left mid-hand; their chips are removed when the hand settles.
    private var retiring: Set<Seat>

    /// - Parameters:
    ///   - players: seats in the match; defaults to every seat of the table.
    ///   - firstButton: defaults to the first player.
    public init(configuration: MatchConfiguration = .standard, players: [Seat]? = nil, firstButton: Seat? = nil) {
        let players = (players ?? Seat.all(count: configuration.maxPlayers)).sorted()
        precondition(players.count >= TableSize.minPlayers, "A match needs at least two players")
        precondition(players.allSatisfy { $0.rawValue < configuration.maxPlayers }, "Seat outside the table")
        self.configuration = configuration
        self.players = players
        stacks = Self.freshStacks(configuration: configuration, players: players)
        button = firstButton ?? players[0]
        precondition(players.contains(firstButton ?? players[0]), "The button must be a player")
        handsPlayed = 0
        currentHand = nil
        phase = .waitingForHand
        eliminations = []
        retiring = []
    }

    public func stack(for seat: Seat) -> Chips { stacks[seat.rawValue] }
    public var nextHandNumber: Int { handsPlayed + 1 }
    public var lastResult: HandResult? { currentHand?.result }
    /// Players who still have chips.
    public var playersWithChips: [Seat] { players.filter { stacks[$0.rawValue] > 0 } }

    public func isBusted(_ seat: Seat) -> Bool {
        eliminations.contains(seat)
    }

    /// Finishing position: 1 for the winner, otherwise counted back from the
    /// last place by elimination order. `nil` while the player is still in.
    public func place(of seat: Seat) -> Int? {
        if case .finished(let winner) = phase, winner == seat { return 1 }
        guard let index = eliminations.firstIndex(of: seat) else { return nil }
        return players.count - index
    }

    /// Deals a new hand from `deck`. If the blinds leave no betting possible the
    /// hand may already be over on return.
    public mutating func startHand(deck: Deck) throws -> [GameEvent] {
        switch phase {
        case .inHand: throw MatchError.handInProgress
        case .finished: throw MatchError.matchFinished
        case .waitingForHand, .lobby: break
        }
        let started = try HandEngine.start(
            handNumber: nextHandNumber,
            button: button,
            stacks: stacks,
            blinds: configuration.blinds,
            deck: deck
        )
        currentHand = started.state
        phase = .inHand
        settleIfOver()
        return started.events
    }

    public mutating func apply(_ action: PlayerAction, by seat: Seat) throws -> [GameEvent] {
        guard phase == .inHand, let hand = currentHand else { throw MatchError.noHandInProgress }
        let step = try HandEngine.apply(action, by: seat, to: hand)
        currentHand = step.state
        settleIfOver()
        return step.events
    }

    /// Folds `seat` regardless of whose turn it is. Used when a player leaves
    /// or drops mid-hand.
    public mutating func forfeit(_ seat: Seat) throws -> [GameEvent] {
        guard phase == .inHand, let hand = currentHand else { throw MatchError.noHandInProgress }
        let step = try HandEngine.forfeit(seat, in: hand)
        currentHand = step.state
        settleIfOver()
        return step.events
    }

    /// Takes a player who left the table out of the match: their chips leave
    /// with them and they count as knocked out. Mid-hand they are folded first
    /// and their stack is removed when the hand settles.
    public mutating func retire(_ seat: Seat) throws -> [GameEvent] {
        guard players.contains(seat), !isBusted(seat) else { return [] }
        if case .finished = phase { return [] }
        var events: [GameEvent] = []
        if phase == .inHand {
            events = try forfeit(seat)
        }
        if phase == .inHand {
            retiring.insert(seat)
        } else {
            stacks[seat.rawValue] = 0
            recordEliminations([seat])
            if phase == .waitingForHand, stacks[button.rawValue] == 0 {
                moveButton()
            }
        }
        return events
    }

    /// Starts over with fresh stacks for every player. The button moves on so
    /// nobody is on the button twice in a row.
    public mutating func rematch() throws {
        guard case .finished = phase else { throw MatchError.matchNotFinished }
        stacks = Self.freshStacks(configuration: configuration, players: players)
        let players = players
        button = HandEngine.nextSeat(after: button, in: configuration.maxPlayers) { players.contains($0) }
        handsPlayed = 0
        currentHand = nil
        phase = .waitingForHand
        eliminations = []
        retiring = []
    }

    private static func freshStacks(configuration: MatchConfiguration, players: [Seat]) -> [Chips] {
        Seat.all(count: configuration.maxPlayers).map { players.contains($0) ? configuration.startingStack : 0 }
    }

    private mutating func settleIfOver() {
        guard let hand = currentHand, hand.isOver else { return }
        let before = stacks
        stacks = hand.seats.map(\.stack)
        for seat in retiring { stacks[seat.rawValue] = 0 }
        retiring = []
        handsPlayed += 1
        // Players knocked out by the same hand: whoever started it with more
        // chips finishes higher, so they are eliminated later.
        let busted = players
            .filter { before[$0.rawValue] > 0 && stacks[$0.rawValue] == 0 }
            .sorted { before[$0.rawValue] < before[$1.rawValue] }
        phase = .waitingForHand
        recordEliminations(busted)
        moveButton()
    }

    /// Clockwise to the next seat with chips; once the match is over, to the
    /// next player, so a rematch carries on the rotation.
    private mutating func moveButton() {
        let finished = if case .finished = phase { true } else { false }
        let stacks = stacks
        let players = players
        button = HandEngine.nextSeat(after: button, in: configuration.maxPlayers) {
            finished ? players.contains($0) : stacks[$0.rawValue] > 0
        }
    }

    private mutating func recordEliminations(_ seats: [Seat]) {
        for seat in seats where !eliminations.contains(seat) {
            eliminations.append(seat)
        }
        let remaining = playersWithChips
        if remaining.count <= 1 {
            phase = .finished(winner: remaining.first ?? button)
        }
    }
}
