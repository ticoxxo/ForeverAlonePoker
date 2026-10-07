import Foundation
import Testing
import PokerCore
import PokerCoreTestSupport
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
        #expect(await iterator.next() == .waitingForOpponent)
        #expect(await room.connectionCount == 1)

        await room.detach(TestPlayers.aliceConnection)
        #expect(await room.connectionCount == 0)
        #expect(await iterator.next() == nil, "stream finishes on detach")
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
