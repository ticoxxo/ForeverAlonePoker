import Foundation
import Testing
import PokerCore
import PokerCoreTestSupport

@Suite("MatchRoom: seating")
struct MatchRoomSeatingTests {
    @Test("first player is welcomed and waits; second player fills the room")
    func joining() {
        var room = MatchRoomBuilder().code("ABC123").build()

        let first = room.handle(.join(TestPlayers.alice), from: TestPlayers.aliceConnection)
        #expect(first.messages(for: TestPlayers.aliceConnection) == [
            .welcome(seat: .one, roomCode: "ABC123"),
            .waitingForOpponent,
        ])
        #expect(!room.isFull)

        let second = room.handle(.join(TestPlayers.bob), from: TestPlayers.bobConnection)
        #expect(second.messages(for: TestPlayers.bobConnection).first == .welcome(seat: .two, roomCode: "ABC123"))
        #expect(second.latestView(for: TestPlayers.aliceConnection)?.opponent?.name == "Bob")
        #expect(second.latestView(for: TestPlayers.bobConnection)?.opponent?.name == "Alice")
        #expect(room.isFull)
    }

    @Test("a third player is rejected")
    func roomFull() {
        var room = MatchRoomBuilder().build()
        _ = room.handle(.join(TestPlayers.alice), from: TestPlayers.aliceConnection)
        _ = room.handle(.join(TestPlayers.bob), from: TestPlayers.bobConnection)
        let out = room.handle(.join(TestPlayers.carol), from: TestPlayers.carolConnection)
        #expect(out.rejections(for: TestPlayers.carolConnection) == ["Room is full."])
    }

    @Test("messages before joining are rejected")
    func mustJoinFirst() {
        var room = MatchRoomBuilder().build()
        let out = room.handle(.act(.fold), from: TestPlayers.aliceConnection)
        #expect(out.rejections(for: TestPlayers.aliceConnection) == ["Join the room first."])
    }

    @Test("nothing is dealt until both players are ready")
    func readyGate() {
        var room = MatchRoomBuilder().build()
        _ = room.handle(.join(TestPlayers.alice), from: TestPlayers.aliceConnection)
        _ = room.handle(.join(TestPlayers.bob), from: TestPlayers.bobConnection)

        let one = room.handle(.ready, from: TestPlayers.aliceConnection)
        #expect(room.match.phase == .waitingForHand)
        #expect(one.latestView(for: TestPlayers.bobConnection)?.opponent?.isReady == true)

        let both = room.handle(.ready, from: TestPlayers.bobConnection)
        #expect(room.match.phase == .inHand)
        #expect(both.events(for: TestPlayers.aliceConnection).first == .handStarted(handNumber: 1, button: .one))
        #expect(both.events(for: TestPlayers.bobConnection) == both.events(for: TestPlayers.aliceConnection), "events are public and identical")
    }
}

@Suite("MatchRoom: redaction")
struct MatchRoomRedactionTests {
    @Test("each player sees only their own hole cards")
    func ownCardsOnly() throws {
        var room = MatchRoomBuilder()
            .deck(HandStateBuilder().holeCards(.one, "As Kd").holeCards(.two, "7c 2h").deck())
            .build()
        let out = room.seatAliceAndBobAndDeal()

        let alice = try #require(out.latestView(for: TestPlayers.aliceConnection))
        let bob = try #require(out.latestView(for: TestPlayers.bobConnection))
        #expect(alice.holeCards == cards("As Kd"))
        #expect(bob.holeCards == cards("7c 2h"))
        #expect(alice.isMyTurn)
        #expect(!bob.isMyTurn)
        #expect(alice.legalActions.callAmount == 10)
        #expect(bob.legalActions == .none)

        // Nothing sent to Bob may mention Alice's cards before showdown.
        let bobPayload = try String(decoding: JSONEncoder().encode(out.messages(for: TestPlayers.bobConnection)), as: UTF8.self)
        #expect(!bobPayload.contains("As"))
        #expect(!bobPayload.contains("Kd"))
    }

