import SwiftUI
import PokerCore

extension EnvironmentValues {
    /// Shared by every seat so the dealer button glides from one seat to the
    /// next between hands instead of blinking (tdr/0018).
    @Entry var dealerButtonNamespace: Namespace.ID? = nil
}

/// The opponent's seat: name, stack, bet in front, and their cards (face
/// down until a showdown reveals them).
struct OpponentSeatView: View {
    let summary: PlayerSummary?
    let isOnButton: Bool
    let revealedCards: [Card]
    let showsCards: Bool
    var isActing: Bool = false
    var avatar: Data? = nil
    var reaction: MatchSessionClient.Reaction? = nil
    var cardHeight: CGFloat = 56
    /// Picture, name plate and cards in one row (`TableArrangement.seatsInline`)
    /// instead of stacked, for windows short on height.
    var isInline: Bool = false

    @ScaledMetric(relativeTo: .headline) private var avatarSize: CGFloat = 48

    var body: some View {
        if let summary {
            if isInline {
                VStack(spacing: Theme.Spacing.xSmall) {
                    HStack(spacing: Theme.Spacing.small) {
                        avatarView(summary, size: min(avatarSize * 0.75, 56))
                        header(summary)
                        cards(summary)
                    }
                    BetView(amount: summary.streetCommitted)
                }
            } else {
                VStack(spacing: Theme.Spacing.small) {
                    avatarView(summary, size: min(avatarSize, 72))
                    header(summary)
                    cards(summary)
                    BetView(amount: summary.streetCommitted)
                }
            }
        } else {
            Label("Waiting for an opponent…", systemImage: "person.badge.clock")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.85))
        }
    }

    private func avatarView(_ summary: PlayerSummary, size: CGFloat) -> some View {
        PlayerAvatar(data: avatar, size: size, name: summary.name, isReconnecting: summary.isReconnecting)
            .emoteBubble(reaction)
    }

    private func header(_ summary: PlayerSummary) -> some View {
        SeatHeaderView(
            name: summary.name,
            stack: summary.stack,
            isOnButton: isOnButton,
            isAllIn: summary.isAllIn,
            hasFolded: summary.hasFolded,
            isBusted: summary.isBusted,
            isActing: isActing
        )
    }

    private func cards(_ summary: PlayerSummary) -> some View {
        HiddenOrRevealedCards(
            showsCards: showsCards,
            revealedCards: revealedCards,
            height: cardHeight,
            spacing: 6,
            ownerName: summary.name
        )
    }
}

/// The player's own seat: cards face up, stack and current bet.
struct MySeatView: View {
    let summary: PlayerSummary?
    let isOnButton: Bool
    let holeCards: [Card]
    var reaction: MatchSessionClient.Reaction? = nil
    var cardHeight: CGFloat = 88
    /// Cards beside the name plate (`TableArrangement.mySeatInline`).
    var isInline: Bool = false

    var body: some View {
        let layout = isInline
            ? AnyLayout(HStackLayout(spacing: Theme.Spacing.medium))
            : AnyLayout(VStackLayout(spacing: Theme.Spacing.small))
        layout {
            if !isInline {
                BetView(amount: summary?.streetCommitted ?? 0)
            }
            if !holeCards.isEmpty {
                CardRowView(cards: holeCards, height: cardHeight)
                    .opacity(summary?.hasFolded == true ? 0.4 : 1)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("Your cards"))
                    .accessibilityValue(Text(holeCards.spokenList))
            }
            VStack(spacing: Theme.Spacing.xSmall) {
                if isInline {
                    BetView(amount: summary?.streetCommitted ?? 0)
                }
                if let summary {
                    SeatHeaderView(
                        name: summary.name,
                        stack: summary.stack,
                        isOnButton: isOnButton,
                        isAllIn: summary.isAllIn,
                        hasFolded: summary.hasFolded,
                        isBusted: summary.isBusted
                    )
                    .emoteBubble(reaction)
                }
            }
        }
    }
}

