import Testing
import PokerCore
import PokerCoreTestSupport
@testable import ForeverAlonePoker

@Suite("InMemoryTransport")
struct InMemoryTransportTests {
    @Test("routes the authority's replies to the connection that should receive them")
    func routing() async throws {
        let table = HostedTable(room: MatchRoomBuilder().code("ROOM42").build())
        let alice = await table.connect(id: TestPlayers.aliceConnection)
        let bob = await table.connect(id: TestPlayers.bobConnection)

        try await alice.send(.join(TestPlayers.alice))
        var aliceMessages = alice.incoming.makeAsyncIterator()
        #expect(await aliceMessages.next() == .welcome(seat: .one, roomCode: "ROOM42"))
        #expect(await aliceMessages.next() == .waitingForOpponent)

        try await bob.send(.join(TestPlayers.bob))
        var bobMessages = bob.incoming.makeAsyncIterator()
        #expect(await bobMessages.next() == .welcome(seat: .two, roomCode: "ROOM42"))
        guard case .state(let bobView) = await bobMessages.next() else {
            Issue.record("expected a state for Bob")
            return
        }
        #expect(bobView.seat == .two)
        guard case .state(let aliceView) = await aliceMessages.next() else {
            Issue.record("expected a state for Alice")
            return
        }
        #expect(aliceView.seat == .one)
        #expect(aliceView.opponent?.name == "Bob")
    }

    @Test("closing finishes the stream and tells the authority")
    func close() async throws {
        let table = HostedTable(room: MatchRoomBuilder().build())
        let alice = await table.connect(id: TestPlayers.aliceConnection)
        let bob = await table.connect(id: TestPlayers.bobConnection)
        try await alice.send(.join(TestPlayers.alice))
        try await bob.send(.join(TestPlayers.bob))

        await bob.close()
        await #expect(throws: TransportError.notConnected) {
            try await bob.send(.ready)
        }
        let room = await table.authority.room
        #expect(room.connectedSeats == [.one])
        #expect(room.isFull, "the seat is held for a reconnect")
    }
}

@Suite("MatchSessionClient")
@MainActor
struct MatchSessionClientTests {
    @Test("connecting seats the player and reports waiting until the opponent arrives")
    func connecting() async {
        let harness = await SessionHarness()
        #expect(harness.alice.connection == .idle)

        await harness.alice.connect()
        #expect(await eventually { harness.alice.connection == .waitingForOpponent })
        #expect(harness.alice.view == nil)

        await harness.bob.connect()
        #expect(await eventually { harness.alice.view?.opponent?.name == "Bob" })
        #expect(await eventually { harness.bob.connection == .seated(.two, roomCode: "TEST01") })
        #expect(harness.alice.connection == .seated(.one, roomCode: "TEST01"))
        #expect(harness.alice.seat == .one)
    }

    @Test("both ready deals a hand and only the button may act")
    func dealing() async {
        let harness = await SessionHarness()
        #expect(await harness.deal())

        #expect(harness.alice.isMyTurn)
        #expect(!harness.bob.isMyTurn)
        #expect(harness.alice.legalActions.callAmount == 10)
        #expect(harness.bob.legalActions == .none)
        #expect(harness.alice.view?.holeCards == cards("Ah Kh"))
        #expect(harness.bob.view?.holeCards == cards("Qs Qd"))
        #expect(harness.alice.events.first == .handStarted(handNumber: 1, button: .one))
        #expect(harness.alice.events == harness.bob.events)
    }

    @Test("a rejected action is reported to the sender only and clears on the next state")
    func rejection() async {
        let harness = await SessionHarness()
        await harness.deal()

        await harness.bob.check()
        #expect(await eventually { harness.bob.lastRejection == "It is not your turn." })
        #expect(harness.alice.lastRejection == nil)

        await harness.alice.call()
        #expect(await eventually { harness.bob.isMyTurn })
        #expect(harness.bob.lastRejection == nil)
    }

    @Test("a scripted hand updates both players' views")
    func scriptedHand() async {
        let harness = await SessionHarness(
            room: MatchRoomBuilder()
                .deck(HandStateBuilder().holeCards(.one, "Ah Kh").holeCards(.two, "Qs Qd").board("Ac 7d Ts 4h 9s").deck())
                .build()
        )
        await harness.deal()

        await harness.alice.raise(to: 60)
        #expect(await eventually { harness.bob.isMyTurn && harness.bob.legalActions.callAmount == 40 })

        await harness.bob.call()
        #expect(await eventually { harness.alice.view?.street == .flop })
        #expect(harness.alice.view?.community == cards("Ac 7d Ts"))
        #expect(harness.alice.view?.pot == 120)
        #expect(harness.bob.isMyTurn, "out of position acts first postflop")

        await harness.bob.allIn()
        #expect(await eventually { harness.alice.isMyTurn })
        await harness.alice.call()
        #expect(await eventually { harness.alice.view?.phase == .finished(winner: .one) })
        #expect(harness.bob.view?.lastResult?.shownHands.count == 2)
        #expect(harness.alice.view?.me.stack == 3000)
        #expect(harness.bob.view?.me.stack == 0)
    }

    @Test("a finished match is reported exactly once with the final stacks")
    func reportsFinishedMatch() async {
        let harness = await SessionHarness(
            room: MatchRoomBuilder()
                .deck(HandStateBuilder().holeCards(.one, "Ah Kh").holeCards(.two, "Qs Qd").board("Ac 7d Ts 4h 9s").deck())
                .build()
        )
        var aliceSummaries: [MatchSummary] = []
        var bobSummaries: [MatchSummary] = []
        harness.alice.onMatchFinished = { aliceSummaries.append($0) }
        harness.bob.onMatchFinished = { bobSummaries.append($0) }
        await harness.deal()

        await harness.alice.allIn()
        #expect(await eventually { harness.bob.isMyTurn })
        await harness.bob.call()
        #expect(await eventually { !aliceSummaries.isEmpty && !bobSummaries.isEmpty })

        #expect(aliceSummaries == [MatchSummary(didWin: true, opponentName: "Bob", myFinalStack: 3000, opponentFinalStack: 0, handsPlayed: 1)])
        #expect(bobSummaries == [MatchSummary(didWin: false, opponentName: "Alice", myFinalStack: 0, opponentFinalStack: 3000, handsPlayed: 1)])

        // Readying for a rematch sends more states for the finished match; still one report.
        await harness.alice.ready()
        #expect(await eventually { harness.bob.view?.opponent?.isReady == true })
        #expect(aliceSummaries.count == 1)
        #expect(bobSummaries.count == 1)
    }

    @Test("leaving tells the opponent and disconnects the leaver")
    func leaving() async {
        let harness = await SessionHarness()
        await harness.deal()

        await harness.bob.leave()
        #expect(harness.bob.connection == .disconnected(reason: nil))
        #expect(await eventually { harness.alice.opponentLeft })
        #expect(harness.alice.view?.opponent == nil)
        #expect(harness.alice.view?.me.stack == 1520, "Alice collects the blinds")
    }
}
