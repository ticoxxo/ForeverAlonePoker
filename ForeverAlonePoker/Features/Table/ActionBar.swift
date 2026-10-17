import SwiftUI
import PokerCore

/// Fold / check / call buttons plus a bet-or-raise control. Entirely driven by
/// `TableActionModel`; it knows nothing about the transport or the session.
/// Buttons sit side by side under the table, or stacked when the panel is
/// docked at the side in landscape (tdr/0017).
struct ActionBar: View {
    let model: TableActionModel
    var axis: Axis = .horizontal
    /// Fold / Call / Raise in a column instead of a row: docked at the side,
    /// or at accessibility text sizes (`TableArrangement.stacksActionButtons`).
    var stacksButtons: Bool = false
    let onAction: (PlayerAction) -> Void

    @State private var amount: Chips = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: Theme.Spacing.medium) {
            if let sizing = model.sizing {
                SizingControl(model: model, sizing: sizing, amount: $amount, onAction: onAction)
            }
            buttons
        }
        .padding(Theme.Spacing.large)
        // A fixed minimum under the table keeps it from jumping when the bar
        // appears; at accessibility sizes the content decides.
        .frame(maxWidth: .infinity, minHeight: axis == .horizontal && !dynamicTypeSize.isAccessibilitySize ? 150 : nil)
        .tablePanel()
        // Rises into place when it becomes the player's turn, so the change
        // is noticed even out of the corner of an eye.
        .opacity(model.isActive ? 1 : 0)
        .offset(y: model.isActive || reduceMotion ? 0 : 24)
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : Theme.Motion.reveal, value: model.isActive)
        .disabled(!model.isActive)
        .accessibilityHidden(!model.isActive)
        .sensoryFeedback(.impact(weight: .light), trigger: model.isActive) { _, isActive in isActive }
        .onChange(of: model.sizing, initial: true) {
            amount = model.sizing?.range.lowerBound ?? 0
        }
    }

    private var buttons: some View {
        let layout = stacksButtons || axis == .vertical
            ? AnyLayout(VStackLayout(spacing: Theme.Spacing.medium))
            : AnyLayout(HStackLayout(spacing: Theme.Spacing.medium))
        // One glass container so the buttons render together and morph as
        // Check turns into Call or the raise button comes and goes.
        return GlassGroup(spacing: Theme.Spacing.medium) {
            layout {
                actionButtons
            }
        }
        .controlSize(.large)
        .animation(reduceMotion ? nil : Theme.Motion.layout, value: model)
    }

    @ViewBuilder
    private var actionButtons: some View {
        if model.canFold {
            Button(role: .destructive) {
                onAction(.fold)
            } label: {
                ActionLabel { Text("Fold") }
            }
            .glassButtonStyle()
            .tint(.red)
        }
        if model.canCheck {
            Button {
                onAction(.check)
            } label: {
                ActionLabel { Text("Check") }
            }
            .glassButtonStyle(.prominent)
        }
        if let callAmount = model.callAmount {
            Button {
                onAction(.call)
            } label: {
                ActionLabel { Text("Call \(callAmount, format: .number)") }
            }
            .glassButtonStyle(.prominent)
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
            .glassButtonStyle(.prominent)
            .tint(.orange)
        }
    }
}

/// A full-width action title at least `Theme.Target.primary` tall once the
/// large button's own padding is added.
private struct ActionLabel<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .font(.headline.monospacedDigit())
            // Two lines rather than shrinking past legibility at big sizes.
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .minimumScaleFactor(0.85)
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
                    .accessibilityLabel(Text("Smallest amount"))
                Spacer()
                if let allIn = model.allInAmount {
                    Button("All in") { onAction(.allIn) }
                        .tint(.orange)
                        .accessibilityLabel(Text("All in, \(allIn, format: .number)"))
                }
            }
            .glassButtonStyle()
            .buttonBorderShape(.capsule)
            .frame(minHeight: Theme.Target.minimum)
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
        .glassButtonStyle()
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
