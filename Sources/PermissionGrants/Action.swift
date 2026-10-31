#if os(macOS) || os(iOS) || os(watchOS)
    import Ink
    import SwiftUI

    extension PermissionGrant {
        /// The hue a standing's action wears: orange for something to fix,
        /// the quieter yellow for an offer not answered yet.
        static func hue(_ grade: Standing.Grade) -> Color {
            grade == .broken ? .orange : .yellow
        }
    }

    extension View {
        /// Return presses the surface's one way on; a watch has no keyboard, so there it is the tap alone.
        func grantDefaultAction(_ on: Bool = true) -> some View {
            #if os(watchOS)
                self
            #else
                keyboardShortcut(on ? .defaultAction : nil)
            #endif
        }
    }

    /// THE grant action, the one control every surface draws (a row's, a
    /// card's, a page's, a chip): Ink's tinted button (`.inkTinted`, the
    /// studio's control language: its words in the hue, on the host's
    /// material, `.inkMaterial(.flat)` for no glass) with a ↗, since it goes
    /// somewhere (a prompt, Settings, a move). The label is told whether the
    /// person is on it (a chip swaps its words for the fix then).
    struct GrantAction<Label: View>: View {
        let hue: Color
        let fill: Bool
        let action: () -> Void
        @ViewBuilder let label: (_ engaged: Bool) -> Label

        @Environment(\.controlSize) private var size
        @State private var hovering = false
        @FocusState private var focused: Bool

        var body: some View {
            let metrics = InkControlMetrics(size)
            Button(action: action) {
                HStack(spacing: 6) {
                    label(hovering || focused)
                    if fill { Spacer(minLength: 0) }
                    Image(systemName: "arrow.up.forward")
                        .font(.system(size: metrics.font - 2, weight: .bold))
                }
                .frame(maxWidth: fill ? .infinity : nil, alignment: .leading)
            }
            .buttonStyle(.inkTinted(hue))
            .focused($focused)
            .inkHover($hovering)
            .animation(.inkFlick, value: hovering || focused)
        }
    }

    /// A standing that needs nothing: good is Ink's status mark (a green
    /// check in a circle the actions' height, plainly no button); unknown is
    /// the quiet word, since the app can't see it and neither vouches nor
    /// warns.
    struct GrantMark: View {
        let grade: PermissionGrant.Standing.Grade

        var body: some View {
            if grade == .good {
                InkStatusMark("checkmark", tint: .green).accessibilityLabel("allowed")
            } else {
                Text("unknown").font(.caption.monospaced()).foregroundStyle(.tertiary)
            }
        }
    }
#endif
