import SwiftUI

/// Landing screen (tdr/0018): who you are, large tiles for the ways to play,
/// and what you played recently. Tiles flow in an adaptive grid, so a folded
/// phone shows one column and an open foldable or an iPad two or three,
/// decided by the width alone. Everything stays in one navigation stack so
/// folding or unfolding mid-match never rebuilds the table.
struct HomeView: View {
    @Environment(IdentityStore.self) private var identity
    @ScaledMetric(relativeTo: .body) private var tileMinimumWidth = Theme.Width.tile

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xLarge) {
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
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Theme.Spacing.large)
                        .surfaceGlass(in: RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous), isInteractive: true)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(Text("Edit your name, country and picture"))

                    HomeSection(title: "Play") {
                        tiles {
                            NavigationLink {
                                LocalMatchView(identity: identity.identity, onMatchFinished: { identity.record($0, mode: .local) })
                            } label: {
                                HomeTile(
                                    title: "Play nearby",
                                    subtitle: "With people in the same room, over Wi-Fi or Bluetooth",
                                    systemImage: "person.2.wave.2.fill",
                                    tint: .green
                                )
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
                                HomeTile(
                                    title: "Play online",
                                    subtitle: "Share a room code with friends anywhere",
                                    systemImage: "globe",
                                    tint: .blue
                                )
                            }
                            #if DEBUG
                            NavigationLink {
                                PracticeTableView(onMatchFinished: { identity.record($0, mode: .practice) })
                                    .navigationTitle("Practice")
                                    .navigationBarTitleDisplayMode(.inline)
                            } label: {
                                HomeTile(
                                    title: "Practice table",
                                    subtitle: "Debug builds only: against a bot that always calls",
                                    systemImage: "hammer.fill",
                                    tint: .gray
                                )
                            }
                            #endif
                        }
                    }

                    HomeSection(title: "More") {
                        tiles {
                            NavigationLink {
                                SkinStoreView()
                            } label: {
                                HomeTile(
                                    title: "Card store",
                                    subtitle: "New card faces and backs",
                                    systemImage: "suit.spade.fill",
                                    tint: .purple
                                )
                            }
                            NavigationLink {
                                LeaderboardView(service: CloudKitLeaderboardService())
                            } label: {
                                HomeTile(
                                    title: "Leaderboard",
                                    subtitle: "Ranked players worldwide and in your country",
                                    systemImage: "trophy.fill",
                                    tint: .orange
                                )
                            }
                        }
                    }

                    if !identity.recentMatches.isEmpty {
                        HomeSection(title: "Recent matches") {
                            VStack(spacing: 0) {
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
                                    .padding(.vertical, Theme.Spacing.small)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    if match.id != identity.recentMatches.prefix(5).last?.id {
                                        Divider()
                                    }
                                }
                            }
                            .padding(.horizontal, Theme.Spacing.large)
                            .padding(.vertical, Theme.Spacing.small)
                            .surfaceGlass(in: RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
                        }
                    }
                }
                .padding(Theme.Spacing.large)
                // Readable on a wide window instead of stretched edge to edge.
                .frame(maxWidth: Theme.Width.readable)
                .frame(maxWidth: .infinity)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("ForeverAlonePoker")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    AudioToggleButton()
                }
                // The account lives in the navigation bar, where iOS apps
                // put it, and stays one tap away from every tile.
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        ProfileView()
                    } label: {
                        AvatarView(data: identity.profile.avatar, size: 32, name: identity.profile.displayName)
                    }
                    .accessibilityLabel(Text("Profile"))
                }
            }
        }
    }

    /// Tiles in as many columns as fit, each at least `tileMinimumWidth`
    /// (which grows with the text size).
    private func tiles(@ViewBuilder content: () -> some View) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: min(tileMinimumWidth, 600)), spacing: Theme.Spacing.medium)],
            spacing: Theme.Spacing.medium
        ) {
            content()
        }
        .buttonStyle(.plain)
    }
}

/// A titled group of the home screen.
private struct HomeSection<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            Text(title)
                .font(.title3.bold())
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }
}

/// One large, easy target: a coloured symbol, a title and a plain-words line
/// about what it does.
private struct HomeTile: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let systemImage: String
    let tint: Color

    @ScaledMetric(relativeTo: .title2) private var iconSize: CGFloat = 52

    var body: some View {
        HStack(spacing: Theme.Spacing.medium) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: iconSize, height: iconSize)
                .background(tint.gradient, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.forward")
                .font(.footnote.bold())
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(Theme.Spacing.large)
        .frame(maxWidth: .infinity, minHeight: Theme.Target.primary + Theme.Spacing.xLarge, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
        .surfaceGlass(in: RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous), isInteractive: true)
        .accessibilityElement(children: .combine)
    }
}

struct PlayerCard: View {
    let name: String
    let countryCode: String
    let avatar: Data?
    let wins: Int
    let losses: Int

    @ScaledMetric(relativeTo: .headline) private var avatarSize: CGFloat = 56

    var body: some View {
        HStack(spacing: Theme.Spacing.medium) {
            AvatarView(data: avatar, size: min(avatarSize, 96))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.headline)
                if !countryCode.isEmpty {
                    HStack(spacing: Theme.Spacing.xSmall) {
                        Text(CountryFlag.emoji(for: countryCode))
                            .accessibilityHidden(true)
                        Text(CountryFlag.name(for: countryCode))
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                Text("^[\(wins) win](inflect: true) · ^[\(losses) loss](inflect: true)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, Theme.Spacing.xSmall)
        .accessibilityElement(children: .combine)
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
        HStack(spacing: Theme.Spacing.medium) {
            Image(systemName: didWin ? "trophy.fill" : "xmark.circle")
                .foregroundStyle(didWin ? .yellow : .secondary)
                .accessibilityHidden(true)
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
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview("With history") {
    HomeView()
        .previewEnvironment()
}

#Preview("New player") {
    HomeView()
        .previewEnvironment(identity: PreviewIdentity.newPlayer, skins: PreviewSkins.empty)
}

#Preview("Landscape", traits: .landscapeLeft) {
    HomeView()
        .previewEnvironment()
}

#Preview("Large text") {
    HomeView()
        .previewEnvironment()
        .dynamicTypeSize(.accessibility2)
}
#endif

