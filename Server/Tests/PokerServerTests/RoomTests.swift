import Foundation
import Testing
import PokerCore
import PokerCoreTestSupport
import NIOCore
@testable import PokerServerCore

@Suite("RoomCode")
struct RoomCodeTests {
    @Test("codes are six characters from the unambiguous alphabet")
    func format() {
        var generator = SeededRandomNumberGenerator(seed: 7)
        for _ in 0..<100 {
            let code = RoomCode.random(using: &generator)
            #expect(code.count == 6)
            #expect(RoomCode.isValid(code))
            #expect(!code.contains("0") && !code.contains("O") && !code.contains("1") && !code.contains("I"))
        }
    }

    @Test("normalisation uppercases and trims user input")
    func normalize() {
        #expect(RoomCode.normalize("  abc234 ") == "ABC234")
        #expect(RoomCode.isValid(RoomCode.normalize("abc234")))
        #expect(!RoomCode.isValid("ABC"))
        #expect(!RoomCode.isValid("ABC0I1"))
    }
}

@Suite("RoomRegistry")
struct RoomRegistryTests {
    @Test("creates rooms with unique codes even when the generator repeats")
    func uniqueCodes() async {
        let codes = ["AAAAAA", "AAAAAA", "BBBBBB"]
        let index = Counter()
        let registry = RoomRegistry(generateCode: { codes[index.next() % codes.count] })
        let first = await registry.create()
        let second = await registry.create()
        #expect(first.code == "AAAAAA")
        #expect(second.code == "BBBBBB")
        #expect(await registry.count == 2)
        #expect(await registry.room("AAAAAA") === first)
        #expect(await registry.room("ZZZZZZ") == nil)
    }

    @Test("a room routes authority replies to the attached connection")
    func roomRouting() async {
        let room = Room(code: "TEST01", deckProvider: { _ in HandStateBuilder().deck() })
        let stream = await room.attach(TestPlayers.aliceConnection)
        await room.receive(.join(TestPlayers.alice), from: TestPlayers.aliceConnection)
        var iterator = stream.makeAsyncIterator()
        #expect(await iterator.next() == .welcome(seat: .one, roomCode: "TEST01"))
        guard case .state(let lobby)? = await iterator.next() else {
            Issue.record("expected the lobby state")
            return
        }
        #expect(lobby.phase == .lobby)
        #expect(await room.connectionCount == 1)

        await room.detach(TestPlayers.aliceConnection)
        #expect(await room.connectionCount == 0)
        #expect(await iterator.next() == nil, "stream finishes on detach")
    }

    @Test("rooms are created with the table size asked for")
    func tableSize() async {
        let registry = RoomRegistry()
        let room = await registry.create(configuration: MatchConfiguration(maxPlayers: 5))
        #expect(await room.authority.room.maxPlayers == 5)
    }

    @Test("idle empty rooms are swept, active ones are kept")
    func sweep() async {
        let registry = RoomRegistry()
        let idle = await registry.create()
        let active = await registry.create()
        _ = await active.attach(TestPlayers.aliceConnection)
        let later = Date().addingTimeInterval(3600)
        let removed = await registry.sweep(idleLongerThan: 600, now: later)
        #expect(removed == 1)
        #expect(await registry.room(idle.code) == nil)
        #expect(await registry.room(active.code) != nil)
    }
}

@Suite("Room: starting a bigger table")
struct RoomStartTests {
    private func lobby(grace: Duration) async -> Room {
        let room = Room(
            code: "TEST01",
            configuration: MatchConfiguration(maxPlayers: 4),
            deckProvider: { _ in HandStateBuilder().deck() },
            graceInterval: grace
        )
        for (identity, connection) in [(TestPlayers.alice, TestPlayers.aliceConnection), (TestPlayers.bob, TestPlayers.bobConnection)] {
            _ = await room.attach(connection)
            await room.receive(.join(identity), from: connection)
        }
        return room
    }

    @Test("with everyone seated the host's start deals at once")
    func startsImmediately() async {
        let room = await lobby(grace: .seconds(30))
        await room.receive(.startMatch, from: TestPlayers.aliceConnection)
        await room.waitForStart()
        #expect(await room.authority.room.phase == .inHand)
    }

