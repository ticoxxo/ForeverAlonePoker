import SwiftUI
import PokerCore
import SkinKit

/// Shared card geometry: the skin artwork is drawn on a 500×700 canvas.
enum CardMetrics {
    static let aspectRatio: CGFloat = 5.0 / 7.0
    static let cornerRadius: CGFloat = 8
}

/// A face-up playing card, drawn with the skin in the environment
/// (`\.cardSkin`, tdr/0011). The card itself knows nothing about skins.
struct CardView: View {
    let card: Card
    @Environment(\.cardSkin) private var skin

    var body: some View {
        SkinImage(source: skin.source(for: .cardFront(card))) {
            DrawnCardFace(card: card)
        }
        .aspectRatio(CardMetrics.aspectRatio, contentMode: .fit)
        .shadow(radius: 1, y: 1)
        .accessibilityElement()
        .accessibilityLabel(Text(card.spokenName))
    }
}

/// A face-down card, drawn with the environment's card-back skin.
struct CardBackView: View {
    @Environment(\.cardSkin) private var skin

    var body: some View {
        SkinImage(source: skin.source(for: .cardBack)) {
            DrawnCardBack()
        }
        .aspectRatio(CardMetrics.aspectRatio, contentMode: .fit)
        .shadow(radius: 1, y: 1)
        .accessibilityElement()
        .accessibilityLabel(Text("Face-down card"))
    }
}

/// Shows a skin image: bundled images synchronously, downloaded files
/// decoded off the main thread, remote previews through `AsyncImage`. Falls
/// back to the bundled default, then to `fallback` (the drawn card) if even
/// that is missing.
struct SkinImage<Fallback: View>: View {
    let source: SkinImageSource
    private let fallback: () -> Fallback
    @State private var loaded: LoadedImage?

    init(source: SkinImageSource, @ViewBuilder fallback: @escaping () -> Fallback) {
        self.source = source
        self.fallback = fallback
    }

    var body: some View {
        switch source {
        case .bundled(let name):
            bundled(name)
        case .file(let url, let fallbackName):
            Group {
                if let loaded, loaded.url == url {
                    Image(uiImage: loaded.image).resizable()
                } else {
                    bundled(fallbackName)
                }
            }
            .task(id: url) {
                if let image = await SkinImageCache.shared.image(at: url) {
                    loaded = LoadedImage(url: url, image: image)
                }
            }
        case .remote(let url, let fallbackName):
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable()
                } else {
                    bundled(fallbackName)
                }
            }
        }
    }

    @ViewBuilder
    private func bundled(_ name: String) -> some View {
        if let image = UIImage(named: name) {
            Image(uiImage: image).resizable()
        } else {
            fallback()
        }
    }

    private struct LoadedImage {
        let url: URL
        let image: UIImage
    }
}

/// The original vector card face, kept as the last-resort fallback.
struct DrawnCardFace: View {
    let card: Card

    /// The card face is always white, so the ink must be a fixed colour.
    /// `.primary` resolves to white in dark mode and made black suits invisible.
    private var color: Color {
        switch card.suit {
        case .hearts, .diamonds: .red
        case .clubs, .spades: .black
        }
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: CardMetrics.cornerRadius)
                .fill(.white)
            VStack(spacing: 0) {
                Text(card.rank.symbol)
                    .font(.system(.title3, design: .rounded, weight: .bold))
                Text(card.suit.symbol)
                    .font(.title3)
            }
            .foregroundStyle(color)
        }
        .environment(\.colorScheme, .light)
    }
}