/// Places the other players of a bigger table on `SeatLayout`'s arc, then
/// nudges each seat inward until it fits its area, so a seat near the top
/// never reaches into the navigation bar and one at the side never leaves
/// the window (tdr/0018). Seats keep their own size; only positions move.
struct SeatArcLayout: Layout {
    let points: [SeatLayout.Point]

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (index, subview) in subviews.enumerated() where index < points.count {
            let size = subview.sizeThatFits(.unspecified)
            let point = points[index]
            let x = Self.clamp(bounds.minX + point.x * bounds.width, low: bounds.minX + size.width / 2, high: bounds.maxX - size.width / 2)
            let y = Self.clamp(bounds.minY + point.y * bounds.height, low: bounds.minY + size.height / 2, high: bounds.maxY - size.height / 2)
            subview.place(at: CGPoint(x: x, y: y), anchor: .center, proposal: ProposedViewSize(size))
        }
    }

    /// Keeps `value` in `low...high`; when the seat is bigger than the area,
    /// the low edge (top or leading) wins so its name stays visible.
    private static func clamp(_ value: CGFloat, low: CGFloat, high: CGFloat) -> CGFloat {
        max(low, min(value, high))
    }
}

/// An opponent's two cards: backs while the hand runs, faces after a
/// showdown. The backs are dealt in like the board.
private struct HiddenOrRevealedCards: View {
    let showsCards: Bool
    let revealedCards: [Card]
    let height: CGFloat
    let spacing: CGFloat
    let ownerName: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if showsCards {
                if revealedCards.isEmpty {
                    HStack(spacing: spacing) {
                        ForEach(0..<2, id: \.self) { index in
                            CardBackView()
                                .frame(height: height)
                                .transition(reduceMotion
                                    ? .opacity
                                    : .dealt(from: height).animation(Theme.Motion.deal.delay(DealTiming.delay(index: index, previousCount: 0))))
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("\(ownerName)'s cards, face down"))
                } else {
                    CardRowView(cards: revealedCards, height: height)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text("\(ownerName) shows"))
                        .accessibilityValue(Text(revealedCards.spokenList))
                }
            }
        }
        .motion(Theme.Motion.deal, value: showsCards)
    }
}

/// Chips pushed forward on this street. They pop in when a bet is made and
/// fade when the street ends and they join the pot.
private struct BetView: View {
    let amount: Chips
    var font: Font = .subheadline

    var body: some View {
        ZStack {
            if amount > 0 {
                ChipAmountView(amount: amount)
                    .font(font)
                    .foregroundStyle(.white)
                    .padding(.horizontal, Theme.Spacing.small)
                    .padding(.vertical, 2)
                    .tableGlass(in: Capsule(), tint: .black.opacity(0.15))
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
                    .accessibilityLabel(Text("Bet \(amount, format: .number)"))
            }
        }
        .motion(Theme.Motion.reveal, value: amount > 0)
    }
}

