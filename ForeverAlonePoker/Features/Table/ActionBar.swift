import SwiftUI
import PokerCore

/// Fold / check / call buttons plus a bet-or-raise control, as one panel under
/// the table. Shown when the window is regular in both size classes; anywhere
/// smaller the same buttons go into the bottom toolbar and the sizing into a
/// `SizingStrip` (tdr/0019). Entirely driven by `TableActionModel`; it knows
/// nothing about the transport or the session. The raise amount is owned by
/// the table, so moving between panel and toolbar keeps a half-chosen raise.
struct ActionBar: View {
    let model: TableActionModel
    @Binding var amount: Chips
    let onAction: (PlayerAction) -> Void

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
        // A fixed minimum keeps the table from jumping when the bar appears;
        // at accessibility sizes the content decides.
        .frame(maxWidth: .infinity, minHeight: dynamicTypeSize.isAccessibilitySize ? nil : 150)
        .tablePanel()
        // Fades in when it becomes the player's turn; the haptic makes sure
        // the change is noticed even out of the corner of an eye.
        .opacity(model.isActive ? 1 : 0)
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : Theme.Motion.reveal, value: model.isActive)
        .disabled(!model.isActive)
        .accessibilityHidden(!model.isActive)
        .sensoryFeedback(.impact(weight: .light), trigger: model.isActive) { _, isActive in isActive }
    }

    private var buttons: some View {
        // One glass container so the buttons render together and morph as
        // Check turns into Call or the raise button comes and goes. At
        // accessibility text sizes they stack instead of sharing a row.
        GlassGroup(spacing: Theme.Spacing.medium) {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: Theme.Spacing.medium))
                : AnyLayout(HStackLayout(spacing: Theme.Spacing.medium))
            layout {
                if model.canFold {
                    FoldActionButton(model: model, onAction: onAction)
                }
                if model.canCheck || model.callAmount != nil {
                    PassiveActionButton(model: model, onAction: onAction)
                }
                if model.sizing != nil {
                    SizedActionButton(model: model, amount: amount, onAction: onAction)
                }
            }
        }
        .controlSize(.regular)
        .animation(reduceMotion ? nil : Theme.Motion.layout, value: model)
    }
}

// MARK: - Action buttons, shared by the panel and the bottom toolbar

/// Fold. Always drawn, disabled when folding isn't legal, so the toolbar
/// keeps its shape between turns.
struct FoldActionButton: View {
    let model: TableActionModel
    let onAction: (PlayerAction) -> Void

    var body: some View {
        Button(role: .destructive) {
            onAction(.fold)
        } label: {
            ActionLabel { Text("Fold") }
        }
        .glassButtonStyle()
        .tint(.red)
        .disabled(!model.canFold)
    }
}

/// Check, or Call with the amount; a disabled Check when neither is legal.
struct PassiveActionButton: View {
    let model: TableActionModel
    let onAction: (PlayerAction) -> Void

    var body: some View {
        Button {
            onAction(model.canCheck ? .check : .call)
        } label: {
            ActionLabel {
                if !model.canCheck, let callAmount = model.callAmount {
                    Text("Call \(callAmount, format: .number)")
                } else {
                    Text("Check")
                }
            }
        }
        .glassButtonStyle(.prominent)
        .disabled(!model.canCheck && model.callAmount == nil)
    }
}

/// Bet or Raise to the chosen amount: the one prominent, tinted action. A
/// disabled Bet when no sized action is legal.
struct SizedActionButton: View {
    let model: TableActionModel
    let amount: Chips
    let onAction: (PlayerAction) -> Void

    var body: some View {
        Button {
            if let action = model.sizedAction(amount) { onAction(action) }
        } label: {
            ActionLabel {
                switch model.sizing {
                case .bet: Text("Bet \(model.clamped(amount), format: .number)")
                case .raise: Text("Raise to \(model.clamped(amount), format: .number)")
                case nil: Text("Bet")
                }
            }
            .contentTransition(.numericText(value: Double(model.clamped(amount))))
        }
        .glassButtonStyle(.prominent)
        .tint(.orange)
        .disabled(model.sizedAction(amount) == nil)
    }
}

extension EnvironmentValues {
    /// Action labels in the bottom toolbar: as wide as their text and 44 pt
    /// tall, instead of filling the panel at 56 pt.
    @Entry var actionLabelIsInToolbar = false
}

/// A full-width action title at least `Theme.Target.primary` tall once the
/// regular button's own padding is added; in the toolbar it hugs its text.
private struct ActionLabel<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.actionLabelIsInToolbar) private var isInToolbar

    var body: some View {
        content()
            .font(.headline.monospacedDigit())
            // One line that shrinks a little at normal sizes, so "Raise to
            // 1,480" never wraps and pushes the panel off screen; at
            // accessibility sizes in the panel, where buttons stack, two lines.
            .lineLimit(dynamicTypeSize.isAccessibilitySize && !isInToolbar ? 2 : 1)
            .multilineTextAlignment(.center)
            .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 0.9 : 0.6)
            // Regular buttons add about 14 pt of padding.
            .frame(
                maxWidth: isInToolbar ? nil : .infinity,
                minHeight: (isInToolbar ? Theme.Target.minimum : Theme.Target.primary) - 14
            )
    }
}

