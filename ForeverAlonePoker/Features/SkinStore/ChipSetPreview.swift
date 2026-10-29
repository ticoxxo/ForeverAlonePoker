import SwiftUI
import SkinKit

/// A few chips of a set fanned out from a stack, for store rows, the unlock
/// panel and refund rows (tdr/0027). Draws whatever chip skin is in the
/// environment, so callers set `store.previewSkin(for:)`.
struct ChipFanView: View {
    var isFannedOut = true
    static let shown: [ChipDenomination] = [.init(10), .init(1_000), .init(100_000)]

    var body: some View {
        GeometryReader { proxy in
            let chip = min(proxy.size.height, proxy.size.width / 2)
            ZStack {
                ForEach(Array(Self.shown.enumerated()), id: \.offset) { index, denomination in
                    ChipView(denomination: denomination, face: .top, size: .large)
                        .frame(width: chip, height: chip)
                        .offset(x: isFannedOut ? CGFloat(index - 1) * chip * 0.5 : 0)
                        .shadow(radius: 1, y: 1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(2, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// Every chip of a set, smallest first, with its value: the enlarged store
/// preview.
struct ChipSetGridView: View {
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: Theme.Spacing.medium)], spacing: Theme.Spacing.medium) {
            ForEach(ChipDenomination.all, id: \.self) { denomination in
                VStack(spacing: Theme.Spacing.xSmall) {
                    ChipView(denomination: denomination, face: .top, size: .large)
                        .frame(width: 56, height: 56)
                    Text(denomination.value, format: .number)
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                }
            }
        }
    }
}
