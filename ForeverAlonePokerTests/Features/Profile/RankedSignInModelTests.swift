import Foundation
import SwiftData
import Testing
import PokerCore
@testable import ForeverAlonePoker

private struct FakeAuth: RankedAuthService {
    var result: Result<RankedSession, RankedAuthError>

    func exchange(identityToken: String) async throws -> RankedSession {
        try result.get()
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

    @Test("signing out drops the ranked identity")
    func signOut() async throws {
        let fixture = try Fixture()
        let model = fixture.model(.success(RankedSession(token: "session-1", playerID: "001234.abc")))
        await model.signIn(identityToken: "apple-jwt")
        model.signOut()
        #expect(fixture.identity.tier == .local)
        #expect(fixture.identity.rankedSessionToken == nil)
    }
}
