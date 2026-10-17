import SwiftUI
import PokerCore

/// The poker table. Works identically for local and online play because it
/// only ever talks to a `MatchSessionClient`. Heads-up the opponent sits
/// across; at a bigger table the others fan out over the top (tdr/0013), and
/// players out of the hand wait in a column at the side (tdr/0016).
struct TableView: View {
    let client: MatchSessionClient
    /// The emote tray (tdr/0015); off where nobody would see the reactions.
    var showsEmotes = true
    /// Offered when the connection is gone for good.
    var onLeave: (() -> Void)? = nil
    @State private var avatars = AvatarLoader()
    @Namespace private var dealerButton
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var view: PlayerView? { client.view }
    private var status: TableStatus { TableStatus.make(view: view, departure: client.lastDeparture) }

    var body: some View {
        GeometryReader { geometry in
            let arrangement = TableArrangement.make(size: geometry.size)
            ZStack {
                table(arrangement, size: geometry.size)
                    .blur(radius: client.isConnectionLost ? 10 : 0)
                    .allowsHitTesting(!client.isConnectionLost)
                    .accessibilityHidden(client.isConnectionLost)
                if client.isConnectionLost {
                    ConnectionLostCard(connection: client.connection, onLeave: onLeave)
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.25), value: client.isConnectionLost)
            // Rotating, resizing a split view or folding and unfolding a
            // foldable glides into the new arrangement instead of jumping.
            .motion(Theme.Motion.layout, value: arrangement)
        }
        .background(TableFelt())
        .environment(\.dealerButtonNamespace, dealerButton)
        // The dealer button moves on at each new hand.
        .motion(Theme.Motion.layout, value: view?.button)
        .onChange(of: status) { _, newStatus in
            announce(newStatus)
        }
    }

    /// Portrait and spacious stack the actions under the table; landscape
    /// docks them at the side so the short height only holds the table.
    /// One `AnyLayout` for both keeps the table and the action panel the
    /// same views when the arrangement changes, so folding the phone or
    /// rotating it mid-hand keeps a half-chosen raise amount (tdr/0018).
    private func table(_ arrangement: TableArrangement, size: CGSize) -> some View {
        let cards = arrangement.cardHeights(in: size)
        let docked = arrangement.docksActionsAtSide
        let isAccessibilitySize = dynamicTypeSize.isAccessibilitySize
        let layout = docked
            ? AnyLayout(HStackLayout(spacing: Theme.Spacing.large))
            : AnyLayout(VStackLayout(spacing: Theme.Spacing.large))
        return layout {
            tableArea(arrangement, size: size, cards: cards)
            actions(axis: docked ? .vertical : .horizontal, stacksButtons: arrangement.stacksActionButtons(isAccessibilitySize: isAccessibilitySize))
                .frame(width: docked ? arrangement.actionDockWidth(in: size, isAccessibilitySize: isAccessibilitySize) : nil)
                .frame(maxWidth: arrangement == .spacious ? TableArrangement.actionPanelMaxWidth : .infinity)
        }
        .padding(docked ? Theme.Spacing.medium : Theme.Spacing.large)
    }

    /// VoiceOver hears whose turn it is without hunting for the banner.
    private func announce(_ status: TableStatus) {
        let message: String? = switch status {
        case .yourTurn: String(localized: "Your turn")
        case .matchOver(let youWon, _): youWon ? String(localized: "You won the match") : String(localized: "Match over")
        default: nil
        }
        guard let message else { return }
        var announcement = AttributedString(message)
        announcement.accessibilitySpeechAnnouncementPriority = .high
        AccessibilityNotification.Announcement(announcement).post()
    }

