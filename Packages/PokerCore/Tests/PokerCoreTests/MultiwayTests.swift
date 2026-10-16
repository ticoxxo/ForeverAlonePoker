import Foundation
import Testing
import PokerCore
import PokerCoreTestSupport

@Suite("HandEngine: multiway")
struct MultiwayHandEngineTests {
    @Test("three-handed: the two seats after the button post, the seat after the big blind acts first")
    func threeHandedBlinds() throws {
        let (state, events) = try HandStateBuilder().stacks(1500, 1500, 1500).button(.one).startWithEvents()

        #expect(state.smallBlindSeat == .two)
        #expect(state.bigBlindSeat == .three)
        #expect(state.actor == .one)
        #expect(state.pot == 30)
        #expect(events.prefix(3) == [
            .handStarted(handNumber: 1, button: .one),
            .blindPosted(seat: .two, kind: .small, amount: 10),
            .blindPosted(seat: .three, kind: .big, amount: 20),
        ])
        #expect(state[.three].holeCards == cards("8c 8d"), "seats are dealt in order")
        #expect(state.deck.count == 46)
    }

    @Test("after the flop the first live seat after the button acts first")
    func postflopOrder() throws {
        let start = try HandStateBuilder().stacks(1500, 1500, 1500).start()
        let flop = try HandEngine.play(start, [(.one, .call), (.two, .call), (.three, .check)]).state
        #expect(flop.street == .flop)
        #expect(flop.actor == .two)
    }

    @Test("a raise reopens the action for everyone still in")
    func raiseReopens() throws {
        let start = try HandStateBuilder().stacks(1500, 1500, 1500).start()
        let limped = try HandEngine.play(start, [(.one, .call), (.two, .raise(to: 60))]).state
        #expect(limped.actor == .three)
        let back = try HandEngine.play(limped, [(.three, .call)]).state
        #expect(back.actor == .one, "the limper must respond to the raise")
        let flop = try HandEngine.play(back, [(.one, .fold)]).state
        #expect(flop.street == .flop)
        #expect(flop.actor == .two)
        #expect(flop.pot == 140)
    }

    @Test("a seat with no chips sits out and the rest play heads-up")
    func sitOut() throws {
        let state = try HandStateBuilder().stacks(1500, 0, 1500).start()
        #expect(state[.two].isSittingOut)
        #expect(state[.two].holeCards.isEmpty)
        #expect(state.smallBlindSeat == .one, "heads-up the button posts the small blind")
        #expect(state.bigBlindSeat == .three)
        #expect(state.actor == .one)
        #expect(state[.three].holeCards == cards("8c 8d"))
        #expect(HandEngine.legalActions(in: state, for: .two) == .none)
    }

    @Test("all-ins of different sizes build a main pot and a side pot")
    func sidePots() throws {
        let start = try HandStateBuilder()
            .stacks(100, 300, 500)
            .holeCards(.one, "Ah Ad")
            .holeCards(.two, "Kh Kd")
            .holeCards(.three, "Qh Qc")
            .start()
        let final = try HandEngine.play(start, [(.one, .allIn), (.two, .allIn), (.three, .call)]).state

        let result = try #require(final.result)
        #expect(result.reason == .showdown)
        #expect(result.pots == [
            PotResult(amount: 300, eligible: [.one, .two, .three], winners: [.one]),
            PotResult(amount: 400, eligible: [.two, .three], winners: [.two]),
        ])
        #expect(result.payouts == [300, 400, 0])
        #expect(result.winners == [.one, .two])
        #expect(final.seats.map(\.stack) == [300, 400, 200])
        #expect(result.shownHands.map(\.seat) == [.one, .two, .three])
    }

    @Test("an odd chip in a chop goes to the first winner after the button")
    func oddChip() throws {
        let start = try HandStateBuilder()
            .stacks(1000, 1000, 1000)
            .blinds(small: 5, big: 10)
            .holeCards(.one, "2c 3d")
            .holeCards(.two, "4c 4d")
            .holeCards(.three, "2d 3c")
            .board("As Ks Qs Js Ts")
            .start()
        let final = try HandEngine.play(start, [
            (.one, .call), (.two, .fold), (.three, .check),
            (.three, .check), (.one, .check),
            (.three, .check), (.one, .check),
            (.three, .check), (.one, .check),
        ]).state

        let result = try #require(final.result)
        #expect(result.winners == [.one, .three])
        #expect(result.payouts == [12, 0, 13], "seat three sits closer to the button's left")
    }

    @Test("forfeiting out of turn folds the seat and play continues")
    func forfeitMultiway() throws {
        let start = try HandStateBuilder().stacks(1500, 1500, 1500).start()
        let (state, events) = try HandEngine.forfeit(.two, in: start)
        #expect(events == [.acted(seat: .two, action: .fold, chips: 0)])
        #expect(!state.isOver)
        #expect(state.actor == .one)

        let final = try HandEngine.apply(.fold, by: .one, to: state).state
        #expect(final.result?.winners == [.three])
        #expect(final.result?.payouts == [0, 0, 30])
        #expect(final[.three].stack == 1510)
    }

    @Test("forfeiting a seat that already folded changes nothing")
    func forfeitTwice() throws {
        let start = try HandStateBuilder().stacks(1500, 1500, 1500).start()
        let folded = try HandEngine.apply(.fold, by: .one, to: start).state
        let again = try HandEngine.forfeit(.one, in: folded)
        #expect(again.state == folded)
        #expect(again.events.isEmpty)
    }
}

