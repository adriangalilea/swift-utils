import SwiftUI

// Keys drawn as keys, designed once (the studio's `kbd`, ui registry
// `kbd.tsx`: one cap shape for every shortcut, wherever it appears). Every
// measure follows the cap's own text size, so a cap is the same shape inline
// beside a 13 pt label or alone at 11 pt.
//
// - `InkKey`: one key ("y", "↩", "esc", "⇪"), on a plain surface a faint
//   face with a deeper foot, on a prominent (accent) button a translucent
//   white one. `lit` is a held key: filled in its tint (the talk key held).
// - `InkKeyed`: a button's label that carries its own key, the label then the
//   cap: a button says how to press it, so no line of keys elsewhere has to.
// - `InkCloseButton`: the way out, an X and its esc cap as ONE control: a
//   click and the key are the same action, drawn once.

/// One key as a cap.
public struct InkKey: View {
    public enum Surface: Sendable { case plain, prominent }

    let cap: String
    let surface: Surface
    let lit: Bool
    let tint: Color
    let size: CGFloat

    public init(
        _ cap: String, on surface: Surface = .plain, lit: Bool = false, tint: Color = .accentColor,
        size: CGFloat = 11
    ) {
        self.cap = cap
        self.surface = surface
        self.lit = lit
        self.tint = tint
        self.size = size
    }

    private var face: AnyShapeStyle {
        if lit { return AnyShapeStyle(tint.opacity(0.9)) }
        switch surface {
        case .plain: return AnyShapeStyle(.primary.opacity(0.09))
        case .prominent: return AnyShapeStyle(.white.opacity(0.22))
        }
    }

    private var ink: AnyShapeStyle {
        if lit || surface == .prominent { return AnyShapeStyle(.white) }
        return AnyShapeStyle(.primary.opacity(0.75))
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.36, style: .continuous)
        Text(cap)
            .font(.system(size: size, weight: .medium))
            .monospacedDigit()
            .lineLimit(1)
            .padding(.horizontal, size * 0.42)
            .frame(minWidth: size * 1.7, minHeight: size * 1.6)
            .foregroundStyle(ink)
            .background(face, in: shape)
            // The foot: a key's lower edge, a hair deeper than its rim.
            .overlay(shape.strokeBorder(.primary.opacity(lit ? 0 : 0.14), lineWidth: 0.5))
            .overlay(alignment: .bottom) {
                shape.fill(.primary.opacity(lit ? 0 : 0.16))
                    .frame(height: 1.2)
                    .padding(.horizontal, size * 0.2)
                    .offset(y: 0.4)
            }
            .fixedSize()
            .animation(.easeOut(duration: 0.12), value: lit)
            .accessibilityHidden(true)
    }
}

/// A button's label with its key after it: "yes [y]", "Submit [↩]".
public struct InkKeyed: View {
    let label: String
    let key: String?
    let surface: InkKey.Surface

    public init(_ label: String, key: String?, on surface: InkKey.Surface = .plain) {
        self.label = label
        self.key = key
        self.surface = surface
    }

    public var body: some View {
        HStack(spacing: 7) {
            Text(label)
            if let key { InkKey(key, on: surface, size: 10.5) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityHint(key.map { "key \($0)" } ?? "")
    }
}

/// The way out: an X in a round well and its esc cap, one control. The
/// host decides what out means (Later, Cancel); this only draws it and
/// takes the click. Never keyboard-focusable: esc is the key's, a click the
/// pointer's.
public struct InkCloseButton: View {
    let key: String?
    let action: () -> Void
    @State private var hovering = false

    public init(key: String? = "esc", action: @escaping () -> Void) {
        self.key = key
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            // ONE surface: the key's word and the X in a single capsule, so
            // the key and the click read as the same act.
            HStack(spacing: 5) {
                if let key {
                    Text(key)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.primary.opacity(hovering ? 0.85 : 0.55))
                }
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.primary.opacity(hovering ? 0.9 : 0.6))
            }
            .padding(.horizontal, key == nil ? 6 : 8)
            .frame(minWidth: 22, minHeight: 22)
            .background(Capsule().fill(.primary.opacity(hovering ? 0.16 : 0.08)))
            .overlay(Capsule().strokeBorder(.primary.opacity(0.1), lineWidth: 0.5))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .inkHover($hovering)
        .animation(.easeOut(duration: 0.12), value: hovering)
        .accessibilityLabel("Close")
    }
}
