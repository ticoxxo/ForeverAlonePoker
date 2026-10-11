import SwiftUI
import PokerCore
import SkinKit

/// A card-face set: buy it whole or card by card, and choose which of the
/// player's cards use it.
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
                            selectedCard = card
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
            } else {
                Text("\(store.ownedCount(of: item)) of \(item.slots.count) cards owned")
                    .foregroundStyle(.secondary)
                if !store.ownsAll(of: item), let productID = item.productID {
                    HStack {
                        Text("Whole set")
                        BuyButton(productID: productID)
                    }
                    if let savings = store.setSavings(for: item) {
                        Text("Saves \(savings) over buying the remaining cards one by one.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    PurchaseStateText(state: store.purchaseStates[productID])
                }
                if store.ownedCount(of: item) > 0 {
                    Button("Use on every card I own") { store.equipAll(item) }
                        .buttonStyle(.bordered)
                }
            }
        }
    }

    @ViewBuilder
    private func cardActions(_ card: Card) -> some View {
        let slot = CosmeticSlot.cardFront(card)
        if store.owns(slot, of: item) {
            if !store.isShowing(item, in: slot) {
                Button("Use this card") { store.equip(item, on: [slot]) }
            }
        } else if let product = store.cardProduct(item, card) {
            Button("Buy for \(product.displayPrice)") {
                Task { await store.purchase(product.id) }
            }
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