@Suite("MatchState: multiway")
struct MultiwayMatchStateTests {
    @Test("the last player with chips wins and the others are placed by elimination")
    func finishThreeHanded() throws {
        var match = MatchStateBuilder().players(3).startingStack(100).build()
        _ = try match.startHand(deck: HandStateBuilder()
            .stacks(100, 100, 100)
            .holeCards(.one, "Ah Ad")
            .holeCards(.two, "Kh Kd")
            .holeCards(.three, "Qh Qc")
            .deck())
        _ = try match.apply(.allIn, by: .one)
        _ = try match.apply(.call, by: .two)
        _ = try match.apply(.call, by: .three)

        #expect(match.phase == .finished(winner: .one))
        #expect(match.stacks == [300, 0, 0])
        #expect(Set(match.eliminations) == [.two, .three])
        #expect(match.place(of: .one) == 1)
        #expect(Set([match.place(of: .two), match.place(of: .three)]) == [2, 3])
    }

    @Test("a player who leaves is knocked out and the button skips their seat")
    func retireSkipsButton() throws {
        var match = MatchStateBuilder().players(3).build()
        _ = try match.retire(.two)
        #expect(match.stack(for: .two) == 0)
        #expect(match.isBusted(.two))
        #expect(match.place(of: .two) == 3)

        _ = try match.startHand(deck: HandStateBuilder().stacks(1500, 0, 1500).deck())
        #expect(match.currentHand?.smallBlindSeat == .one)
        #expect(match.currentHand?.bigBlindSeat == .three)
        _ = try match.apply(.fold, by: .one)
        #expect(match.button == .three)
    }

    @Test("leaving mid-hand folds now and removes the chips when the hand ends")
    func retireMidHand() throws {
        var match = MatchStateBuilder().players(3).build()
        _ = try match.startHand(deck: HandStateBuilder().stacks(1500, 1500, 1500).deck())
        let events = try match.retire(.three)
        #expect(events == [.acted(seat: .three, action: .fold, chips: 0)])
        #expect(match.phase == .inHand)
        #expect(!match.isBusted(.three))

        _ = try match.apply(.fold, by: .one)
        #expect(match.isBusted(.three))
        #expect(match.stacks == [1500, 1520, 0], "seat two wins the blinds; seat three's chips leave with them")
    }
}

@Suite("MatchRoom: lobby")
struct MatchRoomLobbyTests {
    private func lobby(maxPlayers: Int = 3) -> MatchRoom {
        var room = MatchRoomBuilder().maxPlayers(maxPlayers).build()
        _ = room.handle(.join(TestPlayers.alice), from: TestPlayers.aliceConnection)
        _ = room.handle(.join(TestPlayers.bob), from: TestPlayers.bobConnection)
        return room
    }