    private func tableArea(_ arrangement: TableArrangement, size: CGSize, cards: TableArrangement.CardHeights) -> some View {
        VStack(spacing: arrangement == .landscape ? Theme.Spacing.small : Theme.Spacing.large) {
            if let view {
                if view.table.maxPlayers > TableSize.minPlayers {
                    let seating = TableSeating(view: view)
                    OpponentsRing(
                        view: view,
                        players: seating.active,
                        avatars: avatars,
                        reactions: client.reactions,
                        cardHeight: cards.compact
                    )
                    .frame(height: arrangement.opponentsHeight(in: size))
                    .task(id: view.players.map(\.playerID)) {
                        await avatars.load(view.players.map(\.playerID))
                    }
                    Spacer(minLength: 0)
                        .frame(maxWidth: .infinity)
                        .overlay(alignment: .trailing) {
                            WaitingZone(players: seating.waiting, avatars: avatars, reactions: client.reactions)
                        }
                } else {
                    OpponentSeatView(
                        summary: view.opponent,
                        isOnButton: view.opponent.map { view.button == $0.seat } ?? false,
                        revealedCards: view.opponent.map { revealedCards(for: $0.seat, in: view) } ?? [],
                        showsCards: view.street != nil && view.opponent?.hasFolded == false,
                        isActing: view.actor != nil && view.actor == view.opponent?.seat,
                        avatar: view.opponent.flatMap { avatars.avatar(for: $0.playerID) },
                        reaction: view.opponent.flatMap { client.reactions[$0.seat] },
                        cardHeight: cards.opponent
                    )
                    .task(id: view.opponent?.playerID) {
                        if let id = view.opponent?.playerID { await avatars.load([id]) }
                    }
                    Spacer(minLength: 0)
                }
            } else {
                Spacer(minLength: 0)
            }
            BoardView(community: view?.community ?? [], pot: collectedPot, street: view?.street, cardHeight: cards.board)
                .accessibilitySortPriority(2)
            StatusBanner(
                status: status,
                outcome: view.flatMap { HandOutcome(result: $0.lastResult, seat: $0.seat) },
                winnerName: winnerName,
                ratingUpdate: client.ratingUpdate,
                onReady: { Task { await client.ready() } }
            )
            // VoiceOver starts with what is happening, then my cards, then
            // the board; the other seats and the actions follow.
            .accessibilitySortPriority(4)
            if let table = view?.table, table.isRankedCapable, !table.isEloEnabled {
                Label("Elo gain disabled for this game", systemImage: "chart.line.downtrend.xyaxis")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.85))
            }
            Spacer(minLength: 0)
            MySeatView(
                summary: view?.me,
                isOnButton: view?.isOnButton ?? false,
                holeCards: view?.holeCards ?? [],
                reaction: view.flatMap { client.reactions[$0.seat] },
                cardHeight: cards.mine
            )
            .accessibilityElement(children: .contain)
            .accessibilitySortPriority(3)
            if let rejection = client.lastRejection {
                Label(rejection, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.yellow)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // A container so the sort priorities above order its children.
        .accessibilityElement(children: .contain)
    }

    /// The action panel and, beside or under it, the emote tray.
    private func actions(axis: Axis, stacksButtons: Bool) -> some View {
        let layout = axis == .vertical
            ? AnyLayout(VStackLayout(spacing: Theme.Spacing.medium))
            : AnyLayout(HStackLayout(alignment: .bottom, spacing: Theme.Spacing.medium))
        return layout {
            ActionBar(model: TableActionModel(legalActions: client.legalActions), axis: axis, stacksButtons: stacksButtons) { action in
                Task { await client.act(action) }
            }
            if showsEmotes, view != nil {
                EmotePicker(isEnabled: client.canEmote) { emote in
                    Task { await client.emote(emote) }
                }
            }
        }
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
    /// The players still in the hand (`TableSeating.active`), clockwise.
    let players: [PlayerSummary]
    let avatars: AvatarLoader
    let reactions: [Seat: MatchSessionClient.Reaction]
    let cardHeight: CGFloat

    var body: some View {
        GeometryReader { geometry in
            let positions = SeatLayout.positions(count: players.count)
            ZStack {
                ForEach(Array(players.enumerated()), id: \.element.seat) { index, player in
                    let point = positions[index]
                    CompactSeatView(
                        summary: player,
                        avatar: avatars.avatar(for: player.playerID),
                        isOnButton: view.button == player.seat && view.street != nil,
                        isActing: view.actor == player.seat,
                        revealedCards: revealedCards(for: player.seat, in: view),
                        showsCards: view.street != nil && !player.hasFolded && !player.isBusted,
                        reaction: reactions[player.seat],
                        cardHeight: cardHeight
                    )
                    .position(x: point.x * geometry.size.width, y: point.y * geometry.size.height)
                    .transition(.opacity)
                }
            }
            .motion(.spring(duration: 0.4), value: players.map(\.seat))
        }
        .environment(\.cardSkin, .standard)
    }
}

/// Players out of the current hand (folded, or knocked out) at a bigger
/// table, in a slim column at the side until the next hand (tdr/0016):
/// pictures only, still able to emote.
private struct WaitingZone: View {
    let players: [PlayerSummary]
    let avatars: AvatarLoader
    let reactions: [Seat: MatchSessionClient.Reaction]

    @ScaledMetric(relativeTo: .caption) private var avatarSize: CGFloat = 30

