import SwiftUI
import PokerCore
import SkinKit

/// A card-face set: buy it whole, then choose which of the player's cards use
/// it. Cards are never sold one by one (tdr/0012).
struct SkinSetDetailView: View {
    @Environment(SkinStore.self) private var store
    let item: SkinItem
    @State private var selectedCard: Card?

    private let columns = [GridItem(.adaptive(minimum: 56), spacing: 8)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(item.slots.compactMap(\.card), id: \.self) { card in
                        Button {
                            // Locked cards have nothing to offer: they come with the set.
                            if store.owns(.cardFront(card), of: item) { selectedCard = card }
                        } label: {
                            CardCell(item: item, card: card)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .environment(\.cardSkin, store.previewSkin(for: item))
            }
            .padding()
        }
        .navigationTitle(item.name(for: Locale.current.language.languageCode?.identifier))
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            selectedCard.map { Text($0.notation) } ?? Text(""),
            isPresented: Binding(get: { selectedCard != nil }, set: { if !$0 { selectedCard = nil } }),
            presenting: selectedCard
        ) { card in
            cardActions(card)
        }
    }

    @ViewBuilder
    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            if item.isDefault {
                Text("The classic deck is free and always available.")
                    .foregroundStyle(.secondary)
                Button("Use for every card") { store.equipAll(item) }
                    .buttonStyle(.borderedProminent)
            } else if store.ownsAll(of: item) {
                Button("Use for every card") { store.equipAll(item) }
                    .buttonStyle(.borderedProminent)
            } else if let productID = item.productID {
                Text("Buy the set to use all \(item.slots.count) cards.")
                    .foregroundStyle(.secondary)
                HStack {
                    Text("Whole set")
                    BuyButton(productID: productID)
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
                } else if !owned {
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                        .padding(3)
                        .background(.thinMaterial, in: Circle())
                        .offset(x: 4, y: -4)
                }
            }
            .accessibilityValue(Text(store.isShowing(item, in: slot) ? "In use" : owned ? "Owned" : "Locked"))
    }
}
