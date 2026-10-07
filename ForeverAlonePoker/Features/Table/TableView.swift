import SwiftUI
import PokerCore

/// The poker table. Works identically for local and online play because it
/// only ever talks to a `MatchSessionClient`.
struct TableView: View {
    let client: MatchSessionClient

    private var view: PlayerView? { client.view }
    private var status: TableStatus { TableStatus.make(view: view, opponentLeft: client.opponentLeft) }

    var body: some View {
        VStack(spacing: 16) {
            if let view {
                OpponentSeatView(
                    summary: view.opponent,
                    isOnButton: view.button == view.seat.opponent,
                    revealedCards: revealedOpponentCards,
                    showsCards: view.street != nil && view.opponent?.hasFolded == false
                )
            }
            Spacer(minLength: 0)
            BoardView(community: view?.community ?? [], pot: collectedPot, street: view?.street)
            StatusBanner(
                status: status,
                outcome: view.flatMap { HandOutcome(result: $0.lastResult, seat: $0.seat) },
                onReady: { Task { await client.ready() } }
            )
            Spacer(minLength: 0)
            MySeatView(
                summary: view?.me,
                isOnButton: view?.isOnButton ?? false,
                holeCards: view?.holeCards ?? []
            )
            if let rejection = client.lastRejection {
                Text(rejection)
                    .font(.footnote)
                    .foregroundStyle(.yellow)
            }
            ActionBar(model: TableActionModel(legalActions: client.legalActions)) { action in
                Task { await client.act(action) }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TableFelt())
    }

    /// Chips already in the middle. Bets on the current street are shown in
    /// front of each seat instead, so they are not counted twice.
    private var collectedPot: Chips {
        guard let view else { return 0 }
        return view.pot - view.me.streetCommitted - (view.opponent?.streetCommitted ?? 0)
    }

    /// Opponent cards are only known after a showdown.
    private var revealedOpponentCards: [Card] {
        guard let view, view.lastResult?.reason == .showdown, view.phase != .inHand else { return [] }
        return view.lastResult?.shownHands.first { $0.seat == view.seat.opponent }?.holeCards ?? []
    }
}

struct TableFelt: View {
    var body: some View {
        RadialGradient(
            colors: [Color(red: 0.16, green: 0.5, blue: 0.3), Color(red: 0.05, green: 0.25, blue: 0.15)],
            center: .center,
            startRadius: 40,
            endRadius: 600
        )
        .ignoresSafeArea()
    }
}

/// Tells the player what is happening and offers the Ready button between hands.
struct StatusBanner: View {
    let status: TableStatus
    let outcome: HandOutcome?
    let onReady: () -> Void

    var body: some View {
        // Keyed by status so a change swaps the content in one step instead of
        // crossfading old and new text over each other.
        VStack(spacing: 8) {
            if let outcome, showsOutcome {
                OutcomeText(outcome: outcome)
            }
            switch status {
            case .connecting:
                ProgressView("Connecting…")
            case .waitingForOpponent:
                ProgressView("Waiting for an opponent…")
            case .readyPrompt:
                Button("Ready for the next hand", action: onReady)
                    .buttonStyle(.borderedProminent)
            case .waitingForOpponentReady:
                ProgressView("Waiting for your opponent…")
            case .yourTurn:
                Text("Your turn")
                    .font(.headline)
            case .opponentsTurn:
                Text("Opponent is thinking…")
            case .matchOver(let youWon):
                Text(youWon ? "You won the match!" : "You lost the match.")
                    .font(.title2.bold())
                Button("Rematch", action: onReady)
                    .buttonStyle(.borderedProminent)
            case .opponentLeft:
                Text("Your opponent left the table.")
                    .font(.headline)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
        .id(status)
    }

    private var showsOutcome: Bool {
        switch status {
        case .readyPrompt, .waitingForOpponentReady, .matchOver: true
        default: false
        }
    }
}

private struct OutcomeText: View {
    let outcome: HandOutcome

    var body: some View {
        switch outcome.kind {
        case .chop:
            Text("Chopped pot")
        case .youWon:
            if let category = outcome.category {
                Text("You won \(outcome.amount, format: .number) with \(category.displayName)")
            } else {
                Text("Opponent folded. You won \(outcome.amount, format: .number)")
            }
        case .youLost:
            if let category = outcome.category {
                Text("Opponent won \(outcome.amount, format: .number) with \(category.displayName)")
            } else {
                Text("You folded. Opponent won \(outcome.amount, format: .number)")
            }
        }
    }
}

#if DEBUG
#Preview("Live table vs auto-caller") {
    PracticeTableView()
}
#endif
