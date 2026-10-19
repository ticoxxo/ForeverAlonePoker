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
            } footer: {
                VStack(alignment: .leading, spacing: Theme.Spacing.xSmall) {
                    Text("Prices are in your App Store currency. Purchases are tied to your Apple Account and appear on all your devices. Bought on another device? Tap Restore.")
                    if let error = store.lastError {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .navigationTitle("Card store")
        .toolbar {
            // A store-wide action, so it lives in the navigation bar instead
            // of at the bottom of a long list.
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await store.restorePurchases() }
                } label: {
                    if store.isRestoring {
                        ProgressView()
                    } else {
                        Text("Restore")
                    }
                }
                .disabled(store.isRestoring)
                .accessibilityLabel(Text("Restore purchases"))
                .accessibilityHint(Text("Brings back cards bought with your Apple Account"))
            }
        }
        .unlockCelebration()
        .refreshable {
            await store.refreshCatalog()
            await store.refreshEntitlements()
            await store.loadProducts()
            await store.syncAssets()
        }
    }
}

/// One card-face set: preview, name and what the player has of it.
private struct SkinItemRow: View {
    @Environment(SkinStore.self) private var store
    let item: SkinItem
    @ScaledMetric(relativeTo: .headline) private var cardHeight: CGFloat = 56

    var body: some View {
        HStack(spacing: Theme.Spacing.medium) {
            HStack(spacing: -min(cardHeight, 90) * 0.43) {
                ForEach(["As", "Kh", "Qd"], id: \.self) { notation in
                    if let card = Card(notation) {
                        CardView(card: card)
                            .frame(height: min(cardHeight, 90))
                    }
                }
            }
            .environment(\.cardSkin, store.previewSkin(for: item))
            .accessibilityHidden(true)

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
        .padding(.vertical, Theme.Spacing.xSmall)
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Shows every card of the set"))
    }

    private var status: String {
        if item.isDefault { return String(localized: "Free") }
        if store.ownsAll(of: item) { return String(localized: "Owned") }
        let price = store.product(item.productID)?.displayPrice
        return price.map { String(localized: "Full set \($0)") } ?? String(localized: "Unavailable")
    }
}

/// A card back: buy it, or use it once owned.
private struct CardBackRow: View {
    @Environment(SkinStore.self) private var store
    let item: SkinItem
    @ScaledMetric(relativeTo: .headline) private var cardHeight: CGFloat = 56

    var body: some View {
        HStack(spacing: Theme.Spacing.medium) {
            CardBackView()
                .frame(height: min(cardHeight, 90))
                .environment(\.cardSkin, store.previewSkin(for: item))
                .accessibilityHidden(true)
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
            .accessibilityElement(children: .combine)
            Spacer()
            Group {
                if store.owns(.cardBack, of: item) {
                    if store.isShowing(item, in: .cardBack) {
                        Label("In use", systemImage: "checkmark.circle.fill")
                            .labelStyle(.iconOnly)
                            .font(.title2)
                            .foregroundStyle(.green)
                            .transition(.scale.combined(with: .opacity))
                            .accessibilityLabel(Text("In use"))
                    } else {
                        Button("Use") { store.equip(item, on: [.cardBack]) }
                            .glassButtonStyle()
                            .accessibilityLabel(Text("Use \(itemName)"))
                    }
                } else if let productID = item.productID {
                    BuyButton(productID: productID, itemName: itemName)
                }
            }
            .motion(Theme.Motion.reveal, value: store.isShowing(item, in: .cardBack))
        }
        .padding(.vertical, Theme.Spacing.xSmall)
    }
}

extension CardBackRow {
    fileprivate var itemName: String { item.name(for: Locale.current.language.languageCode?.identifier) }
}

/// Buys one product, showing its App Store price. The label morphs from the
/// price to a spinner while the App Store sheet is up.
struct BuyButton: View {
    @Environment(SkinStore.self) private var store
    let productID: String
    /// What VoiceOver says is being bought: "Buy Red check for $0.99".
    var itemName: String = ""

    var body: some View {
        let state = store.purchaseStates[productID]
        let price = store.product(productID)?.displayPrice
        Button {
            Task { await store.purchase(productID) }
        } label: {
            ZStack {
                if state == .purchasing {
                    ProgressView()
                        .transition(.opacity)
                } else {
                    Text(price ?? "…")
                        .monospacedDigit()
                        .transition(.opacity)
                }
            }
            .frame(minWidth: Theme.Target.minimum, minHeight: Theme.Target.minimum - 14)
        }
        .glassButtonStyle(.prominent)
        .disabled(price == nil || state == .purchasing || state == .pending)
        .animation(.easeInOut(duration: 0.2), value: state)
        .accessibilityLabel(price.map { Text("Buy \(itemName) for \($0)") } ?? Text("Price unavailable"))
        .accessibilityValue(state == .purchasing ? Text("Purchasing") : state == .pending ? Text("Waiting for approval") : Text(""))
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
            .padding(.horizontal, Theme.Spacing.small - 2)
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
    .previewEnvironment()
}

#Preview("Offline, defaults only") {
    NavigationStack {
        SkinStoreView()
    }
    .previewEnvironment(identity: PreviewIdentity.newPlayer, skins: PreviewSkins.empty)
}

#Preview("Large text") {
    NavigationStack {
        SkinStoreView()
    }
    .previewEnvironment()
    .dynamicTypeSize(.accessibility2)
}
#endif
