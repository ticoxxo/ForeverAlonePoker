import PokerCore
import SwiftUI

/// Top 100 of the world or the player's country, with the player's own row
/// pinned when they are further down (tdr/0006, tdr/0010).
struct LeaderboardView: View {
    @Environment(IdentityStore.self) private var identity
    @State private var model: LeaderboardModel

    init(service: any LeaderboardService) {
        _model = State(wrappedValue: LeaderboardModel(service: service))
    }

    private var myPlayerID: String? { identity.profile.appleUserID }
    private var countryCode: String { identity.profile.countryCode }

    var body: some View {
        List {
            Section {
                Picker("Scope", selection: $model.scope) {
                    Text("World").tag(LeaderboardScope.world)
                    if !countryCode.isEmpty {
                        Text("\(CountryFlag.emoji(for: countryCode)) \(CountryFlag.name(for: countryCode))")
                            .tag(LeaderboardScope.country(countryCode))
                    }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .accessibilityLabel(Text("Rankings for"))
            }

            switch model.phase {
            case .loading:
                Section {
                    WorkingRow(text: "Loading rankings…")
                }
            case .failed(let reason):
                Section {
                    Label(reason, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                    PrimaryActionButton(title: "Try again", systemImage: "arrow.clockwise") {
                        Task { await model.load(myPlayerID: myPlayerID) }
                    }
                }
            case .loaded:
                if model.rows.isEmpty {
                    Section {
                        Text("No ranked matches yet. Be the first!")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        ForEach(model.rows) { row in
                            LeaderboardRowView(
                                row: row,
                                rank: model.rank(of: row),
                                avatar: model.avatars[row.playerID],
                                isMe: row.playerID == myPlayerID
                            )
                        }
                    }
                }
                if let own = model.ownEntry {
                    Section("You") {
                        LeaderboardRowView(row: own, rank: nil, avatar: model.avatars[own.playerID], isMe: true)
                    }
                }
                if myPlayerID == nil {
                    Section {
                        Text("Sign in with Apple from your profile to play ranked matches and appear here.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Leaderboard")
        .task(id: model.scope) {
            await model.load(myPlayerID: myPlayerID)
        }
        .refreshable {
            await model.load(myPlayerID: myPlayerID)
        }
    }
}

struct LeaderboardRowView: View {
    let row: LeaderboardRow
    let rank: Int?
    let avatar: Data?
    let isMe: Bool

    @ScaledMetric(relativeTo: .subheadline) private var rankWidth: CGFloat = 40
    @ScaledMetric(relativeTo: .body) private var avatarSize: CGFloat = 36

    var body: some View {
        HStack(spacing: Theme.Spacing.medium) {
            Text(rank.map { "#\($0)" } ?? "—")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: rankWidth, alignment: .leading)
            AvatarView(data: avatar, size: min(avatarSize, 64))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if !row.countryCode.isEmpty {
                        Text(CountryFlag.emoji(for: row.countryCode))
                    }
                    Text(row.displayName)
                        .font(isMe ? .headline : .body)
                }
                Text("^[\(row.wins) win](inflect: true) · ^[\(row.losses) loss](inflect: true)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(row.rating.value, format: .number)
                .font(.title3.monospacedDigit().bold())
        }
        // One phrase per row: "Rank 3, Ana, Mexico, rating 1,520, 12 wins, 4 losses".
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .listRowBackground(isMe ? Color.accentColor.opacity(0.12) : nil)
    }

    private var accessibilityLabel: Text {
        var parts: [String] = []
        if let rank { parts.append(String(localized: "Rank \(rank)")) }
        parts.append(isMe ? String(localized: "\(row.displayName), you") : row.displayName)
        if !row.countryCode.isEmpty { parts.append(CountryFlag.name(for: row.countryCode)) }
        parts.append(String(localized: "rating \(row.rating.value.formatted())"))
        parts.append(String(localized: "^[\(row.wins) win](inflect: true), ^[\(row.losses) loss](inflect: true)"))
        return Text(parts.joined(separator: ", "))
    }
}