/// The original gradient card back, kept as the last-resort fallback.
struct DrawnCardBack: View {
    var body: some View {
        RoundedRectangle(cornerRadius: CardMetrics.cornerRadius)
            .fill(LinearGradient(colors: [.blue, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(
                RoundedRectangle(cornerRadius: CardMetrics.cornerRadius)
                    .strokeBorder(.white.opacity(0.7), lineWidth: 2)
                    .padding(3)
            )
    }
}

/// A row of cards, with optional face-down placeholders filling to `slots`.
/// New cards are dealt in one after another (tdr/0018): the flop lands card
/// by card, the turn and river on their own, and a new hand replaces the
/// old one.
struct CardRowView: View {
    let cards: [Card]
    var slots: Int = 0
    var height: CGFloat = 64
    /// Cards come face down from above and flip; off for rows that only
    /// preview cards (the store).
    var dealsIn: Bool = true

    /// The cards showing before the latest change, so only new ones wait
    /// their turn. Updated after each render that changes `cards`.
    @State private var shown: [Card] = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Read during the render that inserts new cards, before `shown`
        // catches up, so it still counts only the cards already showing.
        let previousCount = cards.filter(shown.contains).count
        HStack(spacing: 6) {
            ForEach(Array(cards.enumerated()), id: \.element) { index, card in
                CardView(card: card)
                    .frame(height: height)
                    .transition(transition(delay: DealTiming.delay(index: index, previousCount: previousCount, reduceMotion: reduceMotion)))
            }
            ForEach(0..<max(0, slots - cards.count), id: \.self) { _ in
                RoundedRectangle(cornerRadius: CardMetrics.cornerRadius)
                    .strokeBorder(.white.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4]))
                    .aspectRatio(CardMetrics.aspectRatio, contentMode: .fit)
                    .frame(height: height)
                    .accessibilityHidden(true)
            }
        }
        .onChange(of: cards, initial: true) { shown = cards }
    }

    private func transition(delay: Double) -> AnyTransition {
        guard dealsIn, !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .dealt(from: height).animation(Theme.Motion.deal.delay(delay)),
            removal: .opacity.combined(with: .scale(scale: 0.85))
        )
    }
}

extension AnyTransition {
    /// A card pitched from the dealer: it slides down from above, tilted and
    /// slightly small, and settles flat on the table. Only transforms and
    /// opacity change, which the renderer interpolates on its own, so the
    /// card is never rebuilt mid-flight and the motion stays smooth at the
    /// display's full frame rate (tdr/0018).
    static func dealt(from distance: CGFloat) -> AnyTransition {
        .modifier(active: DealPose(isInFlight: true, distance: distance), identity: DealPose(isInFlight: false, distance: distance))
    }
}

/// Where a dealt card is while in flight, and at rest.
private struct DealPose: ViewModifier {
    let isInFlight: Bool
    let distance: CGFloat

    func body(content: Content) -> some View {
        content
            .rotation3DEffect(.degrees(isInFlight ? 55 : 0), axis: (x: 1, y: 0, z: 0), anchor: .top, perspective: 0.5)
            .rotationEffect(.degrees(isInFlight ? -8 : 0))
            .scaleEffect(isInFlight ? 0.8 : 1)
            .offset(y: isInFlight ? -distance * 0.9 : 0)
            .opacity(isInFlight ? 0 : 1)
    }
}

/// One chip, drawn with the chip skin in the environment (`\.cardSkin`,
/// tdr/0027). Falls back to the bundled classic chip, then to a symbol.
struct ChipView: View {
    let denomination: ChipDenomination
    var face: ChipFace = .top
    var size: ChipSize = .small
    @Environment(\.cardSkin) private var skin

    /// The artwork's proportions: a round chip from above, a wide ellipse
    /// with its edge when lying flat.
    private var aspectRatio: CGFloat {
        switch face {
        case .top: 1
        case .flat: 129.0 / 59.0
        }
    }

