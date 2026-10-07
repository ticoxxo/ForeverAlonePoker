import Foundation
import PokerCore

/// A raw, ordered, reliable byte channel to exactly one other device.
/// MultipeerConnectivity provides the production implementation; tests use an
/// in-memory pair. Everything protocol-aware sits above this.
nonisolated protocol PeerLink: Sendable {
    /// Data from the other device. Finishes when the link drops.
    var incoming: AsyncStream<Data> { get }
    func send(_ data: Data) async throws
    func disconnect() async
}

/// The guest side of a peer-to-peer match: speaks the wire protocol over a
/// `PeerLink` to the device that hosts the authority.
nonisolated struct PeerLinkTransport: MatchTransport {
    private let link: any PeerLink
    let incoming: AsyncStream<ServerMessage>

    init(link: any PeerLink) {
        self.link = link
        incoming = AsyncStream { continuation in
            let task = Task {
                for await data in link.incoming {
                    do {
                        continuation.yield(try WireCodec.decode(ServerMessage.self, from: data))
                    } catch WireError.versionMismatch {
                        continuation.yield(.rejected(reason: "The other player is running an incompatible version of the app."))
                    } catch {
                        // Ignore anything that is not a protocol message.
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func send(_ message: ClientMessage) async throws {
        try await link.send(WireCodec.encode(message))
    }

    func close() async {
        await link.disconnect()
    }
}

/// The host side: relays a remote guest's wire messages into a `HostedTable`
/// and the table's replies back over the link, preserving order both ways.
nonisolated final class RemoteGuestBridge: Sendable {
    let connectionID: ConnectionID
    private let reader: Task<Void, Never>
    private let writer: Task<Void, Never>

    init(link: any PeerLink, table: HostedTable, connectionID: ConnectionID = ConnectionID(UUID().uuidString)) {
        self.connectionID = connectionID
        let (outgoing, outgoingContinuation) = AsyncStream<ServerMessage>.makeStream()

        writer = Task {
            for await message in outgoing {
                guard let data = try? WireCodec.encode(message) else { continue }
                try? await link.send(data)
            }
        }

        reader = Task {
            await table.attachRemote(id: connectionID) { message in
                outgoingContinuation.yield(message)
            }
            for await data in link.incoming {
                do {
                    let message = try WireCodec.decode(ClientMessage.self, from: data)
                    await table.receiveRemote(message, from: connectionID)
                } catch WireError.versionMismatch(let received, let expected) {
                    outgoingContinuation.yield(.rejected(
                        reason: "Incompatible app version (\(received), host expects \(expected))."
                    ))
                } catch {
                    // Ignore anything that is not a protocol message.
                }
            }
            await table.detachRemote(connectionID)
            outgoingContinuation.finish()
        }
    }

    func stop() {
        reader.cancel()
        writer.cancel()
    }
}
