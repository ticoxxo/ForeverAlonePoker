import SwiftUI
import PokerCore

/// Who is at a table that has not started yet (tdr/0013): every seated
/// player with their picture (initials when there is none), the host marked,
/// and how many seats are left. Used by the local and online lobbies.
struct LobbyPlayersSection: View {
    let view: PlayerView
    @ScaledMetric(relativeTo: .body) private var avatarSize: CGFloat = 36
    @Environment(BlockList.self) private var blockList: BlockList?
    private var blocked: Set<String> { blockList?.blockedIDs ?? [] }

    private var seated: [PlayerSummary] {
        ([view.me] + view.players).sorted { $0.seat < $1.seat }
    }

    var body: some View {
        Section {
            ForEach(seated, id: \.seat) { player in
                HStack(spacing: Theme.Spacing.medium) {
                    AvatarView(avatarID: player.shownAvatarID(hiding: blocked), size: min(avatarSize, 64), name: player.shownName(hiding: blocked))
                        .accessibilityHidden(true)
                    Text(player.shownName(hiding: blocked))
                    if player.seat == view.seat {
                        Text("(you)")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if player.seat == view.table.host {
                        Label("Host", systemImage: "crown.fill")
                            .labelStyle(.iconOnly)
                            .foregroundStyle(.yellow)
                            .accessibilityLabel(Text("Host"))
                    }
                    if !player.isConnected {
                        Image(systemName: "wifi.slash")
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(Text("Disconnected"))
                    }
                }
                // "Ana, you, host, disconnected" as one row.
                .accessibilityElement(children: .combine)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        } header: {
            Text("Players \(seated.count) of \(view.table.maxPlayers)")
        } footer: {
            if view.table.isRankedCapable && !view.table.isEloEnabled {
                Label("Elo gain disabled for this game", systemImage: "chart.line.downtrend.xyaxis")
                    .foregroundStyle(.orange)
            }
        }
        .motion(Theme.Motion.layout, value: seated.map(\.seat))
    }
}
