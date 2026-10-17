import SwiftUI
import PokerCore

/// Fold / check / call buttons plus a bet-or-raise control. Entirely driven by
/// `TableActionModel`; it knows nothing about the transport or the session.
/// Buttons sit side by side under the table, or stacked when the panel is
/// docked at the side in landscape (tdr/0017).
struct ActionBar: View {
    let model: TableActionModel
    var axis: Axis = .horizontal
    let onAction: (PlayerAction) -> Void

    @State private var amount: Chips = 0

    var body: some View {
        VStack(spacing: Theme.Spacing.medium) {
            if let sizing = model.sizing {
                SizingControl(model: model, sizing: sizing, amount: $amount, onAction: onAction)
            }
            buttons
        }
        .padding(Theme.Spacing.large)
        // Fixed height under the table keeps it from jumping when the bar appears.
        .frame(maxWidth: .infinity, minHeight: axis == .horizontal ? 150 : nil)
        .tablePanel()
        .opacity(model.isActive ? 1 : 0)
        .disabled(!model.isActive)
        .sensoryFeedback(.impact(weight: .light), trigger: model.isActive) { _, isActive in isActive }
        .onChange(of: model.sizing, initial: true) {
            amount = model.sizing?.range.lowerBound ?? 0
        }
    }

    private var buttons: some View {
        let layout = axis == .horizontal
            ? AnyLayout(HStackLayout(spacing: Theme.Spacing.medium))
            : AnyLayout(VStackLayout(spacing: Theme.Spacing.medium))
        return layout {
            if model.canFold {
                Button(role: .destructive) {
                    onAction(.fold)
                } label: {
                    ActionLabel { Text("Fold") }
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
            if model.canCheck {
                Button {
                    onAction(.check)
                } label: {
                    ActionLabel { Text("Check") }
                }
                .buttonStyle(.glassProminent)
            }
            if let callAmount = model.callAmount {
                Button {
                    onAction(.call)
                } label: {
                    ActionLabel { Text("Call \(callAmount, format: .number)") }
                }
                .buttonStyle(.glassProminent)
            }
            if let sizing = model.sizing, let action = model.sizedAction(amount) {
                Button {
                    onAction(action)
                } label: {
                    ActionLabel {
                        switch sizing {
                        case .bet: Text("Bet \(model.clamped(amount), format: .number)")
                        case .raise: Text("Raise to \(model.clamped(amount), format: .number)")
                        }
                    }
                }
                .buttonStyle(.glassProminent)
                .tint(.orange)
            }
        }
        .controlSize(.large)
    }
}

/// A full-width action title at least `Theme.Target.primary` tall once the
/// large button's own padding is added.
private struct ActionLabel<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .font(.headline.monospacedDigit())
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, minHeight: Theme.Target.primary - 20)
    }
}

/// The chosen bet or raise in big digits, a slider with − / + steps for
/// players who find dragging fiddly, and Min / All in shortcuts.
private struct SizingControl: View {
    let model: TableActionModel
    let sizing: TableActionModel.Sizing
    @Binding var amount: Chips
    let onAction: (PlayerAction) -> Void

    private var range: ClosedRange<Chips> { sizing.range }

    var body: some View {
        VStack(spacing: Theme.Spacing.small) {
            HStack(alignment: .firstTextBaseline) {
                switch sizing {
                case .bet: Text("Bet")
                case .raise: Text("Raise to")
                }
                Spacer()
                Text(model.clamped(amount), format: .number)
                    .font(.title2.bold().monospacedDigit())
                    .contentTransition(.numericText())
                    .animation(.snappy, value: amount)
            }
            .font(.subheadline)
            .foregroundStyle(.white)
            HStack(spacing: Theme.Spacing.small) {
                StepButton(systemImage: "minus", label: "Less") { amount = model.stepped(amount, by: -1) }
                    .disabled(amount <= range.lowerBound)
                Slider(
                    value: Binding(
                        get: { Double(amount) },
                        set: { amount = Chips($0.rounded()) }
                    ),
                    in: Double(range.lowerBound)...Double(max(range.upperBound, range.lowerBound + 1)),
                    step: 1
                )
                .disabled(range.lowerBound == range.upperBound)
                .accessibilityLabel(Text("Amount"))
                .accessibilityValue(Text(model.clamped(amount), format: .number))
                StepButton(systemImage: "plus", label: "More") { amount = model.stepped(amount, by: 1) }
                    .disabled(amount >= range.upperBound)
            }
            HStack {
                Button("Min") { amount = range.lowerBound }
                Spacer()
                if model.allInAmount != nil {
                    Button("All in") { onAction(.allIn) }
                        .tint(.orange)
                }
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
        }
    }
}

private struct StepButton: View {
    let systemImage: String
    let label: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.bold())
                .frame(width: Theme.Target.minimum - 16, height: Theme.Target.minimum - 16)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
        .accessibilityLabel(Text(label))
    }
}

#Preview("Facing a bet") {
    ActionBar(
        model: TableActionModel(legalActions: LegalActions(canFold: true, callAmount: 40, raiseRange: 100...1480, allInAmount: 1480)),
        onAction: { _ in }
    )
    .padding()
    .background(TableFelt())
}

#Preview("No bet") {
    ActionBar(
        model: TableActionModel(legalActions: LegalActions(canFold: true, canCheck: true, betRange: 20...1480, allInAmount: 1480)),
        onAction: { _ in }
    )
    .padding()
    .background(TableFelt())
}

#Preview("Docked at the side", traits: .landscapeLeft) {
    ActionBar(
        model: TableActionModel(legalActions: LegalActions(canFold: true, callAmount: 40, raiseRange: 100...1480, allInAmount: 1480)),
        axis: .vertical,
        onAction: { _ in }
    )
    .frame(width: 280)
    .padding()
    .background(TableFelt())
}
