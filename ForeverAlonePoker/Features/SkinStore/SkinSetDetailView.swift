import SwiftUI
import PokerCore
import SkinKit

/// A card-face set: buy it whole, then choose which of the player's cards use
/// it. Cards are never sold one by one (tdr/0012).
struct SkinSetDetailView: View {
    @Environment(SkinStore.self) private var store
    let item: SkinItem
    @State private var selectedCard: Card?
    @State private var preview: SkinPreview?
    /// Cards grow with the text size so the set stays easy to see and tap.
    @ScaledMetric(relativeTo: .body) private var cellWidth: CGFloat = 64

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: max(Theme.Target.minimum, min(cellWidth, 140))), spacing: Theme.Spacing.small)]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.large) {
                header
                LazyVGrid(columns: columns, spacing: Theme.Spacing.small) {
                    ForEach(item.slots.compactMap(\.card), id: \.self) { card in
                        // Not a Button: a Button would also fire when a long
                        // press lifts, opening the dialog behind the preview.
                        CardCell(item: item, card: card)
                            .contentShape(Rectangle())
                            .onTapGesture { choose(card) }
                            .onLongPressGesture { preview = SkinPreview(item: item, subject: .face(card)) }
                            .accessibilityAddTraits(.isButton)
                            .accessibilityAction { choose(card) }
                            .accessibilityAction(named: Text("Preview")) { preview = SkinPreview(item: item, subject: .face(card)) }
                            .accessibilityHint(store.owns(.cardFront(card), of: item) ? Text("Choose whether this card uses the set") : Text("Comes with the set"))
                    }
                }
                .environment(\.cardSkin, store.previewSkin(for: item))
            }
            .padding()
            .frame(maxWidth: Theme.Width.readable)
            .frame(maxWidth: .infinity)
        }
        .skinPreview($preview)
        .navigationTitle(item.name(for: Locale.current.language.languageCode?.identifier))
        .navigationBarTitleDisplayMode(.inline)
        .unlockCelebration()
        .confirmationDialog(
            selectedCard.map { Text($0.notation) } ?? Text(""),
            isPresented: Binding(get: { selectedCard != nil }, set: { if !$0 { selectedCard = nil } }),
            presenting: selectedCard
        ) { card in
            cardActions(card)
        }
    }

    private func choose(_ card: Card) {
        // Locked cards have nothing to offer: they come with the set.
        if store.owns(.cardFront(card), of: item) { selectedCard = card }
    }

    @ViewBuilder
    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            if item.isDefault {
                Text("The classic deck is free and always available.")
                    .foregroundStyle(.secondary)
                PrimaryActionButton(title: "Use for every card", systemImage: "rectangle.stack.fill") { store.equipAll(item) }
            } else if store.ownsAll(of: item) {
                PrimaryActionButton(title: "Use for every card", systemImage: "rectangle.stack.fill") { store.equipAll(item) }
            } else if let productID = item.productID {
                Text("Buy the set to use all \(item.slots.count) cards.")
                    .foregroundStyle(.secondary)
                HStack {
                    Text("Whole set")
                        .font(.headline)
                    Spacer()
                    BuyButton(productID: productID, itemName: item.name(for: Locale.current.language.languageCode?.identifier))
                        .controlSize(.large)
                }
                PurchaseStateText(state: store.purchaseStates[productID])
            }
        }
    }

    @ViewBuilder
    private func cardActions(_ card: Card) -> some View {
        let slot = CosmeticSlot.cardFront(card)
        if store.owns(slot, of: item), !store.isShowing(item, in: slot) {
            Button("Use this card") { store.equip(item, on: [slot]) }
        }
        if !item.isDefault, store.isShowing(item, in: slot), let classic = store.items(of: .cardFront).first(where: \.isDefault) {
            Button("Use the classic card") { store.equip(classic, on: [slot]) }
        }
    }
}

/// One card of the set with its state: in use, owned, or locked.
private struct CardCell: View {
    @Environment(SkinStore.self) private var store
    let item: SkinItem
    let card: Card

    var body: some View {
        let slot = CosmeticSlot.cardFront(card)
        let owned = store.owns(slot, of: item)
        CardView(card: card)
            .opacity(owned ? 1 : 0.55)
            .overlay(alignment: .topTrailing) {
                if store.isShowing(item, in: slot) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.white, .green)
                        .offset(x: 4, y: -4)
                        .transition(.scale.combined(with: .opacity))
                } else if !owned {
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                        .padding(3)
                        .background(.thinMaterial, in: Circle())
                        .offset(x: 4, y: -4)
                }
            }
            .motion(Theme.Motion.reveal, value: store.isShowing(item, in: slot))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(card.spokenName))
            .accessibilityValue(Text(store.isShowing(item, in: slot) ? "In use" : owned ? "Owned" : "Locked"))
    }
}
