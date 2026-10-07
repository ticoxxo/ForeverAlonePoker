/// One of the two seats at a heads-up table. Raw values double as array
/// indices in `HandState.seats` and `MatchState.stacks`.
public enum Seat: Int, Codable, Sendable, Hashable, CaseIterable {
    case one = 0
    case two = 1

    public var opponent: Seat {
        switch self {
        case .one: .two
        case .two: .one
        }
    }
}

public typealias Chips = Int

/// Forced bets. In heads-up the button posts the small blind.
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
