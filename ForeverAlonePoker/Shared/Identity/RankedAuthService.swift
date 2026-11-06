import Foundation

/// What the server hands back for a verified Sign in with Apple (tdr/0010).
nonisolated struct RankedSession: Equatable, Sendable {
    /// Bearer token sent on ranked joins.
    let token: String
    /// The Apple user id the server verified; becomes `PlayerIdentity.id`.
    let playerID: String
}

nonisolated enum RankedAuthError: Error, Equatable {
    /// The server runs without ranked play.
    case unavailable
    /// Apple did not vouch for the token (expired, wrong app, forged).
    case rejected
    case server(status: Int)
    case badResponse
}

/// Exchanges Apple's short-lived identity token for the server's session token.
nonisolated protocol RankedAuthService: Sendable {
    func exchange(identityToken: String) async throws -> RankedSession
    /// Deletes the ranked account on the server (tdr/0034). Takes a fresh
    /// Sign in with Apple so only the owner can delete, and its authorization
    /// code so the server can revoke the app's Apple tokens.
    func deleteAccount(identityToken: String, authorizationCode: String?) async throws
}

/// `POST /auth/apple` on the game server (tdr/0010).
nonisolated struct HTTPRankedAuthService: RankedAuthService {
    let baseURL: URL
    let session: URLSession

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func exchange(identityToken: String) async throws -> RankedSession {
        let data = try await post("auth/apple", Body(identityToken: identityToken))
        guard let issued = try? JSONDecoder().decode(Reply.self, from: data) else { throw RankedAuthError.badResponse }
        return RankedSession(token: issued.token, playerID: issued.playerID)
    }

    /// `POST /account/delete` (tdr/0034).
    func deleteAccount(identityToken: String, authorizationCode: String?) async throws {
        _ = try await post("account/delete", DeletionBody(identityToken: identityToken, authorizationCode: authorizationCode))
    }

    private func post(_ path: String, _ body: some Encodable) async throws -> Data {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw RankedAuthError.badResponse }
        switch http.statusCode {
        case 200..<300:
            return data
        case 401:
            throw RankedAuthError.rejected
        case 503:
            throw RankedAuthError.unavailable
        default:
            throw RankedAuthError.server(status: http.statusCode)
        }
    }

    private struct Body: Encodable {
        let identityToken: String
    }

    private struct DeletionBody: Encodable {
        let identityToken: String
        let authorizationCode: String?
    }

    private struct Reply: Decodable {
        let token: String
        let playerID: String
    }
}
