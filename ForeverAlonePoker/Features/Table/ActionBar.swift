import SwiftUI
import PokerCore

/// Fold / check / call buttons plus a bet-or-raise slider. Entirely driven by
/// `TableActionModel`; it knows nothing about the transport or the session.
struct ActionBar: View {
    let model: TableActionModel
    let onAction: (PlayerAction) -> Void

    @State private var amount: Chips = 0

    var body: some View {
        VStack(spacing: 12) {
            if let sizing = model.sizing {
                SizingSlider(sizing: sizing, amount: $amount, allInAmount: model.allInAmount, onAction: onAction)
            }
            HStack(spacing: 12) {
                if model.canFold {
                    Button("Fold", role: .destructive) { onAction(.fold) }
                }
                if model.canCheck {
                    Button("Check") { onAction(.check) }
                }
                if let callAmount = model.callAmount {
                    Button {
                        onAction(.call)
                    } label: {
                        Text("Call \(callAmount, format: .number)")
                    }
                }
                if let sizing = model.sizing, let action = model.sizedAction(amount) {
                    Button {
                        onAction(action)
                    } label: {
                        switch sizing {
                        case .bet: Text("Bet \(model.clamped(amount), format: .number)")
                        case .raise: Text("Raise to \(model.clamped(amount), format: .number)")
                        }
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding()
        // Fixed height keeps the table from jumping when the bar appears.
        .frame(maxWidth: .infinity, minHeight: 150)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .opacity(model.isActive ? 1 : 0)
        .disabled(!model.isActive)
        .onChange(of: model.sizing, initial: true) {
            amount = model.sizing?.range.lowerBound ?? 0
        }
    }
}

private struct SizingSlider: View {
    let sizing: TableActionModel.Sizing
    @Binding var amount: Chips
    let allInAmount: Chips?
    let onAction: (PlayerAction) -> Void

    private var range: ClosedRange<Chips> { sizing.range }

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(range.lowerBound, format: .number)
                Slider(
                    value: Binding(
                        get: { Double(amount) },
                        set: { amount = Chips($0.rounded()) }
                    ),
                    in: Double(range.lowerBound)...Double(range.upperBound),
                    step: 1
                )
                .disabled(range.lowerBound == range.upperBound)
                Text(range.upperBound, format: .number)
            }
            .font(.caption.monospacedDigit())
            HStack(spacing: 8) {
                Button("Min") { amount = range.lowerBound }
                Button("½ pot", action: {})
                    .hidden()  // Placeholder keeps layout stable; pot-relative sizing is a later step.
                if allInAmount != nil {
                    Button("All-in") { onAction(.allIn) }
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
}

#Preview("Facing a bet") {
    ActionBar(
        model: TableActionModel(legalActions: LegalActions(canFold: true, callAmount: 40, raiseRange: 100...1480, allInAmount: 1480)),
        onAction: { _ in }
    )
    .padding()
    .background(.green)
}

#Preview("No bet") {
    ActionBar(
        model: TableActionModel(legalActions: LegalActions(canFold: true, canCheck: true, betRange: 20...1480, allInAmount: 1480)),
        onAction: { _ in }
    )
    .padding()
    .background(.green)
}