// MARK: - Bet sizing

/// The chosen bet or raise in big digits with an All in shortcut beside it,
/// and the − / slider / + row. The steps already reach the smallest amount,
/// so there is no Min button.
private struct SizingControl: View {
    let model: TableActionModel
    let sizing: TableActionModel.Sizing
    @Binding var amount: Chips
    let onAction: (PlayerAction) -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.small) {
            HStack(alignment: .center, spacing: Theme.Spacing.small) {
                title.font(.subheadline)
                amountText
                Spacer(minLength: 0)
                AllInButton(model: model, onAction: onAction)
            }
            SizingSlider(model: model, sizing: sizing, amount: $amount)
        }
        .foregroundStyle(.white)
    }

    private var title: Text {
        switch sizing {
        case .bet: Text("Bet")
        case .raise: Text("Raise to")
        }
    }

    private var amountText: some View {
        Text(model.clamped(amount), format: .number)
            .font(.title2.bold().monospacedDigit())
            .contentTransition(.numericText(value: Double(model.clamped(amount))))
            .motion(Theme.Motion.count, value: amount)
            .accessibilityHidden(true)
    }
}

/// The bet sizing that stays at the bottom of the table when the buttons are
/// in the toolbar (tdr/0019): − / slider / + with All in at the trailing end.
/// The amount itself reads on the toolbar's Bet / Raise button. Always laid
/// out and only faded when there is nothing to size, so the table above
/// keeps its height from one turn to the next.
struct SizingStrip: View {
    let model: TableActionModel
    @Binding var amount: Chips
    let onAction: (PlayerAction) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isShown: Bool { model.isActive && model.sizing != nil }

    var body: some View {
        HStack(spacing: Theme.Spacing.small) {
            SizingSlider(model: model, sizing: model.sizing ?? .bet(0...0), amount: $amount)
            AllInButton(model: model, onAction: onAction)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, Theme.Spacing.medium)
        .padding(.vertical, Theme.Spacing.small)
        .tablePanel(cornerRadius: Theme.Radius.panel)
        .opacity(isShown ? 1 : 0)
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : Theme.Motion.reveal, value: isShown)
        .disabled(!isShown)
        .accessibilityHidden(!isShown)
        // The toolbar never moves, so this tap is the cue that it is the
        // player's turn.
        .sensoryFeedback(.impact(weight: .light), trigger: model.isActive) { _, isActive in isActive }
    }
}

/// − / slider / + for players who find dragging fiddly.
private struct SizingSlider: View {
    let model: TableActionModel
    let sizing: TableActionModel.Sizing
    @Binding var amount: Chips

    private var range: ClosedRange<Chips> { sizing.range }

    var body: some View {
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

    private var sizingLabel: Text {
        switch sizing {
        case .bet: Text("Bet amount")
        case .raise: Text("Raise to amount")
        }
    }
}

private struct AllInButton: View {
    let model: TableActionModel
    let onAction: (PlayerAction) -> Void

    var body: some View {
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
    @Previewable @State var amount: Chips = 100
    ActionBar(
        model: TableActionModel(legalActions: LegalActions(canFold: true, callAmount: 40, raiseRange: 100...1480, allInAmount: 1480)),
        amount: $amount,
        onAction: { _ in }
    )
    .padding()
    .background(TableFelt())
}

#Preview("No bet") {
    @Previewable @State var amount: Chips = 20
    ActionBar(
        model: TableActionModel(legalActions: LegalActions(canFold: true, canCheck: true, betRange: 20...1480, allInAmount: 1480)),
        amount: $amount,
        onAction: { _ in }
    )
    .padding()
    .background(TableFelt())
}

#Preview("Sizing strip and toolbar", traits: .landscapeLeft) {
    @Previewable @State var amount: Chips = 100
    let model = TableActionModel(legalActions: LegalActions(canFold: true, callAmount: 40, raiseRange: 100...1480, allInAmount: 1480))
    NavigationStack {
        TableFelt()
            .safeAreaInset(edge: .bottom) {
                SizingStrip(model: model, amount: $amount, onAction: { _ in })
                    .safeAreaPadding(.horizontal, Theme.Spacing.large)
            }
            .toolbar {
                ToolbarItemGroup(placement: .bottomBar) {
                    FoldActionButton(model: model, onAction: { _ in })
                        .environment(\.actionLabelIsInToolbar, true)
                    Spacer()
                    PassiveActionButton(model: model, onAction: { _ in })
                        .environment(\.actionLabelIsInToolbar, true)
                    Spacer()
                    SizedActionButton(model: model, amount: amount, onAction: { _ in })
                        .environment(\.actionLabelIsInToolbar, true)
                }
            }
            .toolbarColorScheme(.dark, for: .bottomBar)
    }
}
