public enum HandError: Error, Equatable, Sendable {
    case invalidStacks
    case handIsOver
    case noActionPending
    case notYourTurn(actor: Seat)
    case cannotCheckFacingBet(toCall: Chips)
    case nothingToCall
    case betNotAllowed
    case raiseNotAllowed
    case amountOutOfRange(min: Chips, max: Chips)
    case cannotGoAllIn
}

/// Pure heads-up No-Limit Hold'em rules. Every function takes a state and
/// returns a new state plus the events that explain the transition; nothing is
/// mutated in place and nothing is random (the deck is supplied pre-shuffled).
///
/// Dealing order is fixed so rigged decks are predictable: seat one's two hole
/// cards, seat two's two hole cards, then community cards in street order. No
/// burn cards are used.
public enum HandEngine {
    // MARK: - Starting a hand

    /// Posts blinds, deals hole cards and determines who acts first.
    /// If a blind puts a player all-in and no betting is possible, the board is
    /// run out immediately and the returned state is already finished.
    public static func start(
        handNumber: Int,
        button: Seat,
        stacks: [Chips],
        blinds: Blinds,
        deck: Deck
    ) throws -> (state: HandState, events: [GameEvent]) {
        guard stacks.count == Seat.allCases.count, stacks.allSatisfy({ $0 > 0 }) else {
            throw HandError.invalidStacks
        }
        var state = HandState(
            handNumber: handNumber,
            button: button,
            blinds: blinds,
            seats: stacks.map(SeatState.init(stack:)),
            deck: deck
        )
        var events: [GameEvent] = [.handStarted(handNumber: handNumber, button: button)]

        let smallPosted = commit(&state, seat: state.smallBlindSeat, upTo: blinds.small)
        events.append(.blindPosted(seat: state.smallBlindSeat, kind: .small, amount: smallPosted))
        let bigPosted = commit(&state, seat: state.bigBlindSeat, upTo: blinds.big)
        events.append(.blindPosted(seat: state.bigBlindSeat, kind: .big, amount: bigPosted))
        state.currentBet = max(smallPosted, bigPosted)
        state.minRaiseIncrement = blinds.big

        for seat in Seat.allCases {
            state[seat].holeCards = try state.deck.deal(2)
        }
        events.append(.holeCardsDealt)

        try progress(&state, after: nil, events: &events)
        return (state, events)
    }

    // MARK: - Acting

