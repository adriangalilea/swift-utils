import SwiftUI

// The answer's buttons, designed once. Drawn by Ink itself, never by the
// platform's bordered styles: those grey out whenever their window does not
// hold the keyboard, and a floating HUD that has not taken the keyboard yet
// is exactly such a window (it only takes it on hover or after typing
// stops), so its yes read grey until hovered. Here the look depends on
// nothing but the role, enabled and hover.
//
// - `.inkProminent`: the yes. The host's tint, deepened so white text reads
//   on any hue (a bright green or orange under white text does not).
// - `.ink`: everything else. A faint fill, the primary ink.

public struct InkButtonStyle: ButtonStyle {
    public enum Role: Sendable { case prominent, plain }

    let role: Role
    /// The label's trailing inset: the cap's padding, or less when the
    /// label ends in its own round well (a Touch ID mark) that sits
    /// concentric with the cap.
    let trailing: CGFloat

    public init(_ role: Role, trailing: CGFloat = Self.capInset) {
        self.role = role
        self.trailing = trailing
    }

    /// The horizontal inset of a label inside the capsule.
    public static let capInset: CGFloat = 14
    /// The capsule's height: one line of 13 pt with room to breathe.
    public static let height: CGFloat = 30

    public func makeBody(configuration: Configuration) -> some View {
        Styled(role: role, trailing: trailing, configuration: configuration)
    }

    private struct Styled: View {
        @Environment(\.isEnabled) private var enabled
        @State private var hovering = false
        let role: Role
        let trailing: CGFloat
        let configuration: Configuration

        var body: some View {
            configuration.label
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .foregroundStyle(
                    role == .prominent ? AnyShapeStyle(.white) : AnyShapeStyle(.primary)
                )
                .padding(.leading, InkButtonStyle.capInset)
                .padding(.trailing, trailing)
                .frame(minHeight: InkButtonStyle.height)
                .background {
                    ZStack {
                        switch role {
                        case .prominent:
                            Capsule().fill(.tint)
                            // Deepened: white text on the tint's own
                            // brightness is unreadable for green and orange.
                            Capsule().fill(.black.opacity(0.3))
                        case .plain:
                            // The primary ink, faint: white at a tenth was
                            // a fill only a dark ground could show.
                            Capsule().fill(.primary.opacity(0.1))
                        }
                        Capsule().fill(.primary.opacity(hovering ? 0.06 : 0))
                        Capsule().fill(.primary.opacity(configuration.isPressed ? 0.12 : 0))
                    }
                }
                .contentShape(Capsule())
                .opacity(enabled ? 1 : 0.45)
                .inkHover($hovering)
                .animation(.inkFlick, value: hovering)
                .animation(.inkFlick, value: configuration.isPressed)
        }
    }
}

extension ButtonStyle where Self == InkButtonStyle {
    /// The yes: the tint, deepened, white text.
    public static var inkProminent: InkButtonStyle { InkButtonStyle(.prominent) }
    /// Every other answer: a faint fill, the primary ink.
    public static var ink: InkButtonStyle { InkButtonStyle(.plain) }
}

/// A toolbar's icon, designed once: one size, quiet at rest (the secondary ink, no
/// fill), a faint fill under the hand, and `on` (a mode that holds: motion playing,
/// a pane shown, the chosen arrangement) a raised fill and the primary ink, never the
/// accent, which belongs to a yes. Every icon of a bar wears it, so a bar of a dozen
/// controls reads as one row, the host's own among them.
public struct InkToolStyle: ButtonStyle {
    let on: Bool

    public init(on: Bool = false) { self.on = on }

    /// The icon's well: a square a toolbar row centres.
    public static let side: CGFloat = 28

    public func makeBody(configuration: Configuration) -> some View {
        Styled(on: on, configuration: configuration)
    }

    private struct Styled: View {
        @Environment(\.isEnabled) private var enabled
        @State private var hovering = false
        let on: Bool
        let configuration: Configuration

        var body: some View {
            configuration.label
                .font(.system(size: 13, weight: .medium))
                .symbolVariant(on ? .fill : .none)
                .foregroundStyle(
                    on || hovering ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary)
                )
                .frame(minWidth: InkToolStyle.side, minHeight: InkToolStyle.side)
                .background {
                    ZStack {
                        RoundedRectangle(cornerRadius: .inkField, style: .continuous)
                            .fill(on ? Color.inkRaised : .clear)
                        RoundedRectangle(cornerRadius: .inkField, style: .continuous)
                            .fill(.primary.opacity(hovering && !on ? 0.08 : 0))
                        RoundedRectangle(cornerRadius: .inkField, style: .continuous)
                            .fill(.primary.opacity(configuration.isPressed ? 0.12 : 0))
                    }
                }
                .contentShape(Rectangle())
                .opacity(enabled ? 1 : 0.35)
                .inkHover($hovering)
                .animation(.inkFlick, value: hovering)
                .animation(.inkFlick, value: on)
        }
    }
}

extension ButtonStyle where Self == InkToolStyle {
    /// A toolbar icon at rest.
    public static var inkTool: InkToolStyle { InkToolStyle() }
    /// A toolbar icon whose mode is on.
    public static func inkTool(on: Bool) -> InkToolStyle { InkToolStyle(on: on) }
}
