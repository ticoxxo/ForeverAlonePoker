/// Things that happened at the table, in order. Events are public information:
/// they are broadcast identically to both players, so they never contain a
/// player's hole cards before showdown.
public enum GameEvent: Codable, Sendable, Hashable {
    case handStarted(handNumber: Int, button: Seat)
    case blindPosted(seat: Seat, kind: BlindKind, amount: Chips)
    case holeCardsDealt
    /// `chips` is what the action actually added to the pot.
    case acted(seat: Seat, action: PlayerAction, chips: Chips)
    case streetDealt(street: Street, cards: [Card])
    case showdown(hands: [ShownHand])
    case handEnded(HandResult)
}
