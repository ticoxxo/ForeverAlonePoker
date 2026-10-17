import Testing
import PokerCore
import PokerCoreTestSupport
@testable import ForeverAlonePoker

/// Skips events up to the next state snapshot.
private func nextState(_ iterator: inout AsyncStream<ServerMessage>.AsyncIterator) async -> PlayerView? {
    while let message = await iterator.next() {
        if case .state(let view) = message { return view }
    }
    return nil
}

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
        #expect(await nextState(&aliceMessages)?.phase == .lobby)

        try await bob.send(.join(TestPlayers.bob))
        var bobMessages = bob.incoming.makeAsyncIterator()
        #expect(await bobMessages.next() == .welcome(seat: .two, roomCode: "ROOM42"))
        let bobView = await nextState(&bobMessages)
        #expect(bobView?.seat == .two)
        let aliceView = await nextState(&aliceMessages)
        #expect(aliceView?.seat == .one)
        #expect(aliceView?.opponent?.name == "Bob")
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

/// A transport the test drives by hand: records what the client sent and
/// pushes whatever server messages the test wants.
private final class ScriptedTransport: MatchTransport, @unchecked Sendable {
    let incoming: AsyncStream<ServerMessage>
    private let continuation: AsyncStream<ServerMessage>.Continuation
    private(set) var sent: [ClientMessage] = []

    init() {
        (incoming, continuation) = AsyncStream<ServerMessage>.makeStream()
    }

    func push(_ message: ServerMessage) { continuation.yield(message) }
    func send(_ message: ClientMessage) async throws { sent.append(message) }
    func close() async { continuation.finish() }
}

@Suite("MatchSessionClient")
@MainActor
struct MatchSessionClientTests {
    @Test("connecting seats the player in the lobby until the opponent arrives")
    func connecting() async {
        let harness = await SessionHarness()
        #expect(harness.alice.connection == .idle)

        await harness.alice.connect()
        #expect(await eventually { harness.alice.isInLobby })
        #expect(harness.alice.isHost, "the first player to sit down hosts")
        #expect(harness.alice.view?.players.isEmpty == true)

        await harness.bob.connect()
        #expect(await eventually { harness.alice.view?.opponent?.name == "Bob" })
        #expect(await eventually { harness.bob.connection == .seated(.two, roomCode: "TEST01") })
        #expect(harness.alice.connection == .seated(.one, roomCode: "TEST01"))
        #expect(harness.alice.seat == .one)
    }

    @Test("the second player sitting down deals a heads-up hand; only the button may act")
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

