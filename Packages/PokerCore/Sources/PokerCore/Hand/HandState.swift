/// Everything the engine tracks about one player during a hand.
public struct SeatState: Codable, Sendable, Hashable {
    public var stack: Chips
    public var holeCards: [Card]
    /// Chips committed on the current street.
    public var streetCommitted: Chips
    /// Chips committed over the whole hand (what the pot is made of).
    public var totalCommitted: Chips
    public var hasFolded: Bool
    /// Whether the player has voluntarily acted on the current street. Posting
    /// a blind does not count, which is what gives the big blind its option.
    public var hasActedThisStreet: Bool

    public init(stack: Chips) {
        self.stack = stack
        holeCards = []
        streetCommitted = 0
        totalCommitted = 0
        hasFolded = false
        hasActedThisStreet = false
    }

    public var isAllIn: Bool { stack == 0 && !hasFolded }
    /// Still in the hand and still has chips to act with.
    public var canAct: Bool { !hasFolded && stack > 0 }
}

public enum HandEndReason: Codable, Sendable, Hashable {
    case fold(by: Seat)
    case showdown
}

/// A hand revealed at showdown.
public struct ShownHand: Codable, Sendable, Hashable {
    public let seat: Seat
    public let holeCards: [Card]
    public let rank: HandRank

    public init(seat: Seat, holeCards: [Card], rank: HandRank) {
        self.seat = seat
        self.holeCards = holeCards
        self.rank = rank
    }
}

/// How a finished hand paid out.
public struct HandResult: Codable, Sendable, Hashable {
    public let reason: HandEndReason
    /// One seat, or both for a chop.
    public let winners: [Seat]
    /// Chips returned to each seat from the pot, indexed by `Seat.rawValue`.
    /// Includes refunds of uncalled chips.
    public let payouts: [Chips]
    /// Hands revealed at showdown; empty when the hand ended on a fold.
    public let shownHands: [ShownHand]

    public init(reason: HandEndReason, winners: [Seat], payouts: [Chips], shownHands: [ShownHand]) {
        self.reason = reason
        self.winners = winners
        self.payouts = payouts
        self.shownHands = shownHands
    }

    public func payout(for seat: Seat) -> Chips { payouts[seat.rawValue] }
}

/// Complete, unredacted state of a single hand. Only the authority (server or
/// Multipeer host) ever holds this; clients receive a `PlayerView`.
public struct HandState: Codable, Sendable, Hashable {
    public let handNumber: Int
    public let button: Seat
    public let blinds: Blinds
    public internal(set) var seats: [SeatState]
    public internal(set) var deck: Deck
    public internal(set) var community: [Card]
    public internal(set) var street: Street
    /// Whose turn it is; `nil` while cards are being run out or once the hand is over.
    public internal(set) var actor: Seat?
    /// Highest `streetCommitted` on the current street.
    public internal(set) var currentBet: Chips
    /// Size of the last full bet or raise; a raise must add at least this much.
    public internal(set) var minRaiseIncrement: Chips
    public internal(set) var result: HandResult?

    init(handNumber: Int, button: Seat, blinds: Blinds, seats: [SeatState], deck: Deck) {
        self.handNumber = handNumber
        self.button = button
        self.blinds = blinds
        self.seats = seats
        self.deck = deck
        community = []
        street = .preflop
        actor = nil
        currentBet = 0
        minRaiseIncrement = blinds.big
        result = nil
    }

    public subscript(seat: Seat) -> SeatState {
        get { seats[seat.rawValue] }
        set { seats[seat.rawValue] = newValue }
    }

    public var isOver: Bool { result != nil }
    public var pot: Chips { seats.reduce(0) { $0 + $1.totalCommitted } }
    /// Heads-up: the button posts the small blind.
    public var smallBlindSeat: Seat { button }
    public var bigBlindSeat: Seat { button.opponent }

    /// Chips `seat` must add to match the current bet.
    public func amountToCall(for seat: Seat) -> Chips {
        max(0, currentBet - self[seat].streetCommitted)
    }
}
