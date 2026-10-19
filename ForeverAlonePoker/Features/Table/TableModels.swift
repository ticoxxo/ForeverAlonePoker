import Foundation
import CoreGraphics
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

    /// How far one tap of the − / + buttons moves the amount: the opening
    /// bet's minimum (the big blind), or half the minimum raise-to, which is
    /// the size of the raise increment over the bet being raised.
    var sizingStep: Chips {
        switch sizing {
        case .bet(let range): max(1, range.lowerBound)
        case .raise(let range): max(1, range.lowerBound / 2)
        case nil: 1
        }
    }

    /// The amount one step up (`direction` > 0) or down from `amount`, kept
    /// in the legal range.
    func stepped(_ amount: Chips, by direction: Int) -> Chips {
        clamped(amount + direction.signum() * sizingStep)
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

/// Who sits at the table and who waits at the side (tdr/0016). At a table of
/// three or more, players out of the current hand (folded, or knocked out)
/// move to the waiting zone, so the ring only shows players still in it.
/// Folded players stay there until the next hand is dealt.
nonisolated struct TableSeating: Equatable {
    let active: [PlayerSummary]
    let waiting: [PlayerSummary]

    init(view: PlayerView) {
        guard view.table.maxPlayers > TableSize.minPlayers else {
            active = view.players
            waiting = []
            return
        }
        // `hasFolded` describes the current or just-finished hand, and is
        // reset when the next one is dealt.
        let isWaiting: (PlayerSummary) -> Bool = { $0.isBusted || (view.street != nil && $0.hasFolded) }
        active = view.players.filter { !isWaiting($0) }
        waiting = view.players.filter(isWaiting)
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

/// When each card of a deal lands (tdr/0018). Cards new to a row arrive one
/// after another, like a dealer pitching them; cards already showing never
/// wait. Under Reduce Motion everything lands at once.
nonisolated enum DealTiming {
    /// Seconds between two cards of the same deal.
    static let step: Double = 0.09

    /// - Parameters:
    ///   - index: the card's position in its row.
    ///   - previousCount: how many cards of the row were already showing.
    static func delay(index: Int, previousCount: Int, reduceMotion: Bool = false) -> Double {
        guard !reduceMotion else { return 0 }
        return Double(max(0, index - previousCount)) * step
    }
}

/// How the table arranges itself for the space it has (tdr/0017). Decided
/// from the container size alone, never the device model, so rotation, iPad
/// split view and a foldable opening or closing all follow from the size.
nonisolated enum TableArrangement: Equatable {
    /// Taller than wide (an upright phone, a narrow split-view column):
    /// opponents on top, the player at the bottom, actions under them.
    case portrait
    /// A phone on its side: the table on the left, the actions docked on the
    /// trailing side so nothing is stacked into the short height.
    case landscape
    /// Plenty of room both ways (iPad, an unfolded foldable): the portrait
    /// order with bigger cards and a width-limited action panel.
    case spacious

    /// Below this on the short side a screen is phone-sized.
    static let spaciousShortSide: CGFloat = 600

    static func make(size: CGSize) -> TableArrangement {
        guard size.width > 0, size.height > 0 else { return .portrait }
        if min(size.width, size.height) >= spaciousShortSide { return .spacious }
        return size.width / size.height > 1.25 ? .landscape : .portrait
    }

    var docksActionsAtSide: Bool { self == .landscape }

    /// The widest the action panel gets under the table, so buttons on a
    /// big screen stay within easy reach of one thumb.
    static let actionPanelMaxWidth: CGFloat = 640

    /// Width of the control rail docked on the trailing edge in landscape,
    /// a slim toolbar like the foldable's side bar (tdr/0018). Accessibility
    /// text sizes get more room so "Raise to 1,480" still fits on a button,
    /// but the table always keeps more than half the width.
    func actionDockWidth(in size: CGSize, isAccessibilitySize: Bool) -> CGFloat {
        let (share, range): (CGFloat, ClosedRange<CGFloat>) = isAccessibilitySize
            ? (0.42, 300...440)
            : (0.26, 200...280)
        let width = min(max(size.width * share, range.lowerBound), range.upperBound)
        return min(width, (size.width * 0.49).rounded(.down)).rounded()
    }

    /// Seats put their cards beside the name plate instead of under it, so
    /// a short window (a phone on its side, an upright phone's table above
    /// the action panel) fits without anything running off the edge.
    var seatsInline: Bool { self != .spacious }

    /// My own cards beside my name plate: only where height is scarcest.
    var mySeatInline: Bool { self == .landscape }

    /// Fold / Call / Raise sit side by side under the table, but stack when
    /// docked at the side or when the text is too big to share a row.
    func stacksActionButtons(isAccessibilitySize: Bool) -> Bool {
        docksActionsAtSide || isAccessibilitySize
    }

    /// Card sizes for every place cards appear, scaled from the short side.
    struct CardHeights: Equatable {
        static let boardRange: ClosedRange<CGFloat> = 44...120

        let board: CGFloat
        /// The player's own hole cards, the biggest on screen.
        var mine: CGFloat { board * 1.375 }
        /// The heads-up opponent.
        var opponent: CGFloat { board * 0.875 }
        /// Opponents at a bigger table.
        var compact: CGFloat { board * 0.47 }
    }

    func cardHeights(in size: CGSize) -> CardHeights {
        let factor: CGFloat = switch self {
        case .portrait: 0.16
        case .landscape: 0.14
        case .spacious: 0.11
        }
        let range = CardHeights.boardRange
        // The height caps the size too, so a short window never gets cards
        // taller than its table can hold.
        let heightCap: CGFloat = switch self {
        case .portrait: 0.085
        case .landscape: 0.16
        case .spacious: 0.09
        }
        let preferred = min(min(size.width, size.height) * factor, size.height * heightCap)
        let board = min(max(preferred, range.lowerBound), range.upperBound)
        return CardHeights(board: board.rounded())
    }

    /// Height of the area the other players fan out in at a bigger table.
    func opponentsHeight(in size: CGSize) -> CGFloat {
        let share: CGFloat = switch self {
        case .portrait: 0.26
        case .landscape: 0.36
        case .spacious: 0.28
        }
        return (size.height * share).rounded()
    }
}
