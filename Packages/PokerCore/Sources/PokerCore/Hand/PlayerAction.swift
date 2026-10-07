/// An action a player can take when it is their turn.
///
/// `bet` is only legal when nobody has bet on the current street; `raise(to:)`
/// is the total amount the player will have committed on the street after the
/// raise (standard "raise to" semantics). `allIn` is a convenience the engine
/// normalises into a call, bet or raise for the player's whole stack, and it
/// is the only way to put in less than a minimum bet or raise.
public enum PlayerAction: Codable, Sendable, Hashable {
    case fold
    case check
    case call
    case bet(Chips)
    case raise(to: Chips)
    case allIn
}

/// What the acting player may legally do right now. Amounts are expressed the
/// same way `PlayerAction` expresses them, so a UI can bind sliders directly.
public struct LegalActions: Codable, Sendable, Hashable {
    public var canFold: Bool
    public var canCheck: Bool
    /// Chips the player would add by calling; `nil` when there is nothing to
    /// call. A call for the player's whole (shorter) stack is still a call.
    public var callAmount: Chips?
    /// Allowed total bet sizes when no bet exists on this street.
    public var betRange: ClosedRange<Chips>?
    /// Allowed "raise to" totals when facing a bet.
    public var raiseRange: ClosedRange<Chips>?
    /// Chips the player would add by moving all-in, when that is allowed as a
    /// bet or raise (never offered when the opponent is already all-in).
    public var allInAmount: Chips?

    public init(
        canFold: Bool = false,
        canCheck: Bool = false,
        callAmount: Chips? = nil,
        betRange: ClosedRange<Chips>? = nil,
        raiseRange: ClosedRange<Chips>? = nil,
        allInAmount: Chips? = nil
    ) {
        self.canFold = canFold
        self.canCheck = canCheck
        self.callAmount = callAmount
        self.betRange = betRange
        self.raiseRange = raiseRange
        self.allInAmount = allInAmount
    }

    /// No action is possible (not this player's turn, or the hand is over).
    public static let none = LegalActions()

    public var isEmpty: Bool { self == .none }
}