struct SeatHeaderView: View {
    let name: String
    let stack: Chips
    let isOnButton: Bool
    let isAllIn: Bool
    let hasFolded: Bool
    var isBusted: Bool = false
    var isActing: Bool = false

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        // At accessibility text sizes a single line would truncate the name,
        // so the stack and tags drop under it.
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: Theme.Spacing.xSmall))
            : AnyLayout(HStackLayout(spacing: Theme.Spacing.small))
        layout {
            HStack(spacing: Theme.Spacing.small) {
                if isOnButton {
                    DealerButton()
                }
                if isActing {
                    Image(systemName: "hourglass")
                        .font(.subheadline.bold())
                        .foregroundStyle(Theme.Palette.highlight)
                        .symbolEffect(.pulse)
                }
                Text(name)
                    .font(.headline)
                    .lineLimit(1)
            }
            HStack(spacing: Theme.Spacing.small) {
                ChipAmountView(amount: stack)
                if let tag {
                    StatusTag(text: tag)
                }
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, Theme.Spacing.medium)
        .padding(.vertical, Theme.Spacing.small)
        .frame(minHeight: Theme.Target.minimum)
        .tableGlass(in: Capsule())
        .overlay {
            if isActing {
                Capsule().strokeBorder(Theme.Palette.highlight, lineWidth: 3)
            }
        }
        .opacity(isBusted ? 0.5 : 1)
        // A plate is the one thing a seat must show whole; neighbours such as
        // the status banner give up width first.
        .layoutPriority(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(name))
        .accessibilityValue(accessibilityValue)
    }

    private var tag: LocalizedStringKey? {
        if isBusted { return "Out" }
        if isAllIn { return "All-in" }
        if hasFolded { return "Folded" }
        return nil
    }

    /// "1,500 chips, dealer, thinking, all-in": everything the plate shows.
    private var accessibilityValue: Text {
        var parts = [String(localized: "^[\(stack) chip](inflect: true)")]
        if isOnButton { parts.append(String(localized: "dealer")) }
        if isActing { parts.append(String(localized: "thinking")) }
        if isBusted {
            parts.append(String(localized: "out"))
        } else if isAllIn {
            parts.append(String(localized: "all-in"))
        } else if hasFolded {
            parts.append(String(localized: "folded"))
        }
        return Text(parts.formatted(.list(type: .and, width: .narrow)))
    }
}

/// The white "D" disc. Inside a table it shares a namespace with every other
/// seat, so it travels to the next dealer instead of reappearing.
struct DealerButton: View {
    var compact: Bool = false
    @Environment(\.dealerButtonNamespace) private var namespace

    var body: some View {
        let disc = Text("D")
            .font((compact ? Font.caption2 : .caption).bold())
            .padding(compact ? 3 : 6)
            .background(.white, in: Circle())
            .foregroundStyle(.black)
            .accessibilityLabel(Text("Dealer button"))
        if let namespace {
            disc.matchedGeometryEffect(id: "dealer", in: namespace)
        } else {
            disc
        }
    }
}

/// One of several other players at a bigger table (tdr/0013): a compact
/// badge with picture, name and stack, small cards, and their bet.
struct CompactSeatView: View {
    let summary: PlayerSummary
    let avatar: Data?
    let isOnButton: Bool
    let isActing: Bool
    let revealedCards: [Card]
    let showsCards: Bool
    var reaction: MatchSessionClient.Reaction? = nil
    var cardHeight: CGFloat = 30

    @ScaledMetric(relativeTo: .caption) private var avatarSize: CGFloat = 36

    var body: some View {
        VStack(spacing: Theme.Spacing.xSmall) {
            ZStack(alignment: .bottomTrailing) {
                PlayerAvatar(data: avatar, size: min(avatarSize, 56), name: summary.name, isReconnecting: summary.isReconnecting)
                    .overlay {
                        if isActing {
                            Circle().strokeBorder(Theme.Palette.highlight, lineWidth: 3)
                        }
                    }
                if isOnButton {
                    DealerButton(compact: true)
                }
            }
            .emoteBubble(reaction)
            HStack(spacing: 2) {
                if isActing {
                    Image(systemName: "hourglass")
                        .foregroundStyle(Theme.Palette.highlight)
                        .accessibilityLabel(Text("Thinking"))
                }
                Text(summary.name)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .font(.caption.bold())
            ChipAmountView(amount: summary.stack)
                .font(.caption2)
            if summary.isBusted {
                StatusTag(text: "Out")
            } else if summary.isAllIn {
                StatusTag(text: "All-in")
            } else if summary.hasFolded {
                StatusTag(text: "Folded")
            }
            HiddenOrRevealedCards(
                showsCards: showsCards,
                revealedCards: revealedCards,
                height: cardHeight,
                spacing: 2,
                ownerName: summary.name
            )
            BetView(amount: summary.streetCommitted, font: .caption2)
        }
        .foregroundStyle(.white)
        .frame(width: max(96, cardHeight * 3.4, avatarSize * 2.6))
        .opacity(summary.isBusted ? 0.5 : 1)
        .accessibilityElement(children: .combine)
    }
}

/// A player's picture. While they are reconnecting (tdr/0016) it is dimmed
/// behind a `wifi.slash` symbol, with a spinning ring around it.
struct PlayerAvatar: View {
    let data: Data?
    let size: CGFloat
    let name: String
    var isReconnecting: Bool = false

