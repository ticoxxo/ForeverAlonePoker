import Testing
import PokerCore
import PokerCoreTestSupport
@testable import ForeverAlonePoker

/// Smoke test proving the app and its test bundle link the CORE package and
/// its shared builders. Feature tests live next to their feature.
struct AppLinksPokerCoreTests {
    @Test("the app target can use PokerCore and the shared builders")
    func linksCore() throws {
        let state = try HandStateBuilder().start()
        #expect(state.pot == 30)
        #expect(state.actor == .one)
    }
}
