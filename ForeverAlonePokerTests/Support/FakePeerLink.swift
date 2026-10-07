import Foundation
@testable import ForeverAlonePoker

/// Two in-memory `PeerLink`s wired to each other, standing in for an
/// `MCSession` between two devices.
nonisolated final class FakePeerLink: PeerLink, @unchecked Sendable {
    let incoming: AsyncStream<Data>
    private let continuation: AsyncStream<Data>.Continuation
    private var peer: FakePeerLink?
    private(set) var isConnected = true
    /// Everything this side has sent, for assertions on the wire format.
    private(set) var sent: [Data] = []

    private init() {
        (incoming, continuation) = AsyncStream<Data>.makeStream()
    }

    static func pair() -> (FakePeerLink, FakePeerLink) {
        let a = FakePeerLink()
        let b = FakePeerLink()
        a.peer = b
        b.peer = a
        return (a, b)
    }

    func send(_ data: Data) async throws {
        guard isConnected, let peer, peer.isConnected else { throw TransportError.notConnected }
        sent.append(data)
        peer.continuation.yield(data)
    }

    func disconnect() async {
        guard isConnected else { return }
        isConnected = false
        continuation.finish()
        peer?.isConnected = false
        peer?.continuation.finish()
    }
}