    public static func apply(
        _ action: PlayerAction,
        by seat: Seat,
        to state: HandState
    ) throws -> (state: HandState, events: [GameEvent]) {
        guard !state.isOver else { throw HandError.handIsOver }
        guard let actor = state.actor else { throw HandError.noActionPending }
        guard actor == seat else { throw HandError.notYourTurn(actor: actor) }

        var state = state
        var events: [GameEvent] = []
        let legal = legalActions(in: state, for: seat)
        let toCall = state.amountToCall(for: seat)
        let opponent = seat.opponent

        switch action {
        case .fold:
            state[seat].hasFolded = true
            state[seat].hasActedThisStreet = true
            events.append(.acted(seat: seat, action: .fold, chips: 0))
            endByFold(&state, folded: seat, events: &events)
            return (state, events)

        case .check:
            guard legal.canCheck else { throw HandError.cannotCheckFacingBet(toCall: toCall) }
            state[seat].hasActedThisStreet = true
            events.append(.acted(seat: seat, action: .check, chips: 0))

        case .call:
            guard let callAmount = legal.callAmount else { throw HandError.nothingToCall }
            let added = commit(&state, seat: seat, upTo: callAmount)
            state[seat].hasActedThisStreet = true
            events.append(.acted(seat: seat, action: .call, chips: added))

        case .bet(let amount):
            guard state.currentBet == 0 else { throw HandError.betNotAllowed }
            guard let range = legal.betRange else { throw HandError.betNotAllowed }
            guard range.contains(amount) else {
                throw HandError.amountOutOfRange(min: range.lowerBound, max: range.upperBound)
            }
            let added = commit(&state, seat: seat, upTo: amount)
            registerAggression(&state, by: seat, newTotal: amount)
            events.append(.acted(seat: seat, action: .bet(amount), chips: added))

        case .raise(let total):
            guard state.currentBet > 0 else { throw HandError.raiseNotAllowed }
            guard let range = legal.raiseRange else { throw HandError.raiseNotAllowed }
            guard range.contains(total) else {
                throw HandError.amountOutOfRange(min: range.lowerBound, max: range.upperBound)
            }
            let added = commit(&state, seat: seat, upTo: total - state[seat].streetCommitted)
            registerAggression(&state, by: seat, newTotal: total)
            events.append(.acted(seat: seat, action: .raise(to: total), chips: added))

        case .allIn:
            guard state[seat].canAct else { throw HandError.cannotGoAllIn }
            let total = state[seat].streetCommitted + state[seat].stack
            let added = commit(&state, seat: seat, upTo: state[seat].stack)
            if total > state.currentBet {
                // An all-in for more than the current bet is a bet or raise,
                // even when it is smaller than the normal minimum.
                guard state[opponent].canAct else { throw HandError.cannotGoAllIn }
                registerAggression(&state, by: seat, newTotal: total)
            } else {
                // All-in for the current bet or less is a (short) call.
                state[seat].hasActedThisStreet = true
            }
            events.append(.acted(seat: seat, action: .allIn, chips: added))
        }

        try progress(&state, after: seat, events: &events)
        return (state, events)
    }

    /// Ends the hand as a fold by `seat` even when it is not their turn (the
    /// player left the table). The opponent takes the whole pot.
    public static func forfeit(_ seat: Seat, in state: HandState) throws -> (state: HandState, events: [GameEvent]) {
        guard !state.isOver else { throw HandError.handIsOver }
        var state = state
        var events: [GameEvent] = []
        state[seat].hasFolded = true
        state[seat].hasActedThisStreet = true
        events.append(.acted(seat: seat, action: .fold, chips: 0))
        endByFold(&state, folded: seat, events: &events)
        return (state, events)
    }

    // MARK: - Legal actions

    public static func legalActions(in state: HandState, for seat: Seat) -> LegalActions {
        guard !state.isOver, state.actor == seat else { return .none }
        let me = state[seat]
        let opponent = state[seat.opponent]
        let toCall = state.amountToCall(for: seat)
        var legal = LegalActions(canFold: true)

        if toCall == 0 {
            legal.canCheck = true
        } else {
            legal.callAmount = min(toCall, me.stack)
        }

        // Betting and raising are only meaningful if the opponent can still respond.
        guard opponent.canAct, me.stack > toCall else { return legal }

        let maxTotal = me.streetCommitted + me.stack
        if state.currentBet == 0 {
            let minBet = min(state.blinds.big, me.stack)
            legal.betRange = minBet...me.stack
        } else {
            let minTotal = min(state.currentBet + state.minRaiseIncrement, maxTotal)
            legal.raiseRange = minTotal...maxTotal
        }
        legal.allInAmount = me.stack
        return legal
    }

    // MARK: - Internals

    /// Moves up to `amount` chips from the seat's stack into the pot and returns
    /// what was actually moved (less when the stack is short).
    @discardableResult
    private static func commit(_ state: inout HandState, seat: Seat, upTo amount: Chips) -> Chips {
        let added = min(max(amount, 0), state[seat].stack)
        state[seat].stack -= added
        state[seat].streetCommitted += added
        state[seat].totalCommitted += added
        return added
    }

    /// Records a bet or raise to `newTotal` and reopens the action for the opponent.
    private static func registerAggression(_ state: inout HandState, by seat: Seat, newTotal: Chips) {
        let increment = newTotal - state.currentBet
        if increment >= state.minRaiseIncrement {
            state.minRaiseIncrement = increment
        }
        state.currentBet = newTotal
        state[seat].hasActedThisStreet = true
        state[seat.opponent].hasActedThisStreet = false
    }