    @Test("a socket still joining gets the grace period, then the table deals without it")
    func waitsForPending() async {
        let room = await lobby(grace: .seconds(1))
        _ = await room.attach(TestPlayers.carolConnection)
        await room.receive(.startMatch, from: TestPlayers.aliceConnection)
        #expect(await room.authority.room.phase == .lobby, "Carol's socket is open but she has not joined")
        await room.waitForStart()
        #expect(await room.authority.room.phase == .inHand)
        #expect(await room.authority.room.match.players == [.one, .two])
    }

    @Test("a player who joins during the grace period is dealt in")
    func joinDuringGrace() async {
        let room = await lobby(grace: .seconds(30))
        _ = await room.attach(TestPlayers.carolConnection)
        await room.receive(.startMatch, from: TestPlayers.aliceConnection)
        await room.receive(.join(TestPlayers.carol), from: TestPlayers.carolConnection)
        await room.waitForStart()
        #expect(await room.authority.room.match.players == [.one, .two, .three])
    }
}

@Suite("Room: between hands and dropped players")
struct RoomTimingTests {
    private func headsUp(pause: Duration = .seconds(30), absence: Duration = .seconds(30)) async -> Room {
        let room = Room(
            code: "TEST01",
            deckProvider: { _ in HandStateBuilder().deck() },
            nextHandPause: pause,
            absenceTimeout: absence
        )
        for (identity, connection) in [(TestPlayers.alice, TestPlayers.aliceConnection), (TestPlayers.bob, TestPlayers.bobConnection)] {
            _ = await room.attach(connection)
            await room.receive(.join(identity), from: connection)
        }
        return room
    }

    @Test("the next hand is dealt after the pause with nobody pressing Ready")
    func autoDeal() async {
        let room = await headsUp(pause: .milliseconds(50))
        await room.receive(.act(.fold), from: TestPlayers.aliceConnection)
        #expect(await room.authority.room.match.phase == .waitingForHand)
        await room.waitForNextHand()
        #expect(await room.authority.room.match.currentHand?.handNumber == 2)
        #expect(await room.authority.room.match.phase == .inHand)
    }

    @Test("a dropped player still away after the timeout is knocked out")
    func absenceExpires() async {
        let room = await headsUp(absence: .milliseconds(50))
        await room.detach(TestPlayers.bobConnection)
        #expect(await room.authority.room.players[.two] != nil, "the seat is held at first")
        await room.waitForAbsences()
        #expect(await room.authority.room.players[.two] == nil)
        #expect(await room.authority.room.match.phase == .finished(winner: .one))
    }

    @Test("a player who leaves is held like a drop and knocked out after the timeout")
    func leaveExpires() async {
        let room = await headsUp(absence: .milliseconds(50))
        await room.receive(.leave, from: TestPlayers.bobConnection)
        #expect(await room.authority.room.players[.two] != nil, "the seat is held at first")
        await room.waitForAbsences()
        #expect(await room.authority.room.players[.two] == nil)
        #expect(await room.authority.room.match.phase == .finished(winner: .one))
    }

    @Test("a player who rejoins before the timeout keeps the seat")
    func rejoinInTime() async {
        let room = await headsUp(absence: .milliseconds(200))
        await room.detach(TestPlayers.bobConnection)
        let back = ConnectionID("conn-bob-2")
        _ = await room.attach(back)
        await room.receive(.join(TestPlayers.bob), from: back)
        await room.waitForAbsences()
        #expect(await room.authority.room.players[.two]?.connection == back)
    }
}

@Suite("POST /rooms body")
struct CreateRoomRequestTests {
    @Test("no body is heads-up; a size in range is accepted; anything else is refused")
    func parsing() {
        #expect(CreateRoomRequest.maxPlayers(from: ByteBuffer()) == 2)
        #expect(CreateRoomRequest.maxPlayers(from: ByteBuffer(string: #"{"maxPlayers": 6}"#)) == 6)
        #expect(CreateRoomRequest.maxPlayers(from: ByteBuffer(string: #"{}"#)) == 2)
        #expect(CreateRoomRequest.maxPlayers(from: ByteBuffer(string: #"{"maxPlayers": 7}"#)) == nil)
        #expect(CreateRoomRequest.maxPlayers(from: ByteBuffer(string: "nonsense")) == nil)
    }
}

/// Tiny thread-safe counter for deterministic generators in tests.
final class Counter: @unchecked Sendable {
    private var value = 0
    private let lock = NSLock()

    func next() -> Int {
        lock.lock()
        defer { lock.unlock() }
        let current = value
        value += 1
        return current
    }
}
