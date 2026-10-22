#if DEBUG
import Foundation
import PokerCore

/// An in-process table for previews: auto-calling players sit around the
/// previewed player, so lobbies and tables show real seats with no network.
/// Keep it alive for the whole preview; it owns the bots.
final class PreviewTable {
    let table: HostedTable
    private var bots: [AutoCallingOpponent] = []

    init(code: String = "PREVIEW", maxPlayers: Int = TableSize.minPlayers) {
        table = HostedTable(
            room: MatchRoom(code: code, configuration: MatchConfiguration(maxPlayers: maxPlayers)),
            graceInterval: .seconds(1)
        )
    }

    /// Seats auto-callers in order. The first to sit at an empty table hosts it.
    func seat(_ names: [String]) async {
        for name in names {
            let client = MatchSessionClient(
                identity: PlayerIdentity(id: "preview-\(name)", displayName: name, countryCode: PreviewPlayers.country(for: name)),
                transport: await table.connect()
            )
            // Seated before returning, so seating order (and the host) is predictable.
            await client.connect()
            let bot = AutoCallingOpponent(client: client)
            bot.start()
            bots.append(bot)
        }
    }

    /// A transport for the previewed player; the session sits down on `connect()`.
    /// Synchronous so a preview can build its session client up front.
    func transport() -> any MatchTransport {
        let table = table
        return DeferredTransport(Task { await table.connect() })
    }
}

/// Forwards to an in-process transport that is still being created:
/// joining a `HostedTable` is async, building a session client is not.
nonisolated struct DeferredTransport: MatchTransport {
    let incoming: AsyncStream<ServerMessage>
    private let pending: Task<InMemoryTransport, Never>

    init(_ pending: Task<InMemoryTransport, Never>) {
        self.pending = pending
        incoming = AsyncStream { continuation in
            let forwarding = Task {
                for await message in await pending.value.incoming {
                    continuation.yield(message)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in forwarding.cancel() }
        }
    }

    func send(_ message: ClientMessage) async throws {
        try await pending.value.send(message)
    }

    func close() async {
        await pending.value.close()
    }
}

/// Names and countries for the opponents shown in previews.
enum PreviewPlayers {
    static let opponents = ["Lucía", "Mateo", "Sofía", "Bob", "Carol"]

    static func country(for name: String) -> String {
        ["Lucía": "ES", "Mateo": "AR", "Sofía": "CO", "Bob": "US", "Carol": "CA"][name] ?? ""
    }

    /// The previewed player, matching `PreviewIdentity.store`.
    static let me = PlayerIdentity(id: "preview-me", displayName: "Ticoxxo", countryCode: "MX")
}
#endif
