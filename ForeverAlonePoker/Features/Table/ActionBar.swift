import SwiftUI
import PokerCore

/// Fold / check / call buttons plus a bet-or-raise control. Entirely driven by
/// `TableActionModel`; it knows nothing about the transport or the session.
/// Under the table it is a panel with the buttons side by side; in landscape
/// (`axis == .vertical`) it becomes a slim rail on the trailing edge, like the
/// foldable's side toolbar, that scrolls if the window is too short
/// (tdr/0017, tdr/0018).
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

    private var isRail: Bool { axis == .vertical }

    var body: some View {
        content
            // A fixed minimum under the table keeps it from jumping when the
            // bar appears; at accessibility sizes the content decides.
            .frame(maxWidth: .infinity, minHeight: !isRail && !dynamicTypeSize.isAccessibilitySize ? 150 : nil)
            .frame(maxHeight: isRail ? .infinity : nil, alignment: .bottom)
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

    @ViewBuilder
    private var content: some View {
        let stack = VStack(spacing: isRail ? Theme.Spacing.small : Theme.Spacing.medium) {
            if let sizing = model.sizing {
                SizingControl(model: model, sizing: sizing, isCompact: isRail, amount: $amount, onAction: onAction)
            }
            buttons
        }
        .padding(isRail ? Theme.Spacing.medium : Theme.Spacing.large)
        if isRail {
            // The buttons sit at the bottom, nearest the thumb; a window too
            // short for everything scrolls instead of clipping.
            ScrollView {
                stack
            }
            .scrollBounceBehavior(.basedOnSize)
            .defaultScrollAnchor(.bottom)
        } else {
            stack
        }
    }

    private var buttons: some View {
        // One glass container so the buttons render together and morph as
        // Check turns into Call or the raise button comes and goes.
        GlassGroup(spacing: Theme.Spacing.medium) {
            if isRail && !stacksButtons {
                // The rail: Fold and Check/Call share a row, the sized bet
                // gets its own, so all three fit a phone on its side.
                VStack(spacing: Theme.Spacing.small) {
                    HStack(spacing: Theme.Spacing.small) {
                        foldButton
                        passiveButton
                    }
                    aggressiveButton
                }
            } else {
                let layout = stacksButtons || isRail
                    ? AnyLayout(VStackLayout(spacing: Theme.Spacing.medium))
                    : AnyLayout(HStackLayout(spacing: Theme.Spacing.medium))
                layout {
                    foldButton
                    passiveButton
                    aggressiveButton
                }
            }
        }
        .controlSize(.regular)
        .environment(\.actionLabelIsCompact, isRail)
        .animation(reduceMotion ? nil : Theme.Motion.layout, value: model)
    }

    @ViewBuilder
    private var foldButton: some View {
        if model.canFold {
            Button(role: .destructive) {
                onAction(.fold)
            } label: {
                ActionLabel { Text("Fold") }
            }
            .glassButtonStyle()
            .tint(.red)
        }
    }

    @ViewBuilder
    private var passiveButton: some View {
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
    }

    @ViewBuilder
    private var aggressiveButton: some View {
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
extension EnvironmentValues {
    /// Action buttons in the landscape rail: a 44 pt minimum instead of 56.
    @Entry var actionLabelIsCompact = false
}

private struct ActionLabel<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.actionLabelIsCompact) private var isCompact

    var body: some View {
        content()
            .font(.headline.monospacedDigit())
            // One line that shrinks a little at normal sizes, so "Raise to
            // 1,480" never wraps and pushes the panel off screen; at
            // accessibility sizes, where buttons stack, two lines instead.
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
            .multilineTextAlignment(.center)
            .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 0.9 : 0.6)
            // Regular buttons add about 14 pt of padding: 44 pt in the rail,
            // 56 pt under the table, with less side padding than large
            // buttons so three fit across a phone.
            .frame(maxWidth: .infinity, minHeight: (isCompact ? Theme.Target.minimum : Theme.Target.primary) - 14)
    }
}

/// The chosen bet or raise in big digits with an All in shortcut beside it,
/// and a slider with − / + steps for players who find dragging fiddly. The
/// steps already reach the smallest amount, so there is no Min button.
private struct SizingControl: View {
    let model: TableActionModel
    let sizing: TableActionModel.Sizing
    /// The landscape rail: label above the amount, All in under the slider.
    var isCompact: Bool = false
    @Binding var amount: Chips
    let onAction: (PlayerAction) -> Void

    private var range: ClosedRange<Chips> { sizing.range }

    var body: some View {
        VStack(spacing: Theme.Spacing.small) {
            if isCompact {
                HStack(spacing: Theme.Spacing.small) {
                    VStack(alignment: .leading, spacing: 0) {
                        title.font(.caption)
                        amountText
                    }
                    Spacer(minLength: 0)
                    allInButton
                }
            } else {
                HStack(alignment: .center, spacing: Theme.Spacing.small) {
                    title.font(.subheadline)
                    amountText
                    Spacer(minLength: 0)
                    allInButton
                }
            }
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
                .accessibilityLabel(sizingLabel)
                .accessibilityValue(Text(model.clamped(amount), format: .number))
                StepButton(systemImage: "plus", label: "More") { amount = model.stepped(amount, by: 1) }
                    .disabled(amount >= range.upperBound)
            }
        }
        .foregroundStyle(.white)
    }

    private var title: Text {
        switch sizing {
        case .bet: Text("Bet")
        case .raise: Text("Raise to")
        }
    }

    private var sizingLabel: Text {
        switch sizing {
        case .bet: Text("Bet amount")
        case .raise: Text("Raise to amount")
        }
    }

    private var amountText: some View {
        Text(model.clamped(amount), format: .number)
            .font(.title2.bold().monospacedDigit())
            .contentTransition(.numericText(value: Double(model.clamped(amount))))
            .motion(Theme.Motion.count, value: amount)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var allInButton: some View {
        if let allIn = model.allInAmount {
            Button("All in") { onAction(.allIn) }
                .glassButtonStyle()
                .buttonBorderShape(.capsule)
                .tint(.orange)
                .frame(minHeight: Theme.Target.minimum)
                .accessibilityLabel(Text("All in, \(allIn, format: .number)"))
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
    .frame(width: 220, height: 330)
    .padding()
    .background(TableFelt())
}
