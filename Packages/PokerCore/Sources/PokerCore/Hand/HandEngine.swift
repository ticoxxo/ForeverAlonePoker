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

/// Pure No-Limit Hold'em rules for two to six seats (tdr/0013). Every
/// function takes a state and returns a new state plus the events that explain
/// the transition; nothing is mutated in place and nothing is random (the deck
/// is supplied pre-shuffled).
///
/// Seats with no chips sit the hand out. Heads-up the button posts the small
/// blind and acts first before the flop; with three or more players the two
/// seats after the button post the blinds and the seat after the big blind
/// acts first. After the flop the first live seat after the button acts first.
///
/// Dealing order is fixed so rigged decks are predictable: two hole cards to
/// each seat dealt in, in seat order (seat one's two, then the next seat's
/// two, ...), then community cards in street order. No burn cards are used.
public enum HandEngine {
    // MARK: - Starting a hand

    /// Posts blinds, deals hole cards and determines who acts first.
    /// `stacks` has one entry per seat; a seat with 0 chips sits out. At least
    /// two seats must have chips and the button must be one of them. If a blind
    /// puts a player all-in and no betting is possible, the board is run out
    /// immediately and the returned state is already finished.
    public static func start(
        handNumber: Int,
        button: Seat,
        stacks: [Chips],
        blinds: Blinds,
        deck: Deck
    ) throws -> (state: HandState, events: [GameEvent]) {
        guard TableSize.range.contains(stacks.count),
              stacks.allSatisfy({ $0 >= 0 }),
              stacks.filter({ $0 > 0 }).count >= 2,
              button.rawValue < stacks.count,
              stacks[button.rawValue] > 0
        else {
            throw HandError.invalidStacks
        }
        let dealtIn = Seat.all(count: stacks.count).filter { stacks[$0.rawValue] > 0 }
        let smallBlind: Seat
        let bigBlind: Seat
        if dealtIn.count == 2 {
            smallBlind = button
            bigBlind = nextSeat(after: button, in: stacks.count) { stacks[$0.rawValue] > 0 }
        } else {
            smallBlind = nextSeat(after: button, in: stacks.count) { stacks[$0.rawValue] > 0 }
            bigBlind = nextSeat(after: smallBlind, in: stacks.count) { stacks[$0.rawValue] > 0 }
        }
        var state = HandState(
            handNumber: handNumber,
            button: button,
            blinds: blinds,
            smallBlindSeat: smallBlind,
            bigBlindSeat: bigBlind,
            seats: stacks.map(SeatState.init(stack:)),
            deck: deck
        )
        var events: [GameEvent] = [.handStarted(handNumber: handNumber, button: button)]

        let smallPosted = commit(&state, seat: smallBlind, upTo: blinds.small)
        events.append(.blindPosted(seat: smallBlind, kind: .small, amount: smallPosted))
        let bigPosted = commit(&state, seat: bigBlind, upTo: blinds.big)
        events.append(.blindPosted(seat: bigBlind, kind: .big, amount: bigPosted))
        state.currentBet = max(smallPosted, bigPosted)
        state.minRaiseIncrement = blinds.big

        for seat in dealtIn {
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

        switch action {
        case .fold:
            state[seat].hasFolded = true
            state[seat].hasActedThisStreet = true
            events.append(.acted(seat: seat, action: .fold, chips: 0))
            if state.liveSeats.count == 1 {
                endByFold(&state, folded: seat, events: &events)
                return (state, events)
            }

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
            if total > state.currentBet {
                // An all-in for more than the current bet is a bet or raise,
                // even when it is smaller than the normal minimum.
                guard othersCanAct(state, besides: seat) else { throw HandError.cannotGoAllIn }
                guard mayRaise(state, seat: seat) else { throw HandError.raiseNotAllowed }
                let added = commit(&state, seat: seat, upTo: state[seat].stack)
                registerAggression(&state, by: seat, newTotal: total)
                events.append(.acted(seat: seat, action: .allIn, chips: added))
            } else {
                // All-in for the current bet or less is a (short) call.
                let added = commit(&state, seat: seat, upTo: state[seat].stack)
                state[seat].hasActedThisStreet = true
                events.append(.acted(seat: seat, action: .allIn, chips: added))
            }
        }

        state[seat].actedAtBet = state.currentBet
        try progress(&state, after: seat, events: &events)
        return (state, events)
    }

    /// Folds `seat` even when it is not their turn (the player left or dropped).
    /// When one player remains they take the pot; otherwise play continues. A
    /// seat that already folded (or sits out) changes nothing.
    public static func forfeit(_ seat: Seat, in state: HandState) throws -> (state: HandState, events: [GameEvent]) {
        guard !state.isOver else { throw HandError.handIsOver }
        guard !state[seat].hasFolded else { return (state, []) }
        var state = state
        var events: [GameEvent] = []
        state[seat].hasFolded = true
        state[seat].hasActedThisStreet = true
        events.append(.acted(seat: seat, action: .fold, chips: 0))
        if state.liveSeats.count == 1 {
            endByFold(&state, folded: seat, events: &events)
        } else if state.actor == seat || streetIsClosed(state) {
            try progress(&state, after: state.actor ?? seat, events: &events)
        }
        return (state, events)
    }

    // MARK: - Legal actions

    public static func legalActions(in state: HandState, for seat: Seat) -> LegalActions {
        guard !state.isOver, state.actor == seat else { return .none }
        let me = state[seat]
        let toCall = state.amountToCall(for: seat)
        var legal = LegalActions(canFold: true)

        if toCall == 0 {
            legal.canCheck = true
        } else {
            legal.callAmount = min(toCall, me.stack)
        }

        // Betting and raising are only meaningful if someone can still respond,
        // and a short all-in does not reopen raising for who already acted.
        guard othersCanAct(state, besides: seat), me.stack > toCall, mayRaise(state, seat: seat) else { return legal }

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

    /// The first seat clockwise after `seat` (wrapping, `seat` itself last)
    /// that satisfies `matches`.
    static func nextSeat(after seat: Seat, in count: Int, where matches: (Seat) -> Bool) -> Seat {
        for step in 1...count {
            let candidate = seat.advanced(by: step, tableSize: count)
            if matches(candidate) { return candidate }
        }
        return seat
    }

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

    /// Records a bet or raise to `newTotal`; everyone else must respond. Only a
    /// full raise lets those who already acted raise again (`mayRaise`).
    private static func registerAggression(_ state: inout HandState, by seat: Seat, newTotal: Chips) {
        let increment = newTotal - state.currentBet
        if increment >= state.minRaiseIncrement {
            state.minRaiseIncrement = increment
        }
        state.currentBet = newTotal
        for other in state.allSeats {
            state[other].hasActedThisStreet = other == seat
        }
    }

    /// Whether `seat` may bet or raise: they have not acted on this street, or
    /// the bet has grown by at least a full raise since they did. Short
    /// all-ins only add up to reopen raising once together they make a full
    /// raise (tdr/0014).
    private static func mayRaise(_ state: HandState, seat: Seat) -> Bool {
        guard let faced = state[seat].actedAtBet else { return true }
        return state.currentBet - faced >= state.minRaiseIncrement
    }

    private static func othersCanAct(_ state: HandState, besides seat: Seat) -> Bool {
        state.allSeats.contains { $0 != seat && state[$0].canAct }
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
        state.allSeats.allSatisfy { !needsToAct(state, seat: $0) }
    }

    /// The next seat clockwise that owes an action. A street opens after the
    /// big blind preflop and after the button on later streets.
    private static func nextActor(_ state: HandState, after last: Seat?) -> Seat? {
        let anchor = last ?? (state.street == .preflop ? state.bigBlindSeat : state.button)
        let candidate = nextSeat(after: anchor, in: state.seats.count) { needsToAct(state, seat: $0) }
        return needsToAct(state, seat: candidate) ? candidate : nil
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
            for seat in state.allSeats {
                state[seat].streetCommitted = 0
                state[seat].hasActedThisStreet = false
                state[seat].actedAtBet = nil
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
        let winner = state.liveSeats[0]
        var payouts = [Chips](repeating: 0, count: state.seats.count)
        payouts[winner.rawValue] = state.pot
        state[winner].stack += state.pot
        state.actor = nil
        let result = HandResult(reason: .fold(by: folded), winners: [winner], payouts: payouts, shownHands: [])
        state.result = result
        events.append(.handEnded(result))
    }

    private static func showdown(_ state: inout HandState, events: inout [GameEvent]) {
        let live = state.liveSeats
        let shown = live.map { seat in
            ShownHand(
                seat: seat,
                holeCards: state[seat].holeCards,
                rank: HandEvaluator.evaluate(state[seat].holeCards + state.community)
            )
        }
        events.append(.showdown(hands: shown))
        let ranks = Dictionary(uniqueKeysWithValues: shown.map { ($0.seat, $0.rank) })

        let count = state.seats.count
        let committed = state.seats.map(\.totalCommitted)
        var payouts = [Chips](repeating: 0, count: count)
        var pots: [PotResult] = []
        var winners = Set<Seat>()

        // Each distinct commitment of a live player caps one pot: the main pot
        // first, then side pots. Folded players' chips feed the pots they reach.
        let levels = Set(live.map { committed[$0.rawValue] }).sorted()
        var previous: Chips = 0
        for level in levels {
            let amount = committed.reduce(0) { $0 + max(0, min($1, level) - previous) }
            let eligible = live.filter { committed[$0.rawValue] >= level }
            previous = level
            guard amount > 0 else { continue }
            if eligible.count == 1 {
                // Nobody matched these chips: they go back uncalled.
                payouts[eligible[0].rawValue] += amount
                continue
            }
            let best = eligible.compactMap { ranks[$0] }.max()!
            let potWinners = eligible.filter { ranks[$0] == best }
            // Odd chips go to the first winners clockwise from the button.
            let ordered = potWinners.sorted {
                distance(from: state.button, to: $0, count: count) < distance(from: state.button, to: $1, count: count)
            }
            let share = amount / ordered.count
            let oddChips = amount % ordered.count
            for (index, winner) in ordered.enumerated() {
                payouts[winner.rawValue] += share + (index < oddChips ? 1 : 0)
            }
            winners.formUnion(potWinners)
            pots.append(PotResult(amount: amount, eligible: eligible, winners: potWinners))
        }

        for seat in state.allSeats {
            state[seat].stack += payouts[seat.rawValue]
        }
        state.actor = nil
        let result = HandResult(reason: .showdown, winners: winners.sorted(), payouts: payouts, shownHands: shown, pots: pots)
        state.result = result
        events.append(.handEnded(result))
    }

    /// Steps clockwise from the button to `seat` (1 for the seat after it).
    private static func distance(from button: Seat, to seat: Seat, count: Int) -> Int {
        let steps = (seat.rawValue - button.rawValue + count) % count
        return steps == 0 ? count : steps
    }
}
