import Testing
import PokerCore
import PokerCoreTestSupport
@testable import ForeverAlonePoker

@Suite("TableActionModel")
struct TableActionModelTests {
    @Test("facing a bet offers fold, call and a raise slider")
    func facingBet() throws {
        let state = try HandStateBuilder().start()
        let model = TableActionModel(legalActions: HandEngine.legalActions(in: state, for: .one))
        #expect(model.isActive)
        #expect(model.canFold)
        #expect(!model.canCheck)
        #expect(model.callAmount == 10)
        #expect(model.sizing == .raise(40...1500))
        #expect(model.allInAmount == 1490)
        #expect(model.sizedAction(60) == .raise(to: 60))
    }

    @Test("with no bet it offers check and a bet slider")
    func noBet() throws {
        let flop = try HandEngine.play(try HandStateBuilder().start(), [(.one, .call), (.two, .check)]).state
        let model = TableActionModel(legalActions: HandEngine.legalActions(in: flop, for: .two))
        #expect(model.canCheck)
        #expect(model.callAmount == nil)
        #expect(model.sizing == .bet(20...1480))
        #expect(model.sizedAction(100) == .bet(100))
    }

    @Test("slider values are clamped to the legal range")
    func clamping() throws {
        let state = try HandStateBuilder().start()
        let model = TableActionModel(legalActions: HandEngine.legalActions(in: state, for: .one))
        #expect(model.clamped(5) == 40)
        #expect(model.clamped(9999) == 1500)
        #expect(model.sizedAction(5) == .raise(to: 40))
    }

    @Test("facing an all-in there is no sizing, only call or fold")
    func facingAllIn() throws {
        let shoved = try HandEngine.apply(.allIn, by: .one, to: try HandStateBuilder().start()).state
        let model = TableActionModel(legalActions: HandEngine.legalActions(in: shoved, for: .two))
        #expect(model.sizing == nil)
        #expect(model.allInAmount == nil)
        #expect(model.callAmount == 1480)
        #expect(model.sizedAction(100) == nil)
    }

    @Test("when it is not the player's turn the model is inactive")
    func inactive() {
        #expect(TableActionModel.inactive.isActive == false)
        #expect(TableActionModel(legalActions: .none) == .inactive)
    }
}

@Suite("TableStatus")
struct TableStatusTests {
    private func views(after script: [(Seat, PlayerAction)] = [], ready: Bool = true) -> (PlayerView, PlayerView) {
        var room = MatchRoomBuilder().build()
        _ = room.handle(.join(TestPlayers.alice), from: TestPlayers.aliceConnection)
        _ = room.handle(.join(TestPlayers.bob), from: TestPlayers.bobConnection)
        if ready {
            _ = room.handle(.ready, from: TestPlayers.aliceConnection)
            _ = room.handle(.ready, from: TestPlayers.bobConnection)
        }
        for (seat, action) in script {
            let connection = seat == .one ? TestPlayers.aliceConnection : TestPlayers.bobConnection
            _ = room.handle(.act(action), from: connection)
        }
        return (room.view(for: .one), room.view(for: .two))
    }

    @Test("no view yet means connecting")
    func connecting() {
        #expect(TableStatus.make(view: nil, opponentLeft: false) == .connecting)
    }

    @Test("alone at the table means waiting for an opponent")
    func waitingForOpponent() {
        var room = MatchRoomBuilder().build()
        _ = room.handle(.join(TestPlayers.alice), from: TestPlayers.aliceConnection)
        #expect(TableStatus.make(view: room.view(for: .one), opponentLeft: false) == .waitingForOpponent)
    }

    @Test("between hands shows the ready prompt until the player is ready")
    func readyPrompt() {
        let (alice, _) = views(ready: false)
        #expect(TableStatus.make(view: alice, opponentLeft: false) == .readyPrompt)

        var room = MatchRoomBuilder().build()
        _ = room.handle(.join(TestPlayers.alice), from: TestPlayers.aliceConnection)
        _ = room.handle(.join(TestPlayers.bob), from: TestPlayers.bobConnection)
        _ = room.handle(.ready, from: TestPlayers.aliceConnection)
        #expect(TableStatus.make(view: room.view(for: .one), opponentLeft: false) == .waitingForOpponentReady)
    }

    @Test("during a hand it reports whose turn it is")
    func turns() {
        let (alice, bob) = views()
        #expect(TableStatus.make(view: alice, opponentLeft: false) == .yourTurn)
        #expect(TableStatus.make(view: bob, opponentLeft: false) == .opponentsTurn)
    }

    @Test("a finished match reports the winner from each side")
    func matchOver() {
        // Default deck: Alice Ah Kh, Bob Qs Qd on a dry board, so Bob's queens hold.
        let (alice, bob) = views(after: [(.one, .allIn), (.two, .call)])
        #expect(TableStatus.make(view: alice, opponentLeft: false) == .matchOver(youWon: false))
        #expect(TableStatus.make(view: bob, opponentLeft: false) == .matchOver(youWon: true))
    }

    @Test("an opponent leaving overrides everything else")
    func opponentLeft() {
        let (alice, _) = views()
        #expect(TableStatus.make(view: alice, opponentLeft: true) == .opponentLeft)
    }
}

@Suite("HandOutcome")
struct HandOutcomeTests {
    @Test("a fold describes who folded and what the winner gained")
    func fold() throws {
        let state = try HandEngine.apply(.fold, by: .one, to: try HandStateBuilder().start()).state
        let mine = try #require(HandOutcome(result: state.result, seat: .one))
        #expect(mine.kind == .youLost)
        #expect(mine.endedByFold)
        #expect(mine.amount == 30)
        #expect(mine.category == nil)
        #expect(HandOutcome(result: state.result, seat: .two)?.kind == .youWon)
    }

    @Test("a showdown names the winning hand")
    func showdown() throws {
        let start = try HandStateBuilder()
            .holeCards(.one, "Ah Kh").holeCards(.two, "Qs Qd").board("Ac 7d Ts 4h 9s")
            .start()
        let final = try HandEngine.play(start, [(.one, .allIn), (.two, .call)]).state
        let outcome = try #require(HandOutcome(result: final.result, seat: .two))
        #expect(outcome.kind == .youLost)
        #expect(outcome.category == .onePair)
        #expect(outcome.amount == 3000)
        #expect(!outcome.endedByFold)
    }

    @Test("a chop is reported as such")
    func chop() throws {
        let start = try HandStateBuilder()
            .holeCards(.one, "2h 3h").holeCards(.two, "2s 3s").board("As Ks Qs Js Ts")
            .start()
        let final = try HandEngine.play(start, [(.one, .allIn), (.two, .call)]).state
        #expect(HandOutcome(result: final.result, seat: .one)?.kind == .chop)
        #expect(HandOutcome(result: final.result, seat: .one)?.amount == 0)
    }

    @Test("no result yields no outcome")
    func none() {
        #expect(HandOutcome(result: nil, seat: .one) == nil)
    }
}
