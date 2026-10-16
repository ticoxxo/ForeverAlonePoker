import SwiftUI
import PokerCore

/// The host's table-size picker (tdr/0013): enabled while setting up, locked
/// once the table is searching for opponents. Used by local and online play.
struct TableSizeSection: View {
    @Binding var maxPlayers: Int
    let isEnabled: Bool

    var body: some View {
        Section {
            Picker("Max players", selection: $maxPlayers) {
                ForEach(Array(TableSize.range), id: \.self) { count in
                    Text(count, format: .number).tag(count)
                }
            }
            .disabled(!isEnabled)
        } footer: {
            if maxPlayers == TableSize.minPlayers {
                Text("Heads-up: the match starts as soon as your opponent joins.")
            } else {
                Text("Up to \(maxPlayers) players. You start the game when you are ready.")
            }
        }
    }
}
