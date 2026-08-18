import SwiftUI

/// THE styling ladder for the studio's dark-glass surfaces. Five roles, no
/// raw values at call sites - a view names WHAT a surface is, never how
/// transparent it is. Products build on these atoms (Keymap's panel and
/// overlay today; AppSettings and the credits pane next) so surfaces can
/// never drift apart.
///
/// tailwind-discipline, Swift-shaped: when a second theme appears, this
/// becomes an Environment-injected struct and these turn into its defaults.
extension ShapeStyle where Self == Color {
    /// A resting interactive surface: a filter field, an idle ＋ slot.
    public static var inkRest: Color { .white.opacity(0.12) }
    /// A raised element: keycaps, chips, the focused field.
    public static var inkRaised: Color { .white.opacity(0.18) }
    /// A hovered control - unmistakably live.
    public static var inkHover: Color { .white.opacity(0.32) }
    /// The cursor/flash row - paired with `inkEdge` as its border.
    public static var inkSelection: Color { .white.opacity(0.22) }
    /// The stroke that separates a selected/active region from the glass.
    public static var inkEdge: Color { .white.opacity(0.38) }
    /// THE highlight color - the one hue for "a moment the user marked"
    /// (karaoke gold words, scrubber ticks/spans, timeline markers).
    /// One color, alpha tiers only, per the flare rule: full for the mark
    /// itself, ~0.55 for spans/corridors. Never a second yellow per app.
    public static var inkGold: Color { .yellow }
}

/// The radius ladder - four sizes, named by WHAT wears them, so two
/// surfaces of the same kind can never round differently.
extension CGFloat {
    /// Keycaps, small pills, recording chips.
    public static let inkChip: CGFloat = 4
    /// A cursor/hover row highlight.
    public static let inkRow: CGFloat = 6
    /// Fields and inner surfaces.
    public static let inkField: CGFloat = 8
    /// The outer shell of a floating panel/card.
    public static let inkPanel: CGFloat = 18
}

/// The motion ladder - two speeds, no bespoke durations. Feedback that
/// tracks the hand (hover, cursor, tips) flicks; structural change
/// (fades, reveals) settles.
extension Animation {
    public static let inkFlick: Animation = .easeOut(duration: 0.12)
    public static let inkSettle: Animation = .easeOut(duration: 0.15)
}

/// The spacing ladder - the four gaps a surface composes from.
extension CGFloat {
    /// Glyph-to-glyph inside one control.
    public static let inkTight: CGFloat = 4
    /// Sibling controls in one row.
    public static let inkGap: CGFloat = 8
    /// Rows within a section.
    public static let inkLane: CGFloat = 12
    /// Section to section.
    public static let inkBlock: CGFloat = 16
}

extension View {
    /// A column-header label (the plane headers, any grid's column caps) -
    /// ONE style; every surface wears it, so two surfaces can never drift.
    /// `tint` covers accent-tinted headers (the manifest card) without the
    /// caller fighting the style's own color.
    public func planeHeaderStyle(_ tint: some ShapeStyle = HierarchicalShapeStyle.secondary)
        -> some View
    {
        font(.caption2.weight(.semibold))
            .textCase(.uppercase)
            .foregroundStyle(tint)
    }
}

/// The one key-cap. Every surface renders combos through it - never
/// re-styled per site.
public struct ShortcutBadge: View {
    let text: String
    public init(_ text: String) { self.text = text }

    public var body: some View {
        Text(text)
            .font(.caption2.monospacedDigit().weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: .inkChip))
    }
}

// Pointer-shaped micro-components (.onHover/.help) - mac-only by nature,
// not by neglect: a hover affordance has no meaning under a focus engine.
#if os(macOS)
    /// A bound accelerator: a keycap showing the combo (glyphs read as the keys
    /// they are). The chip IS the remove control - on hover it turns red and
    /// shows an ✕ over the combo, the tag-delete idiom. Zero reserved space (no
    /// external badge), so sibling chips pack tight and align perfectly with ＋.
    public struct ComboChip: View {
        let display: String
        let remove: () -> Void
        @State private var hovering = false

        public init(_ display: String, remove: @escaping () -> Void) {
            self.display = display
            self.remove = remove
        }

        // A one-glyph combo (←, [, ⌫) gets a square frame, so the Capsule below
        // renders as a perfect circle; multi-glyph combos (Space, ⌘←) stay capsules.
        private var single: Bool { display.count == 1 }

        public var body: some View {
            Button(action: remove) {
                ZStack {
                    Text(verbatim: display)
                        .font(.callout.monospaced())
                        .opacity(hovering ? 0 : 1)
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .opacity(hovering ? 1 : 0)
                }
                .frame(width: single ? 24 : nil, height: 24)
                .padding(.horizontal, single ? 0 : 9)
                .background(
                    hovering
                        ? AnyShapeStyle(.red.opacity(0.9))
                        : AnyShapeStyle(.quaternary.opacity(0.85)),
                    in: Capsule()
                )
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help(String(localized: "Remove this shortcut", bundle: .module))
            .onHover { hovering = $0 }
            .animation(.inkFlick, value: hovering)
        }
    }

    /// The ＋ that arms an add - a visible slot, not a ghost: a filled circle
    /// that brightens and sharpens on hover so it reads as pressable.
    public struct AddSlot: View {
        let arm: () -> Void
        @State private var hovering = false

        public init(arm: @escaping () -> Void) { self.arm = arm }

        public var body: some View {
            Button(action: arm) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(hovering ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                    .frame(width: 18, height: 18)
                    .background(hovering ? Color.inkHover : Color.inkRest, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .animation(.inkFlick, value: hovering)
        }
    }
#endif

/// THE LAW OF NAVIGABLE SURFACES: a keyboard cursor must never leave its
/// own viewport. Any scrollable list/gallery a cursor walks keeps the
/// focused item CENTERED while scrolling is possible (clamped naturally at
/// the edges - SwiftUI's .center anchor does the right thing at both ends).
/// This component IS the pattern: wrap the content, give every row
/// `.id(...)`, bind the cursor - the lock follows. Hand-rolling this per
/// surface is how the cursor-below-the-fold sin keeps recurring; don't.
public struct CursorScrollView<Cursor: Hashable, Content: View>: View {
    let cursor: Cursor?
    let content: Content

    public init(cursor: Cursor?, @ViewBuilder content: () -> Content) {
        self.cursor = cursor
        self.content = content()
    }

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                content
            }
            .onChange(of: cursor) { _, target in
                guard let target else { return }
                withAnimation(.inkFlick) {
                    proxy.scrollTo(target, anchor: .center)
                }
            }
            // A surface that APPEARS with a live cursor centers it too - the
            // law holds from the first frame, not the first keypress.
            .onAppear {
                if let cursor { proxy.scrollTo(cursor, anchor: .center) }
            }
        }
    }
}
