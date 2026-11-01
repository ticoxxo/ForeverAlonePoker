import Foundation
import Observation

/// Drives the Sign in with Apple exchange (tdr/0010): Apple's identity token
/// goes to the server and the returned session is stored on the profile.
/// Nothing is published: the server writes the leaderboard (tdr/0029).
@Observable
final class RankedSignInModel {
    enum Phase: Equatable {
        case idle
        case working
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private let identity: IdentityStore
    private let auth: any RankedAuthService

    init(identity: IdentityStore, auth: any RankedAuthService) {
        self.identity = identity
        self.auth = auth
    }

    func signIn(identityToken: String) async {
        phase = .working
        do {
            let session = try await auth.exchange(identityToken: identityToken)
            identity.linkAppleAccount(userID: session.playerID, sessionToken: session.token)
            phase = .idle
        } catch {
            phase = .failed(Self.describe(error))
        }
    }

    func signOut() {
        identity.unlinkAppleAccount()
        phase = .idle
    }

    /// The sign-in sheet failed before we got a token (not a user cancel).
    func reportSignInFailure() {
        phase = .failed(String(localized: "Sign in with Apple did not complete. Try again."))
    }

    func dismissFailure() {
        if case .failed = phase { phase = .idle }
    }

    private static func describe(_ error: Error) -> String {
        switch error {
        case RankedAuthError.unavailable: String(localized: "This server does not offer ranked play.")
        case RankedAuthError.rejected: String(localized: "The server could not verify your Apple sign-in. Try again.")
        case RankedAuthError.server(let status): String(localized: "The server answered with an error (\(status)).")
        case RankedAuthError.badResponse: String(localized: "Unexpected reply from the server.")
        default: String(localized: "Could not reach the server. Check the server address below.")
        }
    }
}
