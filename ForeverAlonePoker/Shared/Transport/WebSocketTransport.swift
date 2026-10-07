import Foundation
import PokerCore

/// The few things `WebSocketTransport` needs from a socket, so tests can
/// substitute a fake for `URLSessionWebSocketTask`.
nonisolated protocol WebSocketConnection: Sendable {
    func resume()
    func send(text: String) async throws
    /// Waits for the next text frame. Throws when the socket closes.
    func receiveText() async throws -> String
    func cancel()
}

extension URLSessionWebSocketTask: WebSocketConnection {
    nonisolated func send(text: String) async throws {
        try await send(.string(text))
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
/// player, JSON envelopes as text frames.
nonisolated final class WebSocketTransport: MatchTransport, Sendable {
    let incoming: AsyncStream<ServerMessage>
    private let connection: any WebSocketConnection
    private let receiveTask: Task<Void, Never>

    init(connection: any WebSocketConnection) {
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
    }

    convenience init(url: URL, session: URLSession = .shared) {
        self.init(connection: session.webSocketTask(with: url))
    }

    func send(_ message: ClientMessage) async throws {
        try await connection.send(text: try WireCodec.encodeText(message))
    }

    func close() async {
        receiveTask.cancel()
        connection.cancel()
    }
}
