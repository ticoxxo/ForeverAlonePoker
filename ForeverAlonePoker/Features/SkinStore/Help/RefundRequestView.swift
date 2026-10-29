import SwiftUI
import PokerCore
import SkinKit

/// "Request a Refund" (tdr/0022): recent purchases with their art, name and
/// purchase date. Tapping one opens Apple's refund sheet directly; Apple's
/// sheet and its confirmation are never imitated or wrapped.
struct RefundRequestView: View {
    let model: PurchaseHelpModel

    var body: some View {
        List {
            Section {
                ForEach(model.rows) { row in
                    RefundRow(model: model, row: row)
                }
            } header: {
                Text("Purchases")
            } footer: {
                if model.hasLoaded, !model.rows.isEmpty {
                    Text("To check on a request, visit reportaproblem.apple.com.")
                }
            }
        }
        .overlay {
            if model.hasLoaded, model.rows.isEmpty {
                ContentUnavailableView(
                    "No purchases yet",
                    systemImage: "bag",
                    description: Text("Card faces and backs you buy appear here.")
                )
            } else if !model.hasLoaded {
                ProgressView()
            }
        }
        .navigationTitle("Request a Refund")
        .task { await model.load() }
        .refreshable { await model.load() }
    }
}

private struct RefundRow: View {
    @Environment(SkinStore.self) private var store
    let model: PurchaseHelpModel
    let row: PurchaseHelpModel.Row
    @ScaledMetric(relativeTo: .headline) private var thumbnailHeight: CGFloat = 56

    var body: some View {
        Button {
            Task { await model.requestRefund(row) }
        } label: {
            HStack(spacing: Theme.Spacing.medium) {
                thumbnail
                    .frame(height: min(thumbnailHeight, 90))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("Purchased on \(row.record.purchaseDate.formatted(date: .long, time: .omitted))")
                        .font(.subheadline)
                        .foregroundStyle(.tint)
                    status
                }
                Spacer()
                if model.refundStates[row.id] == .requesting {
                    ProgressView()
                }
            }
            .padding(.vertical, Theme.Spacing.xSmall)
            .contentShape(Rectangle())
        }
        .disabled(!model.canRequestRefund(row))
        .accessibilityHint(model.canRequestRefund(row) ? Text("Opens the App Store refund request") : Text(""))
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let item = row.item {
            if item.kind == .chips {
                ChipView(denomination: .init(1_000), size: .large)
                    .environment(\.cardSkin, store.previewSkin(for: item))
            } else if item.kind == .cardBack {
                CardBackView()
                    .environment(\.cardSkin, store.previewSkin(for: item))
            } else if let ace = Card("As") {
                CardView(card: ace)
                    .environment(\.cardSkin, store.previewSkin(for: item))
            }
        } else {
            Image(systemName: "rectangle.portrait.on.rectangle.portrait")
                .font(.title)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var status: some View {
        if row.record.isRevoked {
            Text("Refunded")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            switch model.refundStates[row.id] {
            case .submitted:
                Label("Refund requested", systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .failed(let message):
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.orange)
            case .requesting, nil:
                EmptyView()
            }
        }
    }
}

#if DEBUG
#Preview("Refunds") {
    NavigationStack {
        RefundRequestView(model: PurchaseHelpModel(store: PreviewSkins.store))
    }
    .previewEnvironment()
}
#endif
