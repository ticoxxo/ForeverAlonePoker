/// Wire protocol shared by the app (client), the Multipeer host and the
/// Hummingbird server. Everything is `Codable` JSON. Bump `ProtocolVersion`
/// whenever a message changes shape so mismatched builds fail loudly.
public enum ProtocolVersion {
    /// 2: `PlayerIdentity.countryCode`, session tokens on `join`, `rated` (tdr/0010).
    public static let current = 2
}

/// Versioned wrapper around any message.
public struct Envelope<Message: Codable & Sendable & Hashable>: Codable, Sendable, Hashable {
    public let version: Int
    public let message: Message

    public init(_ message: Message, version: Int = ProtocolVersion.current) {
        self.version = version
        self.message = message
    }
}

public typealias ClientEnvelope = Envelope<ClientMessage>
public typealias ServerEnvelope = Envelope<ServerMessage>

/// Who a player is. `id` is stable for the player (a local UUID for the
/// default user; the Sign in with Apple subject for ranked play) and is what
/// lets a disconnected player reclaim their seat.
public struct PlayerIdentity: Codable, Sendable, Hashable {
    public let id: String
    public let displayName: String
    /// ISO 3166-1 alpha-2 region code shown next to the name and used for
    /// country leaderboards. Empty when the player has not set one.
    public let countryCode: String

    public init(id: String, displayName: String, countryCode: String = "") {
        self.id = id
        self.displayName = displayName
        self.countryCode = countryCode
    }
}

/// Client to authority.
public enum ClientMessage: Codable, Sendable, Hashable {
    /// `sessionToken` is the server-issued ranked token (tdr/0010); `nil`
    /// plays unranked. Only the internet server verifies it.
    case join(PlayerIdentity, sessionToken: String? = nil)
    /// Ready for the next hand (or for a rematch once the match is finished).
    case ready
    case act(PlayerAction)
    case leave
}

/// The referee's verdict on a ranked match for one player.
public struct RatingUpdate: Codable, Sendable, Hashable {
    public let rating: Rating
    /// Points gained (positive) or lost (negative) by this match.
    public let delta: Int

    public init(rating: Rating, delta: Int) {
        self.rating = rating
        self.delta = delta
    }
}

/// Authority to client.
public enum ServerMessage: Codable, Sendable, Hashable {
    case welcome(seat: Seat, roomCode: String)
    case waitingForOpponent
    /// Full redacted snapshot for the recipient. Sent after every change; a
    /// client can always rebuild its UI from the latest one.
    case state(PlayerView)
    /// Public table events, identical for both players, for animations and logs.
    case event(GameEvent)
    case rejected(reason: String)
    case opponentLeft
    /// Sent once by the internet server after a ranked match is published.
    case rated(RatingUpdate)
}
