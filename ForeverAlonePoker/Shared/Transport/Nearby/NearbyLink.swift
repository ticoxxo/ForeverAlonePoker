import Foundation
import Network

/// `PeerLink` over an `NWConnection`. Network.framework calls back on its own
/// queue, so this type is not main-actor isolated and only feeds async
/// streams, which are safe from any thread.
nonisolated final class NearbyLink: PeerLink, @unchecked Sendable {
    let incoming: AsyncStream<Data>
    /// For the lobby: `.ready` means the TLS handshake succeeded.
    let stateChanges: AsyncStream<NWConnection.State>

    private let connection: NWConnection
    private let queue = DispatchQueue(label: "ForeverAlonePoker.nearby.link")
    private let incomingContinuation: AsyncStream<Data>.Continuation
    private let stateContinuation: AsyncStream<NWConnection.State>.Continuation
    private var decoder = LengthPrefixedFraming.Decoder()
    private var isClosed = false

    init(connection: NWConnection) {
        self.connection = connection
        (incoming, incomingContinuation) = AsyncStream<Data>.makeStream()
        (stateChanges, stateContinuation) = AsyncStream<NWConnection.State>.makeStream()
        connection.stateUpdateHandler = { [weak self] state in
            self?.handle(state)
        }
    }

    func start() {
        connection.start(queue: queue)
    }

    func send(_ data: Data) async throws {
        guard connection.state == .ready else { throw TransportError.notConnected }
        let framed = LengthPrefixedFraming.frame(data)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: framed, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }

    func disconnect() async {
        close()
        connection.cancel()
    }

    // MARK: - Private

    private func handle(_ state: NWConnection.State) {
        stateContinuation.yield(state)
        switch state {
        case .ready:
            receiveNext()
        case .failed, .cancelled:
            close()
        default:
            break
        }
    }

    private func receiveNext() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] content, _, isComplete, error in
            guard let self else { return }
            if let content, !content.isEmpty {
                do {
                    for frame in try decoder.append(content) {
                        incomingContinuation.yield(frame)
                    }
                } catch {
                    connection.cancel()
                    return
                }
            }
            if isComplete || error != nil {
                close()
                return
            }
            receiveNext()
        }
    }

    private func close() {
        guard !isClosed else { return }
        isClosed = true
        incomingContinuation.finish()
        stateContinuation.finish()
    }
}