    var body: some View {
        SkinImage(source: skin.source(for: .chip(denomination, face: face, size: size))) {
            Image(systemName: "circle.circle.fill")
                .resizable()
        }
        .aspectRatio(aspectRatio, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// Up to three piles of chips that picture an amount roughly
/// (`ChipStack.stacks`, tdr/0028): each pile leans up and to the left, and
/// the piles sit in a small cluster, the last one in front.
struct ChipStacksView: View {
    let amount: Chips
    /// The width of one chip.
    let chipSize: CGFloat

    /// Where each pile's bottom chip sits, in chip widths, by pile count.
    private static let clusters: [[CGPoint]] = [
        [CGPoint(x: 0, y: 0)],
        [CGPoint(x: 0, y: 0), CGPoint(x: 0.8, y: 0.2)],
        [CGPoint(x: 0, y: 0.05), CGPoint(x: 0.85, y: -0.1), CGPoint(x: 0.45, y: 0.5)],
    ]

    private struct PlacedChip: Identifiable {
        let id: String
        let denomination: ChipDenomination
        let center: CGPoint
    }

    /// Every chip's center, from the back pile's bottom chip to the front
    /// pile's top one, so later chips draw over earlier ones.
    private var chips: [PlacedChip] {
        let stacks = ChipStack.stacks(for: amount)
        let anchors = Self.clusters[min(stacks.count, Self.clusters.count) - 1]
        let rise = chipSize * 0.16
        return zip(stacks, anchors).enumerated().flatMap { pile, element in
            let (stack, anchor) = element
            return (0..<stack.count).map { level in
                PlacedChip(
                    id: "\(pile)-\(level)",
                    denomination: stack.denomination,
                    center: CGPoint(
                        x: anchor.x * chipSize - CGFloat(level) * rise * 0.6,
                        y: anchor.y * chipSize - CGFloat(level) * rise
                    )
                )
            }
        }
    }

    var body: some View {
        let chips = chips
        let radius = chipSize / 2
        let minX = (chips.map(\.center.x).min() ?? 0) - radius
        let minY = (chips.map(\.center.y).min() ?? 0) - radius
        let maxX = (chips.map(\.center.x).max() ?? 0) + radius
        let maxY = (chips.map(\.center.y).max() ?? 0) + radius
        ZStack(alignment: .topLeading) {
            ForEach(chips) { chip in
                ChipView(denomination: chip.denomination, face: .top, size: .small)
                    .frame(width: chipSize, height: chipSize)
                    .shadow(color: .black.opacity(0.35), radius: 0.5, y: 0.5)
                    .offset(x: chip.center.x - radius - minX, y: chip.center.y - radius - minY)
            }
        }
        .frame(width: maxX - minX, height: maxY - minY, alignment: .topLeading)
        .accessibilityHidden(true)
    }
}

/// A chip amount with a consistent style: a few piles of chips that picture
/// it, then the number, which is the truth. The digits roll when it changes.
struct ChipAmountView: View {
    let amount: Chips
    @ScaledMetric(relativeTo: .subheadline) private var chipSize: CGFloat = 18

    var body: some View {
        Label {
            Text(amount, format: .number)
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(amount)))
        } icon: {
            ChipStacksView(amount: amount, chipSize: chipSize)
        }
        .font(.subheadline.weight(.semibold))
        .motion(Theme.Motion.count, value: amount)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("^[\(amount) chip](inflect: true)"))
    }
}

#Preview("Cards") {
    VStack(spacing: 16) {
        CardRowView(cards: [Card("As")!, Card("Kd")!, Card("Th")!, Card("2c")!], slots: 5)
        HStack {
            CardBackView().frame(height: 64)
            DrawnCardFace(card: Card("Qh")!).aspectRatio(CardMetrics.aspectRatio, contentMode: .fit).frame(height: 64)
            DrawnCardBack().aspectRatio(CardMetrics.aspectRatio, contentMode: .fit).frame(height: 64)
        }
        ChipAmountView(amount: 1500)
        HStack {
            ForEach(ChipDenomination.all, id: \.self) { denomination in
                ChipView(denomination: denomination, size: .large).frame(width: 28)
            }
        }
        ChipView(denomination: .init(1_000), face: .flat, size: .large).frame(width: 64)
    }
    .padding()
    .background(.green)
}
