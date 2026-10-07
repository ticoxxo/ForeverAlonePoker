import Foundation
import Hummingbird
import HummingbirdTesting
import HummingbirdWebSocket
import HummingbirdWSTesting
import Testing
import PokerCore
import PokerCoreTestSupport
@testable import PokerServerCore

@Suite("HTTP")
struct HTTPTests {
    @Test("health check answers")
    func health() async throws {
        let app = buildApplication(registry: RoomRegistry())
        try await app.test(.router) { client in
            try await client.execute(uri: "/health", method: .get) { response in
                #expect(response.status == .ok)
                #expect(String(buffer: response.body) == "OK")
            }
        }
    }

    @Test("creating a room returns a code that can then be looked up")
    func createAndLookup() async throws {
        let registry = RoomRegistry(generateCode: { "ABC234" })
        let app = buildApplication(registry: registry)
        try await app.test(.router) { client in
            try await client.execute(uri: "/rooms", method: .post) { response in
                #expect(response.status == .ok)
                let created = try JSONDecoder().decode(RoomCreated.self, from: response.body)
                #expect(created.code == "ABC234")
            }
            try await client.execute(uri: "/rooms/abc234", method: .get) { response in
                #expect(response.status == .ok)
                let info = try JSONDecoder().decode(RoomInfo.self, from: response.body)
                #expect(info == RoomInfo(code: "ABC234", seatsTaken: 0, connected: 0))
            }
            try await client.execute(uri: "/rooms/ZZZZZZ", method: .get) { response in
                #expect(response.status == .notFound)
            }
        }
    }
}

/// Reads protocol messages from one test WebSocket. A class so it can be
/// captured by the nested `@Sendable` socket closures; each reader is only
/// ever used from one task at a time.
private final class MessageReader: @unchecked Sendable {
    private var iterator: WebSocketInboundMessageStream.AsyncIterator

    init(_ inbound: WebSocketInboundStream) {
        iterator = inbound.messages(maxSize: 64 * 1024).makeAsyncIterator()
    }

    func next() async throws -> ServerMessage? {
        guard let frame = try await iterator.next() else { return nil }
        guard case .text(let text) = frame else { return nil }
        return try ServerWire.decode(ServerMessage.self, from: text)
    }

    /// Skips events and returns the next state that satisfies `predicate`.
    func nextState(where predicate: (PlayerView) -> Bool = { _ in true }) async throws -> PlayerView? {
        while let message = try await next() {
            if case .state(let view) = message, predicate(view) { return view }
        }
        return nil
    }
}

private enum Wire {
    static func send(_ message: ClientMessage, to outbound: WebSocketOutboundWriter) async throws {
        try await outbound.write(.text(try ServerWire.encode(message)))
    }
}

@Suite("WebSocket flow")
struct WebSocketFlowTests {
    @Test("two players join over WebSockets and play a hand")
    func playsAHand() async throws {
        let registry = RoomRegistry(
            generateCode: { "ABC234" },
            deckProvider: { _ in HandStateBuilder().holeCards(.one, "As Kd").holeCards(.two, "7c 2h").deck() }
        )
        let app = buildApplication(registry: registry)
        try await app.test(.live) { client in
            try await client.execute(uri: "/rooms", method: .post) { response in
                #expect(response.status == .ok)
            }

            try await client.ws("/rooms/ABC234/ws") { aliceIn, aliceOut, _ in
                let alice = MessageReader(aliceIn)
                try await Wire.send(.join(TestPlayers.alice), to: aliceOut)
                #expect(try await alice.next() == .welcome(seat: .one, roomCode: "ABC234"))
                #expect(try await alice.next() == .waitingForOpponent)

                try await client.ws("/rooms/ABC234/ws") { bobIn, bobOut, _ in
                    let bob = MessageReader(bobIn)
                    try await Wire.send(.join(TestPlayers.bob), to: bobOut)
                    #expect(try await bob.next() == .welcome(seat: .two, roomCode: "ABC234"))

                    let aliceView = try await alice.nextState()
                    let bobView = try await bob.nextState()
                    #expect(aliceView?.opponent?.name == "Bob")
                    #expect(bobView?.opponent?.name == "Alice")

                    try await Wire.send(.ready, to: aliceOut)
                    try await Wire.send(.ready, to: bobOut)

                    let dealtAlice = try await alice.nextState { $0.phase == .inHand }
                    let dealtBob = try await bob.nextState { $0.phase == .inHand }
                    #expect(dealtAlice?.holeCards == cards("As Kd"))
                    #expect(dealtBob?.holeCards == cards("7c 2h"))
                    #expect(dealtAlice?.isMyTurn == true)
                    #expect(dealtBob?.isMyTurn == false)

                    // Alice folds; Bob collects the blinds.
                    try await Wire.send(.act(.fold), to: aliceOut)
                    let bobAfter = try await bob.nextState { $0.phase == .waitingForHand }
                    #expect(bobAfter?.me.stack == 1510)
                    #expect(bobAfter?.lastResult?.winners == [.two])
                }

                // Bob's socket closed: Alice is told and the seat is held.
                var sawOpponentLeft = false
                while !sawOpponentLeft, let message = try await alice.next() {
                    if message == .opponentLeft { sawOpponentLeft = true }
                }
                #expect(sawOpponentLeft)
            }
        }
    }

    @Test("an unknown room code refuses the upgrade")
    func unknownRoom() async throws {
        let app = buildApplication(registry: RoomRegistry())
        try await app.test(.live) { client in
            await #expect(throws: (any Error).self) {
                try await client.ws("/rooms/ZZZZZZ/ws") { _, _, _ in }
            }
        }
    }

    @Test("an incompatible protocol version is answered with a rejection")
    func versionMismatch() async throws {
        let registry = RoomRegistry(generateCode: { "ABC234" })
        let app = buildApplication(registry: registry)
        try await app.test(.live) { client in
            try await client.execute(uri: "/rooms", method: .post) { _ in }
            try await client.ws("/rooms/ABC234/ws") { inbound, outbound, _ in
                let messages = MessageReader(inbound)
                try await outbound.write(.text(#"{"version": 42, "message": {"ready": {}}}"#))
                guard case .rejected(let reason)? = try await messages.next() else {
                    Issue.record("expected a rejection")
                    return
                }
                #expect(reason.contains("Incompatible app version"))
            }
        }
    }
}
