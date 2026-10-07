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
        case waitingForOpponent
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
    private(set) var opponentLeft = false
    /// Called once each time a match reaches `.finished`, so a feature can
    /// record it (the client itself knows nothing about persistence).
    var onMatchFinished: ((MatchSummary) -> Void)?
    private var reportedFinishedHand: Int?

    var seat: Seat? {
        if case .seated(let seat, _) = connection { return seat }
        return nil
    }

    var isMyTurn: Bool { view?.isMyTurn ?? false }
    var legalActions: LegalActions { view?.legalActions ?? .none }

    private let transport: any MatchTransport
    private var receiveTask: Task<Void, Never>?
    private var assignedSeat: (seat: Seat, roomCode: String)?
    private let maxEvents = 50

    init(identity: PlayerIdentity, transport: any MatchTransport) {
        self.identity = identity
        self.transport = transport
    }

    // MARK: - Lifecycle

    /// Starts listening and asks for a seat.
    func connect() async {
        guard connection == .idle || isDisconnected else { return }
        connection = .connecting
        opponentLeft = false
        startReceiving()
        await send(.join(identity))
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
            assignedSeat = (seat, roomCode)
            connection = .seated(seat, roomCode: roomCode)
        case .waitingForOpponent:
            connection = .waitingForOpponent
        case .state(let newView):
            // The first state after waiting means the opponent has arrived.
            if connection == .waitingForOpponent, let assignedSeat {
                connection = .seated(assignedSeat.seat, roomCode: assignedSeat.roomCode)
            }
            view = newView
            lastRejection = nil
            if newView.opponent != nil { opponentLeft = false }
            reportIfFinished(newView)
        case .event(let event):
            events.append(event)
            if events.count > maxEvents { events.removeFirst(events.count - maxEvents) }
        case .rejected(let reason):
            lastRejection = reason
        case .opponentLeft:
            opponentLeft = true
        }
    }

    private func reportIfFinished(_ view: PlayerView) {
        guard case .finished(let winner) = view.phase else {
            reportedFinishedHand = nil
            return
        }
        // A finished match keeps sending the same hand number; report it once.
        guard reportedFinishedHand != view.handNumber else { return }
        reportedFinishedHand = view.handNumber
        onMatchFinished?(MatchSummary(
            didWin: winner == view.seat,
            opponentName: view.opponent?.name ?? "",
            myFinalStack: view.me.stack,
            opponentFinalStack: view.opponent?.stack ?? 0,
            handsPlayed: view.handNumber
        ))
    }
}

/// The facts worth keeping about a finished match.
nonisolated struct MatchSummary: Equatable, Sendable {
    let didWin: Bool
    let opponentName: String
    let myFinalStack: Chips
    let opponentFinalStack: Chips
    let handsPlayed: Int
}
