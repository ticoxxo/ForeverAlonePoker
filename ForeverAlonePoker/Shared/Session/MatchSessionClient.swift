import Foundation
import Observation
import PokerCore

/// The player's side of a match. It owns a transport, turns the authority's
/// messages into observable UI state, and exposes the actions a player can
/// take. Views bind to this type and never see the transport or the protocol.
@Observable
final class MatchSessionClient {
    enum ConnectionState: Equatable {
        case idle
        case connecting
        case seated(Seat, roomCode: String)
        case disconnected(reason: String?)
    }

    let identity: PlayerIdentity

    private(set) var connection: ConnectionState = .idle
    /// Latest snapshot from the authority; the whole table UI derives from it.
    private(set) var view: PlayerView?
    /// Recent public events, oldest first, capped to `maxEvents`.
    private(set) var events: [GameEvent] = []
    /// The most recent rejected action, cleared when the next state arrives.
    private(set) var lastRejection: String?
    /// Name of the last player who left the table for good; cleared when the
    /// next hand is dealt.
    private(set) var lastDeparture: String?
    /// Called once each time a match reaches `.finished`, so a feature can
    /// record it (the client itself knows nothing about persistence).
    var onMatchFinished: ((MatchSummary) -> Void)?
    private var reportedFinishedHand: Int?
    /// The referee's verdict after a ranked match (tdr/0010); `nil` otherwise
    /// and cleared when the next match starts.
    private(set) var ratingUpdate: RatingUpdate?
    var onRated: ((RatingUpdate) -> Void)?
    /// Sent with the join; `nil` plays unranked.
    private let sessionToken: String?

    var seat: Seat? {
        if case .seated(let seat, _) = connection { return seat }
        return nil
    }

    var isMyTurn: Bool { view?.isMyTurn ?? false }
    /// This player opened the table and decides when it starts (tdr/0013).
    var isHost: Bool { view?.isHost ?? false }
    /// Still gathering players.
    var isInLobby: Bool { view?.phase == .lobby }
    /// A heads-up opponent left and nobody else is at the table.
    var opponentLeft: Bool { lastDeparture != nil && view?.players.isEmpty == true }
    var legalActions: LegalActions { view?.legalActions ?? .none }

    private let transport: any MatchTransport
    private var receiveTask: Task<Void, Never>?
    private let maxEvents = 50

    init(identity: PlayerIdentity, transport: any MatchTransport, sessionToken: String? = nil) {
        self.identity = identity
        self.transport = transport
        self.sessionToken = sessionToken
    }

    // MARK: - Lifecycle

    /// Starts listening and asks for a seat.
    func connect() async {
        guard connection == .idle || isDisconnected else { return }
        connection = .connecting
        lastDeparture = nil
        startReceiving()
        await send(.join(identity, sessionToken: sessionToken))
    }

    func leave() async {
        await send(.leave)
        await transport.close()
        receiveTask?.cancel()
        receiveTask = nil
        connection = .disconnected(reason: nil)
    }

    // MARK: - Player actions

    func ready() async { await send(.ready) }
    /// Host only: deal the first hand of a table of three or more.
    func startMatch() async { await send(.startMatch) }
    func act(_ action: PlayerAction) async { await send(.act(action)) }
    func fold() async { await act(.fold) }
    func check() async { await act(.check) }
    func call() async { await act(.call) }
    func bet(_ amount: Chips) async { await act(.bet(amount)) }
    func raise(to total: Chips) async { await act(.raise(to: total)) }
    func allIn() async { await act(.allIn) }

    // MARK: - Private

    private var isDisconnected: Bool {
        if case .disconnected = connection { return true }
        return false
    }

    private func send(_ message: ClientMessage) async {
        do {
            try await transport.send(message)
        } catch {
            connection = .disconnected(reason: "\(error)")
        }
    }

    private func startReceiving() {
        receiveTask?.cancel()
        let stream = transport.incoming
        receiveTask = Task { [weak self] in
            for await message in stream {
                guard let self else { return }
                self.handle(message)
            }
            guard let self, !Task.isCancelled else { return }
            if case .disconnected = self.connection { return }
            self.connection = .disconnected(reason: "Connection closed.")
        }
    }

    private func handle(_ message: ServerMessage) {
        switch message {
        case .welcome(let seat, let roomCode):
            connection = .seated(seat, roomCode: roomCode)
        case .state(let newView):
            if newView.phase == .inHand, newView.handNumber != view?.handNumber { lastDeparture = nil }
            view = newView
            lastRejection = nil
            reportIfFinished(newView)
        case .event(let event):
            events.append(event)
            if events.count > maxEvents { events.removeFirst(events.count - maxEvents) }
        case .rejected(let reason):
            lastRejection = reason
        case .playerLeft(_, let name):
            lastDeparture = name
        case .rated(let update):
            ratingUpdate = update
            onRated?(update)
        }
    }

    private func reportIfFinished(_ view: PlayerView) {
        guard case .finished(let winner) = view.phase else {
            reportedFinishedHand = nil
            ratingUpdate = nil
            return
        }
        // A finished match keeps sending the same hand number; report it once.
        guard reportedFinishedHand != view.handNumber else { return }
        reportedFinishedHand = view.handNumber
        onMatchFinished?(MatchSummary(view: view, winner: winner))
    }
}

/// The facts worth keeping about a finished match.
nonisolated struct MatchSummary: Equatable, Sendable {
    let didWin: Bool
    /// Everyone else at the table, e.g. "Bob" or "Bob, Carol and Dave".
    let opponentName: String
    let myFinalStack: Chips
    /// The winner's stack when this player lost; the best other stack otherwise.
    let opponentFinalStack: Chips
    let handsPlayed: Int
    /// Finishing position, 1 for the winner.
    let place: Int
    /// Players at the table when the match ended, this player included.
    let playerCount: Int

    init(
        didWin: Bool,
        opponentName: String,
        myFinalStack: Chips,
        opponentFinalStack: Chips,
        handsPlayed: Int,
        place: Int? = nil,
        playerCount: Int = 2
    ) {
        self.didWin = didWin
        self.opponentName = opponentName
        self.myFinalStack = myFinalStack
        self.opponentFinalStack = opponentFinalStack
        self.handsPlayed = handsPlayed
        self.playerCount = playerCount
        self.place = place ?? (didWin ? 1 : playerCount)
    }

    init(view: PlayerView, winner: Seat) {
        let didWin = winner == view.seat
        let playerCount = max(view.players.count + 1, TableSize.minPlayers)
        self.init(
            didWin: didWin,
            opponentName: view.players.map(\.name).formatted(.list(type: .and)),
            myFinalStack: view.me.stack,
            opponentFinalStack: view.players.map(\.stack).max() ?? 0,
            handsPlayed: view.handNumber,
            place: view.me.place,
            playerCount: max(playerCount, view.me.place ?? 0)
        )
    }
}
