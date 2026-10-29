import Testing
import SkinKit

@Suite("Chip stacks")
struct ChipStackTests {
    @Test("an amount breaks into stacks of its largest chips, biggest first")
    func breakdown() {
        let stacks = ChipStack.stacks(for: 1_490)
        #expect(stacks == [
            ChipStack(denomination: .init(1_000), count: 1),
            ChipStack(denomination: .init(250), count: 1),
            ChipStack(denomination: .init(100), count: 2),
        ])
    }

    @Test("an amount never shows more than three stacks")
    func atMostThreeStacks() {
        #expect(ChipStack.stacks(for: 1_960).count == 3)
    }

    @Test("a stack never holds more than five chips")
    func cappedHeight() {
        #expect(ChipStack.stacks(for: 1_000_000) == [ChipStack(denomination: .init(100_000), count: 5)])
    }

    @Test("a small amount shows one chip of the smallest denomination")
    func smallAmount() {
        #expect(ChipStack.stacks(for: 5) == [ChipStack(denomination: .init(10), count: 1)])
        #expect(ChipStack.stacks(for: 0) == [ChipStack(denomination: .init(10), count: 1)])
    }
}
