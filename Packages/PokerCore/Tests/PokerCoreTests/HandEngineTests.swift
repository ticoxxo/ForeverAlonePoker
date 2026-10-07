import Foundation
import Testing
import PokerCore
import PokerCoreTestSupport

@Suite("HandEngine: starting a hand")
struct HandEngineStartTests {
    @Test("button posts the small blind, opponent the big blind, button acts first")
    func blindsAndFirstActor() throws {
        let (state, events) = try HandStateBuilder().button(.one).startWithEvents()

        #expect(state[.one].stack == 1490)
        #expect(state[.two].stack == 1480)
        #expect(state[.one].streetCommitted == 10)
        #expect(state[.two].streetCommitted == 20)
        #expect(state.pot == 30)
        #expect(state.currentBet == 20)
        #expect(state.street == .preflop)
        #expect(state.actor == .one)
        #expect(events.prefix(3) == [
            .handStarted(handNumber: 1, button: .one),
            .blindPosted(seat: .one, kind: .small, amount: 10),
            .blindPosted(seat: .two, kind: .big, amount: 20),
        ])
        #expect(events.contains(.holeCardsDealt))
    }

    @Test("button on seat two mirrors the blinds")
    func buttonOnSeatTwo() throws {
        let state = try HandStateBuilder().button(.two).start()
        #expect(state[.two].streetCommitted == 10)
        #expect(state[.one].streetCommitted == 20)
        #expect(state.actor == .two)
    }

    @Test("hole cards follow the deal order: seat one, then seat two")
    func holeCards() throws {
        let state = try HandStateBuilder()
            .holeCards(.one, "As Kd")
            .holeCards(.two, "7c 2h")
            .start()
        #expect(state[.one].holeCards == cards("As Kd"))
        #expect(state[.two].holeCards == cards("7c 2h"))
        #expect(state.community.isEmpty)
        #expect(state.deck.count == 48)
    }

    @Test("a player must have chips to start a hand")
    func rejectsEmptyStack() {
        #expect(throws: HandError.invalidStacks) {
            try HandStateBuilder().stacks(1500, 0).start()
        }
    }

    @Test("a short big blind posts all-in and the board runs out once the button calls")
    func shortBigBlind() throws {
        let state = try HandStateBuilder().stacks(1500, 15).start()
        #expect(state[.two].isAllIn)
        #expect(state.currentBet == 15)
        #expect(state.actor == .one)

        let legal = HandEngine.legalActions(in: state, for: .one)
        #expect(legal.callAmount == 5)
        #expect(legal.raiseRange == nil, "no raising against an all-in opponent")
        #expect(legal.allInAmount == nil)

        let final = try HandEngine.apply(.call, by: .one, to: state).state
        #expect(final.isOver)
        #expect(final.community.count == 5)
        #expect(final.pot == 30)
    }
}

@Suite("HandEngine: legal actions and validation")
struct HandEngineValidationTests {
    @Test("preflop options for the button facing the big blind")
    func buttonOptions() throws {
        let state = try HandStateBuilder().start()
        let legal = HandEngine.legalActions(in: state, for: .one)
        #expect(legal.canFold)
        #expect(!legal.canCheck)
        #expect(legal.callAmount == 10)
        #expect(legal.betRange == nil)
        #expect(legal.raiseRange == 40...1500, "min raise is one big blind over the current bet; max is the whole stack")
        #expect(legal.allInAmount == 1490)
    }

    @Test("the player not to act has no legal actions")
    func notToAct() throws {
        let state = try HandStateBuilder().start()
        #expect(HandEngine.legalActions(in: state, for: .two) == .none)
    }

