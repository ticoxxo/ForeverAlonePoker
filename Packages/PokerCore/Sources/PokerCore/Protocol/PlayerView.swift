/// What one player is allowed to know about another.
public struct PlayerSummary: Codable, Sendable, Hashable {
    public let name: String
    public let stack: Chips
    public let streetCommitted: Chips
    public let hasFolded: Bool
    public let isAllIn: Bool
    public let isReady: Bool
    public let isConnected: Bool

    public init(
        name: String,
        stack: Chips,
        streetCommitted: Chips,
        hasFolded: Bool,
        isAllIn: Bool,
        isReady: Bool,
        isConnected: Bool
    ) {
        self.name = name
        self.stack = stack
        self.streetCommitted = streetCommitted
        self.hasFolded = hasFolded
        self.isAllIn = isAllIn
        self.isReady = isReady
        self.isConnected = isConnected
    }
}

/// The table as seen from one seat. This is the only game state a client ever
/// receives: it contains the recipient's hole cards but never the opponent's
/// live cards or the deck. Opponent cards appear only inside
/// `lastResult.shownHands` after a showdown.
public struct PlayerView: Codable, Sendable, Hashable {
    public let seat: Seat
    public let me: PlayerSummary
    public let opponent: PlayerSummary?
    public let phase: MatchPhase
    public let handNumber: Int
    public let button: Seat
    public let street: Street?
    public let holeCards: [Card]
    public let community: [Card]
    public let pot: Chips
    public let isMyTurn: Bool
    public let legalActions: LegalActions
    public let lastResult: HandResult?

    public init(
        seat: Seat,
        me: PlayerSummary,
        opponent: PlayerSummary?,
        phase: MatchPhase,
        handNumber: Int,
        button: Seat,
        street: Street?,
        holeCards: [Card],
        community: [Card],
        pot: Chips,
        isMyTurn: Bool,
        legalActions: LegalActions,
        lastResult: HandResult?
    ) {
        self.seat = seat
        self.me = me
        self.opponent = opponent
        self.phase = phase
        self.handNumber = handNumber
        self.button = button
        self.street = street
        self.holeCards = holeCards
        self.community = community
        self.pot = pot
        self.isMyTurn = isMyTurn
        self.legalActions = legalActions
        self.lastResult = lastResult
    }

    public var isOnButton: Bool { button == seat }
}
