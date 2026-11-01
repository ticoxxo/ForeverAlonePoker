import SwiftUI

/// Everyone this player blocked, with Unblock (tdr/0029).
struct BlockedPlayersView: View {
    @Environment(BlockList.self) private var blockList

    var body: some View {
        List {
            if blockList.players.isEmpty {
                ContentUnavailableView(
                    "No blocked players",
                    systemImage: "person.crop.circle.badge.checkmark",
                    description: Text("Block a player from their seat at the table. You won't see their name, picture or reactions.")
                )
            } else {
                ForEach(blockList.players, id: \.playerID) { player in
                    HStack {
                        Text(player.displayName)
                        Spacer()
                        Button("Unblock") {
                            blockList.unblock(playerID: player.playerID)
                        }
                        .buttonStyle(.borderless)
                        .frame(minHeight: Theme.Target.minimum)
                    }
                }
            }
        }
        .navigationTitle("Blocked players")
    }
}