    @Test("a bigger table waits in the lobby and lists who joined")
    func waitsInLobby() throws {
        var room = MatchRoomBuilder().maxPlayers(4).build()
        _ = room.handle(.join(TestPlayers.alice), from: TestPlayers.aliceConnection)
        let out = room.handle(.join(TestPlayers.bob), from: TestPlayers.bobConnection)

        #expect(room.phase == .lobby)
        let bob = try #require(out.latestView(for: TestPlayers.bobConnection))
        #expect(bob.table.maxPlayers == 4)
        #expect(bob.table.host == .one)
        #expect(!bob.isHost)
        #expect(bob.players.map(\.name) == ["Alice"])
        #expect(bob.players.first?.playerID == "alice-id")
    }

    @Test("only the host can start, and not alone")
    func startGuards() {
        var room = MatchRoomBuilder().maxPlayers(3).build()
        _ = room.handle(.join(TestPlayers.alice), from: TestPlayers.aliceConnection)
        let alone = room.handle(.startMatch, from: TestPlayers.aliceConnection)
        #expect(alone.rejections(for: TestPlayers.aliceConnection) == ["Wait for at least one more player."])

        _ = room.handle(.join(TestPlayers.bob), from: TestPlayers.bobConnection)
        let guest = room.handle(.startMatch, from: TestPlayers.bobConnection)
        #expect(guest.rejections(for: TestPlayers.bobConnection) == ["Only the host can start the game."])
        #expect(!room.isStarting)
    }

    @Test("players may still join during the grace period; the deal closes the table")
    func graceThenDeal() throws {
        var room = lobby(maxPlayers: 4)
        let starting = room.handle(.startMatch, from: TestPlayers.aliceConnection)
        #expect(starting.latestView(for: TestPlayers.bobConnection)?.table.isStarting == true)
        #expect(room.phase == .lobby)

        let late = room.handle(.join(TestPlayers.carol), from: TestPlayers.carolConnection)
        #expect(late.messages(for: TestPlayers.carolConnection).first == .welcome(seat: .three, roomCode: "TEST01"))

        let dealt = room.beginMatch()
        #expect(room.phase == .inHand)
        #expect(room.match.players == [.one, .two, .three])
        let carol = try #require(dealt.latestView(for: TestPlayers.carolConnection))
        #expect(carol.holeCards.count == 2)
        #expect(carol.players.map(\.seat) == [.one, .two], "clockwise after seat three")

        let tooLate = room.handle(.join(TestPlayers.dave), from: TestPlayers.daveConnection)
        #expect(tooLate.rejections(for: TestPlayers.daveConnection) == ["The game has already started."])
    }

    @Test("beginMatch does nothing unless the host asked to start")
    func beginNeedsRequest() {
        var room = lobby()
        #expect(room.beginMatch().isEmpty)
        #expect(room.phase == .lobby)
    }

    @Test("a full lobby turns newcomers away")
    func fullLobby() {
        var room = lobby(maxPlayers: 3)
        _ = room.handle(.join(TestPlayers.carol), from: TestPlayers.carolConnection)
        #expect(room.phase == .lobby, "a bigger table never starts by itself")
        let out = room.handle(.join(TestPlayers.dave), from: TestPlayers.daveConnection)
        #expect(out.rejections(for: TestPlayers.daveConnection) == ["Room is full."])
    }

    @Test("when the host leaves the lobby the next player becomes host")
    func hostHandoff() throws {
        var room = lobby()
        let out = room.handle(.leave, from: TestPlayers.aliceConnection)
        #expect(room.host == .two)
        #expect(out.latestView(for: TestPlayers.bobConnection)?.isHost == true)
        #expect(out.messages(for: TestPlayers.bobConnection).contains(.playerLeft(seat: .one, name: "Alice")))
    }

    @Test("Elo is on only when every seated player is ranked")
    func eloEnabled() {
        var room = MatchRoomBuilder().maxPlayers(3).rankedCapable().build()
        _ = room.handle(.join(TestPlayers.alice), from: TestPlayers.aliceConnection, verifiedRanked: true)
        _ = room.handle(.join(TestPlayers.bob), from: TestPlayers.bobConnection, verifiedRanked: true)
        #expect(room.isEloEnabled)

        let out = room.handle(.join(TestPlayers.carol), from: TestPlayers.carolConnection)
        #expect(!room.isEloEnabled)
        #expect(out.latestView(for: TestPlayers.aliceConnection)?.table.isEloEnabled == false)
        #expect(out.latestView(for: TestPlayers.aliceConnection)?.players.last?.isRanked == false)

        let local = lobby()
        #expect(!local.isEloEnabled, "a table that cannot rate never enables Elo")
    }
}

