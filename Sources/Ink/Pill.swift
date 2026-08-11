import SwiftUI

// THE pill. One rule makes it a pill and not a botch: the leading slot -
// avatar or icon, ALWAYS - is a CIRCLE whose diameter is the pill's height,
// sitting flush at the left end, so its curvature IS the cap's curvature
// (same radius, same center - the two curves coincide). Trailing text
// breathes with cap-radius padding so the right side wears the same
// geometry.

public struct Pill<Leading: View, Content: View>: View {
    let height: CGFloat
    let tint: Color
    let leading: Leading
    let content: Content

    public init(
        height: CGFloat = 64,
        tint: Color = .inkRest,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder content: () -> Content
    ) {
        self.height = height
        self.tint = tint
        self.leading = leading()
        self.content = content()
    }

    public var body: some View {
        HStack(spacing: height * 0.18) {
            leading
                .frame(width: height, height: height)
                .clipShape(Circle())   // round, always - diameter = height = the cap's own circle
            content
                .padding(.trailing, height * 0.42)
        }
        .frame(height: height)
        .background(tint, in: Capsule())
        .contentShape(Capsule())       // hit/focus shape = the visible shape
    }
}

/// A person as a pill: portrait filling the left cap, name (+ optional
/// quiet detail line). The portrait arrives as a view so the host owns
/// image loading/auth; it should fill its square (resizable + fill).
public struct PersonPill<Portrait: View>: View {
    let name: String
    let detail: String?
    let height: CGFloat
    let portrait: Portrait

    public init(name: String, detail: String? = nil, height: CGFloat = 64, @ViewBuilder portrait: () -> Portrait) {
        self.name = name
        self.detail = detail
        self.height = height
        self.portrait = portrait()
    }

    public var body: some View {
        Pill(height: height) {
            portrait
        } content: {
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(.callout.weight(.medium)).lineLimit(1)
                if let detail, !detail.isEmpty {
                    Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
    }
}

/// The pill's button dress: focus/press scale with a grounding shadow and
/// NO platter - the capsule is the whole visual. The host row must give
/// the lift room (padding) and the focused pill the top of the stack
/// (zIndex), or it clips at the row's edge and slides UNDER its neighbor.
public struct PillButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        Styled(configuration: configuration)
    }

    private struct Styled: View {
        @Environment(\.isFocused) private var focused
        let configuration: Configuration

        var body: some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? 0.96 : focused ? 1.08 : 1)
                .shadow(color: .black.opacity(focused ? 0.45 : 0), radius: 16, y: 10)
                .animation(.inkFlick, value: focused)
                .animation(.inkFlick, value: configuration.isPressed)
        }
    }
}