    @Test("opponent cards are revealed only through the showdown result")
    func showdownReveal() throws {
        var room = MatchRoomBuilder()
            .deck(HandStateBuilder().holeCards(.one, "Ah Kh").holeCards(.two, "Qs Qd").board("Ac 7d Ts 4h 9s").deck())
            .build()
        room.seatAliceAndBobAndDeal()
        _ = room.handle(.act(.allIn), from: TestPlayers.aliceConnection)
        let out = room.handle(.act(.call), from: TestPlayers.bobConnection)

        let bob = try #require(out.latestView(for: TestPlayers.bobConnection))
        #expect(bob.lastResult?.reason == .showdown)
        #expect(bob.lastResult?.shownHands.first { $0.seat == .one }?.holeCards == cards("Ah Kh"))
        #expect(bob.phase == .finished(winner: .one))
        #expect(bob.pot == 0, "the pot has been paid out")
        #expect(bob.me.stack == 0)
        #expect(bob.opponent?.stack == 3000)
    }
}

@Suite("MatchRoom: play")
struct MatchRoomPlayTests {
    @Test("an illegal action is rejected only to its sender")
    func rejection() {
        var room = MatchRoomBuilder().build()
        room.seatAliceAndBobAndDeal()
        let out = room.handle(.act(.check), from: TestPlayers.bobConnection)
        #expect(out.rejections(for: TestPlayers.bobConnection) == ["It is not your turn."])
        #expect(out.messages(for: TestPlayers.aliceConnection).isEmpty)
    }

    @Test("a full hand flows through the room and the next hand needs both ready again")
    func fullHand() throws {
        var room = MatchRoomBuilder().build()
        room.seatAliceAndBobAndDeal()
        let out = room.handle(.act(.fold), from: TestPlayers.aliceConnection)

        #expect(out.events(for: TestPlayers.aliceConnection).contains(.acted(seat: .one, action: .fold, chips: 0)))
        let view = try #require(out.latestView(for: TestPlayers.bobConnection))
        #expect(view.phase == .waitingForHand)
        #expect(view.me.stack == 1510)
        #expect(view.lastResult?.winners == [.two])

        _ = room.handle(.ready, from: TestPlayers.aliceConnection)
        #expect(room.match.phase == .waitingForHand)
        _ = room.handle(.ready, from: TestPlayers.bobConnection)
        #expect(room.match.currentHand?.handNumber == 2)
        #expect(room.match.currentHand?.button == .two)
    }

    @Test("ready after the match is over starts a rematch")
    func rematch() {
        var room = MatchRoomBuilder()
            .deck(HandStateBuilder().holeCards(.one, "Ah Kh").holeCards(.two, "Qs Qd").board("Ac 7d Ts 4h 9s").deck())
            .build()
        room.seatAliceAndBobAndDeal()
        _ = room.handle(.act(.allIn), from: TestPlayers.aliceConnection)
        _ = room.handle(.act(.call), from: TestPlayers.bobConnection)
        #expect(room.match.phase == .finished(winner: .one))

        _ = room.handle(.ready, from: TestPlayers.aliceConnection)
        _ = room.handle(.ready, from: TestPlayers.bobConnection)
        #expect(room.match.phase == .inHand)
        #expect(room.match.currentHand?.handNumber == 1)
        #expect(room.match.stacks == [1500, 1500], "fresh stacks for the rematch")
        #expect(room.match.currentHand?.pot == 30)
    }

    @Test("leaving mid-hand forfeits the pot and frees the seat")
    func leave() throws {
        var room = MatchRoomBuilder().build()
        room.seatAliceAndBobAndDeal()
        let out = room.handle(.leave, from: TestPlayers.bobConnection)

        #expect(out.messages(for: TestPlayers.aliceConnection).contains(.opponentLeft))
        let view = try #require(out.latestView(for: TestPlayers.aliceConnection))
        #expect(view.me.stack == 1520, "Alice collects the 30 in blinds")
        #expect(view.opponent == nil)
        #expect(!room.isFull)
        #expect(out.messages(for: TestPlayers.bobConnection).isEmpty)
    }

