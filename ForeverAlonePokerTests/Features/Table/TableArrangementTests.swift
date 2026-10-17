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
