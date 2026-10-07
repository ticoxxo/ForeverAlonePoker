import Foundation
import PokerCore

/// A table whose authority runs in this process. Players connect either
/// locally (`connect()` returns an in-process transport) or remotely
/// (`attachRemote` registers a delivery closure for a peer on another device).
/// Every message, local or remote, goes through the same `MatchAuthority`, and
/// its replies are routed back to whichever connection should receive them.
///
/// Used by tests and previews (two local players), and by the Multipeer host
/// (host local, guest remote). The Hummingbird server does the equivalent with
/// WebSockets and does not use this type.
actor HostedTable {
    let authority: MatchAuthority
    private var locals: [ConnectionID: AsyncStream<ServerMessage>.Continuation] = [:]
    private var remotes: [ConnectionID: @Sendable (ServerMessage) -> Void] = [:]

    init(authority: MatchAuthority) {
        self.authority = authority
    }

    init(room: MatchRoom) {
        self.init(authority: MatchAuthority(room: room))
    }

    // MARK: - Local connections

    func connect(id: ConnectionID = ConnectionID(UUID().uuidString)) -> InMemoryTransport {
        let (stream, continuation) = AsyncStream<ServerMessage>.makeStream()
        locals[id] = continuation
        return InMemoryTransport(id: id, table: self, incoming: stream)
    }

    fileprivate func send(_ message: ClientMessage, from id: ConnectionID) async throws {
        guard locals[id] != nil else { throw TransportError.notConnected }
        deliver(await authority.handle(message, from: id))
    }

    fileprivate func close(_ id: ConnectionID) async {
        guard let continuation = locals.removeValue(forKey: id) else { return }
        continuation.finish()
        deliver(await authority.disconnect(id))
    }

    // MARK: - Remote connections

    /// Registers a remote player. `deliver` is called, in order, with every
    /// message the authority addresses to this connection.
    func attachRemote(id: ConnectionID, deliver: @escaping @Sendable (ServerMessage) -> Void) {
        remotes[id] = deliver
    }

    func receiveRemote(_ message: ClientMessage, from id: ConnectionID) async {
        guard remotes[id] != nil else { return }
        deliver(await authority.handle(message, from: id))
    }

    func detachRemote(_ id: ConnectionID) async {
        guard remotes.removeValue(forKey: id) != nil else { return }
        deliver(await authority.disconnect(id))
    }

    // MARK: - Delivery

    func deliver(_ outbound: [Outbound]) {
        for item in outbound {
            if let continuation = locals[item.to] {
                continuation.yield(item.message)
            } else if let remote = remotes[item.to] {
                remote(item.message)
            }
        }
    }
}

/// Transport for a player in the same process as the `HostedTable`.
nonisolated struct InMemoryTransport: MatchTransport {
    let id: ConnectionID
    private let table: HostedTable
    let incoming: AsyncStream<ServerMessage>

    fileprivate init(id: ConnectionID, table: HostedTable, incoming: AsyncStream<ServerMessage>) {
        self.id = id
        self.table = table
        self.incoming = incoming
    }

    func send(_ message: ClientMessage) async throws {
        try await table.send(message, from: id)
    }

    func close() async {
        await table.close(id)
    }
}