    @Test("a dropped connection keeps the seat for the same identity")
    func reconnect() throws {
        var room = MatchRoomBuilder().build()
        room.seatAliceAndBobAndDeal()
        let dropped = room.disconnect(TestPlayers.bobConnection)
        #expect(dropped.latestView(for: TestPlayers.aliceConnection)?.opponent?.isConnected == false)
        #expect(room.isFull, "seat is held")

        let stranger = room.handle(.join(TestPlayers.carol), from: TestPlayers.carolConnection)
        #expect(stranger.rejections(for: TestPlayers.carolConnection) == ["Room is full."])

        let newConnection = ConnectionID("conn-bob-2")
        let back = room.handle(.join(TestPlayers.bob), from: newConnection)
        #expect(back.messages(for: newConnection).first == .welcome(seat: .two, roomCode: "TEST01"))
        #expect(back.latestView(for: newConnection)?.me.stack == 1480, "the forfeited hand already settled")
        #expect(back.latestView(for: TestPlayers.aliceConnection)?.opponent?.isConnected == true)
    }
}

@Suite("Protocol")
struct ProtocolTests {
    @Test("envelopes carry the protocol version and round-trip")
    func envelope() throws {
        let envelope = ClientEnvelope(.act(.raise(to: 60)))
        let data = try JSONEncoder().encode(envelope)
        let decoded = try JSONDecoder().decode(ClientEnvelope.self, from: data)
        #expect(decoded.version == ProtocolVersion.current)
        #expect(decoded.message == .act(.raise(to: 60)))
    }

    @Test("server messages round-trip")
    func serverMessages() throws {
        var room = MatchRoomBuilder().build()
        let out = room.seatAliceAndBobAndDeal()
        let messages = out.messages(for: TestPlayers.aliceConnection)
        let data = try JSONEncoder().encode(messages.map { ServerEnvelope($0) })
        let decoded = try JSONDecoder().decode([ServerEnvelope].self, from: data)
        #expect(decoded.map(\.message) == messages)
    }

    @Test("a ranked join carries the session token and the identity's country")
    func rankedJoin() throws {
        let identity = PlayerIdentity(id: "001234.abc", displayName: "Ana", countryCode: "MX")
        let message = ClientMessage.join(identity, sessionToken: "token-1")
        let data = try JSONEncoder().encode(ClientEnvelope(message))
        let decoded = try JSONDecoder().decode(ClientEnvelope.self, from: data)
        #expect(decoded.message == message)
        #expect(ClientMessage.join(TestPlayers.alice) == .join(TestPlayers.alice, sessionToken: nil), "unranked joins carry no token")
        #expect(TestPlayers.alice.countryCode == "")
    }

    @Test("rating updates round-trip")
    func ratingUpdate() throws {
        let update = RatingUpdate(rating: Rating(value: 1218, matchesPlayed: 1), delta: 18)
        let data = try JSONEncoder().encode(ServerEnvelope(.rated(update)))
        #expect(try JSONDecoder().decode(ServerEnvelope.self, from: data).message == .rated(update))
    }

    @Test("the protocol version was bumped for the ranked fields")
    func version() {
        #expect(ProtocolVersion.current == 2)
    }

    @Test("the match authority serialises room access")
    func authority() async {
        let authority = MatchAuthority(room: MatchRoomBuilder().build())
        _ = await authority.handle(.join(TestPlayers.alice), from: TestPlayers.aliceConnection)
        _ = await authority.handle(.join(TestPlayers.bob), from: TestPlayers.bobConnection)
        _ = await authority.handle(.ready, from: TestPlayers.aliceConnection)
        _ = await authority.handle(.ready, from: TestPlayers.bobConnection)
        let view = await authority.view(for: .one)
        #expect(view.isMyTurn)
        #expect(view.holeCards.count == 2)
    }
}
