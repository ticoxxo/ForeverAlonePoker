import Foundation
import Testing
import PokerCore
import PokerCoreTestSupport
@testable import ForeverAlonePoker

@Suite("WireCodec")
struct WireCodecTests {
    @Test("client and server messages round-trip inside a versioned envelope")
    func roundTrip() throws {
        let data = try WireCodec.encode(ClientMessage.act(.raise(to: 60)))
        #expect(try WireCodec.decode(ClientMessage.self, from: data) == .act(.raise(to: 60)))

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json?["version"] as? Int == ProtocolVersion.current)
    }

    @Test("a different protocol version is rejected even if the payload changed shape")
    func versionMismatch() throws {
        let data = Data(#"{"version": 99, "message": {"somethingNew": true}}"#.utf8)
        #expect(throws: WireError.versionMismatch(received: 99, expected: ProtocolVersion.current)) {
            try WireCodec.decode(ClientMessage.self, from: data)
        }
    }

    @Test("garbage is reported as malformed")
    func malformed() {
        #expect(throws: WireError.malformed) {
            try WireCodec.decode(ServerMessage.self, from: Data("not json".utf8))
        }
    }
}

/// Host (Alice) plays through the hosted table in-process; guest (Bob) plays
/// over a fake peer link, exactly as a Multipeer guest would.
@MainActor
private struct PeerHarness {
    let table: HostedTable
    let bridge: RemoteGuestBridge
    let hostLink: FakePeerLink
    let guestLink: FakePeerLink
    let alice: MatchSessionClient
    let bob: MatchSessionClient

    init(room: MatchRoom = MatchRoomBuilder().build()) async {
        table = HostedTable(room: room)
        (hostLink, guestLink) = FakePeerLink.pair()
        bridge = RemoteGuestBridge(link: hostLink, table: table, connectionID: TestPlayers.bobConnection)
        alice = MatchSessionClient(identity: TestPlayers.alice, transport: await table.connect(id: TestPlayers.aliceConnection))
        bob = MatchSessionClient(identity: TestPlayers.bob, transport: PeerLinkTransport(link: guestLink))
    }

    @discardableResult
    func deal() async -> Bool {
        await alice.connect()
        await bob.connect()
        guard await eventually({ alice.view?.opponent != nil && bob.view?.opponent != nil }) else { return false }
        await alice.ready()
        await bob.ready()
        return await eventually { alice.view?.phase == .inHand && bob.view?.phase == .inHand }
    }
}

@Suite("PeerLinkTransport and RemoteGuestBridge")
@MainActor
struct PeerLinkTransportTests {
    @Test("a remote guest is seated and sees only their own cards")
    func guestJoins() async {
        let harness = await PeerHarness(
            room: MatchRoomBuilder().deck(HandStateBuilder().holeCards(.one, "As Kd").holeCards(.two, "7c 2h").deck()).build()
        )
        #expect(await harness.deal())
        #expect(harness.bob.connection == .seated(.two, roomCode: "TEST01"))
        #expect(harness.bob.view?.holeCards == cards("7c 2h"))
        #expect(harness.alice.view?.holeCards == cards("As Kd"))

        // Nothing that crossed the wire to Bob may contain Alice's cards.
        let wire = harness.hostLink.sent.map { String(decoding: $0, as: UTF8.self) }.joined()
        #expect(!wire.contains("As"))
        #expect(!wire.contains("Kd"))
        #expect(wire.contains("7c"))
    }

    @Test("a hand plays across the link in both directions")
    func playsAcrossLink() async {
        let harness = await PeerHarness()
        await harness.deal()

        await harness.alice.raise(to: 60)
        #expect(await eventually { harness.bob.isMyTurn && harness.bob.legalActions.callAmount == 40 })

        await harness.bob.call()
        #expect(await eventually { harness.alice.view?.street == .flop && harness.bob.view?.street == .flop })
        #expect(harness.bob.view?.pot == 120)

        await harness.bob.check()
        #expect(await eventually { harness.alice.isMyTurn })
        await harness.alice.fold()
        #expect(await eventually { harness.bob.view?.phase == .waitingForHand })
        #expect(harness.bob.view?.me.stack == 1560)
        #expect(harness.alice.view?.me.stack == 1440)
    }

    @Test("a rejected action reaches the guest and nobody else")
    func rejection() async {
        let harness = await PeerHarness()
        await harness.deal()
        await harness.bob.check()
        #expect(await eventually { harness.bob.lastRejection == "It is not your turn." })
        #expect(harness.alice.lastRejection == nil)
    }

    @Test("an incompatible version from the guest is answered with a rejection")
    func versionMismatchFromGuest() async throws {
        let harness = await PeerHarness()
        await harness.alice.connect()
        await harness.bob.connect()
        try await harness.guestLink.send(Data(#"{"version": 42, "message": {"ready": {}}}"#.utf8))
        #expect(await eventually { harness.bob.lastRejection?.contains("Incompatible app version") == true })
    }

    @Test("dropping the link forfeits the guest's hand and holds the seat")
    func linkDrops() async {
        let harness = await PeerHarness()
        await harness.deal()

        await harness.guestLink.disconnect()
        #expect(await eventually { harness.alice.view?.opponent?.isConnected == false })
        #expect(harness.alice.view?.me.stack == 1520, "the forfeited blinds are collected")
        #expect(await eventually { harness.bob.connection == .disconnected(reason: "Connection closed.") })
        let room = await harness.table.authority.room
        #expect(room.isFull, "seat is held for a reconnect")
    }
}
