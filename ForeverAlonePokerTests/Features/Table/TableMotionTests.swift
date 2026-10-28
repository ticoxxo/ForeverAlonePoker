import CoreGraphics
import Foundation
import Testing
import PokerCore
import PokerCoreTestSupport
@testable import ForeverAlonePoker

@Suite("DealTiming")
struct DealTimingTests {
    @Test("the flop lands one card after another")
    func flopStaggers() {
        let delays = (0..<3).map { DealTiming.delay(index: $0, previousCount: 0) }
        #expect(delays == [0, DealTiming.step, 2 * DealTiming.step])
    }

    @Test("the turn and the river land at once")
    func singleCard() {
        #expect(DealTiming.delay(index: 3, previousCount: 3) == 0)
        #expect(DealTiming.delay(index: 4, previousCount: 4) == 0)
    }

    @Test("cards already on the table never wait")
    func existingCards() {
        #expect(DealTiming.delay(index: 1, previousCount: 3) == 0)
    }

    @Test("Reduce Motion deals everything at once")
    func reduceMotion() {
        #expect(DealTiming.delay(index: 2, previousCount: 0, reduceMotion: true) == 0)
    }
}

@Suite("TableSounds actions")
struct TableSoundsActionTests {
    @Test("All in pushes the whole stack")
    func allIn() {
        #expect(TableSounds.effect(for: .allIn) == .allInChips)
    }

    @Test("Check, Bet and Raise place chips")
    func chips() {
        #expect(TableSounds.effect(for: .check) == .placingPokerChips)
        #expect(TableSounds.effect(for: .bet(20)) == .placingPokerChips)
        #expect(TableSounds.effect(for: .raise(to: 40)) == .placingPokerChips)
    }

    /// A fold is heard from the table update instead, so everyone's folds
    /// sound alike and the player's own never plays twice.
    @Test("the Fold and Call buttons play nothing themselves")
    func silent() {
        #expect(TableSounds.effect(for: .fold) == nil)
        #expect(TableSounds.effect(for: .call) == nil)
    }
}

@Suite("TableSounds table changes")
struct TableSoundsUpdateTests {
    private func act(_ seat: Seat, _ action: PlayerAction, in room: inout MatchRoom) {
        let connection = seat == .one ? TestPlayers.aliceConnection : TestPlayers.bobConnection
        _ = room.handle(.act(action), from: connection)
    }

    /// Heads-up, dealt; Alice is on the button and acts first.
    private func dealtRoom() -> MatchRoom {
        var room = MatchRoomBuilder().build()
        room.seatAliceAndBobAndDeal()
        return room
    }

    @Test("the first deal of a match shuffles")
    func firstDeal() {
        var room = MatchRoomBuilder().build()
        _ = room.handle(.join(TestPlayers.alice), from: TestPlayers.aliceConnection)
        let lobby = room.view(for: .one)
        _ = room.handle(.join(TestPlayers.bob), from: TestPlayers.bobConnection)
        #expect(TableSounds.effects(from: lobby, to: room.view(for: .one)) == [.shufflingCards])
    }

    @Test("a rematch shuffles")
    func rematch() {
        var room = dealtRoom()
        act(.one, .allIn, in: &room)
        act(.two, .call, in: &room)
        let finished = room.view(for: .one)
        _ = room.handle(.ready, from: TestPlayers.aliceConnection)
        _ = room.handle(.ready, from: TestPlayers.bobConnection)
        #expect(TableSounds.effects(from: finished, to: room.view(for: .one)) == [.shufflingCards])
    }

    @Test("the flop is dealt")
    func flop() {
        var room = dealtRoom()
        act(.one, .call, in: &room)
        let preflop = room.view(for: .one)
        act(.two, .check, in: &room)
        #expect(TableSounds.effects(from: preflop, to: room.view(for: .one)) == [.cardsBeingDealt])
    }

    @Test("the turn places a new card")
    func turn() {
        var room = dealtRoom()
        act(.one, .call, in: &room)
        act(.two, .check, in: &room)
        act(.two, .check, in: &room)
        let flop = room.view(for: .one)
        act(.one, .check, in: &room)
        #expect(TableSounds.effects(from: flop, to: room.view(for: .one)) == [.placingNewCard])
    }

