import Foundation
import PokerCore

nonisolated enum RoomServiceError: Error, Equatable {
    case invalidCode
    case roomNotFound
    case server(status: Int)
    case badResponse
}

/// Creating and finding rooms on the server, and opening the transport to one.
nonisolated protocol RoomService: Sendable {
    /// Creates a room and returns its code.
    func createRoom() async throws -> String
    /// Throws `roomNotFound` when the code is unknown.
    func checkRoom(_ code: String) async throws
    func makeTransport(roomCode: String) -> any MatchTransport
}

/// Talks to the Hummingbird server's REST surface (tdr/0008).
nonisolated struct HTTPRoomService: RoomService {
    let baseURL: URL
    let session: URLSession

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    /// Default development server. IPv4 loopback on purpose: `localhost`
    /// resolves to `::1` first on the simulator while the server listens on
    /// IPv4, costing a refused connection before the fallback.
    static let defaultBaseURL = URL(string: "http://127.0.0.1:8080")!

    func createRoom() async throws -> String {
        var request = URLRequest(url: baseURL.appending(path: "rooms"))
        request.httpMethod = "POST"
        let (data, response) = try await session.data(for: request)
        try Self.ensureOK(response)
        guard let created = try? JSONDecoder().decode(RoomCreated.self, from: data) else {
            throw RoomServiceError.badResponse
        }
        return created.code
    }

    func checkRoom(_ code: String) async throws {
        let normalized = Self.normalize(code)
        guard !normalized.isEmpty else { throw RoomServiceError.invalidCode }
        let (_, response) = try await session.data(from: baseURL.appending(path: "rooms/\(normalized)"))
        try Self.ensureOK(response)
    }

    func makeTransport(roomCode: String) -> any MatchTransport {
        WebSocketTransport(url: webSocketURL(roomCode: Self.normalize(roomCode)), session: session)
    }

    func webSocketURL(roomCode: String) -> URL {
        var components = URLComponents(url: baseURL.appending(path: "rooms/\(roomCode)/ws"), resolvingAgainstBaseURL: false)!
        components.scheme = baseURL.scheme == "https" ? "wss" : "ws"
        return components.url!
    }

    static func normalize(_ code: String) -> String {
        code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private static func ensureOK(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw RoomServiceError.badResponse }
        switch http.statusCode {
        case 200..<300: return
        case 404: throw RoomServiceError.roomNotFound
        default: throw RoomServiceError.server(status: http.statusCode)
        }
    }

    private struct RoomCreated: Decodable {
        let code: String
    }
}
