import Foundation
import Observation
import PokerCore

/// Creates or joins a room on the server and hands the lobby and the table a
/// session client. The creator picks the table size and is the host (tdr/0013).
/// A player can also search for any open table without a code (tdr/0021).
@Observable
final class OnlineLobbyModel {
    enum Phase: Equatable {
        case idle
        case working
        /// Looking for an open table to join without a code.
        case searching
        case connected(roomCode: String)
        case failed(String)
    }

    let identity: PlayerIdentity
    private(set) var phase: Phase = .idle
    private(set) var client: MatchSessionClient?
    /// Seats at a table this player creates. Only editable before searching.
    /// Clamped in a setter, not `didSet`: writing back from an `@Observable`
    /// property's `didSet` re-enters the setter and recurses forever.
    var maxPlayers: Int {
        get { chosenMaxPlayers }
        set {
            guard canChooseTableSize, TableSize.range.contains(newValue) else { return }
            chosenMaxPlayers = newValue
        }
    }
    private var chosenMaxPlayers = TableSize.minPlayers
    /// Set when a search ran out of time; the lobby shows "No match found".
    var showsNoMatchFound = false
    private let service: any RoomService
    /// Ranked session token (tdr/0010); `nil` plays unranked.
    private let sessionToken: String?
    /// How long a search without a code keeps looking, and how often it asks.
    private let searchTimeout: Duration
    private let searchInterval: Duration
    private var searchTask: Task<Void, Never>?

    static let defaultSearchTimeout: Duration = .seconds(180)
    static let defaultSearchInterval: Duration = .seconds(3)

    init(
        identity: PlayerIdentity,
        service: any RoomService,
        sessionToken: String? = nil,
        searchTimeout: Duration = OnlineLobbyModel.defaultSearchTimeout,
        searchInterval: Duration = OnlineLobbyModel.defaultSearchInterval
    ) {
        self.identity = identity
        self.service = service
        self.sessionToken = sessionToken
        self.searchTimeout = searchTimeout
        self.searchInterval = searchInterval
    }

    var roomCode: String? {
        if case .connected(let code) = phase { return code }
        return nil
    }

    var canChooseTableSize: Bool { phase == .idle }

    /// The match has been dealt; the table replaces the lobby.
    var isPlaying: Bool {
        guard let view = client?.view else { return false }
        return view.phase != .lobby
    }

    /// Creates a table of `maxPlayers` and sits down as its host.
    func searchOpponents() async {
        guard phase == .idle else { return }
        phase = .working
        do {
            let code = try await service.createRoom(maxPlayers: maxPlayers)
            await connect(to: code)
        } catch {
            phase = .failed(Self.describe(error))
        }
    }

    /// Starts `findMatch()` in a task the lobby can cancel.
    func startMatchSearch() {
        guard phase == .idle else { return }
        phase = .searching
        showsNoMatchFound = false
        searchTask = Task { await search() }
    }

    func cancelSearch() {
        searchTask?.cancel()
        searchTask = nil
        if phase == .searching { phase = .idle }
    }

    /// Asks the server for open tables until one has a free seat, then sits
    /// down there. Full tables are never entered. Gives up after
    /// `searchTimeout` and raises `showsNoMatchFound`; a cancelled search
    /// just returns to idle.
    func findMatch() async {
        guard phase == .idle else { return }
        phase = .searching
        showsNoMatchFound = false
        await search()
    }

    private func search() async {
        let clock = ContinuousClock()
        let deadline = clock.now + searchTimeout
        while phase == .searching, !Task.isCancelled {
            // A failed request is retried on the next round, like an empty list.
            let rooms = (try? await service.openRooms()) ?? []
            guard phase == .searching, !Task.isCancelled else { return }
            if let room = rooms.first(where: \.hasFreeSeat) {
                searchTask = nil
                await connect(to: room.code)
                return
            }
            let remaining = deadline - clock.now
            guard remaining > .zero else { break }
            try? await Task.sleep(for: min(searchInterval, remaining))
        }
        guard phase == .searching else { return }
        searchTask = nil
        phase = .idle
        showsNoMatchFound = !Task.isCancelled
    }

    func join(code rawCode: String) async {
        guard phase == .idle else { return }
        phase = .working
        let code = HTTPRoomService.normalize(rawCode)
        do {
            try await service.checkRoom(code)
            await connect(to: code)
        } catch {
            phase = .failed(Self.describe(error))
        }
    }

    /// Host: deal now; players still connecting get a short grace period.
    func startGame() async {
        guard let client, client.isHost else { return }
        await client.startMatch()
    }

    func leave() async {
        cancelSearch()
        await client?.leave()
        client = nil
        phase = .idle
    }

    /// Back to the lobby after a failure.
    func reset() {
        phase = .idle
    }

    private func connect(to code: String) async {
        let service = service
        let client = MatchSessionClient(
            identity: identity,
            transport: service.makeTransport(roomCode: code),
            sessionToken: sessionToken,
            reconnect: { service.makeTransport(roomCode: code) }
        )
        self.client = client
        phase = .connected(roomCode: code)
        await client.connect()
    }

    private static func describe(_ error: Error) -> String {
        switch error {
        case RoomServiceError.roomNotFound: String(localized: "No table with that code.")
        case RoomServiceError.invalidCode: String(localized: "Enter the 6-character code.")
        case RoomServiceError.server(let status): String(localized: "The server answered with an error (\(status)).")
        case RoomServiceError.badResponse: String(localized: "Unexpected reply from the server.")
        default: String(localized: "Could not reach the server. Check the server address in your profile.")
        }
    }
}
