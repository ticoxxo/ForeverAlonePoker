/// What one player is allowed to know about another.
public struct PlayerSummary: Codable, Sendable, Hashable {
    public let seat: Seat
    /// Stable player id (tdr/0006); used to look up their public profile picture.
    public let playerID: String
    public let name: String
    public let countryCode: String
    public let stack: Chips
    public let streetCommitted: Chips
    public let hasFolded: Bool
    public let isAllIn: Bool
    public let isReady: Bool
    public let isConnected: Bool
    /// Signed in for ranked play and verified by the server (tdr/0010).
    public let isRanked: Bool
    /// Knocked out of the match; still at the table watching.
    public let isBusted: Bool
    /// Finishing position once knocked out or the match is won.
    public let place: Int?

    public init(
        seat: Seat,
        playerID: String = "",
        name: String,
        countryCode: String = "",
        stack: Chips,
        streetCommitted: Chips,
        hasFolded: Bool,
        isAllIn: Bool,
        isReady: Bool,
        isConnected: Bool,
        isRanked: Bool = false,
        isBusted: Bool = false,
        place: Int? = nil
    ) {
        self.seat = seat
        self.playerID = playerID
        self.name = name
        self.countryCode = countryCode
        self.stack = stack
        self.streetCommitted = streetCommitted
        self.hasFolded = hasFolded
        self.isAllIn = isAllIn
        self.isReady = isReady
        self.isConnected = isConnected
        self.isRanked = isRanked
        self.isBusted = isBusted
        self.place = place
    }
}

/// Table-wide facts every player sees, in the lobby and during play.
public struct TableInfo: Codable, Sendable, Hashable {
    public let maxPlayers: Int
    /// The player who opened the table and decides when it starts.
    public let host: Seat?
    /// The host pressed Start and the first hand is about to be dealt.
    public let isStarting: Bool
    /// The authority can rate matches (the internet server with ranked play on).
    public let isRankedCapable: Bool
    /// Every seated player is ranked, so the match will change ratings.
    public let isEloEnabled: Bool

    public init(maxPlayers: Int, host: Seat?, isStarting: Bool, isRankedCapable: Bool, isEloEnabled: Bool) {
        self.maxPlayers = maxPlayers
        self.host = host
        self.isStarting = isStarting
        self.isRankedCapable = isRankedCapable
        self.isEloEnabled = isEloEnabled
    }

    public static let headsUp = TableInfo(maxPlayers: 2, host: nil, isStarting: false, isRankedCapable: false, isEloEnabled: false)
}

/// The table as seen from one seat. This is the only game state a client ever
/// receives: it contains the recipient's hole cards but never another
/// player's live cards or the deck. Other players' cards appear only inside
/// `lastResult.shownHands` after a showdown.
public struct PlayerView: Codable, Sendable, Hashable {
    public let seat: Seat
    public let me: PlayerSummary
    /// Everyone else seated, clockwise starting after `seat`.
    public let players: [PlayerSummary]
    public let table: TableInfo
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
        players: [PlayerSummary],
        table: TableInfo = .headsUp,
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
        self.players = players
        self.table = table
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
    public var isHost: Bool { table.host == seat }
    /// The other player at a heads-up table; `nil` when there are none or several.
    public var opponent: PlayerSummary? { players.count == 1 ? players[0] : nil }

    public func player(at seat: Seat) -> PlayerSummary? {
        seat == self.seat ? me : players.first { $0.seat == seat }
    }
}
