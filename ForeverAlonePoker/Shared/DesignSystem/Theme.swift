import SwiftUI

/// Shared design tokens (tdr/0017). Views use these instead of literal
/// spacings, radii and colours so the whole app moves together.
enum Theme {
    enum Spacing {
        static let xSmall: CGFloat = 4
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let large: CGFloat = 16
        static let xLarge: CGFloat = 24
    }

    enum Radius {
        static let control: CGFloat = 14
        static let panel: CGFloat = 24
    }

    /// Tap target heights. The HIG minimum is 44 pt; the main table actions
    /// are bigger because many of our players are not used to small controls.
    enum Target {
        static let minimum: CGFloat = 44
        static let primary: CGFloat = 56
    }

    enum Palette {
        static let feltCenter = Color(red: 0.12, green: 0.45, blue: 0.3)
        static let feltEdge = Color(red: 0.04, green: 0.24, blue: 0.16)
        /// Marks whoever has to act. Always paired with a label or symbol.
        static let highlight = Color.yellow
    }
}

/// The table background: a calm felt gradient behind everything.
struct TableFelt: View {
    var body: some View {
        RadialGradient(
            colors: [Theme.Palette.feltCenter, Theme.Palette.feltEdge],
            center: .center,
            startRadius: 40,
            endRadius: 700
        )
        .ignoresSafeArea()
    }
}

extension View {
    /// A floating panel over the felt: Liquid Glass, or a solid dark material
    /// when the player asked for less transparency.
    func tablePanel(cornerRadius: CGFloat = Theme.Radius.panel) -> some View {
        modifier(TablePanel(cornerRadius: cornerRadius))
    }
}

private struct TablePanel: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if reduceTransparency {
            content.background(.black.opacity(0.75), in: shape)
        } else {
            content.glassEffect(.regular.tint(.black.opacity(0.25)), in: shape)
        }
    }
}
