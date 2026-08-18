#if os(macOS)
    import AppKit
    import SwiftUI

    /// A shell command the user must run elsewhere: a monospaced chip whose
    /// trailing segment IS the button (hairline divider, its own hover
    /// raise), while the whole chip stays the click target. Copying
    /// confirms in place - Copy flips to a green ✓ Copied and reverts on
    /// its own; repeated clicks just restart the confirm.
    ///
    /// The geometry is static BY CONSTRUCTION, the lesson this component
    /// encodes: every variable element sits in a fixed-size slot. The
    /// action label is sized by its wider state rendered invisibly, and
    /// the icon slot is pinned in BOTH dimensions - the two glyphs differ
    /// in width and height, and either dimension left loose lets the chip
    /// breathe on the swap.
    public struct CopyableCommand: View {
        let command: String
        @State private var copied = false
        @State private var hovering = false
        @State private var revert: Task<Void, Never>?

        public init(_ command: String) { self.command = command }

        public var body: some View {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(command, forType: .string)
                withAnimation(.easeOut(duration: 0.12)) { copied = true }
                revert?.cancel()
                revert = Task {
                    try? await Task.sleep(for: .seconds(1.6))
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeOut(duration: 0.25)) { copied = false }
                }
            } label: {
                HStack(spacing: 0) {
                    Text(command)
                        .font(.caption.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                    Rectangle()
                        .fill(.quaternary)
                        .frame(width: 1)
                    ZStack(alignment: .leading) {
                        HStack(spacing: 4) {
                            Color.clear.frame(width: 14, height: 14)
                            Text("Copied", bundle: .module).font(.caption2.weight(.medium))
                        }
                        .hidden()
                        HStack(spacing: 4) {
                            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                .font(.caption2.weight(.semibold))
                                .contentTransition(.symbolEffect(.replace))
                                .frame(width: 14, height: 14)
                            Text(copied ? "Copied" : "Copy", bundle: .module)
                                .font(.caption2.weight(.medium))
                        }
                        .foregroundStyle(
                            copied ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.quaternary.opacity(hovering ? 0.95 : 0.45))
                }
                .background(.quaternary.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .contentShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
            .help(String(localized: "Copy to clipboard", bundle: .module))
        }
    }
#endif
