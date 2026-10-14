import SwiftUI
import PokerCore
import SkinKit

/// The card store (tdr/0012): card-face sets and card backs from the remote
/// catalog, with prices from the App Store in the player's storefront currency.
struct SkinStoreView: View {
    @Environment(SkinStore.self) private var store

    var body: some View {
        List {
            Section("Card faces") {
                ForEach(store.items(of: .cardFront)) { item in
                    NavigationLink {
                        SkinSetDetailView(item: item)
                    } label: {
                        SkinItemRow(item: item)
                    }
                }
            }

            Section("Card backs") {
                ForEach(store.items(of: .cardBack)) { item in
                    CardBackRow(item: item)
                }
            }

            Section {
                Button {
                    Task { await store.restorePurchases() }
                } label: {
                    if store.isRestoring {
                        ProgressView()
                    } else {
                        Text("Restore purchases")
                    }
                }
                .disabled(store.isRestoring)
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Prices are in your App Store currency. Purchases are tied to your Apple Account and appear on all your devices.")
                    if let error = store.lastError {
                        Text(error).foregroundStyle(.orange)
                    }
                }
            }
        }
        .navigationTitle("Card store")
        .refreshable {
            await store.refreshCatalog()
            await store.loadProducts()
            await store.syncAssets()
        }
    }
}

/// One card-face set: preview, name and what the player has of it.
private struct SkinItemRow: View {
    @Environment(SkinStore.self) private var store
    let item: SkinItem

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: -24) {
                ForEach(["As", "Kh", "Qd"], id: \.self) { notation in
                    CardView(card: Card(notation)!)
                        .frame(height: 56)
                }
            }
            .environment(\.cardSkin, store.previewSkin(for: item))

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(item.name(for: Locale.current.language.languageCode?.identifier))
                        .font(.headline)
                    if let badge = item.badge {
                        BadgeView(text: badge)
                    }
                }
                Text(status)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var status: String {
        if item.isDefault { return String(localized: "Free") }
        let owned = store.ownedCount(of: item)
        if owned == item.slots.count { return String(localized: "Owned") }
        let price = store.product(item.productID)?.displayPrice
        if owned > 0 {
            return String(localized: "\(owned) of \(item.slots.count) cards owned")
        }
        return price.map { String(localized: "Full set \($0)") } ?? String(localized: "Unavailable")
    }
}

/// A card back: buy it, or use it once owned.
private struct CardBackRow: View {
    @Environment(SkinStore.self) private var store
    let item: SkinItem

    var body: some View {
        HStack(spacing: 12) {
            CardBackView()
                .frame(height: 56)
                .environment(\.cardSkin, store.previewSkin(for: item))
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(item.name(for: Locale.current.language.languageCode?.identifier))
                        .font(.headline)
                    if let badge = item.badge {
                        BadgeView(text: badge)
                    }
                }
                PurchaseStateText(state: item.productID.flatMap { store.purchaseStates[$0] })
            }
            Spacer()
            if store.owns(.cardBack, of: item) {
                if store.isShowing(item, in: .cardBack) {
                    Label("In use", systemImage: "checkmark.circle.fill")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.green)
                        .accessibilityLabel(Text("In use"))
                } else {
                    Button("Use") { store.equip(item, on: [.cardBack]) }
                        .buttonStyle(.bordered)
                }
            } else if let productID = item.productID {
                BuyButton(productID: productID)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Buys one product, showing its App Store price.
struct BuyButton: View {
    @Environment(SkinStore.self) private var store
    let productID: String

    var body: some View {
        let state = store.purchaseStates[productID]
        Button {
            Task { await store.purchase(productID) }
        } label: {
            if state == .purchasing {
                ProgressView()
            } else {
                Text(store.product(productID)?.displayPrice ?? "…")
            }
        }
        .buttonStyle(.borderedProminent)
        .disabled(store.product(productID) == nil || state == .purchasing || state == .pending)
    }
}

struct PurchaseStateText: View {
    let state: SkinStore.PurchaseState?

    var body: some View {
        switch state {
        case .pending:
            Text("Waiting for approval").font(.caption).foregroundStyle(.secondary)
        case .failed(let message):
            Text(message).font(.caption).foregroundStyle(.orange)
        case .purchasing, nil:
            EmptyView()
        }
    }
}

struct BadgeView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.yellow, in: Capsule())
            .foregroundStyle(.black)
    }
}

#if DEBUG
#Preview("Store") {
    NavigationStack {
        SkinStoreView()
    }
    .environment(PreviewSkins.store)
}
#endif
