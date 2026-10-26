import SwiftUI
import UIKit

/// "How can we help?" for purchases (tdr/0022, HIG Apple In-App Purchase >
/// Providing help): fix a missing purchase, read the FAQ, request a refund
/// through the system sheet, or write to us.
struct PurchaseHelpView: View {
    @Environment(SkinStore.self) private var store
    @Environment(\.openURL) private var openURL
    @State private var model: PurchaseHelpModel?
    /// The mail address to show when no mail app can take a `mailto:` link.
    @State private var showsAddress = false

    var body: some View {
        List {
            Section("How can we help?") {
                NavigationLink("Missing a Purchase") {
                    MissingPurchaseView(model: model)
                }
                NavigationLink("Frequently Asked Questions") {
                    PurchaseFAQView()
                }
                NavigationLink("Request a Refund") {
                    if let model {
                        RefundRequestView(model: model)
                    }
                }
                .disabled(model == nil)
                Button {
                    write(.feedback)
                } label: {
                    HelpLinkLabel(title: "Submit Feedback")
                }
                Button {
                    write(.support)
                } label: {
                    HelpLinkLabel(title: "Contact Us")
                }
            }

            Section {
            } footer: {
                Link("Request a refund for apps or content that you bought from Apple", destination: SupportContact.appleRefundHelp)
                    .font(.footnote)
            }
        }
        .navigationTitle("Help")
        .task {
            if model == nil { model = PurchaseHelpModel(store: store) }
        }
        .alert("Write to us", isPresented: $showsAddress) {
            Button("Copy address") { UIPasteboard.general.string = SupportContact.email }
            Button("OK", role: .cancel) {}
        } message: {
            Text("No mail app is set up on this device. Write to \(SupportContact.email).")
        }
    }

    private func write(_ topic: SupportContact.Topic) {
        openURL(SupportContact.mailURL(topic)) { accepted in
            if !accepted { showsAddress = true }
        }
    }
}

/// A row that leaves the app (Mail), drawn like the navigation rows around it.
private struct HelpLinkLabel: View {
    let title: LocalizedStringKey

    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(.primary)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.footnote.bold())
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
    }
}

/// Explains where purchases come from and offers the immediate fix: a
/// restore. Refunds stay one tap away from the help screen.
private struct MissingPurchaseView: View {
    @Environment(SkinStore.self) private var store
    let model: PurchaseHelpModel?

    var body: some View {
        List {
            Section {
                Text("Card faces and backs belong to the Apple Account that bought them and appear on every device signed in with it.")
                Text("If someone in your family has to approve purchases, the item appears once they approve it.")
                Text("Downloaded art can take a moment to appear. Until then the classic cards show.")
            }
            .foregroundStyle(.secondary)

            Section {
                PrimaryActionButton(title: "Restore Purchases", systemImage: "arrow.clockwise", isWorking: store.isRestoring) {
                    Task {
                        if let model {
                            await model.recoverMissingPurchase()
                        } else {
                            await store.restorePurchases()
                        }
                    }
                }
            } footer: {
                if store.isRestoring {
                    Label("Checking with the App Store…", systemImage: "hourglass")
                } else if let error = store.lastError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }
        }
        .navigationTitle("Missing a Purchase")
    }
}

#if DEBUG
#Preview("Help") {
    NavigationStack {
        PurchaseHelpView()
    }
    .previewEnvironment()
}
#endif
