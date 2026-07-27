import SwiftUI

/// THE styling ladder for Keymap's dark-glass surfaces (the cheat panel,
/// the overlay). Five roles, no raw values at call sites - a view names
/// WHAT a surface is, never how transparent it is. The settings grid keeps
/// system semantic styles (it lives on the system Form background, light or
/// dark); this ladder is for surfaces the library draws on its own glass.
///
/// tailwind-discipline, Swift-shaped: when a second theme appears, this
/// becomes an Environment-injected struct and these turn into its defaults.
extension View {
    /// The plane column header (In-app / From any app) - ONE style; the
    /// settings grid and the cheat panel both wear it, so the two surfaces
    /// can never drift apart again.
    func planeHeaderStyle() -> some View {
        font(.caption2.weight(.semibold))
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
    }
}

extension ShapeStyle where Self == Color {
    /// A resting interactive surface: the filter field, an idle ＋ slot.
    static var inkRest: Color { .white.opacity(0.12) }
    /// A raised element: keycaps, chips, the focused field.
    static var inkRaised: Color { .white.opacity(0.18) }
    /// A hovered control - unmistakably live.
    static var inkHover: Color { .white.opacity(0.32) }
    /// The cursor/flash row - paired with `inkEdge` as its border.
    static var inkSelection: Color { .white.opacity(0.22) }
    /// The stroke that separates a selected/active region from the glass.
    static var inkEdge: Color { .white.opacity(0.38) }
}
