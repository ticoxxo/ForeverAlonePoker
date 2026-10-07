import Foundation
import Testing
import PokerCore
import PokerCoreTestSupport

@Suite("MatchState")
struct MatchStateTests {
    @Test("a new match has full stacks and is waiting for the first hand")
    func initialState() {
        let match = MatchStateBuilder().startingStack(2000).button(.two).build()
        #expect(match.stacks == [2000, 2000])
        #expect(match.button == .two)
        #expect(match.phase == .waitingForHand)
        #expect(match.handsPlayed == 0)
        #expect(match.nextHandNumber == 1)
        #expect(match.currentHand == nil)
    }

    @Test("stacks carry over and the button alternates between hands")
    func stacksCarryOverAndButtonRotates() throws {
        var match = MatchStateBuilder().build()
        _ = try match.startHand(deck: HandStateBuilder().deck())
        #expect(match.phase == .inHand)
        #expect(match.currentHand?.handNumber == 1)
        #expect(match.currentHand?.button == .one)

        _ = try match.apply(.fold, by: .one)
        #expect(match.phase == .waitingForHand)
        #expect(match.stacks == [1490, 1510])
        #expect(match.button == .two)
        #expect(match.handsPlayed == 1)
        #expect(match.lastResult?.reason == .fold(by: .one))

        _ = try match.startHand(deck: HandStateBuilder().deck())
        #expect(match.currentHand?.handNumber == 2)
        #expect(match.currentHand?.button == .two)
        #expect(match.currentHand?[.two].stack == 1500, "seat two posts the small blind from its 1510")
        #expect(match.currentHand?[.one].stack == 1470)
    }

    @Test("acting without a hand or starting during a hand is rejected")
    func phaseGuards() throws {
        var match = MatchStateBuilder().build()
        #expect(throws: MatchError.noHandInProgress) {
            try match.apply(.check, by: .one)
        }
        _ = try match.startHand(deck: HandStateBuilder().deck())
        #expect(throws: MatchError.handInProgress) {
            try match.startHand(deck: HandStateBuilder().deck())
        }
    }

    @Test("busting ends the match and a rematch resets it")
    func bustAndRematch() throws {
        var match = MatchStateBuilder().build()
        _ = try match.startHand(deck: HandStateBuilder().holeCards(.one, "Ah Kh").holeCards(.two, "Qs Qd").board("Ac 7d Ts 4h 9s").deck())
        _ = try match.apply(.allIn, by: .one)
        _ = try match.apply(.call, by: .two)

        #expect(match.phase == .finished(winner: .one))
        #expect(match.stacks == [3000, 0])
        #expect(throws: MatchError.matchFinished) {
            try match.startHand(deck: HandStateBuilder().deck())
        }

        try match.rematch()
        #expect(match.phase == .waitingForHand)
        #expect(match.stacks == [1500, 1500])
        #expect(match.handsPlayed == 0)
        #expect(match.button == .one, "button moved twice: once after the hand, once for the rematch")
    }

    @Test("rematch is only allowed once the match is finished")
    func rematchGuard() {
        var match = MatchStateBuilder().build()
        #expect(throws: MatchError.matchNotFinished) {
            try match.rematch()
        }
    }

    @Test("forfeiting ends the hand in the opponent's favour regardless of turn")
    func forfeit() throws {
        var match = MatchStateBuilder().build()
        _ = try match.startHand(deck: HandStateBuilder().deck())
        #expect(match.currentHand?.actor == .one)
        let events = try match.forfeit(.two)
        #expect(match.phase == .waitingForHand)
        #expect(match.stacks == [1520, 1480], "seat one collects the 30 in blinds")
        #expect(events.contains(.acted(seat: .two, action: .fold, chips: 0)))
    }

    @Test("match state round-trips through Codable")
    func codable() throws {
        var match = MatchStateBuilder().build()
        _ = try match.startHand(deck: HandStateBuilder().deck())
        let data = try JSONEncoder().encode(match)
        #expect(try JSONDecoder().decode(MatchState.self, from: data) == match)
    }
}
