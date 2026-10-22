import SwiftUI

/// Shared design tokens (tdr/0017, tdr/0018). Views use these instead of
/// literal spacings, radii, colours and animations so the whole app moves
/// together.
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
        static let tile: CGFloat = 20
        static let panel: CGFloat = 24
    }

    /// Tap target heights. The HIG minimum is 44 pt; the main table actions
    /// are bigger because many of our players are not used to small controls.
    enum Target {
        static let minimum: CGFloat = 44
        static let primary: CGFloat = 56
    }

    /// Widths that keep content readable on wide windows (iPad, an open
    /// foldable) instead of stretching edge to edge.
    enum Width {
        /// Floating cards such as "Connection lost" or a purchase celebration.
        static let card: CGFloat = 360
        /// Home tiles: below twice this, one column.
        static let tile: CGFloat = 300
        /// Scrolling pages of tiles and text.
        static let readable: CGFloat = 900
    }

    enum Palette {
        static let feltCenter = Color(red: 0.12, green: 0.45, blue: 0.3)
        static let feltEdge = Color(red: 0.04, green: 0.24, blue: 0.16)
        /// Marks whoever has to act. Always paired with a label or symbol.
        static let highlight = Color.yellow
        /// Celebrations: a won pot, an unlocked skin.
        static let celebration = Color.orange
    }

    /// Named animations, so the same kind of change always moves the same way.
    enum Motion {
        /// A card leaving the dealer's hand.
        static let deal = Animation.spring(duration: 0.35, bounce: 0.12)
        /// Layout following a new arrangement, a seat change.
        static let layout = Animation.smooth(duration: 0.35)
        /// Chip counts and other numbers ticking.
        static let count = Animation.snappy(duration: 0.3)
        /// Something appearing that the player should notice.
        static let reveal = Animation.spring(duration: 0.5, bounce: 0.3)
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
        tableGlass(in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    /// Liquid Glass in any shape over the felt, darkened slightly so white
    /// text keeps its contrast. With Reduce Transparency on it becomes a
    /// solid fill of the same shape.
    func tableGlass(in shape: some Shape, tint: Color = .black.opacity(0.25), isInteractive: Bool = false) -> some View {
        modifier(TableGlass(shape: shape, tint: tint, isInteractive: isInteractive))
    }

    /// Liquid Glass for content over the system background (home tiles,
    /// store celebrations), with the same Reduce Transparency fallback.
    func surfaceGlass(in shape: some Shape, tint: Color? = nil, isInteractive: Bool = false) -> some View {
        modifier(SurfaceGlass(shape: shape, tint: tint, isInteractive: isInteractive))
    }

    /// Liquid Glass buttons where the system has them (iOS 26 and later),
    /// bordered buttons of the same weight before that.
    @ViewBuilder
    func glassButtonStyle(_ kind: GlassButtonKind = .regular) -> some View {
        if #available(iOS 26, *) {
            switch kind {
            case .regular: buttonStyle(.glass)
            case .prominent: buttonStyle(.glassProminent)
            }
        } else {
            switch kind {
            case .regular: buttonStyle(.bordered)
            case .prominent: buttonStyle(.borderedProminent)
            }
        }
    }

    /// `animation(_:value:)` that stands still when Reduce Motion is on.
    /// Use it for movement; colour and opacity changes can keep `animation`.
    func motion<V: Equatable>(_ animation: Animation?, value: V) -> some View {
        modifier(ReducibleAnimation(animation: animation, value: value))
    }
}

enum GlassButtonKind {
    case regular
    /// The main action: tinted, filled glass.
    case prominent
}

/// Groups glass shapes so they render together and morph into each other
/// (`GlassEffectContainer`, iOS 26 and later). Before iOS 26 it is a
/// plain wrapper around its content.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        if #available(iOS 26, *) {
            GlassEffectContainer(spacing: spacing) { content() }
        } else {
            content()
        }
    }
}

/// Glass over the felt. Order of preference: solid fill when the player
/// asked for less transparency, Liquid Glass on iOS 26 and later, a dark
/// material before that.
private struct TableGlass<S: Shape>: ViewModifier {
    let shape: S
    let tint: Color
    let isInteractive: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(.black.opacity(0.75), in: shape)
        } else if #available(iOS 26, *) {
            content.glassEffect(.regular.tint(tint).interactive(isInteractive), in: shape)
        } else {
            content.background {
                shape.fill(.ultraThinMaterial)
                    .overlay(shape.fill(tint))
                    .environment(\.colorScheme, .dark)
            }
        }
    }
}

/// Glass over the system background, with the same fallbacks as `TableGlass`.
private struct SurfaceGlass<S: Shape>: ViewModifier {
    let shape: S
    let tint: Color?
    let isInteractive: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(Color(.secondarySystemGroupedBackground), in: shape)
        } else if #available(iOS 26, *) {
            content.glassEffect(.regular.tint(tint).interactive(isInteractive), in: shape)
        } else {
            content.background {
                shape.fill(.regularMaterial)
                    .overlay(shape.fill(tint?.opacity(0.25) ?? .clear))
            }
        }
    }
}

private struct ReducibleAnimation<V: Equatable>: ViewModifier {
    let animation: Animation?
    let value: V
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}
