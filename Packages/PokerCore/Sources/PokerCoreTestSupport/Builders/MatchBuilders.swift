import PokerCore

/// Builds a `MatchState` between hands with chosen stacks and button.
public struct MatchStateBuilder {
    public var configuration = MatchConfiguration.standard
    public var firstButton: Seat = .one

    public init() {}

    public func startingStack(_ chips: Chips) -> Self { with { $0.configuration.startingStack = chips } }
    public func blinds(small: Chips, big: Chips) -> Self { with { $0.configuration.blinds = Blinds(small: small, big: big) } }
    public func button(_ seat: Seat) -> Self { with { $0.firstButton = seat } }

    public func build() -> MatchState {
        MatchState(configuration: configuration, firstButton: firstButton)
    }

    private func with(_ mutate: (inout Self) -> Void) -> Self {
        var copy = self
        mutate(&copy)
        return copy
    }
}

/// Builds a `MatchRoom` whose decks are scripted per hand. Hand N uses the Nth
/// deck given; later hands reuse the last one. The default deck is the
/// `HandStateBuilder` default (seat one Ah Kh, seat two Qs Qd, dry board).
public struct MatchRoomBuilder {
    public var code = "TEST01"
    public var configuration = MatchConfiguration.standard
    public var decks: [Deck] = [HandStateBuilder().deck()]

    public init() {}

    public func code(_ value: String) -> Self { with { $0.code = value } }
    public func startingStack(_ chips: Chips) -> Self { with { $0.configuration.startingStack = chips } }
    public func decks(_ value: [Deck]) -> Self { with { $0.decks = value } }
    public func deck(_ value: Deck) -> Self { with { $0.decks = [value] } }
    /// Convenience: rig every hand from a `HandStateBuilder`'s cards.
    public func hands(_ builders: [HandStateBuilder]) -> Self { with { $0.decks = builders.map { $0.deck() } } }

    public func build() -> MatchRoom {
        let decks = self.decks
        return MatchRoom(code: code, configuration: configuration) { handNumber in
            decks[min(handNumber, decks.count) - 1]
        }
    }

    private func with(_ mutate: (inout Self) -> Void) -> Self {
        var copy = self
        mutate(&copy)
        return copy
    }
}

/// Two well-known connections and identities for room tests.
public enum TestPlayers {
    public static let alice = PlayerIdentity(id: "alice-id", displayName: "Alice")
    public static let bob = PlayerIdentity(id: "bob-id", displayName: "Bob")
    public static let carol = PlayerIdentity(id: "carol-id", displayName: "Carol")

    public static let aliceConnection = ConnectionID("conn-alice")
    public static let bobConnection = ConnectionID("conn-bob")
    public static let carolConnection = ConnectionID("conn-carol")
}

public extension MatchRoom {
    /// Seats Alice (seat one) and Bob (seat two) and marks both ready, so the
    /// first hand is dealt. Returns everything sent along the way.
    @discardableResult
    mutating func seatAliceAndBobAndDeal() -> [Outbound] {
        var out = handle(.join(TestPlayers.alice), from: TestPlayers.aliceConnection)
        out += handle(.join(TestPlayers.bob), from: TestPlayers.bobConnection)
        out += handle(.ready, from: TestPlayers.aliceConnection)
        out += handle(.ready, from: TestPlayers.bobConnection)
        return out
    }
}

public extension Array where Element == Outbound {
    func messages(for connection: ConnectionID) -> [ServerMessage] {
        filter { $0.to == connection }.map(\.message)
    }

    /// The most recent `PlayerView` sent to a connection, if any.
    func latestView(for connection: ConnectionID) -> PlayerView? {
        for message in messages(for: connection).reversed() {
            if case .state(let view) = message { return view }
        }
        return nil
    }

    func events(for connection: ConnectionID) -> [GameEvent] {
        messages(for: connection).compactMap {
            if case .event(let event) = $0 { return event }
            return nil
        }
    }

    func rejections(for connection: ConnectionID) -> [String] {
        messages(for: connection).compactMap {
            if case .rejected(let reason) = $0 { return reason }
            return nil
        }
    }
}
