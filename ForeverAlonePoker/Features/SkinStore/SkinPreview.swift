import SwiftUI
import PokerCore
import SkinKit

/// What a long press in the store enlarges (tdr/0023): a card back, or one
/// card of a face set. Locked cards preview too; that is what the store is for.
struct SkinPreview: Equatable {
    enum Subject: Equatable {
        case back
        case face(Card)
    }

    let item: SkinItem
    let subject: Subject
}

extension View {
    /// Shows `preview` enlarged over this view until the player taps anywhere.
    func skinPreview(_ preview: Binding<SkinPreview?>) -> some View {
        modifier(SkinPreviewOverlay(preview: preview))
    }
}

private struct SkinPreviewOverlay: ViewModifier {
    @Environment(SkinStore.self) private var store
    @Binding var preview: SkinPreview?

    func body(content: Content) -> some View {
        content
            .overlay {
                if let preview {
                    enlarged(preview)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
            .motion(Theme.Motion.reveal, value: preview)
            .sensoryFeedback(.impact, trigger: preview) { _, new in new != nil }
    }

    private func enlarged(_ preview: SkinPreview) -> some View {
        ZStack {
            Rectangle()
                .fill(.black.opacity(0.6))
                .ignoresSafeArea()
            VStack(spacing: Theme.Spacing.medium) {
                Group {
                    switch preview.subject {
                    case .back: CardBackView()
                    case .face(let card): CardView(card: card)
                    }
                }
                .environment(\.cardSkin, store.previewSkin(for: preview.item))
                .shadow(radius: 16, y: 8)
                .frame(maxWidth: Theme.Width.card)
                Text(title(of: preview))
                    .font(.headline)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
            }
            .padding(Theme.Spacing.large)
        }
        .contentShape(Rectangle())
        .onTapGesture { self.preview = nil }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title(of: preview)))
        .accessibilityHint(Text("Double-tap to close the preview"))
        .accessibilityAddTraits(.isModal)
        .accessibilityAction { self.preview = nil }
        .accessibilityAction(.escape) { self.preview = nil }
    }

    private func title(of preview: SkinPreview) -> String {
        let name = preview.item.name(for: Locale.current.language.languageCode?.identifier)
        switch preview.subject {
        case .back: return name
        case .face(let card): return "\(card.spokenName) · \(name)"
        }
    }
}