    var body: some View {
        AvatarView(data: data, size: size, name: name)
            .overlay {
                if isReconnecting {
                    ZStack {
                        Circle().fill(.black.opacity(0.55))
                        Image(systemName: "wifi.slash")
                            .font(.system(size: size * 0.42, weight: .semibold))
                            .foregroundStyle(.white)
                            .symbolEffect(.pulse)
                    }
                    .transition(.opacity)
                }
            }
            .overlay {
                if isReconnecting {
                    ReconnectRing(diameter: size + max(6, size * 0.16))
                }
            }
            .animation(.easeInOut(duration: 0.25), value: isReconnecting)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(isReconnecting ? Text("\(name), reconnecting") : Text("Profile picture of \(name)"))
    }
}

/// An arc that keeps spinning around a reconnecting player's picture. Under
/// Reduce Motion it stays still; the `wifi.slash` symbol still says why.
private struct ReconnectRing: View {
    let diameter: CGFloat
    @State private var isSpinning = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.7)
            .stroke(.white, style: StrokeStyle(lineWidth: max(2, diameter * 0.05), lineCap: .round))
            .frame(width: diameter, height: diameter)
            .rotationEffect(.degrees(isSpinning ? 360 : 0))
            .animation(reduceMotion ? nil : .linear(duration: 1).repeatForever(autoreverses: false), value: isSpinning)
            .onAppear { isSpinning = true }
            .allowsHitTesting(false)
    }
}

extension PlayerSummary {
    /// Dropped but still holding the seat (tdr/0014, tdr/0016).
    nonisolated var isReconnecting: Bool { !isConnected && !isBusted }
}

struct StatusTag: View {
    let text: LocalizedStringKey

    var body: some View {
        Text(text)
            .font(.caption.bold())
            .padding(.horizontal, Theme.Spacing.small)
            .padding(.vertical, 3)
            .background(Theme.Palette.highlight, in: Capsule())
            .foregroundStyle(.black)
    }
}

/// Community cards and the pot.
struct BoardView: View {
    let community: [Card]
    let pot: Chips
    let street: Street?
    var cardHeight: CGFloat = 64
    /// The pot to the leading side of the cards rather than above them, to
    /// save height in landscape.
    var potBeside: Bool = false

    var body: some View {
        let layout = potBeside
            ? AnyLayout(HStackLayout(spacing: Theme.Spacing.medium))
            : AnyLayout(VStackLayout(spacing: Theme.Spacing.medium))
        layout {
            ZStack {
                if pot > 0 {
                    HStack(spacing: Theme.Spacing.xSmall) {
                        Text("Pot")
                        ChipAmountView(amount: pot)
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, Theme.Spacing.large)
                    .padding(.vertical, Theme.Spacing.small)
                    .tableGlass(in: Capsule())
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("Pot"))
                    .accessibilityValue(Text("^[\(pot) chip](inflect: true)"))
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
            }
            .motion(Theme.Motion.reveal, value: pot > 0)
            CardRowView(cards: community, slots: street == nil ? 0 : 5, height: cardHeight)
                .motion(Theme.Motion.layout, value: community)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Board"))
                .accessibilityValue(community.isEmpty ? Text("No cards yet") : Text(community.spokenList))
        }
        .onChange(of: community.count) { previousCount, newCount in
            if BoardSound.playsOnDeal(previousCount: previousCount, newCount: newCount) {
                SoundEffects.shared.play(.placingNewCard)
            }
        }
    }
}
