/// One of the four French suits. The raw value is the single-letter notation
/// used on the wire and in tests ("As" = ace of spades).
public enum Suit: String, CaseIterable, Codable, Sendable, Hashable {
    case clubs = "c"
    case diamonds = "d"
    case hearts = "h"
    case spades = "s"

    public var symbol: String {
        switch self {
        case .clubs: "♣"
        case .diamonds: "♦"
        case .hearts: "♥"
        case .spades: "♠"
        }
    }
}
