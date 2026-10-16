import SwiftUI
import PokerCore

/// The poker table. Works identically for local and online play because it
/// only ever talks to a `MatchSessionClient`. Heads-up the opponent sits
/// across; at a bigger table the others fan out over the top (tdr/0013).
struct TableView: View {
    let client: MatchSessionClient
    @State private var avatars = AvatarLoader()

    private var view: PlayerView? { client.view }
    private var status: TableStatus { TableStatus.make(view: view, departure: client.lastDeparture) }

    var body: some View {
        VStack(spacing: 16) {
            if let view {
                if view.table.maxPlayers > TableSize.minPlayers {
                    OpponentsRing(view: view, avatars: avatars)
                        .frame(height: 200)
                        .task(id: view.players.map(\.playerID)) {
                            await avatars.load(view.players.map(\.playerID))
                        }
                } else {
                    OpponentSeatView(
                        summary: view.opponent,
                        isOnButton: view.opponent.map { view.button == $0.seat } ?? false,
                        revealedCards: view.opponent.map { revealedCards(for: $0.seat, in: view) } ?? [],
                        showsCards: view.street != nil && view.opponent?.hasFolded == false,
                        isActing: view.actor != nil && view.actor == view.opponent?.seat
                    )
                }
            }
            Spacer(minLength: 0)
            BoardView(community: view?.community ?? [], pot: collectedPot, street: view?.street)
            StatusBanner(
                status: status,
                outcome: view.flatMap { HandOutcome(result: $0.lastResult, seat: $0.seat) },
                winnerName: winnerName,
                ratingUpdate: client.ratingUpdate,
                onReady: { Task { await client.ready() } }
            )
            if let table = view?.table, table.isRankedCapable, !table.isEloEnabled {
                Text("Elo gain disabled for this game")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
            }
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
        return view.pot - view.me.streetCommitted - view.players.reduce(0) { $0 + $1.streetCommitted }
    }

    /// Who the outcome names when this player lost.
    private var winnerName: String {
        guard let view, let seat = HandOutcome(result: view.lastResult, seat: view.seat)?.winner else { return "" }
        return view.player(at: seat)?.name ?? ""
    }
}

/// Another player's cards are only known after a showdown.
func revealedCards(for seat: Seat, in view: PlayerView) -> [Card] {
    guard view.lastResult?.reason == .showdown, view.phase != .inHand else { return [] }
    return view.lastResult?.shownHands.first { $0.seat == seat }?.holeCards ?? []
}

/// The other players of a bigger table, placed by `SeatLayout`. Their cards
/// never use our skin: until loadouts travel with the protocol (tdr/0012) we
/// know nothing about theirs, and unknown means the default.
private struct OpponentsRing: View {
    let view: PlayerView
    let avatars: AvatarLoader

    var body: some View {
        GeometryReader { geometry in
            let positions = SeatLayout.positions(count: view.players.count)
            ZStack {
                ForEach(view.players.indices, id: \.self) { index in
                    let player = view.players[index]
                    let point = positions[index]
                    CompactSeatView(
                        summary: player,
                        avatar: avatars.avatar(for: player.playerID),
                        isOnButton: view.button == player.seat && view.street != nil,
                        isActing: view.actor == player.seat,
                        revealedCards: revealedCards(for: player.seat, in: view),
                        showsCards: view.street != nil && !player.hasFolded && !player.isBusted
                    )
                    .position(x: point.x * geometry.size.width, y: point.y * geometry.size.height)
                }
            }
        }
        .environment(\.cardSkin, .standard)
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
    /// Name of the player the outcome credits when this player lost.
    var winnerName: String = ""
    /// Shown with the match result once the server has rated a ranked match.
    var ratingUpdate: RatingUpdate? = nil
    let onReady: () -> Void

    var body: some View {
        // Keyed by status so a change swaps the content in one step instead of
        // crossfading old and new text over each other.
        VStack(spacing: 8) {
            if let outcome, showsOutcome {
                OutcomeText(outcome: outcome, winnerName: winnerName)
            }
            switch status {
            case .connecting:
                ProgressView("Connecting…")
            case .waitingForOpponent:
                ProgressView("Waiting for players…")
            case .readyPrompt:
                Button("Ready for the next hand", action: onReady)
                    .buttonStyle(.borderedProminent)
            case .waitingForOthersReady:
                ProgressView("Waiting for the others…")
            case .yourTurn:
                Text("Your turn")
                    .font(.headline)
            case .othersTurn(let name):
                if name.isEmpty {
                    Text("Opponent is thinking…")
                } else {
                    Text("\(name) is thinking…")
                }
            case .spectating:
                Text("You are out. Watching the rest of the match.")
                    .font(.headline)
            case .matchOver(let youWon, let place):
                if youWon {
                    Text("You won the match!")
                        .font(.title2.bold())
                } else if let place, place > TableSize.minPlayers {
                    Text("You finished \(place.formatted(.number)).")
                        .font(.title2.bold())
                } else {
                    Text("You lost the match.")
                        .font(.title2.bold())
                }
                if let ratingUpdate {
                    Text("Rating \(ratingUpdate.rating.value, format: .number) (\(ratingUpdate.delta, format: .number.sign(strategy: .always())))")
                        .font(.subheadline)
                }
                Button("Rematch", action: onReady)
                    .buttonStyle(.borderedProminent)
            case .playerLeft(let name):
                Text("\(name) left the table.")
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
        case .readyPrompt, .waitingForOthersReady, .spectating, .matchOver: true
        default: false
        }
    }
}

private struct OutcomeText: View {
    let outcome: HandOutcome
    let winnerName: String

    var body: some View {
        switch outcome.kind {
        case .chop:
            Text("Chopped pot")
        case .youWon:
            if let category = outcome.category {
                Text("You won \(outcome.amount, format: .number) with \(category.displayName)")
            } else {
                Text("Everyone else folded. You won \(outcome.amount, format: .number)")
            }
        case .youLost:
            let name = winnerName.isEmpty ? String(localized: "Opponent") : winnerName
            if let category = outcome.category {
                Text("\(name) won \(outcome.amount, format: .number) with \(category.displayName)")
            } else {
                Text("\(name) won \(outcome.amount, format: .number)")
            }
        }
    }
}

#if DEBUG
#Preview("Live table vs auto-caller") {
    PracticeTableView()
}
#endif