    @Test("a ranked client joins with its session token and keeps the referee's rating")
    func rankedJoin() async {
        let transport = ScriptedTransport()
        let client = MatchSessionClient(identity: TestPlayers.alice, transport: transport, sessionToken: "session-1")
        var rated: [RatingUpdate] = []
        client.onRated = { rated.append($0) }

        await client.connect()
        #expect(transport.sent == [.join(TestPlayers.alice, sessionToken: "session-1")])

        let update = RatingUpdate(rating: Rating(value: 1220, matchesPlayed: 1), delta: 20)
        transport.push(.rated(update))
        #expect(await eventually { client.ratingUpdate == update })
        #expect(rated == [update])
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

    @Test("a bigger table: the host starts it and every player is dealt in")
    func multiwayStart() async {
        let table = HostedTable(room: MatchRoomBuilder().maxPlayers(3).build(), graceInterval: .seconds(30))
        let alice = MatchSessionClient(identity: TestPlayers.alice, transport: await table.connect(id: TestPlayers.aliceConnection))
        let bob = MatchSessionClient(identity: TestPlayers.bob, transport: await table.connect(id: TestPlayers.bobConnection))
        let carol = MatchSessionClient(identity: TestPlayers.carol, transport: await table.connect(id: TestPlayers.carolConnection))
        await alice.connect()
        await bob.connect()
        #expect(await eventually { alice.view?.players.count == 1 })
        #expect(alice.isInLobby, "a bigger table waits for the host")

        await bob.startMatch()
        #expect(await eventually { bob.lastRejection == "Only the host can start the game." })

        await alice.startMatch()
        #expect(await eventually { alice.view?.table.isStarting == true })
        // Carol's connection is open but she has not sat down: the grace period waits for her.
        await carol.connect()
        await table.waitForStart()
        #expect(await eventually { carol.view?.phase == .inHand && alice.view?.phase == .inHand })
        #expect(carol.view?.players.map(\.name) == ["Alice", "Bob"])
        #expect(alice.view?.holeCards.count == 2)
    }

    @Test("an emote shows by the sender's seat for everyone, once per turn, then fades")
    func emotes() async {
        let harness = await SessionHarness()
        harness.alice.reactionDuration = .milliseconds(100)
        await harness.deal()
        #expect(harness.bob.canEmote)

        await harness.bob.emote(.laughing)
        #expect(await eventually { harness.alice.reactions[.two]?.emote == .laughing })
        #expect(await eventually { harness.bob.reactions[.two]?.emote == .laughing })
        #expect(!harness.bob.canEmote, "one emote per turn")

        #expect(await eventually { harness.alice.reactions[.two] == nil }, "the bubble fades")
        await harness.alice.call()
        #expect(await eventually { harness.bob.canEmote }, "the action moved on")
    }

    @Test("the hosted table deals the next hand by itself after the pause")
    func autoDeal() async {
        let table = HostedTable(room: MatchRoomBuilder().build(), nextHandPause: .milliseconds(50))
        let alice = MatchSessionClient(identity: TestPlayers.alice, transport: await table.connect(id: TestPlayers.aliceConnection))
        let bob = MatchSessionClient(identity: TestPlayers.bob, transport: await table.connect(id: TestPlayers.bobConnection))
        await alice.connect()
        await bob.connect()
        #expect(await eventually { alice.view?.phase == .inHand })

        await alice.fold()
        #expect(await eventually { alice.view?.handNumber == 2 && alice.view?.phase == .inHand })
    }

    @Test("a dropped player is shown reconnecting, then knocked out when the timeout passes")
    func absenceExpires() async {
        let table = HostedTable(room: MatchRoomBuilder().maxPlayers(3).build(), graceInterval: .zero, absenceTimeout: .milliseconds(100))
        let alice = MatchSessionClient(identity: TestPlayers.alice, transport: await table.connect(id: TestPlayers.aliceConnection))
        let bob = MatchSessionClient(identity: TestPlayers.bob, transport: await table.connect(id: TestPlayers.bobConnection))
        let carolTransport = await table.connect(id: TestPlayers.carolConnection)
        let carol = MatchSessionClient(identity: TestPlayers.carol, transport: carolTransport)
        await alice.connect()
        await bob.connect()
        await carol.connect()
        #expect(await eventually { alice.view?.players.count == 2 })
        await alice.startMatch()
        await table.waitForStart()
        #expect(await eventually { alice.view?.phase == .inHand })

        // The connection drops without a leave.
        await carolTransport.close()
        #expect(await eventually { alice.view?.player(at: .three)?.isConnected == false })
        #expect(alice.view?.player(at: .three)?.hasFolded == false, "the hand stays live until Carol's turn")

        await table.waitForAbsences()
        #expect(await eventually { alice.lastDeparture == "Carol" })
        #expect(alice.view?.player(at: .three) == nil)
    }

    @Test("a player leaving a bigger table is named to the others")
    func departureNamed() async {
        let table = HostedTable(room: MatchRoomBuilder().maxPlayers(3).build(), graceInterval: .zero)
        let alice = MatchSessionClient(identity: TestPlayers.alice, transport: await table.connect(id: TestPlayers.aliceConnection))
        let bob = MatchSessionClient(identity: TestPlayers.bob, transport: await table.connect(id: TestPlayers.bobConnection))
        let carol = MatchSessionClient(identity: TestPlayers.carol, transport: await table.connect(id: TestPlayers.carolConnection))
        await alice.connect()
        await bob.connect()
        await carol.connect()
        #expect(await eventually { alice.view?.players.count == 2 })
        await alice.startMatch()
        await table.waitForStart()
        #expect(await eventually { alice.view?.phase == .inHand })

        await carol.leave()
        #expect(await eventually { alice.lastDeparture == "Carol" })
        #expect(!alice.opponentLeft, "Bob is still at the table")
    }
}
