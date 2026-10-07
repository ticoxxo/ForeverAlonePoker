import PokerCore

/// Pure presentation state for the action bar, derived from `LegalActions`.
/// Keeping it a plain value makes the button and slider rules unit-testable
/// without rendering anything.
nonisolated struct TableActionModel: Equatable {
    enum Sizing: Equatable {
        /// Opening bet; the range is the total bet size.
        case bet(ClosedRange<Chips>)
        /// Raise; the range is the total "raise to" amount.
        case raise(ClosedRange<Chips>)

        var range: ClosedRange<Chips> {
            switch self {
            case .bet(let range), .raise(let range): range
            }
        }
    }

    let canFold: Bool
    let canCheck: Bool
    let callAmount: Chips?
    let sizing: Sizing?
    let allInAmount: Chips?

    init(legalActions: LegalActions) {
        canFold = legalActions.canFold
        canCheck = legalActions.canCheck
        callAmount = legalActions.callAmount
        if let range = legalActions.betRange {
            sizing = .bet(range)
        } else if let range = legalActions.raiseRange {
            sizing = .raise(range)
        } else {
            sizing = nil
        }
        allInAmount = legalActions.allInAmount
    }

    static let inactive = TableActionModel(legalActions: .none)

    /// Whether the player has anything to do right now.
    var isActive: Bool { canFold || canCheck || callAmount != nil }

    /// Keeps a slider value inside the legal range.
    func clamped(_ amount: Chips) -> Chips {
        guard let range = sizing?.range else { return amount }
        return min(max(amount, range.lowerBound), range.upperBound)
    }

    /// The action for a chosen slider amount.
    func sizedAction(_ amount: Chips) -> PlayerAction? {
        switch sizing {
        case .bet: .bet(clamped(amount))
        case .raise: .raise(to: clamped(amount))
        case nil: nil
        }
    }
}

/// What the table should tell the player outside of acting.
nonisolated enum TableStatus: Hashable {
    case connecting
    case waitingForOpponent
    /// Between hands; the player has not pressed Ready yet.
    case readyPrompt
    /// Between hands; waiting for the opponent to press Ready.
    case waitingForOpponentReady
    case yourTurn
    case opponentsTurn
    case matchOver(youWon: Bool)
    case opponentLeft

    static func make(view: PlayerView?, opponentLeft: Bool) -> TableStatus {
        guard let view else { return .connecting }
        if opponentLeft || view.opponent == nil { return view.opponent == nil && !opponentLeft ? .waitingForOpponent : .opponentLeft }
        switch view.phase {
        case .finished(let winner):
            return .matchOver(youWon: winner == view.seat)
        case .waitingForHand:
            return view.me.isReady ? .waitingForOpponentReady : .readyPrompt
        case .inHand:
            return view.isMyTurn ? .yourTurn : .opponentsTurn
        }
    }
}

/// Human-readable outcome of the last hand from one seat's perspective.
nonisolated struct HandOutcome: Equatable {
    enum Kind: Equatable {
        case youWon
        case youLost
        case chop
    }

    let kind: Kind
    let amount: Chips
    /// Winning hand category at showdown; `nil` when the hand ended on a fold.
    let category: HandCategory?
    let endedByFold: Bool

    init?(result: HandResult?, seat: Seat) {
        guard let result else { return nil }
        let iWon = result.winners.contains(seat)
        if result.winners.count == 2 {
            kind = .chop
        } else {
            kind = iWon ? .youWon : .youLost
        }
        // What changed hands: the loser's contribution, i.e. the smaller payout
        // subtracted from the larger one is noise; show the winner's net gain.
        let contested = result.payouts.min() ?? 0
        amount = result.payouts.max().map { $0 - contested } ?? 0
        switch result.reason {
        case .fold:
            category = nil
            endedByFold = true
        case .showdown:
            category = result.shownHands.first { result.winners.contains($0.seat) }?.rank.category
            endedByFold = false
        }
    }
}
