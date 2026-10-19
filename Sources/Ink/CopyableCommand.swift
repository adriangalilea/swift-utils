#if os(macOS) || os(iOS)
    import SwiftUI

    /// Copyable text, such as a shell command or pairing code: a monospaced chip whose
    /// trailing segment IS the button (hairline divider, its own hover
    /// raise), while the whole chip stays the click target. Copying
    /// confirms in place - Copy flips to a green ✓ Copied and reverts on
    /// its own; repeated clicks just restart the confirm. The copy itself is
    /// `CopyFeedback`, the one every Ink copy surface shares; for a value in a row
    /// rather than a chip on its own, `Copy`. `tip` is its tooltip, as `Copy`'s:
    /// the only one on its hover; without one, a cut command shows itself whole.
    ///
    /// The geometry is static BY CONSTRUCTION, the lesson this component
    /// encodes: every variable element sits in a fixed-size slot. The
    /// action label is sized by its widest state rendered invisibly, and
    /// the icon slot is pinned in BOTH dimensions - the glyphs differ
    /// in width and height, and either dimension left loose lets the chip
    /// breathe on the swap.
    public struct CopyableCommand: View {
        let command: String
        let font: Font
        let tip: String?
        @State private var feedback = CopyFeedback()
        @State private var hovering = false

        public init(_ command: String, font: Font = .caption.monospaced(), tip: String? = nil) {
            self.command = command
            self.font = font
            self.tip = tip
        }

        public var body: some View {
            Button {
                feedback.copy(command)
            } label: {
                HStack(spacing: 0) {
                    MiddleTruncate(command)
                        .font(font)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                    Rectangle()
                        .fill(.quaternary)
                        .frame(width: 1)
                    ZStack(alignment: .leading) {
                        ForEach(Self.words, id: \.self) { word in
                            HStack(spacing: 4) {
                                Color.clear.frame(width: 14, height: 14)
                                Text(word).font(.caption2.weight(.medium))
                            }
                            .hidden()
                        }
                        HStack(spacing: 4) {
                            CopyMark(feedback.state)
                                .font(.caption2.weight(.semibold))
                                .frame(width: 14, height: 14)
                            Text(word).font(.caption2.weight(.medium))
                        }
                        .foregroundStyle(tint)
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
            .accessibilityLabel(command)
            .accessibilityHint(String(localized: "Copy to clipboard", bundle: .module))
            .onDisappear { feedback.reset() }
            .onChange(of: command) { _, _ in feedback.reset() }
            .inkHover($hovering)
            .animation(.inkFlick, value: hovering)
            .inkTip(tip)
        }

        /// Every word the action slot can say: the slot is as wide as the widest.
        private static let words = [
            String(localized: "Copy", bundle: .module),
            String(localized: "Copied", bundle: .module),
            String(localized: "Retry", bundle: .module),
        ]

        private var word: String {
            switch feedback.state {
            case .idle: Self.words[0]
            case .copied: Self.words[1]
            case .failed: Self.words[2]
            }
        }

        private var tint: AnyShapeStyle {
            switch feedback.state {
            case .idle: AnyShapeStyle(.secondary)
            case .copied: AnyShapeStyle(.green)
            case .failed: AnyShapeStyle(.red)
            }
        }
    }
#endif
