import Foundation
import SwiftData
import Testing
import PokerCore
@testable import ForeverAlonePoker

private struct FakeAuth: RankedAuthService {
    var result: Result<RankedSession, RankedAuthError>
    var deletion: Result<Void, RankedAuthError> = .success(())

    func exchange(identityToken: String) async throws -> RankedSession {
        try result.get()
    }

    func deleteAccount(identityToken: String, authorizationCode: String?) async throws {
        try deletion.get()
    }
}

private struct UnreachableAuth: RankedAuthService {
    func exchange(identityToken: String) async throws -> RankedSession {
        throw URLError(.cannotConnectToHost)
    }

    func deleteAccount(identityToken: String, authorizationCode: String?) async throws {
        throw URLError(.cannotConnectToHost)
    }
}

@MainActor
private struct Fixture {
    let container: ModelContainer
    let identity: IdentityStore

    init() throws {
        container = try Persistence.inMemoryContainer()
        identity = try IdentityStore(context: container.mainContext, defaultCountryCode: "MX")
    }

    func model(_ result: Result<RankedSession, RankedAuthError>) -> RankedSignInModel {
        RankedSignInModel(identity: identity, auth: FakeAuth(result: result))
    }

    /// A model whose player is already signed in, deleting with `deletion`.
    func signedIn(deleting deletion: Result<Void, RankedAuthError>) async -> RankedSignInModel {
        let auth = FakeAuth(result: .success(RankedSession(token: "session-1", playerID: "001234.abc")), deletion: deletion)
        let model = RankedSignInModel(identity: identity, auth: auth)
        await model.signIn(identityToken: "apple-jwt")
        return model
    }
}

@Suite("RankedSignInModel")
@MainActor
struct RankedSignInModelTests {
    @Test("a successful exchange links the account")
    func success() async throws {
        let fixture = try Fixture()
        let model = fixture.model(.success(RankedSession(token: "session-1", playerID: "001234.abc")))
        await model.signIn(identityToken: "apple-jwt")

        #expect(model.phase == .idle)
        #expect(fixture.identity.tier == .ranked)
        #expect(fixture.identity.identity(avatarID: nil).id == "001234.abc")
        #expect(fixture.identity.rankedSessionToken == "session-1")
    }

    @Test("a rejected exchange explains itself and leaves the player unranked")
    func rejected() async throws {
        let fixture = try Fixture()
        let model = fixture.model(.failure(.rejected))
        await model.signIn(identityToken: "apple-jwt")

        #expect(model.phase == .failed("The server could not verify your Apple sign-in. Try again."))
        #expect(fixture.identity.tier == .local)

        model.dismissFailure()
        #expect(model.phase == .idle)
    }

    @Test("a server without ranked play says so")
    func unavailable() async throws {
        let fixture = try Fixture()
        let model = fixture.model(.failure(.unavailable))
        await model.signIn(identityToken: "apple-jwt")
        #expect(model.phase == .failed("This server does not offer ranked play."))
    }

    @Test("an unreachable server does not mention an address release builds cannot edit")
    func unreachable() async throws {
        let fixture = try Fixture()
        let model = RankedSignInModel(identity: fixture.identity, auth: UnreachableAuth())
        await model.signIn(identityToken: "apple-jwt")
        #expect(model.phase == .failed("Could not reach the server. Check your connection and try again."))
    }

    @Test("signing out drops the ranked identity")
    func signOut() async throws {
        let fixture = try Fixture()
        let model = fixture.model(.success(RankedSession(token: "session-1", playerID: "001234.abc")))
        await model.signIn(identityToken: "apple-jwt")
        model.signOut()
        #expect(fixture.identity.tier == .local)
        #expect(fixture.identity.rankedSessionToken == nil)
    }

    @Test("deleting the account on the server drops the ranked identity")
    func deleteAccount() async throws {
        let fixture = try Fixture()
        let model = await fixture.signedIn(deleting: .success(()))
        await model.deleteAccount(identityToken: "fresh-jwt", authorizationCode: "code")

        #expect(model.phase == .idle)
        #expect(fixture.identity.tier == .local)
        #expect(fixture.identity.rankedSessionToken == nil)
    }

    @Test("a server without ranked play keeps no account, so deletion still completes")
    func deleteWithoutRankedServer() async throws {
        let fixture = try Fixture()
        let model = await fixture.signedIn(deleting: .failure(.unavailable))
        await model.deleteAccount(identityToken: "fresh-jwt", authorizationCode: "code")

        #expect(model.phase == .idle)
        #expect(fixture.identity.tier == .local)
    }

    @Test("a failed deletion explains itself and keeps the player signed in")
    func deleteRejected() async throws {
        let fixture = try Fixture()
        let model = await fixture.signedIn(deleting: .failure(.rejected))
        await model.deleteAccount(identityToken: "fresh-jwt", authorizationCode: "code")

        #expect(model.phase == .failed("The server could not verify your Apple sign-in. Try again."))
        #expect(fixture.identity.tier == .ranked)
    }
}
