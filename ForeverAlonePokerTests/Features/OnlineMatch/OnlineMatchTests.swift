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
    /// Set to make the next pings fail, as when the network vanished.
    var pingFails = false

    func push(_ text: String) { continuation.yield(text) }
    func close() { continuation.finish() }

    func resume() { resumed = true }

    func send(text: String) async throws { sent.append(text) }

    func receiveText() async throws -> String {
        if iterator == nil { iterator = frames.makeAsyncIterator() }
        guard let text = await iterator?.next() else { throw URLError(.networkConnectionLost) }
        return text
    }

    func sendPing() async throws {
        if pingFails { throw URLError(.timedOut) }
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

        socket.push(try WireCodec.encodeText(ServerMessage.welcome(seat: .three, roomCode: "ABC234")))
        var incoming = transport.incoming.makeAsyncIterator()
        #expect(await incoming.next() == .welcome(seat: .three, roomCode: "ABC234"))

        socket.push(#"{"version": 99, "message": {}}"#)
        #expect(await incoming.next() == .rejected(reason: "The server runs an incompatible protocol version."))

        socket.push("not json")
        socket.push(try WireCodec.encodeText(ServerMessage.playerLeft(seat: .two, name: "Bob")))
        #expect(await incoming.next() == .playerLeft(seat: .two, name: "Bob"), "non-protocol frames are skipped")
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

    @Test("a missed heartbeat closes the socket and finishes the stream")
    func heartbeat() async {
        let socket = FakeWebSocketConnection()
        let transport = WebSocketTransport(connection: socket, heartbeat: .milliseconds(20))
        socket.pingFails = true
        var incoming = transport.incoming.makeAsyncIterator()
        #expect(await incoming.next() == nil)
        #expect(socket.cancelled)
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

/// Table sizes the fake service was asked for.
private final class CreatedSizes: @unchecked Sendable {
    var values: [Int] = []
}

/// How many times the fake service was asked for open rooms.
private final class Polls: @unchecked Sendable {
    var count = 0
}

/// Fake service: known codes connect to an in-process authority so the lobby
/// test exercises the real client against the real room.
private struct FakeRoomService: RoomService {
    let transport: InMemoryTransport
    let knownCodes: Set<String>
    let createdCode: String
    /// What `GET /rooms` answers when searching without a code.
    var listed: [OpenRoom] = []
    let created = CreatedSizes()
    let polls = Polls()

    func createRoom(maxPlayers: Int) async throws -> String {
        created.values.append(maxPlayers)
        return createdCode
    }

    func checkRoom(_ code: String) async throws {
        guard knownCodes.contains(code) else { throw RoomServiceError.roomNotFound }
    }

    func openRooms() async throws -> [OpenRoom] {
        polls.count += 1
        return listed
    }

    func makeTransport(roomCode: String) -> any MatchTransport { transport }
}

@Suite("OnlineLobbyModel")
@MainActor
struct OnlineLobbyModelTests {
    private func makeModel(
        known: Set<String> = ["ABC234"],
        maxPlayers: Int = 2,
        listed: [OpenRoom] = [],
        searchTimeout: Duration = .seconds(180)
    ) async -> (OnlineLobbyModel, HostedTable, FakeRoomService) {
        let table = HostedTable(room: MatchRoomBuilder().code("ABC234").maxPlayers(maxPlayers).build())
        let service = FakeRoomService(transport: await table.connect(), knownCodes: known, createdCode: "ABC234", listed: listed)
        let model = OnlineLobbyModel(
            identity: TestPlayers.alice,
            service: service,
            searchTimeout: searchTimeout,
            searchInterval: .milliseconds(10)
        )
        return (model, table, service)
    }

    @Test("searching creates a room, connects a client and exposes the code")
    func create() async {
        let (model, _, service) = await makeModel()
        await model.searchOpponents()
        #expect(model.phase == .connected(roomCode: "ABC234"))
        #expect(model.roomCode == "ABC234")
        #expect(service.created.values == [2], "heads-up by default")
        #expect(await eventually { model.client?.isInLobby == true })
        #expect(!model.isPlaying)
    }

    @Test("the chosen table size is sent and locked once searching")
    func tableSize() async {
        let (model, _, service) = await makeModel(maxPlayers: 4)
        model.maxPlayers = 4
        model.maxPlayers = 9
        #expect(model.maxPlayers == 4, "out of range sizes are ignored")
        await model.searchOpponents()
        #expect(service.created.values == [4])
        #expect(!model.canChooseTableSize)
        model.maxPlayers = 6
        #expect(model.maxPlayers == 4, "the picker is disabled while searching")
    }

    @Test("the host starts a bigger table and the table replaces the lobby")
    func hostStarts() async {
        let (model, table, _) = await makeModel(maxPlayers: 3)
        model.maxPlayers = 3
        await model.searchOpponents()
        #expect(await eventually { model.client?.isHost == true })

        let bob = MatchSessionClient(identity: TestPlayers.bob, transport: await table.connect())
        await bob.connect()
        #expect(await eventually { model.client?.view?.players.count == 1 })
        #expect(bob.isHost == false)

        await model.startGame()
        await table.waitForStart()
        #expect(await eventually { model.isPlaying })
        #expect(await eventually { bob.view?.phase == .inHand })
    }

    @Test("joining an unknown code fails with a readable reason and can be retried")
    func joinUnknown() async {
        let (model, _, _) = await makeModel()
        await model.join(code: "zzzzzz")
        #expect(model.phase == .failed("No table with that code."))
        #expect(model.client == nil)
        model.reset()
        #expect(model.phase == .idle)
    }

    @Test("joining a known code normalises it and connects")
    func joinKnown() async {
        let (model, _, _) = await makeModel()
        await model.join(code: " abc234 ")
        #expect(model.phase == .connected(roomCode: "ABC234"))
    }

    @Test("leaving returns to idle and frees the seat")
    func leave() async {
        let (model, table, _) = await makeModel()
        await model.searchOpponents()
        #expect(await eventually { model.client?.isInLobby == true })
        await model.leave()
        #expect(model.phase == .idle)
        #expect(model.client == nil)
        let room = await table.authority.room
        #expect(room.isEmpty)
    }

    @Test("searching without a code joins the first open room with a free seat")
    func findMatch() async {
        let (model, _, _) = await makeModel(listed: [
            OpenRoom(code: "FULL22", seatsTaken: 2, maxPlayers: 2),
            OpenRoom(code: "ABC234", seatsTaken: 1, maxPlayers: 2),
        ])
        await model.findMatch()
        #expect(model.phase == .connected(roomCode: "ABC234"), "the full room is skipped")
        #expect(!model.showsNoMatchFound)
        #expect(await eventually { model.client?.isInLobby == true })
    }

    @Test("a search that finds only full rooms gives up after the timeout and says so")
    func noMatchFound() async {
        let (model, _, service) = await makeModel(
            listed: [OpenRoom(code: "FULL22", seatsTaken: 2, maxPlayers: 2)],
            searchTimeout: .milliseconds(100)
        )
        await model.findMatch()
        #expect(model.phase == .idle)
        #expect(model.client == nil, "a full room is never entered")
        #expect(model.showsNoMatchFound)
        #expect(service.polls.count > 1, "the server is asked again while searching")
    }

    @Test("cancelling a search returns to idle without the no-match message")
    func cancelSearch() async {
        let (model, _, _) = await makeModel()
        model.startMatchSearch()
        #expect(model.phase == .searching)
        model.cancelSearch()
        #expect(model.phase == .idle)
        try? await Task.sleep(for: .milliseconds(50))
        #expect(model.phase == .idle)
        #expect(!model.showsNoMatchFound)
    }
}
