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
    /// The seat had no chips when the hand began (empty or busted) and is not
    /// dealt in. It counts as folded for every rule.
    public var isSittingOut: Bool

    public init(stack: Chips) {
        self.stack = stack
        holeCards = []
        streetCommitted = 0
        totalCommitted = 0
        isSittingOut = stack == 0
        hasFolded = stack == 0
        hasActedThisStreet = false
    }

    public var isAllIn: Bool { stack == 0 && !hasFolded }
    /// Still in the hand and still has chips to act with.
    public var canAct: Bool { !hasFolded && stack > 0 }
}

public enum HandEndReason: Codable, Sendable, Hashable {
    /// Everyone else folded; `by` is the seat whose fold ended the hand.
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

/// One pot at showdown: the main pot first, then each side pot.
public struct PotResult: Codable, Sendable, Hashable {
    public let amount: Chips
    /// Seats still in the hand that covered this pot.
    public let eligible: [Seat]
    /// Seats that split it (more than one for a chop).
    public let winners: [Seat]

    public init(amount: Chips, eligible: [Seat], winners: [Seat]) {
        self.amount = amount
        self.eligible = eligible
        self.winners = winners
    }
}

/// How a finished hand paid out.
public struct HandResult: Codable, Sendable, Hashable {
    public let reason: HandEndReason
    /// Every seat that won chips from another player (any pot), in seat
    /// order. More than one for a chop or when side pots go different ways.
    public let winners: [Seat]
    /// Chips returned to each seat from the pot, indexed by `Seat.rawValue`.
    /// Includes refunds of uncalled chips.
    public let payouts: [Chips]
    /// Hands revealed at showdown; empty when the hand ended on a fold.
    public let shownHands: [ShownHand]
    /// Contested pots at showdown, main pot first; empty when the hand ended
    /// on a fold. Uncalled chips returned to a single player are not a pot.
    public let pots: [PotResult]

    public init(reason: HandEndReason, winners: [Seat], payouts: [Chips], shownHands: [ShownHand], pots: [PotResult] = []) {
        self.reason = reason
        self.winners = winners
        self.payouts = payouts
        self.shownHands = shownHands
        self.pots = pots
    }

    public func payout(for seat: Seat) -> Chips { payouts[seat.rawValue] }
}

/// Complete, unredacted state of a single hand. Only the authority (server or
/// hosting device) ever holds this; clients receive a `PlayerView`.
public struct HandState: Codable, Sendable, Hashable {
    public let handNumber: Int
    public let button: Seat
    public let blinds: Blinds
    /// Heads-up the button; otherwise the first seat dealt in after it.
    public let smallBlindSeat: Seat
    public let bigBlindSeat: Seat
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

    init(handNumber: Int, button: Seat, blinds: Blinds, smallBlindSeat: Seat, bigBlindSeat: Seat, seats: [SeatState], deck: Deck) {
        self.handNumber = handNumber
        self.button = button
        self.blinds = blinds
        self.smallBlindSeat = smallBlindSeat
        self.bigBlindSeat = bigBlindSeat
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
    /// Every seat at the table, dealt in or not, in clockwise order.
    public var allSeats: [Seat] { Seat.all(count: seats.count) }
    /// Seats dealt into this hand.
    public var dealtSeats: [Seat] { allSeats.filter { !self[$0].isSittingOut } }
    /// Seats that have not folded (including all-in players).
    public var liveSeats: [Seat] { allSeats.filter { !self[$0].hasFolded } }

    /// Chips `seat` must add to match the current bet.
    public func amountToCall(for seat: Seat) -> Chips {
        max(0, currentBet - self[seat].streetCommitted)
    }
}
