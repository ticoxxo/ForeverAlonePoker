import Foundation
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
    /// Nobody else is seated yet.
    case waitingForOpponent
    /// Between hands; the table deals the next one by itself (tdr/0014).
    case nextHandSoon
    case yourTurn
    case othersTurn(name: String)
    /// Knocked out; watching until the match ends (tdr/0013).
    case spectating
    /// `place` is the finishing position when known.
    case matchOver(youWon: Bool, place: Int?)
    /// The last other player left the table.
    case playerLeft(name: String)

    /// - Parameter departure: name of the last player who left, if any.
    static func make(view: PlayerView?, departure: String?) -> TableStatus {
        guard let view else { return .connecting }
        if view.players.isEmpty {
            if case .finished(let winner) = view.phase, departure == nil {
                return .matchOver(youWon: winner == view.seat, place: view.me.place)
            }
            return departure.map { .playerLeft(name: $0) } ?? .waitingForOpponent
        }
        switch view.phase {
        case .lobby:
            return .waitingForOpponent
        case .finished(let winner):
            return .matchOver(youWon: winner == view.seat, place: view.me.place)
        case .waitingForHand:
            return view.me.isBusted ? .spectating : .nextHandSoon
        case .inHand:
            if view.isMyTurn { return .yourTurn }
            let name = view.actor.flatMap { view.player(at: $0)?.name } ?? ""
            return .othersTurn(name: name)
        }
    }
}

/// Outcome of the last hand from one seat's perspective.
nonisolated struct HandOutcome: Equatable {
    enum Kind: Equatable {
        case youWon
        case youLost
        case chop
    }

    let kind: Kind
    /// What the player collected (won or chopped), or what the main winner
    /// collected when the player lost.
    let amount: Chips
    /// The seat named when the player lost: the main pot's winner.
    let winner: Seat?
    /// Hand category of the named winner at showdown; `nil` on a fold.
    let category: HandCategory?
    let endedByFold: Bool

    init?(result: HandResult?, seat: Seat) {
        guard let result else { return nil }
        let mainWinners = result.pots.first?.winners ?? result.winners
        if result.winners.contains(seat) {
            kind = mainWinners.count > 1 && mainWinners.contains(seat) ? .chop : .youWon
            winner = seat
        } else {
            kind = .youLost
            winner = mainWinners.first ?? result.winners.first
        }
        let named = winner ?? seat
        switch result.reason {
        case .fold:
            amount = result.payout(for: named)
            category = nil
            endedByFold = true
        case .showdown:
            amount = result.pots
                .filter { $0.winners.contains(named) }
                .reduce(0) { $0 + $1.amount / $1.winners.count }
            category = result.shownHands.first { $0.seat == named }?.rank.category
            endedByFold = false
        }
    }
}

/// Where the other players sit around the table, as unit coordinates
/// (0...1, origin top-left) inside the area above the board. The player is
/// always at the bottom, so the others fan out over the top arc, clockwise
/// from the left.
nonisolated enum SeatLayout {
    struct Point: Equatable {
        let x: Double
        let y: Double
    }

    static func positions(count: Int) -> [Point] {
        guard count > 0 else { return [] }
        return (0..<count).map { index in
            let angle = Double.pi - Double(index + 1) * Double.pi / Double(count + 1)
            // Rounded to three places so positions compare exactly in tests.
            return Point(
                x: ((0.5 + 0.4 * cos(angle)) * 1000).rounded() / 1000,
                y: ((0.85 - 0.75 * sin(angle)) * 1000).rounded() / 1000
            )
        }
    }
}