    @Test("acting out of turn is rejected")
    func outOfTurn() throws {
        let state = try HandStateBuilder().start()
        #expect(throws: HandError.notYourTurn(actor: .one)) {
            try HandEngine.apply(.call, by: .two, to: state)
        }
    }

    @Test("checking while facing a bet is rejected")
    func checkFacingBet() throws {
        let state = try HandStateBuilder().start()
        #expect(throws: HandError.cannotCheckFacingBet(toCall: 10)) {
            try HandEngine.apply(.check, by: .one, to: state)
        }
    }

    @Test("bet is rejected when a bet already exists; raise when none does")
    func betVersusRaise() throws {
        let preflop = try HandStateBuilder().start()
        #expect(throws: HandError.betNotAllowed) {
            try HandEngine.apply(.bet(50), by: .one, to: preflop)
        }
        let flop = try HandEngine.play(preflop, [(.one, .call), (.two, .check)]).state
        #expect(throws: HandError.raiseNotAllowed) {
            try HandEngine.apply(.raise(to: 50), by: .two, to: flop)
        }
    }

    @Test("raise below the minimum or above the stack is rejected")
    func raiseOutOfRange() throws {
        let state = try HandStateBuilder().start()
        #expect(throws: HandError.amountOutOfRange(min: 40, max: 1500)) {
            try HandEngine.apply(.raise(to: 39), by: .one, to: state)
        }
        #expect(throws: HandError.amountOutOfRange(min: 40, max: 1500)) {
            try HandEngine.apply(.raise(to: 1501), by: .one, to: state)
        }
    }

    @Test("bet below one big blind is rejected unless it is the whole stack")
    func minimumBet() throws {
        let flop = try HandEngine.play(try HandStateBuilder().start(), [(.one, .call), (.two, .check)]).state
        #expect(HandEngine.legalActions(in: flop, for: .two).betRange == 20...1480)
        #expect(throws: HandError.amountOutOfRange(min: 20, max: 1480)) {
            try HandEngine.apply(.bet(5), by: .two, to: flop)
        }

        let shortFlop = try HandEngine.play(
            try HandStateBuilder().stacks(1500, 35).start(),
            [(.one, .call), (.two, .check)]
        ).state
        #expect(HandEngine.legalActions(in: shortFlop, for: .two).betRange == 15...15)
    }

    @Test("no action is accepted once the hand is over")
    func handOver() throws {
        let state = try HandEngine.apply(.fold, by: .one, to: try HandStateBuilder().start()).state
        #expect(throws: HandError.handIsOver) {
            try HandEngine.apply(.check, by: .two, to: state)
        }
        #expect(HandEngine.legalActions(in: state, for: .two) == .none)
    }
}

@Suite("HandEngine: betting flow")
struct HandEngineFlowTests {
    @Test("big blind keeps the option after a limp, then the flop is dealt")
    func bigBlindOption() throws {
        let start = try HandStateBuilder().board("2c 7d Ts 4h 9s").start()
        let limped = try HandEngine.apply(.call, by: .one, to: start).state
        #expect(limped.street == .preflop)
        #expect(limped.actor == .two, "big blind still has the option")
        let option = HandEngine.legalActions(in: limped, for: .two)
        #expect(option.canCheck)
        #expect(option.raiseRange == 40...1500)

        let (flop, events) = try HandEngine.apply(.check, by: .two, to: limped)
        #expect(flop.street == .flop)
        #expect(flop.community == cards("2c 7d Ts"))
        #expect(flop.actor == .two, "out of position player acts first postflop")
        #expect(flop.currentBet == 0)
        #expect(flop[.one].streetCommitted == 0)
        #expect(flop.pot == 40)
        #expect(events.contains(.streetDealt(street: .flop, cards: cards("2c 7d Ts"))))
    }

    @Test("raise and call close the street")
    func raiseAndCall() throws {
        let (flop, events) = try HandEngine.play(try HandStateBuilder().start(), [
            (.one, .raise(to: 60)),
            (.two, .call),
        ])
        #expect(flop.street == .flop)
        #expect(flop.pot == 120)
        #expect(flop[.one].stack == 1440)
        #expect(flop[.two].stack == 1440)
        #expect(events.contains(.acted(seat: .one, action: .raise(to: 60), chips: 50)))
        #expect(events.contains(.acted(seat: .two, action: .call, chips: 40)))
    }

    @Test("minimum raise tracks the size of the last raise")
    func minRaiseTracking() throws {
        let flop = try HandEngine.play(try HandStateBuilder().start(), [(.one, .call), (.two, .check)]).state
        let afterBet = try HandEngine.apply(.bet(50), by: .two, to: flop).state
        #expect(HandEngine.legalActions(in: afterBet, for: .one).raiseRange == 100...1480)

        let afterRaise = try HandEngine.apply(.raise(to: 150), by: .one, to: afterBet).state
        #expect(afterRaise.actor == .two, "a raise reopens the action")
        let reraise = HandEngine.legalActions(in: afterRaise, for: .two)
        #expect(reraise.callAmount == 100)
        #expect(reraise.raiseRange == 250...1480, "must raise by at least the last raise of 100")

        let turn = try HandEngine.apply(.call, by: .two, to: afterRaise).state
        #expect(turn.street == .turn)
        #expect(turn.community.count == 4)
        #expect(turn.pot == 340)
    }

    @Test("checking down every street reaches showdown")
    func checkDown() throws {
        let final = try HandEngine.play(try HandStateBuilder().start(), [
            (.one, .call), (.two, .check),
            (.two, .check), (.one, .check),
            (.two, .check), (.one, .check),
            (.two, .check), (.one, .check),
        ]).state
        #expect(final.isOver)
        #expect(final.result?.reason == .showdown)
        #expect(final.community.count == 5)
        #expect(final.pot == 40)
    }
}

