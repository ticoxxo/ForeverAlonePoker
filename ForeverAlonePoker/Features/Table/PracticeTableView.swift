#if DEBUG
import SwiftUI

/// Development scaffold: the real `TableView` against the auto-calling
/// opponent, all in one process. Lets the table be used and UI-tested without
/// a second device.
struct PracticeTableView: View {
    @State private var session = PracticeSession()
    var onMatchFinished: (MatchSummary) -> Void = { _ in }

    var body: some View {
        ZStack {
            if let player = session.player {
                TableView(client: player)
                    .onAppear { player.onMatchFinished = onMatchFinished }
            } else {
                TableFelt()
                ProgressView()
            }
        }
        .task {
            await session.start()
        }
    }
}
#endif
