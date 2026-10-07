/// Wire protocol shared by the app (client), the Multipeer host and the
/// Hummingbird server. Everything is `Codable` JSON. Bump `ProtocolVersion`
/// whenever a message changes shape so mismatched builds fail loudly.
public enum ProtocolVersion {
    public static let current = 1
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
/// default user; later the Sign in with Apple subject for ranked play) and is
/// what lets a disconnected player reclaim their seat.
public struct PlayerIdentity: Codable, Sendable, Hashable {
    public let id: String
    public let displayName: String

    public init(id: String, displayName: String) {
        self.id = id
        self.displayName = displayName
    }
}

/// Client to authority.
public enum ClientMessage: Codable, Sendable, Hashable {
    case join(PlayerIdentity)
    /// Ready for the next hand (or for a rematch once the match is finished).
    case ready
    case act(PlayerAction)
    case leave
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
}
