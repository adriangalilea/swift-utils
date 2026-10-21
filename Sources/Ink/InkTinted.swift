import SwiftUI

// A control whose words carry its colour, and a status that is no control:
// the studio's pair for anything that needs the person (orange to fix, yellow
// to ask) and anything that is fine (a green check). One design language for
// both, on one material the host chooses.
//
//     Button("Allow…") { … }.buttonStyle(.inkTinted(.yellow))
//     InkStatusMark("checkmark", tint: .green)
//     someHost.inkMaterial(.flat)            // no Liquid Glass anywhere inside
//
// Liquid Glass, as Apple designs it: interactive from rest (`.interactive()`
// gives custom glass the reactions the system's glass buttons have; switched
// on only under the hand, it reacts to nothing), the colour in the words and
// never a filled slab, tint kept for a status that should stand out. Ink's own
// response on top (`inkHover`, a press), so the flat material answers too.

/// The surface a host's Ink controls stand on.
public enum InkMaterial: Sendable {
    /// Liquid Glass, the default.
    case glass
    /// A quiet neutral fill, for an app or a place that does not use glass.
    case flat
}

extension EnvironmentValues {
    @Entry public var inkMaterial: InkMaterial = .glass
}

extension View {
    /// The surface of every Ink control drawn inside.
    public func inkMaterial(_ material: InkMaterial) -> some View {
        environment(\.inkMaterial, material)
    }
}

/// The sizes every tinted control and mark share, by `.controlSize`, so a
/// mark beside a button is the button's height.
public struct InkControlMetrics: Sendable {
    public let font: CGFloat
    public let height: CGFloat
    public let inset: CGFloat

    public init(_ size: ControlSize) {
        switch size {
        case .mini: (font, height, inset) = (9.5, 18, 7)
        case .small: (font, height, inset) = (10.5, 22, 9)
        case .large, .extraLarge: (font, height, inset) = (13, 30, 14)
        default: (font, height, inset) = (11.5, 26, 11)
        }
    }
}

/// A button whose words (and symbols) carry its colour, on the host's
/// material: a capsule of interactive Liquid Glass, or a quiet fill. Under the
/// hand the surface lifts; pressed, it gives. Its size follows `.controlSize`.
public struct InkTintedStyle: ButtonStyle {
    let tint: Color

    public init(_ tint: Color) { self.tint = tint }

    public func makeBody(configuration: Configuration) -> some View {
        Styled(tint: tint, configuration: configuration)
    }

    private struct Styled: View {
        @Environment(\.isEnabled) private var enabled
        @Environment(\.inkMaterial) private var material
        @Environment(\.controlSize) private var size
        @State private var hovering = false
        let tint: Color
        let configuration: Configuration

        var body: some View {
            let metrics = InkControlMetrics(size)
            configuration.label
                .font(.system(size: metrics.font, weight: .semibold))
                .lineLimit(1)
                .foregroundStyle(tint)
                .padding(.horizontal, metrics.inset)
                .frame(minHeight: metrics.height)
                .background {
                    ZStack {
                        if material == .flat { Capsule().fill(.primary.opacity(0.08)) }
                        Capsule().fill(.primary.opacity(hovering ? 0.08 : 0))
                        Capsule().fill(.primary.opacity(configuration.isPressed ? 0.12 : 0))
                    }
                }
                .modifier(InkGlass(on: material == .glass, in: Capsule()))
                .contentShape(Capsule())
                .scaleEffect(configuration.isPressed ? 0.96 : 1)
                .opacity(enabled ? 1 : 0.45)
                .inkHover($hovering)
                .animation(.inkFlick, value: hovering)
                .animation(.inkFlick, value: configuration.isPressed)
        }
    }

}

/// A control's glass: interactive from rest, so it reacts the way the
/// system's own glass buttons do (switched on only under the hand, it reacts
/// to nothing). Off on the flat material.
struct InkGlass<S: Shape>: ViewModifier {
    let on: Bool
    let shape: S

    init(on: Bool, in shape: S) {
        self.on = on
        self.shape = shape
    }

    func body(content: Content) -> some View {
        if on {
            content.glassEffect(.regular.interactive(), in: shape)
        } else {
            content
        }
    }
}

extension ButtonStyle where Self == InkTintedStyle {
    /// A button whose words carry `tint`: something to fix, something to ask.
    public static func inkTinted(_ tint: Color) -> InkTintedStyle { InkTintedStyle(tint) }
}

/// A status, never a control: a circle the height of the controls beside it
/// (`.controlSize`), the symbol in `tint` on glass that carries the same
/// colour faintly (or a faint fill of it on the flat material). One colour,
/// alpha the only variable: never white on a saturated disc. Beside a tinted
/// button it reads as the same family and as plainly not pressable.
public struct InkStatusMark: View {
    let symbol: String
    let tint: Color
    @Environment(\.inkMaterial) private var material
    @Environment(\.controlSize) private var size

    public init(_ symbol: String, tint: Color) {
        self.symbol = symbol
        self.tint = tint
    }

    public var body: some View {
        let metrics = InkControlMetrics(size)
        let mark = Image(systemName: symbol)
            .font(.system(size: metrics.font, weight: .bold))
            .foregroundStyle(tint)
            .frame(width: metrics.height, height: metrics.height)
        switch material {
        case .glass:
            mark.glassEffect(.regular.tint(tint.opacity(0.18)), in: Circle())
        case .flat:
            mark.background(Circle().fill(tint.opacity(0.16)))
        }
    }
}
