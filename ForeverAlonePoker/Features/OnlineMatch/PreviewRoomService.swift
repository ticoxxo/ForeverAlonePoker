#if DEBUG
import Foundation
import PokerCore

/// A room server for previews: rooms are `PreviewTable`s in this process,
/// so the online lobby and table run for real without a network.
nonisolated struct PreviewRoomService: RoomService {
    enum Scenario: Sendable {
        /// You create the table; these players sit down after you.
        case hostTable(opponents: [String])
        /// The code belongs to `host`'s table of `maxPlayers`, already seated with `others`.
        case joinTable(host: String, others: [String], maxPlayers: Int)
        /// The server never answers.
        case slowServer
        /// Every code is unknown.
        case noSuchRoom
    }

    static let roomCode = "PRV42K"

    let scenario: Scenario
    private let room = PreviewRoom()

    init(_ scenario: Scenario) {
        self.scenario = scenario
    }

    func createRoom(maxPlayers: Int) async throws -> String {
        switch scenario {
        case .hostTable:
            await room.open(maxPlayers: maxPlayers)
            return Self.roomCode
        case .joinTable:
            throw RoomServiceError.badResponse
        case .slowServer:
            try await Task.sleep(for: .seconds(3600))
            throw RoomServiceError.badResponse
        case .noSuchRoom:
            throw RoomServiceError.roomNotFound
        }
    }

    func checkRoom(_ code: String) async throws {
        switch scenario {
        case .joinTable(let host, let others, let maxPlayers):
            await room.open(maxPlayers: maxPlayers)
            await room.seat([host] + others)
        case .slowServer:
            try await Task.sleep(for: .seconds(3600))
        case .hostTable, .noSuchRoom:
            throw RoomServiceError.roomNotFound
        }
    }

    func makeTransport(roomCode: String) -> any MatchTransport {
        let opponents: [String]
        if case .hostTable(let names) = scenario {
            opponents = names
        } else {
            opponents = []
        }
        let room = room
        return DeferredTransport(Task {
            let transport = await room.connect()
            // Opponents arrive once you have taken the host's seat.
            Task {
                try? await Task.sleep(for: .milliseconds(300))
                await room.seat(opponents)
            }
            return transport
        })
    }
}

/// Holds the scenario's table; created when the room is created or checked.
@MainActor
private final class PreviewRoom {
    private var previewTable: PreviewTable?

    /// The service is built off the main actor; the table only on first use.
    nonisolated init() {}

    @discardableResult
    func open(maxPlayers: Int) -> PreviewTable {
        if let previewTable { return previewTable }
        let created = PreviewTable(code: PreviewRoomService.roomCode, maxPlayers: maxPlayers)
        previewTable = created
        return created
    }

    func seat(_ names: [String]) async {
        await previewTable?.seat(names)
    }

    func connect() async -> InMemoryTransport {
        await open(maxPlayers: TableSize.minPlayers).table.connect()
    }
}

#endif