@Suite("HandEngine: ending a hand")
struct HandEngineEndingTests {
    @Test("folding gives the whole pot to the opponent")
    func fold() throws {
        let (state, events) = try HandEngine.apply(.fold, by: .one, to: try HandStateBuilder().start())
        #expect(state.isOver)
        #expect(state.actor == nil)
        #expect(state.result?.reason == .fold(by: .one))
        #expect(state.result?.winners == [.two])
        #expect(state.result?.payouts == [0, 30])
        #expect(state[.one].stack == 1490)
        #expect(state[.two].stack == 1510)
        #expect(state.result?.shownHands.isEmpty == true, "nothing is revealed on a fold")
        #expect(events.last == .handEnded(state.result!))
    }

    @Test("all-in and call run the board out and the best hand wins everything")
    func allInRunout() throws {
        let start = try HandStateBuilder()
            .holeCards(.one, "Ah Kh")
            .holeCards(.two, "Qs Qd")
            .board("Ac 7d Ts 4h 9s")
            .start()
        let (final, events) = try HandEngine.play(start, [(.one, .allIn), (.two, .call)])

        #expect(final.isOver)
        #expect(final.community.count == 5)
        #expect(final.result?.reason == .showdown)
        #expect(final.result?.winners == [.one], "pair of aces beats pair of queens")
        #expect(final[.one].stack == 3000)
        #expect(final[.two].stack == 0)
        #expect(events.contains { if case .showdown = $0 { true } else { false } })
        #expect(final.result?.shownHands.map(\.seat) == [.one, .two])
        #expect(final.result?.shownHands.first?.rank.category == .onePair)
    }

    @Test("an all-in for less only contests what it covers; the excess is refunded")
    func shortAllInRefund() throws {
        let start = try HandStateBuilder()
            .stacks(1500, 500)
            .holeCards(.one, "Ah Kh")
            .holeCards(.two, "Qs Qd")
            .board("2c 7d Ts 4h 9s")
            .start()
        let final = try HandEngine.play(start, [(.one, .allIn), (.two, .call)]).state

        #expect(final.result?.winners == [.two], "queens hold on a dry board")
        #expect(final.result?.payouts == [1000, 1000], "seat one gets 1000 back uncalled; seat two wins the 1000 contested")
        #expect(final[.one].stack == 1000)
        #expect(final[.two].stack == 1000)
    }

    @Test("identical hands chop the pot evenly")
    func chop() throws {
        let start = try HandStateBuilder()
            .holeCards(.one, "2h 3h")
            .holeCards(.two, "2s 3s")
            .board("As Ks Qs Js Ts")
            .start()
        let final = try HandEngine.play(start, [(.one, .allIn), (.two, .call)]).state

        #expect(final.result?.winners == [.one, .two])
        #expect(final.result?.payouts == [1500, 1500])
        #expect(final[.one].stack == 1500)
        #expect(final[.two].stack == 1500)
    }

    @Test("facing an all-in, the opponent can only call or fold")
    func facingAllIn() throws {
        let start = try HandStateBuilder().stacks(1500, 1500).start()
        let shoved = try HandEngine.apply(.allIn, by: .one, to: start).state
        let legal = HandEngine.legalActions(in: shoved, for: .two)
        #expect(legal.canFold)
        #expect(legal.callAmount == 1480)
        #expect(legal.raiseRange == nil)
        #expect(legal.allInAmount == nil)
    }

    @Test("a short all-in raise does not reopen the action for a full raise")
    func shortAllInRaise() throws {
        // Seat two has 50 total; after posting 20 it has 30 behind. Seat one raises to 60.
        let start = try HandStateBuilder().stacks(1500, 50).start()
        let raised = try HandEngine.apply(.raise(to: 60), by: .one, to: start).state
        let legal = HandEngine.legalActions(in: raised, for: .two)
        #expect(legal.callAmount == 30, "a call for the remaining stack")
        #expect(legal.raiseRange == nil)

        let final = try HandEngine.apply(.call, by: .two, to: raised).state
        #expect(final.isOver, "nobody can bet after the short call, so the board runs out")
        #expect(final.result?.payouts.reduce(0, +) == 110)
        #expect(final[.one].stack + final[.two].stack == 1550)
    }

    @Test("hand state round-trips through Codable")
    func codable() throws {
        let state = try HandEngine.play(try HandStateBuilder().start(), [(.one, .raise(to: 60)), (.two, .call)]).state
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(HandState.self, from: data)
        #expect(decoded == state)
    }
}
