public struct MatchConfiguration: Codable, Sendable, Hashable {
    public var startingStack: Chips
    public var blinds: Blinds

    public init(startingStack: Chips = 1500, blinds: Blinds = Blinds(small: 10, big: 20)) {
        precondition(startingStack > 0)
        self.startingStack = startingStack
        self.blinds = blinds
    }

    public static let standard = MatchConfiguration()
}

public enum MatchPhase: Codable, Sendable, Hashable {
    /// Before the first hand or between hands.
    case waitingForHand
    case inHand
    /// One player has lost all their chips.
    case finished(winner: Seat)
}

public enum MatchError: Error, Equatable, Sendable {
    case handInProgress
    case noHandInProgress
    case matchFinished
    case matchNotFinished
}

/// A heads-up match: a sequence of hands with stacks carried over, the button
/// alternating every hand, and the match ending when a player busts.
public struct MatchState: Codable, Sendable, Hashable {
    public let configuration: MatchConfiguration
    public private(set) var stacks: [Chips]
    public private(set) var button: Seat
    public private(set) var handsPlayed: Int
    /// The hand in progress, or the last finished hand until the next one starts.
    public private(set) var currentHand: HandState?
    public private(set) var phase: MatchPhase

    public init(configuration: MatchConfiguration = .standard, firstButton: Seat = .one) {
        self.configuration = configuration
        stacks = Seat.allCases.map { _ in configuration.startingStack }
        button = firstButton
        handsPlayed = 0
        currentHand = nil
        phase = .waitingForHand
    }

    public func stack(for seat: Seat) -> Chips { stacks[seat.rawValue] }
    public var nextHandNumber: Int { handsPlayed + 1 }
    public var lastResult: HandResult? { currentHand?.result }

    /// Deals a new hand from `deck`. If the blinds leave no betting possible the
    /// hand may already be over on return.
    public mutating func startHand(deck: Deck) throws -> [GameEvent] {
        switch phase {
        case .inHand: throw MatchError.handInProgress
        case .finished: throw MatchError.matchFinished
        case .waitingForHand: break
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

    /// Ends the current hand as a fold by `seat` regardless of whose turn it is.
    /// Used when a player leaves mid-hand.
    public mutating func forfeit(_ seat: Seat) throws -> [GameEvent] {
        guard phase == .inHand, let hand = currentHand else { throw MatchError.noHandInProgress }
        let step = try HandEngine.forfeit(seat, in: hand)
        currentHand = step.state
        settleIfOver()
        return step.events
    }

    /// Starts over with fresh stacks. The button moves on so the loser of the
    /// previous match is not on the button twice in a row.
    public mutating func rematch() throws {
        guard case .finished = phase else { throw MatchError.matchNotFinished }
        stacks = Seat.allCases.map { _ in configuration.startingStack }
        button = button.opponent
        handsPlayed = 0
        currentHand = nil
        phase = .waitingForHand
    }

    private mutating func settleIfOver() {
        guard let hand = currentHand, hand.isOver else { return }
        stacks = hand.seats.map(\.stack)
        handsPlayed += 1
        button = button.opponent
        if let bust = Seat.allCases.first(where: { stacks[$0.rawValue] == 0 }) {
            phase = .finished(winner: bust.opponent)
        } else {
            phase = .waitingForHand
        }
    }
}
