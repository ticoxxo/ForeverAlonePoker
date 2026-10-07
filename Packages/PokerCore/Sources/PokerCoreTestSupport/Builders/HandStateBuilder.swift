import PokerCore

/// Builds a started `HandState` with rigged cards so a test controls the exact
/// outcome. Defaults describe an unremarkable hand: equal 1500 stacks, 10/20
/// blinds, seat one on the button, and a dry board with no straight or flush.
///
/// Deal order matches `HandEngine`: seat one's hole cards, seat two's, then the
/// board. Any cards not specified are filled from the remaining deck.
public struct HandStateBuilder {
    public var handNumber = 1
    public var button: Seat = .one
    public var stacks: [Chips] = [1500, 1500]
    public var blinds = Blinds(small: 10, big: 20)
    public var holeCards: [Seat: [Card]] = [
        .one: cards("Ah Kh"),
        .two: cards("Qs Qd"),
    ]
    public var board: [Card] = cards("2c 7d Ts 4h 9s")

    public init() {}

    public func handNumber(_ value: Int) -> Self { with { $0.handNumber = value } }
    public func button(_ seat: Seat) -> Self { with { $0.button = seat } }
    public func stacks(_ one: Chips, _ two: Chips) -> Self { with { $0.stacks = [one, two] } }
    public func blinds(small: Chips, big: Chips) -> Self { with { $0.blinds = Blinds(small: small, big: big) } }
    public func holeCards(_ seat: Seat, _ notation: String) -> Self { with { $0.holeCards[seat] = cards(notation) } }
    /// Flop, turn and river in order, e.g. `"2c 7d Ts 4h 9s"`.
    public func board(_ notation: String) -> Self { with { $0.board = cards(notation) } }

    /// The deck the engine will deal from.
    public func deck() -> Deck {
        Deck.rigged(holeCards[.one]! + holeCards[.two]! + board)
    }

    /// Starts the hand. Blinds are posted and hole cards dealt.
    public func start() throws -> HandState {
        try startWithEvents().state
    }

    public func startWithEvents() throws -> (state: HandState, events: [GameEvent]) {
        try HandEngine.start(handNumber: handNumber, button: button, stacks: stacks, blinds: blinds, deck: deck())
    }

    private func with(_ mutate: (inout Self) -> Void) -> Self {
        var copy = self
        mutate(&copy)
        return copy
    }
}

public extension HandEngine {
    /// Applies a scripted sequence of actions, returning the final state and
    /// every event emitted along the way.
    static func play(
        _ state: HandState,
        _ script: [(Seat, PlayerAction)]
    ) throws -> (state: HandState, events: [GameEvent]) {
        var state = state
        var events: [GameEvent] = []
        for (seat, action) in script {
            let step = try apply(action, by: seat, to: state)
            state = step.state
            events += step.events
        }
        return (state, events)
    }
}
