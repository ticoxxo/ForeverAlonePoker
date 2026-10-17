import Foundation
import PokerCore

/// The few things `WebSocketTransport` needs from a socket, so tests can
/// substitute a fake for `URLSessionWebSocketTask`.
nonisolated protocol WebSocketConnection: Sendable {
    func resume()
    func send(text: String) async throws
    /// Waits for the next text frame. Throws when the socket closes.
    func receiveText() async throws -> String
    /// Round-trips a ping; throws when no pong comes back.
    func sendPing() async throws
    func cancel()
}

extension URLSessionWebSocketTask: WebSocketConnection {
    nonisolated func send(text: String) async throws {
        try await send(.string(text))
    }

    nonisolated func sendPing() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            sendPing { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
    }

    nonisolated func receiveText() async throws -> String {
        while true {
            switch try await receive() {
            case .string(let text):
                return text
            case .data(let data):
                return String(decoding: data, as: UTF8.self)
            @unknown default:
                continue
            }
        }
    }
}

/// `MatchTransport` to the Hummingbird server (tdr/0008): one WebSocket per
/// player, JSON envelopes as text frames. A ping every `heartbeat` notices a
/// link that died silently (the phone lost its network) and closes the
/// socket, so the session client can reconnect (tdr/0016).
nonisolated final class WebSocketTransport: MatchTransport, Sendable {
    static let defaultHeartbeat: Duration = .seconds(10)

    let incoming: AsyncStream<ServerMessage>
    private let connection: any WebSocketConnection
    private let receiveTask: Task<Void, Never>
    private let heartbeatTask: Task<Void, Never>

    init(connection: any WebSocketConnection, heartbeat: Duration = WebSocketTransport.defaultHeartbeat) {
        self.connection = connection
        let (stream, continuation) = AsyncStream<ServerMessage>.makeStream()
        incoming = stream
        connection.resume()
        receiveTask = Task {
            while !Task.isCancelled {
                let text: String
                do {
                    text = try await connection.receiveText()
                } catch {
                    break
                }
                do {
                    continuation.yield(try WireCodec.decodeText(ServerMessage.self, from: text))
                } catch WireError.versionMismatch {
                    continuation.yield(.rejected(reason: "The server runs an incompatible protocol version."))
                } catch {
                    // Ignore anything that is not a protocol message.
                }
            }
            continuation.finish()
        }
        heartbeatTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: heartbeat)
                guard !Task.isCancelled else { return }
                do {
                    try await connection.sendPing()
                } catch {
                    // Cancelling makes the pending receive throw, which ends `incoming`.
                    connection.cancel()
                    return
                }
            }
        }
    }

    deinit {
        heartbeatTask.cancel()
    }

    convenience init(url: URL, session: URLSession = .shared) {
        self.init(connection: session.webSocketTask(with: url))
    }

    func send(_ message: ClientMessage) async throws {
        try await connection.send(text: try WireCodec.encodeText(message))
    }

    func close() async {
        heartbeatTask.cancel()
        receiveTask.cancel()
        connection.cancel()
    }
}