    var body: some View {
        ZStack {
            if !players.isEmpty {
                VStack(spacing: Theme.Spacing.medium) {
                    ForEach(players, id: \.seat) { player in
                        PlayerAvatar(
                            data: avatars.avatar(for: player.playerID),
                            size: min(avatarSize, 44),
                            name: player.name,
                            isReconnecting: player.isReconnecting
                        )
                        .opacity(player.isBusted ? 0.5 : 0.85)
                        .emoteBubble(reactions[player.seat], size: .small)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(player.isBusted ? Text("\(player.name), out") : Text("\(player.name), folded"))
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .padding(.vertical, Theme.Spacing.medium)
                .padding(.horizontal, 7)
                .tableGlass(in: Capsule(), tint: .black.opacity(0.15))
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .motion(.spring(duration: 0.4), value: players.map(\.seat))
    }
}

/// Covers the blurred table while this device's own connection is down: a
/// spinner while reconnecting, then the reason and a way out (tdr/0016).
private struct ConnectionLostCard: View {
    let connection: MatchSessionClient.ConnectionState
    let onLeave: (() -> Void)?

    var body: some View {
        VStack(spacing: 14) {
            switch connection {
            case .disconnected(let reason):
                Image(systemName: "wifi.exclamationmark")
                    .font(.largeTitle)
                    .foregroundStyle(.orange)
                Text("Connection lost")
                    .font(.headline)
                if let reason {
                    Text(reason)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                if let onLeave {
                    Button("Leave", action: onLeave)
                        .glassButtonStyle(.prominent)
                        .controlSize(.large)
                }
            default:
                Text("Unstable connection")
                    .font(.headline)
                ProgressView()
                    .controlSize(.large)
                    .tint(.orange)
                Text("Check your connection.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(.white)
        .padding(Theme.Spacing.xLarge)
        .frame(maxWidth: Theme.Width.card)
        .tablePanel()
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isModal)
    }
}

/// Tells the player what is happening and offers the Rematch button once a
/// match is over.
struct StatusBanner: View {
    let status: TableStatus
    let outcome: HandOutcome?
    /// Name of the player the outcome credits when this player lost.
    var winnerName: String = ""
    /// Shown with the match result once the server has rated a ranked match.
    var ratingUpdate: RatingUpdate? = nil
    let onReady: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Keyed by status so a change swaps the content in one step instead of
        // crossfading old and new text over each other.
        VStack(spacing: Theme.Spacing.small) {
            if let outcome, showsOutcome {
                OutcomeText(outcome: outcome, winnerName: winnerName)
            }
            switch status {
            case .connecting:
                ProgressView("Connecting…")
            case .waitingForOpponent:
                ProgressView("Waiting for players…")
            case .nextHandSoon:
                ProgressView("Next hand…")
            case .yourTurn:
                Label("Your turn", systemImage: "hand.point.down.fill")
                    .font(.title3.bold())
                    .foregroundStyle(Theme.Palette.highlight)
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
                    .glassButtonStyle(.prominent)
                    .controlSize(.large)
            case .playerLeft(let name):
                Text("\(name) left the table.")
                    .font(.headline)
            }
        }
        .font(.body)
        .foregroundStyle(.white)
        .multilineTextAlignment(.center)
        .padding(.horizontal, Theme.Spacing.large)
        .padding(.vertical, Theme.Spacing.medium)
        .tablePanel(cornerRadius: Theme.Radius.control)
        .id(status)
        .transition(reduceMotion ? .opacity : AnyTransition(.blurReplace))
        .motion(Theme.Motion.reveal, value: status)
        // A tap of success when the player takes a pot or the match.
        .sensoryFeedback(.success, trigger: celebrates) { _, celebrates in celebrates }
    }

    /// The player just won something worth a little fanfare.
    private var celebrates: Bool {
        if case .matchOver(youWon: true, _) = status { return true }
        return showsOutcome && outcome?.kind == .youWon
    }

    private var showsOutcome: Bool {
        switch status {
        case .nextHandSoon, .spectating, .matchOver: true
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
            Label {
                if let category = outcome.category {
                    Text("You won \(outcome.amount, format: .number) with \(category.displayName)")
                } else {
                    Text("Everyone else folded. You won \(outcome.amount, format: .number)")
                }
            } icon: {
                Image(systemName: "trophy.fill")
                    .foregroundStyle(Theme.Palette.highlight)
                    .symbolEffect(.bounce, options: .nonRepeating, value: outcome.amount)
            }
            .font(.headline)
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