    @Test("opening a table mid-hand is silent")
    func rejoin() {
        var room = dealtRoom()
        act(.one, .call, in: &room)
        act(.two, .check, in: &room)
        #expect(TableSounds.effects(from: nil, to: room.view(for: .one)).isEmpty)
    }

    @Test("both sides hear a fold; only the winner collects the pot")
    func handWon() {
        var room = dealtRoom()
        let before = (room.view(for: .one), room.view(for: .two))
        act(.one, .fold, in: &room)
        #expect(TableSounds.effects(from: before.1, to: room.view(for: .two)) == [.foldHand, .winningPot])
        #expect(TableSounds.effects(from: before.0, to: room.view(for: .one)) == [.foldHand])
    }

    @Test("a fold that leaves the hand going is heard by everyone")
    func foldMidHand() throws {
        var room = MatchRoomBuilder().maxPlayers(3).build()
        _ = room.seatThreeAndDeal()
        let actor = try #require(room.view(for: .one).actor)
        let connections: [Seat: ConnectionID] = [
            .one: TestPlayers.aliceConnection, .two: TestPlayers.bobConnection, .three: TestPlayers.carolConnection,
        ]
        let before = Seat.all(count: 3).map { room.view(for: $0) }
        _ = room.handle(.act(.fold), from: try #require(connections[actor]))
        for view in before {
            #expect(TableSounds.effects(from: view, to: room.view(for: view.seat)) == [.foldHand])
        }
    }

    @Test("the match's last hand plays only the match result")
    func matchOver() {
        // Default deck: Bob's queens beat Alice's ace-king on a dry board.
        var room = dealtRoom()
        act(.one, .allIn, in: &room)
        let before = (room.view(for: .one), room.view(for: .two))
        act(.two, .call, in: &room)
        let alice = TableSounds.effects(from: before.0, to: room.view(for: .one))
        let bob = TableSounds.effects(from: before.1, to: room.view(for: .two))
        #expect(alice.last == .lostSound && !alice.contains(.winningPot))
        #expect(bob.last == .winSound && !bob.contains(.winningPot))
    }
}

@Suite("TableArrangement action dock")
struct ActionDockTests {
    private let phoneLandscape = CGSize(width: 852, height: 393)

    @Test("the docked rail takes about a quarter of a phone on its side")
    func regularText() {
        let width = TableArrangement.landscape.actionDockWidth(in: phoneLandscape, isAccessibilitySize: false)
        #expect(width >= 200 && width <= 280)
    }

    @Test("accessibility text sizes get a wider panel so labels still fit")
    func largeText() {
        let regular = TableArrangement.landscape.actionDockWidth(in: phoneLandscape, isAccessibilitySize: false)
        let large = TableArrangement.landscape.actionDockWidth(in: phoneLandscape, isAccessibilitySize: true)
        #expect(large > regular)
        #expect(large < phoneLandscape.width / 2, "the table keeps at least half the width")
    }

    @Test("accessibility text sizes stack the action buttons")
    func stackedButtons() {
        #expect(TableArrangement.portrait.stacksActionButtons(isAccessibilitySize: true))
        #expect(!TableArrangement.portrait.stacksActionButtons(isAccessibilitySize: false))
        #expect(TableArrangement.landscape.stacksActionButtons(isAccessibilitySize: false), "docked at the side")
    }
}

@Suite("Card spoken names")
struct CardSpokenNameTests {
    @Test("VoiceOver reads a card in words, not notation")
    func words() {
        #expect(card("As").spokenName == "Ace of spades")
        #expect(card("Td").spokenName == "10 of diamonds")
        #expect(card("Qh").spokenName == "Queen of hearts")
        #expect(card("2c").spokenName == "2 of clubs")
    }

    @Test("a row of cards is read as a list")
    func list() {
        #expect(cards("As Kd").spokenList == "Ace of spades, King of diamonds")
        #expect([Card]().spokenList == "")
    }
}
