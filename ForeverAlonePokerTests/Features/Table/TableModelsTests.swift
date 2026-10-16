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
    /// Heads-up: joining both seats deals the first hand.
    private func views(after script: [(Seat, PlayerAction)] = []) -> (PlayerView, PlayerView) {
        var room = MatchRoomBuilder().build()
        room.seatAliceAndBobAndDeal()
        for (seat, action) in script {
            let connection = seat == .one ? TestPlayers.aliceConnection : TestPlayers.bobConnection
            _ = room.handle(.act(action), from: connection)
        }
        return (room.view(for: .one), room.view(for: .two))
    }

    @Test("no view yet means connecting")
    func connecting() {
        #expect(TableStatus.make(view: nil, departure: nil) == .connecting)
    }

    @Test("alone at the table means waiting for players")
    func waitingForOpponent() {
        var room = MatchRoomBuilder().build()
        _ = room.handle(.join(TestPlayers.alice), from: TestPlayers.aliceConnection)
        #expect(TableStatus.make(view: room.view(for: .one), departure: nil) == .waitingForOpponent)
    }

    @Test("between hands shows the ready prompt until the player is ready")
    func readyPrompt() {
        var room = MatchRoomBuilder().build()
        room.seatAliceAndBobAndDeal()
        _ = room.handle(.act(.fold), from: TestPlayers.aliceConnection)
        #expect(TableStatus.make(view: room.view(for: .one), departure: nil) == .readyPrompt)

        _ = room.handle(.ready, from: TestPlayers.aliceConnection)
        #expect(TableStatus.make(view: room.view(for: .one), departure: nil) == .waitingForOthersReady)
    }

    @Test("during a hand it reports whose turn it is, by name")
    func turns() {
        let (alice, bob) = views()
        #expect(TableStatus.make(view: alice, departure: nil) == .yourTurn)
        #expect(TableStatus.make(view: bob, departure: nil) == .othersTurn(name: "Alice"))
    }

    @Test("a finished match reports the winner and places from each side")
    func matchOver() {
        // Default deck: Alice Ah Kh, Bob Qs Qd on a dry board, so Bob's queens hold.
        let (alice, bob) = views(after: [(.one, .allIn), (.two, .call)])
        #expect(TableStatus.make(view: alice, departure: nil) == .matchOver(youWon: false, place: 2))
        #expect(TableStatus.make(view: bob, departure: nil) == .matchOver(youWon: true, place: 1))
    }

    @Test("the last other player leaving is reported by name")
    func playerLeft() {
        var room = MatchRoomBuilder().build()
        room.seatAliceAndBobAndDeal()
        _ = room.handle(.leave, from: TestPlayers.bobConnection)
        #expect(TableStatus.make(view: room.view(for: .one), departure: "Bob") == .playerLeft(name: "Bob"))
    }

    @Test("a knocked-out player watches between hands")
    func spectating() throws {
        var room = MatchRoomBuilder()
            .maxPlayers(3)
            .startingStack(100)
            .deck(HandStateBuilder()
                .stacks(100, 100, 100)
                .holeCards(.one, "Ah Ad")
                .holeCards(.two, "Kh Kd")
                .holeCards(.three, "Qh Qc")
                .deck())
            .build()
        room.seatThreeAndDeal()
        // Carol (big blind, 80 behind) is the only one to call Alice's shove.
        _ = room.handle(.act(.allIn), from: TestPlayers.aliceConnection)
        _ = room.handle(.act(.fold), from: TestPlayers.bobConnection)
        _ = room.handle(.act(.call), from: TestPlayers.carolConnection)
        #expect(room.match.isBusted(.three))
        #expect(TableStatus.make(view: room.view(for: .three), departure: nil) == .spectating)
        #expect(TableStatus.make(view: room.view(for: .two), departure: nil) == .readyPrompt)
    }
}

@Suite("SeatLayout")
struct SeatLayoutTests {
    @Test("one opponent sits straight across")
    func headsUp() {
        #expect(SeatLayout.positions(count: 1) == [SeatLayout.Point(x: 0.5, y: 0.1)])
    }

    @Test("several opponents fan out clockwise from the left, symmetric about the middle")
    func fan() {
        let five = SeatLayout.positions(count: 5)
        #expect(five.count == 5)
        #expect(five.map(\.x) == five.map(\.x).sorted(), "left to right")
        #expect(five[0].y == five[4].y)
        #expect(abs(five[0].x + five[4].x - 1) < 0.0001)
        #expect(five[2] == SeatLayout.Point(x: 0.5, y: 0.1))
        #expect(SeatLayout.positions(count: 0).isEmpty)
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
        #expect(HandOutcome(result: final.result, seat: .one)?.amount == 1500, "half of the pot each")
    }

    @Test("with side pots the loser is told who took the main pot")
    func sidePots() throws {
        let start = try HandStateBuilder()
            .stacks(100, 300, 500)
            .holeCards(.one, "Ah Ad")
            .holeCards(.two, "Kh Kd")
            .holeCards(.three, "Qh Qc")
            .start()
        let final = try HandEngine.play(start, [(.one, .allIn), (.two, .allIn), (.three, .call)]).state
        let carol = try #require(HandOutcome(result: final.result, seat: .three))
        #expect(carol.kind == .youLost)
        #expect(carol.winner == .one)
        #expect(carol.amount == 300)
        let bob = try #require(HandOutcome(result: final.result, seat: .two))
        #expect(bob.kind == .youWon)
        #expect(bob.amount == 400, "the side pot")
    }

    @Test("no result yields no outcome")
    func none() {
        #expect(HandOutcome(result: nil, seat: .one) == nil)
    }
}
