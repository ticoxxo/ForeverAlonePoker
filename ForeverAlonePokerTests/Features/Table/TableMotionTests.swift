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
