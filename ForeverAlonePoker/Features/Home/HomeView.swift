import SwiftUI

/// Landing screen: who you are, how to play, and what you played recently.
struct HomeView: View {
    @Environment(IdentityStore.self) private var identity

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        ProfileView()
                    } label: {
                        PlayerCard(
                            name: identity.profile.displayName,
                            countryCode: identity.profile.countryCode,
                            avatar: identity.profile.avatar,
                            wins: identity.wins,
                            losses: identity.losses
                        )
                    }
                }

                Section("Play") {
                    NavigationLink {
                        LocalMatchView(identity: identity.identity, onMatchFinished: { identity.record($0, mode: .local) })
                    } label: {
                        Label("Local match", systemImage: "wifi")
                    }
                    NavigationLink {
                        OnlineMatchView(
                            identity: identity.identity,
                            service: HTTPRoomService(baseURL: identity.serverURL),
                            sessionToken: identity.rankedSessionToken,
                            onMatchFinished: { identity.record($0, mode: .online) },
                            onRated: { _ in identity.markLatestOnlineMatchRanked() }
                        )
                    } label: {
                        Label("Online match", systemImage: "globe")
                    }
                    #if DEBUG
                    NavigationLink {
                        PracticeTableView(onMatchFinished: { identity.record($0, mode: .practice) })
                            .navigationBarTitleDisplayMode(.inline)
                    } label: {
                        Label("Practice table (debug)", systemImage: "hammer")
                    }
                    #endif
                }

                Section("Customize") {
                    NavigationLink {
                        SkinStoreView()
                    } label: {
                        Label("Card store", systemImage: "suit.spade")
                    }
                }

                Section("Rankings") {
                    NavigationLink {
                        LeaderboardView(service: CloudKitLeaderboardService())
                    } label: {
                        Label("Leaderboard", systemImage: "trophy")
                    }
                }

                if !identity.recentMatches.isEmpty {
                    Section("Recent matches") {
                        ForEach(identity.recentMatches.prefix(5)) { match in
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
                }
            }
            .navigationTitle("ForeverAlonePoker")
        }
    }
}

struct PlayerCard: View {
    let name: String
    let countryCode: String
    let avatar: Data?
    let wins: Int
    let losses: Int

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(data: avatar, size: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.headline)
                HStack(spacing: 4) {
                    if !countryCode.isEmpty {
                        Text(CountryFlag.emoji(for: countryCode))
                        Text(CountryFlag.name(for: countryCode))
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                Text("^[\(wins) win](inflect: true) · ^[\(losses) loss](inflect: true)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct MatchRecordRow: View {
    let opponentName: String
    let didWin: Bool
    let mode: MatchMode
    let date: Date
    var isRanked: Bool = false
    var place: Int = 0
    var playerCount: Int = 2

    var body: some View {
        HStack {
            Image(systemName: didWin ? "trophy.fill" : "xmark.circle")
                .foregroundStyle(didWin ? .yellow : .secondary)
            VStack(alignment: .leading) {
                if didWin {
                    Text("Won against \(opponentName)")
                } else if playerCount > 2, place > 0 {
                    Text("Finished \(place.formatted(.number)) of \(playerCount.formatted(.number)) against \(opponentName)")
                } else {
                    Text("Lost to \(opponentName)")
                }
                Text("\(mode.displayName)\(isRanked ? " · Ranked" : "") · \(date, format: .dateTime.day().month().hour().minute())")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
