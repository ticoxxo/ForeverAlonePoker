import Foundation
import Testing
import PokerCore
import PokerCoreTestSupport
@testable import ForeverAlonePoker

/// A scripted socket: the test pushes server frames in and records what the
/// transport sent.
private final class FakeWebSocketConnection: WebSocketConnection, @unchecked Sendable {
    private let (frames, continuation) = AsyncStream<String>.makeStream()
    private var iterator: AsyncStream<String>.AsyncIterator?
    private(set) var sent: [String] = []
    private(set) var resumed = false
    private(set) var cancelled = false

    func push(_ text: String) { continuation.yield(text) }
    func close() { continuation.finish() }

    func resume() { resumed = true }

    func send(text: String) async throws { sent.append(text) }

    func receiveText() async throws -> String {
        if iterator == nil { iterator = frames.makeAsyncIterator() }
        guard let text = await iterator?.next() else { throw URLError(.networkConnectionLost) }
        return text
    }

    func cancel() {
        cancelled = true
        continuation.finish()
    }
}

@Suite("WebSocketTransport")
struct WebSocketTransportTests {
    @Test("sends envelopes as text and decodes incoming text frames")
    func sendAndReceive() async throws {
        let socket = FakeWebSocketConnection()
        let transport = WebSocketTransport(connection: socket)
        #expect(socket.resumed)

        try await transport.send(.act(.call))
        #expect(try WireCodec.decodeText(ClientMessage.self, from: socket.sent[0]) == .act(.call))

        socket.push(try WireCodec.encodeText(ServerMessage.waitingForOpponent))
        var incoming = transport.incoming.makeAsyncIterator()
        #expect(await incoming.next() == .waitingForOpponent)

        socket.push(#"{"version": 99, "message": {}}"#)
        #expect(await incoming.next() == .rejected(reason: "The server runs an incompatible protocol version."))

        socket.push("not json")
        socket.push(try WireCodec.encodeText(ServerMessage.opponentLeft))
        #expect(await incoming.next() == .opponentLeft, "non-protocol frames are skipped")
    }

    @Test("closing cancels the socket and finishes the stream")
    func close() async {
        let socket = FakeWebSocketConnection()
        let transport = WebSocketTransport(connection: socket)
        await transport.close()
        #expect(socket.cancelled)
        var incoming = transport.incoming.makeAsyncIterator()
        #expect(await incoming.next() == nil)
    }

    @Test("a socket error finishes the stream")
    func socketError() async {
        let socket = FakeWebSocketConnection()
        let transport = WebSocketTransport(connection: socket)
        socket.close()
        var incoming = transport.incoming.makeAsyncIterator()
        #expect(await incoming.next() == nil)
    }
}

@Suite("HTTPRoomService")
struct HTTPRoomServiceTests {
    @Test("derives the WebSocket URL from the base URL")
    func webSocketURL() {
        let http = HTTPRoomService(baseURL: URL(string: "http://localhost:8080")!)
        #expect(http.webSocketURL(roomCode: "ABC234").absoluteString == "ws://localhost:8080/rooms/ABC234/ws")
        let https = HTTPRoomService(baseURL: URL(string: "https://poker.example.com")!)
        #expect(https.webSocketURL(roomCode: "ABC234").absoluteString == "wss://poker.example.com/rooms/ABC234/ws")
    }

    @Test("normalises codes typed by the user")
    func normalize() {
        #expect(HTTPRoomService.normalize(" abc234\n") == "ABC234")
    }
}

/// Fake service: known codes connect to an in-process authority so the lobby
/// test exercises the real client against the real room.
private struct FakeRoomService: RoomService {
    let transport: InMemoryTransport
    let knownCodes: Set<String>
    let createdCode: String

    func createRoom() async throws -> String { createdCode }

    func checkRoom(_ code: String) async throws {
        guard knownCodes.contains(code) else { throw RoomServiceError.roomNotFound }
    }

    func makeTransport(roomCode: String) -> any MatchTransport { transport }
}

@Suite("OnlineLobbyModel")
@MainActor
struct OnlineLobbyModelTests {
    private func makeModel(known: Set<String> = ["ABC234"]) async -> (OnlineLobbyModel, HostedTable) {
        let table = HostedTable(room: MatchRoomBuilder().code("ABC234").build())
        let service = FakeRoomService(transport: await table.connect(), knownCodes: known, createdCode: "ABC234")
        return (OnlineLobbyModel(identity: TestPlayers.alice, service: service), table)
    }

    @Test("creating a room connects a client and exposes the code")
    func create() async {
        let (model, _) = await makeModel()
        await model.createRoom()
        #expect(model.phase == .connected(roomCode: "ABC234"))
        #expect(model.roomCode == "ABC234")
        #expect(await eventually { model.client?.connection == .waitingForOpponent })
    }

    @Test("joining an unknown code fails with a readable reason and can be retried")
    func joinUnknown() async {
        let (model, _) = await makeModel()
        await model.join(code: "zzzzzz")
        #expect(model.phase == .failed("No table with that code."))
        #expect(model.client == nil)
        model.reset()
        #expect(model.phase == .idle)
    }

    @Test("joining a known code normalises it and connects")
    func joinKnown() async {
        let (model, _) = await makeModel()
        await model.join(code: " abc234 ")
        #expect(model.phase == .connected(roomCode: "ABC234"))
    }

    @Test("leaving returns to idle and frees the seat")
    func leave() async {
        let (model, table) = await makeModel()
        await model.createRoom()
        #expect(await eventually { model.client?.connection == .waitingForOpponent })
        await model.leave()
        #expect(model.phase == .idle)
        #expect(model.client == nil)
        let room = await table.authority.room
        #expect(room.isEmpty)
    }
}
