#if DEBUG
import Foundation
import PokerCore

/// A development-only opponent that readies up and checks or calls whenever
/// it is its turn. Used by previews and the practice table so the UI can be
/// exercised without a second device. Not a bot and not shipped.
final class AutoCallingOpponent {
    let client: MatchSessionClient
    private var loop: Task<Void, Never>?

    init(client: MatchSessionClient) {
        self.client = client
    }

    func start() {
        loop?.cancel()
        loop = Task { [client] in
            await client.connect()
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(400))
                guard let view = client.view else { continue }
                switch view.phase {
                case .waitingForHand, .finished:
                    if !view.me.isReady, view.opponent != nil { await client.ready() }
                case .inHand:
                    guard view.isMyTurn else { continue }
                    if view.legalActions.canCheck {
                        await client.check()
                    } else if view.legalActions.callAmount != nil {
                        await client.call()
                    }
                }
            }
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
    }
}

/// A complete in-process practice setup: the human on seat one, the
/// auto-caller on seat two, both through one `HostedTable`.
@Observable
final class PracticeSession {
    let table: HostedTable
    private(set) var player: MatchSessionClient?
    private var opponent: AutoCallingOpponent?

    init(room: MatchRoom = MatchRoom(code: "PRACTICE")) {
        table = HostedTable(room: room)
    }

    func start(playerName: String = "You") async {
        guard player == nil else { return }
        let player = MatchSessionClient(
            identity: PlayerIdentity(id: "practice-player", displayName: playerName),
            transport: await table.connect()
        )
        let opponent = AutoCallingOpponent(client: MatchSessionClient(
            identity: PlayerIdentity(id: "practice-caller", displayName: "Auto-caller"),
            transport: await table.connect()
        ))
        self.player = player
        self.opponent = opponent
        await player.connect()
        opponent.start()
    }

    func stop() async {
        opponent?.stop()
        await player?.leave()
    }
}
#endif
