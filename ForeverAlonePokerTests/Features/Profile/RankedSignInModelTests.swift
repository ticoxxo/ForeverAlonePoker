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

private final class RecordingPublisher: PublicProfilePublishing, @unchecked Sendable {
    private(set) var published: [PublicProfileSnapshot] = []

    func publish(_ snapshot: PublicProfileSnapshot) async throws {
        published.append(snapshot)
    }
}

@MainActor
private struct Fixture {
    let container: ModelContainer
    let identity: IdentityStore
    let publisher = RecordingPublisher()

    init() throws {
        container = try Persistence.inMemoryContainer()
        identity = try IdentityStore(context: container.mainContext, defaultCountryCode: "MX")
    }

    func model(_ result: Result<RankedSession, RankedAuthError>) -> RankedSignInModel {
        RankedSignInModel(identity: identity, auth: FakeAuth(result: result), publisher: publisher)
    }
}

@Suite("RankedSignInModel")
@MainActor
struct RankedSignInModelTests {
    @Test("a successful exchange links the account and publishes the public profile")
    func success() async throws {
        let fixture = try Fixture()
        let model = fixture.model(.success(RankedSession(token: "session-1", playerID: "001234.abc")))
        await model.signIn(identityToken: "apple-jwt")

        #expect(model.phase == .idle)
        #expect(fixture.identity.tier == .ranked)
        #expect(fixture.identity.identity.id == "001234.abc")
        #expect(fixture.identity.rankedSessionToken == "session-1")
        #expect(fixture.publisher.published == [PublicProfileSnapshot(playerID: "001234.abc", displayName: "Player", countryCode: "MX", avatar: nil)])
    }

    @Test("a rejected exchange explains itself and leaves the player unranked")
    func rejected() async throws {
        let fixture = try Fixture()
        let model = fixture.model(.failure(.rejected))
        await model.signIn(identityToken: "apple-jwt")

        #expect(model.phase == .failed("The server could not verify your Apple sign-in. Try again."))
        #expect(fixture.identity.tier == .local)
        #expect(fixture.publisher.published.isEmpty)

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

    @Test("signing out drops the ranked identity and nothing is published while unranked")
    func signOut() async throws {
        let fixture = try Fixture()
        let model = fixture.model(.success(RankedSession(token: "session-1", playerID: "001234.abc")))
        await model.signIn(identityToken: "apple-jwt")
        model.signOut()
        #expect(fixture.identity.tier == .local)
        await model.publishProfile()
        #expect(fixture.publisher.published.count == 1)
    }
}
