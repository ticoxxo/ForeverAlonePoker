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

/// Which sound effects the table plays (tdr/0025). Sounds follow what the
/// player sees (`PlayerView`), never the rules (tdr/0003).
nonisolated enum TableSounds {
    /// The sound for one of the player's own action buttons. Fold plays
    /// nothing here: folds are heard from `effects(from:to:)` for everyone.
    static func effect(for action: PlayerAction) -> SoundEffect? {
        switch action {
        case .allIn: .allInChips
        case .check, .bet, .raise: .placingPokerChips
        case .fold, .call: nil
        }
    }

    /// The sounds for the table moving from `old` to `new`. With no `old`
    /// (the table just opened, or a rejoin) only a fresh match shuffles, so
    /// landing mid-hand never replays what already happened.
    static func effects(from old: PlayerView?, to new: PlayerView) -> [SoundEffect] {
        var effects: [SoundEffect] = []
        // Hand numbers restart at 1 for every match, rematches included.
        let wasInFirstHand = old?.phase == .inHand && old?.handNumber == 1
        let isFreshDeal = old != nil || new.community.isEmpty
        if new.phase == .inHand, new.handNumber == 1, !wasInFirstHand, isFreshDeal {
            effects.append(.shufflingCards)
        }
        guard let old else { return effects }

        if old.handNumber == new.handNumber {
            // Anyone's fold, the player's own included, is heard from here
            // so it sounds the same for every seat.
            let foldedBefore = Set(([old.me] + old.players).filter(\.hasFolded).map(\.seat))
            if ([new.me] + new.players).contains(where: { $0.hasFolded && !foldedBefore.contains($0.seat) }) {
                effects.append(.foldHand)
            }
            if new.community.count > old.community.count {
                effects.append(old.community.isEmpty ? .cardsBeingDealt : .placingNewCard)
            }
        }

        if case .finished(let winner) = new.phase {
            if case .finished = old.phase {} else {
                // The match result replaces the last hand's pot sound.
                effects.append(winner == new.seat ? .winSound : .lostSound)
            }
        } else if let result = new.lastResult,
                  old.lastResult == nil || old.handNumber != new.handNumber,
                  HandOutcome(result: result, seat: new.seat)?.kind == .youWon {
            effects.append(.winningPot)
        }
        return effects
    }
}

/// Where the Fold / Check / Raise actions live (tdr/0019), decided from the
/// size classes the system reports rather than the device or orientation.
nonisolated enum TableActionPlacement: Equatable {
    /// Regular width and height (iPad, an open foldable): the `ActionBar`
    /// panel under the table.
    case panel
    /// Any compact dimension (a phone either way up, a narrow split view):
    /// the buttons in the bottom toolbar, the bet sizing in a strip above it.
    case toolbar

    static func make(isRegularWidth: Bool, isRegularHeight: Bool) -> TableActionPlacement {
        isRegularWidth && isRegularHeight ? .panel : .toolbar
    }
}

/// How the table arranges itself for the space it has (tdr/0017). Decided
/// from the container size alone, never the device model, so rotation, iPad
/// split view and a foldable opening or closing all follow from the size.
nonisolated enum TableArrangement: Equatable {
    /// Taller than wide (an upright phone, a narrow split-view column):
    /// opponents on top, the player at the bottom, actions under them.
    case portrait
    /// A phone on its side: board and pot side by side, my seat inline with
    /// the status, so nothing is stacked into the short height.
    case landscape
    /// Plenty of room both ways (iPad, an unfolded foldable): the portrait
    /// order with bigger cards and a width-limited action panel.
    case spacious
    /// A foldable half open on its side, the fold running top to bottom
    /// like an open book (tdr/0020): the opponents, board and status on the
    /// left half, my seat and the actions on the right, nothing on the fold.
    case book

    /// Below this on the short side a screen is phone-sized.
    static let spaciousShortSide: CGFloat = 600

    /// A half-open hinge in a window wider than tall means the fold runs top
    /// to bottom. The hinge reports no direction, so the shape decides; a
    /// half-open foldable held upright keeps its usual layout.
    static func isBookPosture(isHingePartiallyOpen: Bool, size: CGSize) -> Bool {
        isHingePartiallyOpen && size.width > size.height
    }

    static func make(size: CGSize, isBookPosture: Bool = false) -> TableArrangement {
        if isBookPosture { return .book }
        guard size.width > 0, size.height > 0 else { return .portrait }
        if min(size.width, size.height) >= spaciousShortSide { return .spacious }
        return size.width / size.height > 1.25 ? .landscape : .portrait
    }

    /// The landscape rail API below no longer drives any view: actions are
    /// placed by size class (`TableActionPlacement`, tdr/0019). It stays
    /// until its tests are replaced.
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
    var seatsInline: Bool { self != .spacious && self != .book }

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

    /// The most of the window height the board cards may take, however big
    /// the text: a hard ceiling over the Dynamic Type growth.
    var maxBoardShare: CGFloat {
        switch self {
        case .portrait: 0.12
        case .landscape: 0.24
        case .spacious: 0.13
        case .book: 0.14
        }
    }

    /// `textScale` is the Dynamic Type growth relative to the default size
    /// (1 at Large). Cards grow with bigger text, so they keep pace with the
    /// name plates and labels around them, but never shrink below their
    /// default for smaller text: they are already the smallest readable.
    func cardHeights(in size: CGSize, textScale: CGFloat = 1) -> CardHeights {
        let factor: CGFloat = switch self {
        case .portrait: 0.16
        case .landscape: 0.18
        case .spacious: 0.11
        case .book: 0.2
        }
        let range = CardHeights.boardRange
        // The height caps the size too, so a short window never gets cards
        // taller than its table can hold.
        let heightCap: CGFloat = switch self {
        case .portrait: 0.085
        case .landscape: 0.2
        case .spacious: 0.09
        case .book: 0.12
        }
        let scale = min(max(textScale, 1), 1.6)
        // A book lays each side out in one half of the width.
        let width = self == .book ? size.width / 2 : size.width
        let preferred = min(min(width, size.height) * factor, size.height * heightCap) * scale
        // Rounded down so rounding the result can't step over the ceiling.
        let capped = min(preferred, (size.height * maxBoardShare).rounded(.down))
        let board = min(max(capped, range.lowerBound), range.upperBound)
        return CardHeights(board: board.rounded())
    }

    /// Height of the area the other players fan out in at a bigger table.
    func opponentsHeight(in size: CGSize) -> CGFloat {
        let share: CGFloat = switch self {
        case .portrait: 0.26
        case .landscape: 0.36
        case .spacious: 0.28
        case .book: 0.4
        }
        return (size.height * share).rounded()
    }
}
