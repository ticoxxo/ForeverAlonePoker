/// A seat at the table, numbered clockwise from zero. A table has between
/// `TableSize.minPlayers` and `TableSize.maxPlayers` seats (tdr/0013). The
/// raw value doubles as the array index in `HandState.seats` and
/// `MatchState.stacks`, and is what goes over the wire (a bare integer).
public struct Seat: RawRepresentable, Codable, Sendable, Hashable, Comparable, CustomStringConvertible {
    public let rawValue: Int

    public init(rawValue: Int) {
        precondition(rawValue >= 0, "Seats are numbered from zero")
        self.rawValue = rawValue
    }

    public init(_ index: Int) {
        self.init(rawValue: index)
    }

    public static let one = Seat(0)
    public static let two = Seat(1)
    public static let three = Seat(2)
    public static let four = Seat(3)
    public static let five = Seat(4)
    public static let six = Seat(5)

    /// Every seat of a table with `count` seats, in clockwise order.
    public static func all(count: Int) -> [Seat] {
        (0..<count).map(Seat.init)
    }

    /// The seat `steps` places clockwise on a table with `count` seats.
    public func advanced(by steps: Int, tableSize count: Int) -> Seat {
        Seat(((rawValue + steps) % count + count) % count)
    }

    public static func < (lhs: Seat, rhs: Seat) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var description: String { "seat \(rawValue + 1)" }

    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(Int.self)
        guard value >= 0 else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Negative seat \(value)"))
        }
        self.init(rawValue: value)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// How many players a table seats.
public enum TableSize {
    public static let minPlayers = 2
    public static let maxPlayers = 6
    public static let range = minPlayers...maxPlayers
}

public typealias Chips = Int

/// Forced bets. Heads-up the button posts the small blind; with three or more
/// players the two seats after the button post them.
public struct Blinds: Codable, Sendable, Hashable {
    public let small: Chips
    public let big: Chips

    public init(small: Chips, big: Chips) {
        precondition(small > 0 && big >= small, "Blinds must be positive and big >= small")
        self.small = small
        self.big = big
    }
}

public enum BlindKind: String, Codable, Sendable, Hashable {
    case small
    case big
}

/// Betting rounds in order.
public enum Street: Int, Codable, Sendable, Hashable, Comparable, CaseIterable {
    case preflop
    case flop
    case turn
    case river

    public static func < (lhs: Street, rhs: Street) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var next: Street? {
        Street(rawValue: rawValue + 1)
    }

    /// Number of community cards dealt when this street begins.
    public var cardsDealt: Int {
        switch self {
        case .preflop: 0
        case .flop: 3
        case .turn, .river: 1
        }
    }
}
