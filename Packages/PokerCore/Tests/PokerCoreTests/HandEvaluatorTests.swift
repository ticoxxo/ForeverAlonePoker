import Testing
import PokerCore
import PokerCoreTestSupport

@Suite("HandEvaluator")
struct HandEvaluatorTests {
    private func evaluate(_ notation: String) -> HandRank {
        HandEvaluator.evaluate(cards(notation))
    }

    @Test("recognises every category", arguments: [
        ("As Kd 9h 5c 2s", HandCategory.highCard, [Rank.ace, .king, .nine, .five, .two]),
        ("As Ad 9h 5c 2s", .onePair, [.ace, .nine, .five, .two]),
        ("As Ad 9h 9c 2s", .twoPair, [.ace, .nine, .two]),
        ("As Ad Ah 9c 2s", .threeOfAKind, [.ace, .nine, .two]),
        ("9s 8d 7h 6c 5s", .straight, [.nine]),
        ("As Ks 9s 5s 2s", .flush, [.ace, .king, .nine, .five, .two]),
        ("As Ad Ah 9c 9s", .fullHouse, [.ace, .nine]),
        ("As Ad Ah Ac 9s", .fourOfAKind, [.ace, .nine]),
        ("9s 8s 7s 6s 5s", .straightFlush, [.nine]),
    ])
    func categories(notation: String, category: HandCategory, tiebreakers: [Rank]) {
        let rank = evaluate(notation)
        #expect(rank.category == category)
        #expect(rank.tiebreakers == tiebreakers)
    }

    @Test("the wheel is a five-high straight and loses to a six-high straight")
    func wheel() {
        let wheel = evaluate("As 2d 3h 4c 5s")
        #expect(wheel.category == .straight)
        #expect(wheel.tiebreakers == [.five])
        #expect(wheel.bestFive.last == card("As"), "ace plays low so it is listed last")
        #expect(wheel < evaluate("2s 3d 4h 5c 6s"))
    }

    @Test("ace-high straight beats king-high straight")
    func broadway() {
        #expect(evaluate("As Kd Qh Jc Ts") > evaluate("Ks Qd Jh Tc 9s"))
    }

    @Test("categories outrank each other regardless of card ranks")
    func categoryOrdering() {
        #expect(evaluate("2s 2d 2h 3c 3s") > evaluate("As Ks Qs Js 9s"), "full house beats flush")
        #expect(evaluate("2s 3s 4s 5s 7s") < evaluate("As Ad Ah Kc Ks"), "flush does not beat full house")
        #expect(evaluate("2s 3d 4h 5c 6s") > evaluate("As Ad Ah Kc Qs"), "straight beats trips")
        #expect(evaluate("2s 2d 3h 3c 4s") > evaluate("As Ad Kh Qc Js"), "two pair beats one pair")
    }

    @Test("kickers decide between hands of the same category")
    func kickers() {
        #expect(evaluate("As Ad Kh 5c 2s") > evaluate("As Ad Qh 5c 2s"))
        #expect(evaluate("Ks Kd 9h 9c As") > evaluate("Ks Kd 9h 9c Qs"))
        #expect(evaluate("As Kd 9h 5c 3s") > evaluate("As Kd 9h 5c 2s"))
    }

    @Test("identical ranks with different suits are an exact chop")
    func chop() {
        let hearts = evaluate("Ah Kh 9h 5h 2h")
        let spades = evaluate("As Ks 9s 5s 2s")
        #expect(hearts == spades)
        #expect(!(hearts < spades))
        #expect(!(spades < hearts))
    }

    @Test("picks the best five from seven cards")
    func sevenCards() {
        // Two pair on board, pocket pair makes a full house: 9s 9d 9h Kc Ks.
        let fullHouse = evaluate("9s 9d Kc Ks 9h 4d 2c")
        #expect(fullHouse.category == .fullHouse)
        #expect(fullHouse.tiebreakers == [.nine, .king])

        // Board offers a straight that beats the flush draw that missed.
        let straight = evaluate("Ah Kh 7c 8d 9s Ts Jc")
        #expect(straight.category == .straight)
        #expect(straight.tiebreakers == [.jack])

        // Ignores the two lowest cards for a high-card hand.
        let high = evaluate("As Kd 9h 5c 2s 3d 4c")
        #expect(high.category == .straight, "A 2 3 4 5 is on the board: the wheel is found")
    }

    @Test("seven cards with a flush and a higher straight choose the flush")
    func flushBeatsStraightInSeven() {
        let rank = evaluate("2h 5h 9h Jh Kh Qc Td")
        #expect(rank.category == .flush)
        #expect(rank.bestFive.allSatisfy { $0.suit == .hearts })
    }

    @Test("best five lists the significant cards first")
    func bestFiveOrdering() {
        let rank = evaluate("2s Ad 9h Ac 9s")
        #expect(rank.bestFive.map(\.rank) == [.ace, .ace, .nine, .nine, .two])
    }
}