@Suite("MatchRoom: multiway play")
struct MatchRoomMultiwayTests {
    @Test("a disconnected player is folded when the action reaches them")
    func autoFoldAbsent() throws {
        var room = MatchRoomBuilder().maxPlayers(3).build()
        room.seatThreeAndDeal()
        _ = room.disconnect(TestPlayers.bobConnection)
        #expect(room.match.currentHand?[.two].hasFolded == true)
        _ = room.handle(.act(.fold), from: TestPlayers.aliceConnection)
        #expect(room.match.phase == .waitingForHand)
        #expect(room.match.button == .two)

        _ = room.handle(.ready, from: TestPlayers.aliceConnection)
        let dealt = room.handle(.ready, from: TestPlayers.carolConnection)
        #expect(dealt.events(for: TestPlayers.aliceConnection).contains(.acted(seat: .two, action: .fold, chips: 0)))
        #expect(room.match.currentHand?.actor == .three)
    }

    @Test("a player who leaves mid-match is knocked out and the others play on")
    func leaveMidMatch() throws {
        var room = MatchRoomBuilder().maxPlayers(3).build()
        room.seatThreeAndDeal()
        let out = room.handle(.leave, from: TestPlayers.carolConnection)
        #expect(out.messages(for: TestPlayers.aliceConnection).contains(.playerLeft(seat: .three, name: "Carol")))
        #expect(room.players[.three] == nil)
        #expect(room.match.phase == .inHand)

        _ = room.handle(.act(.fold), from: TestPlayers.aliceConnection)
        #expect(room.match.isBusted(.three))
        #expect(room.match.phase == .waitingForHand, "Alice and Bob still have chips")
    }

    @Test("knocked-out players stay at the table and see the result")
    func spectators() throws {
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
        _ = room.handle(.act(.allIn), from: TestPlayers.aliceConnection)
        _ = room.handle(.act(.call), from: TestPlayers.bobConnection)
        let out = room.handle(.act(.call), from: TestPlayers.carolConnection)

        let bob = try #require(out.latestView(for: TestPlayers.bobConnection))
        #expect(bob.phase == .finished(winner: .one))
        #expect(bob.me.isBusted)
        #expect(bob.me.place != nil)
        #expect(bob.player(at: .one)?.place == 1)
        #expect(bob.player(at: .one)?.stack == 300)
    }

    @Test("ready after a multiway match ends deals a rematch for everyone still seated")
    func multiwayRematch() throws {
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
        _ = room.handle(.act(.allIn), from: TestPlayers.aliceConnection)
        _ = room.handle(.act(.call), from: TestPlayers.bobConnection)
        _ = room.handle(.act(.call), from: TestPlayers.carolConnection)

        _ = room.handle(.ready, from: TestPlayers.aliceConnection)
        _ = room.handle(.ready, from: TestPlayers.bobConnection)
        #expect(room.phase != .inHand, "every seated player must be ready")
        _ = room.handle(.ready, from: TestPlayers.carolConnection)
        #expect(room.phase == .inHand)
        #expect(room.match.stacks.prefix(3).allSatisfy { $0 <= 100 })
        #expect(room.match.eliminations.isEmpty)
    }
}

@Suite("Elo: multiway")
struct MultiwayRatingTests {
    @Test("with one loser it matches a heads-up update")
    func matchesHeadsUp() {
        let winner = Rating(value: 1300, matchesPlayed: 12)
        let loser = Rating(value: 1250, matchesPlayed: 3)
        let headsUp = EloCalculator.update(player: winner, opponent: loser, outcome: .win)
        let multiway = EloCalculator.updateMultiway(winner: winner, losers: [loser])
        #expect(multiway.winner == headsUp.player)
        #expect(multiway.losers == [headsUp.opponent])
    }

    @Test("the winner gains about one win's worth; every loser drops")
    func fieldOfFive() {
        let field = Array(repeating: Rating.initial, count: 5)
        let result = EloCalculator.updateMultiway(winner: .initial, losers: field)
        #expect(result.winner.value == 1220, "K 40 shared over five even pairings: 5 × 8 × 0.5")
        #expect(result.winner.matchesPlayed == 1)
        #expect(result.losers.allSatisfy { $0.value == 1180 && $0.matchesPlayed == 1 })
    }
}
