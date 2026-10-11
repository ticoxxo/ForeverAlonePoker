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
        .accessibilityLabel(Text(card.notation))
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
struct CardRowView: View {
    let cards: [Card]
    var slots: Int = 0
    var height: CGFloat = 64

    var body: some View {
        HStack(spacing: 6) {
            ForEach(cards, id: \.self) { card in
                CardView(card: card)
                    .frame(height: height)
                    .transition(.scale.combined(with: .opacity))
            }
            ForEach(0..<max(0, slots - cards.count), id: \.self) { _ in
                RoundedRectangle(cornerRadius: CardMetrics.cornerRadius)
                    .strokeBorder(.white.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4]))
                    .aspectRatio(CardMetrics.aspectRatio, contentMode: .fit)
                    .frame(height: height)
            }
        }
    }
}

/// A chip amount with a consistent style.
struct ChipAmountView: View {
    let amount: Chips

    var body: some View {
        Label {
            Text(amount, format: .number)
                .monospacedDigit()
        } icon: {
            Image(systemName: "circle.circle.fill")
        }
        .font(.subheadline.weight(.semibold))
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
    }
    .padding()
    .background(.green)
}
