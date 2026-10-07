/// Card rank. Raw values follow poker ordering so `Comparable` falls out of the
/// integer value; the ace is high (14) and the wheel straight is a special case
/// handled by the hand evaluator.
public enum Rank: Int, CaseIterable, Codable, Sendable, Hashable, Comparable {
    case two = 2, three, four, five, six, seven, eight, nine, ten
    case jack, queen, king, ace

    public static func < (lhs: Rank, rhs: Rank) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Single-character notation ("T" for ten, "A" for ace).
    public var symbol: String {
        switch self {
        case .ten: "T"
        case .jack: "J"
        case .queen: "Q"
        case .king: "K"
        case .ace: "A"
        default: String(rawValue)
        }
    }

    public init?(symbol: Character) {
        guard let rank = Rank.allCases.first(where: { $0.symbol == String(symbol).uppercased() }) else {
            return nil
        }
        self = rank
    }
}
