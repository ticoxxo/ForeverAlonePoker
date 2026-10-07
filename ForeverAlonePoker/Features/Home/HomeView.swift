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
                            onMatchFinished: { identity.record($0, mode: .online) }
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

                if !identity.recentMatches.isEmpty {
                    Section("Recent matches") {
                        ForEach(identity.recentMatches.prefix(5)) { match in
                            MatchRecordRow(
                                opponentName: match.opponentName,
                                didWin: match.didWin,
                                mode: match.mode,
                                date: match.date
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

struct AvatarView: View {
    let data: Data?
    let size: CGFloat

    var body: some View {
        Group {
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityLabel(Text("Profile picture"))
    }
}

struct MatchRecordRow: View {
    let opponentName: String
    let didWin: Bool
    let mode: MatchMode
    let date: Date

    var body: some View {
        HStack {
            Image(systemName: didWin ? "trophy.fill" : "xmark.circle")
                .foregroundStyle(didWin ? .yellow : .secondary)
            VStack(alignment: .leading) {
                Text(didWin ? "Won against \(opponentName)" : "Lost to \(opponentName)")
                Text("\(mode.displayName) · \(date, format: .dateTime.day().month().hour().minute())")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
