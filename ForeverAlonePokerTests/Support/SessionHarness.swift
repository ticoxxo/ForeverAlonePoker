import PokerCore
import PokerCoreTestSupport
@testable import ForeverAlonePoker

/// Two session clients sharing one in-process table. The default room deals
/// the `HandStateBuilder` default hand (seat one Ah Kh, seat two Qs Qd).
///
/// The test target has no default actor isolation, so anything touching the
/// main-actor `MatchSessionClient` is marked `@MainActor` explicitly.
@MainActor
struct SessionHarness {
    let table: HostedTable
    let alice: MatchSessionClient
    let bob: MatchSessionClient

    init(room: MatchRoom = MatchRoomBuilder().build()) async {
        table = HostedTable(room: room)
        alice = MatchSessionClient(identity: TestPlayers.alice, transport: await table.connect(id: TestPlayers.aliceConnection))
        bob = MatchSessionClient(identity: TestPlayers.bob, transport: await table.connect(id: TestPlayers.bobConnection))
    }

    /// Connects both players and waits until both are seated.
    @discardableResult
    func connectBoth() async -> Bool {
        await alice.connect()
        await bob.connect()
        return await eventually { alice.view?.opponent != nil && bob.view?.opponent != nil }
    }

    /// Connects, readies both players and waits for the first hand to be dealt.
    @discardableResult
    func deal() async -> Bool {
        guard await connectBoth() else { return false }
        await alice.ready()
        await bob.ready()
        return await eventually { alice.view?.phase == .inHand && bob.view?.phase == .inHand }
    }
}