    private static func firstToAct(on street: Street, button: Seat) -> Seat {
        street == .preflop ? button : button.opponent
    }

    /// At least two players can still put chips in.
    private static func bettingPossible(_ state: HandState) -> Bool {
        state.seats.filter(\.canAct).count >= 2
    }

    private static func needsToAct(_ state: HandState, seat: Seat) -> Bool {
        let player = state[seat]
        guard player.canAct else { return false }
        if state.amountToCall(for: seat) > 0 { return true }
        // With no bet to face, a player only owes an action while betting is
        // still possible (otherwise there is nothing to decide).
        return bettingPossible(state) && !player.hasActedThisStreet
    }

    private static func streetIsClosed(_ state: HandState) -> Bool {
        Seat.allCases.allSatisfy { !needsToAct(state, seat: $0) }
    }

    private static func nextActor(_ state: HandState, after last: Seat?) -> Seat? {
        let order: [Seat]
        if let last {
            order = [last.opponent, last]
        } else {
            let first = firstToAct(on: state.street, button: state.button)
            order = [first, first.opponent]
        }
        return order.first { needsToAct(state, seat: $0) }
    }

    /// Decides who acts next, or advances streets (running the board out when
    /// nobody can bet) until someone can act or the hand reaches showdown.
    private static func progress(_ state: inout HandState, after last: Seat?, events: inout [GameEvent]) throws {
        if !streetIsClosed(state) {
            state.actor = nextActor(state, after: last)
            return
        }
        state.actor = nil
        while let next = state.street.next {
            let dealt = try state.deck.deal(next.cardsDealt)
            state.community += dealt
            state.street = next
            state.currentBet = 0
            state.minRaiseIncrement = state.blinds.big
            for seat in Seat.allCases {
                state[seat].streetCommitted = 0
                state[seat].hasActedThisStreet = false
            }
            events.append(.streetDealt(street: next, cards: dealt))
            if bettingPossible(state) {
                state.actor = nextActor(state, after: nil)
                return
            }
        }
        showdown(&state, events: &events)
    }

    private static func endByFold(_ state: inout HandState, folded: Seat, events: inout [GameEvent]) {
        let winner = folded.opponent
        var payouts = [Chips](repeating: 0, count: Seat.allCases.count)
        payouts[winner.rawValue] = state.pot
        state[winner].stack += state.pot
        state.actor = nil
        let result = HandResult(reason: .fold(by: folded), winners: [winner], payouts: payouts, shownHands: [])
        state.result = result
        events.append(.handEnded(result))
    }

    private static func showdown(_ state: inout HandState, events: inout [GameEvent]) {
        let shown = Seat.allCases.map { seat in
            ShownHand(
                seat: seat,
                holeCards: state[seat].holeCards,
                rank: HandEvaluator.evaluate(state[seat].holeCards + state.community)
            )
        }
        events.append(.showdown(hands: shown))

        let committed = state.seats.map(\.totalCommitted)
        let contested = 2 * committed.min()!
        var payouts = [Chips](repeating: 0, count: Seat.allCases.count)
        // Uncalled chips go back to whoever put them in.
        for seat in Seat.allCases {
            payouts[seat.rawValue] += committed[seat.rawValue] - committed.min()!
        }

        let best = shown.map(\.rank).max()!
        let winners = shown.filter { $0.rank == best }.map(\.seat)
        // `contested` is always even, so a chop never leaves an odd chip.
        for winner in winners {
            payouts[winner.rawValue] += contested / winners.count
        }
        for seat in Seat.allCases {
            state[seat].stack += payouts[seat.rawValue]
        }
        state.actor = nil
        let result = HandResult(reason: .showdown, winners: winners, payouts: payouts, shownHands: shown)
        state.result = result
        events.append(.handEnded(result))
    }
}
