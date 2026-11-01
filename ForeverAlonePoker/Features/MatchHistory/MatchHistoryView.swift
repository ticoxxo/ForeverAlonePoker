import SwiftUI

/// The last few matches, with a way into the full history.
struct MatchHistoryView: View {
    @Environment(IdentityStore.self) private var identity

    var body: some View {
        Group {
            if identity.recentMatches.isEmpty {
                ContentUnavailableView(
                    "No matches yet",
                    systemImage: "clock",
                    description: Text("Finished matches show up here.")
                )
            } else {
                List {
                    Section("Recent matches") {
                        ForEach(identity.recentMatches.prefix(IdentityStore.recentMatchLimit)) { match in
                            MatchHistoryRow(match: match)
                        }
                    }
                    Section {
                        NavigationLink {
                            FullMatchHistoryView()
                        } label: {
                            Label("See full history", systemImage: "list.bullet")
                        }
                    }
                }
            }
        }
        .navigationTitle("Match history")
    }
}

/// Every match, loaded in batches while scrolling, in the order the player picks.
struct FullMatchHistoryView: View {
    @Environment(IdentityStore.self) private var identity
    @State private var model: MatchHistoryModel?

    var body: some View {
        List {
            if let model {
                ForEach(model.matches) { match in
                    MatchHistoryRow(match: match)
                        .onAppear { model.loadMoreIfNeeded(after: match) }
                }
            }
        }
        .navigationTitle("Full history")
        .toolbar {
            if let model {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Sort", selection: Binding(get: { model.order }, set: { model.order = $0 })) {
                            ForEach(MatchHistoryOrder.allCases, id: \.self) { order in
                                Text(order.displayName).tag(order)
                            }
                        }
                    } label: {
                        Label("Sort", systemImage: "arrow.up.arrow.down")
                    }
                }
            }
        }
        .onChange(of: model?.order) {
            model?.reload()
        }
        .onAppear {
            if model == nil {
                model = MatchHistoryModel(identity: identity)
            }
        }
    }
}

private struct MatchHistoryRow: View {
    let match: MatchRecord

    var body: some View {
        MatchRecordRow(
            opponentName: match.opponentName,
            didWin: match.didWin,
            mode: match.mode,
            date: match.date,
            isRanked: match.wasRanked,
            place: match.place,
            playerCount: match.playerCount
        )
    }
}

#if DEBUG
#Preview("With history") {
    NavigationStack {
        MatchHistoryView()
    }
    .previewEnvironment()
}

#Preview("New player") {
    NavigationStack {
        MatchHistoryView()
    }
    .previewEnvironment(identity: PreviewIdentity.newPlayer, skins: PreviewSkins.empty)
}

#Preview("Full history") {
    NavigationStack {
        FullMatchHistoryView()
    }
    .previewEnvironment()
}
#endif
