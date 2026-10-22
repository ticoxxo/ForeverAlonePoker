import CoreGraphics
import Foundation
import Testing
@testable import ForeverAlonePoker

@Suite("TableArrangement")
struct TableArrangementTests {
    @Test("an iPhone held upright stacks the table vertically")
    func phonePortrait() {
        #expect(TableArrangement.make(size: CGSize(width: 393, height: 852)) == .portrait)
    }

    @Test("an iPhone on its side puts the actions beside the table")
    func phoneLandscape() {
        #expect(TableArrangement.make(size: CGSize(width: 852, height: 393)) == .landscape)
    }

    @Test("an iPad uses the spacious table in either orientation")
    func iPad() {
        #expect(TableArrangement.make(size: CGSize(width: 1024, height: 1366)) == .spacious)
        #expect(TableArrangement.make(size: CGSize(width: 1366, height: 1024)) == .spacious)
    }

    @Test("an unfolded foldable's near-square screen uses the spacious table")
    func unfoldedFoldable() {
        #expect(TableArrangement.make(size: CGSize(width: 1000, height: 800)) == .spacious)
        #expect(TableArrangement.make(size: CGSize(width: 800, height: 1000)) == .spacious)
    }

    @Test("a narrow iPad split-view column behaves like a phone")
    func narrowColumn() {
        #expect(TableArrangement.make(size: CGSize(width: 320, height: 1024)) == .portrait)
        #expect(TableArrangement.make(size: CGSize(width: 590, height: 1024)) == .portrait)
    }

    @Test("a small near-square window stays portrait")
    func smallSquare() {
        #expect(TableArrangement.make(size: CGSize(width: 500, height: 480)) == .portrait)
    }

    @Test("a foldable half open on its side, fold running top to bottom, is a book")
    func halfOpenWideIsBook() {
        #expect(TableArrangement.isBookPosture(isHingePartiallyOpen: true, size: CGSize(width: 1000, height: 780)))
    }

    @Test("a foldable half open upright, fold running side to side, keeps its layout")
    func halfOpenTallIsNotBook() {
        #expect(!TableArrangement.isBookPosture(isHingePartiallyOpen: true, size: CGSize(width: 780, height: 1000)))
    }

    @Test("a foldable opened flat is not a book")
    func fullyOpenIsNotBook() {
        #expect(!TableArrangement.isBookPosture(isHingePartiallyOpen: false, size: CGSize(width: 1000, height: 780)))
    }

    @Test("the book posture gets the book arrangement whatever the size")
    func bookArrangement() {
        #expect(TableArrangement.make(size: CGSize(width: 1000, height: 780), isBookPosture: true) == .book)
        #expect(TableArrangement.make(size: CGSize(width: 1000, height: 780), isBookPosture: false) == .spacious)
    }

    @Test("a book sizes its cards for one half and stacks every seat")
    func bookCardsFitHalf() {
        let size = CGSize(width: 1000, height: 780)
        let cards = TableArrangement.book.cardHeights(in: size)
        #expect(cards.mine <= size.width / 2)
        #expect(cards.board <= size.height * TableArrangement.book.maxBoardShare)
        #expect(!TableArrangement.book.seatsInline)
        #expect(!TableArrangement.book.mySeatInline)
    }

    @Test("an empty size falls back to portrait")
    func emptySize() {
        #expect(TableArrangement.make(size: .zero) == .portrait)
    }

    @Test("cards grow with the screen and keep their proportions")
    func cardHeights() {
        let phone = TableArrangement.portrait.cardHeights(in: CGSize(width: 393, height: 852))
        let pad = TableArrangement.spacious.cardHeights(in: CGSize(width: 1024, height: 1366))
        #expect(pad.board > phone.board)
        #expect(phone.mine > phone.board)
        #expect(phone.board > phone.opponent)
        #expect(phone.opponent > phone.compact)
    }

    @Test("card heights stay within readable bounds")
    func cardHeightClamps() {
        let tiny = TableArrangement.landscape.cardHeights(in: CGSize(width: 300, height: 100))
        let huge = TableArrangement.spacious.cardHeights(in: CGSize(width: 4000, height: 4000))
        #expect(tiny.board == TableArrangement.CardHeights.boardRange.lowerBound)
        #expect(huge.board == TableArrangement.CardHeights.boardRange.upperBound)
    }

    @Test("cards grow with a larger text size")
    func cardsFollowDynamicType() {
        let size = CGSize(width: 852, height: 320)
        let regular = TableArrangement.landscape.cardHeights(in: size)
        let larger = TableArrangement.landscape.cardHeights(in: size, textScale: 1.3)
        #expect(larger.board > regular.board)
    }

    @Test("a smaller text size never shrinks the cards")
    func smallTextKeepsCards() {
        let size = CGSize(width: 393, height: 700)
        let regular = TableArrangement.portrait.cardHeights(in: size)
        let small = TableArrangement.portrait.cardHeights(in: size, textScale: 0.8)
        #expect(small.board == regular.board)
    }

    @Test("text scaling never makes the cards taller than the window can hold")
    func textScaleIsCappedByHeight() {
        let size = CGSize(width: 852, height: 320)
        let huge = TableArrangement.landscape.cardHeights(in: size, textScale: 3)
        #expect(huge.board <= size.height * TableArrangement.landscape.maxBoardShare)
    }

    @Test("a phone on its side gives the board a readable share of its height")
    func landscapeBoardIsReadable() {
        let size = CGSize(width: 852, height: 320)
        let cards = TableArrangement.landscape.cardHeights(in: size)
        #expect(cards.board >= size.height * 0.17)
    }

    @Test("the opponents area takes a share of the height, never a fixed size")
    func opponentsHeight() {
        let short = TableArrangement.landscape.opponentsHeight(in: CGSize(width: 852, height: 393))
        let tall = TableArrangement.portrait.opponentsHeight(in: CGSize(width: 393, height: 852))
        #expect(short < tall)
        #expect(short > 0 && short < 393 / 2)
        #expect(tall < 852 / 2)
    }

    @Test("only the landscape table docks the actions at the side")
    func actionDock() {
        #expect(TableArrangement.landscape.docksActionsAtSide)
        #expect(!TableArrangement.portrait.docksActionsAtSide)
        #expect(!TableArrangement.spacious.docksActionsAtSide)
    }
}
