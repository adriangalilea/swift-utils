#if os(macOS) || os(iOS)
    #if os(macOS)
        import AppKit
    #else
        import UIKit
    #endif
    import SwiftUI

    /// THE copy action: writes to the pasteboard and says, in place, that it worked.
    /// Every copy surface in Ink stands on it (`Copy`, `CopyableCommand`), so they
    /// confirm alike and for as long; a surface of its own takes one as `@State` and
    /// draws `CopyMark(feedback.state)`. The same contract as ui's `useCopy`.
    @MainActor @Observable
    public final class CopyFeedback {
        public enum State: Sendable { case idle, copied, failed }

        /// How long a copy admits it worked: read at a glance, never long enough to
        /// stand in the way of a second copy.
        public static let confirmFor: Duration = .milliseconds(1400)

        public private(set) var state: State = .idle
        private var revert: Task<Void, Never>?

        public init() {}

        /// Empty is no copy: writing "" would wipe what the clipboard held.
        public func copy(_ text: String) {
            revert?.cancel()
            guard !text.isEmpty else {
                state = .idle
                return
            }
            #if os(macOS)
                NSPasteboard.general.clearContents()
                let wrote = NSPasteboard.general.setString(text, forType: .string)
            #else
                UIPasteboard.general.string = text
                let wrote = true
            #endif
            withAnimation(.inkFlick) { state = wrote ? .copied : .failed }
            guard wrote else { return }
            revert = Task {
                try? await Task.sleep(for: Self.confirmFor)
                guard !Task.isCancelled else { return }
                withAnimation(.inkSettle) { self.state = .idle }
            }
        }

        /// Back to idle at once: the value changed under it, or its view left.
        public func reset() {
            revert?.cancel()
            state = .idle
        }
    }

    /// The copy glyph in its three states, one drawing for every surface. Size and
    /// colour are the caller's (`.font`, `.foregroundStyle`); a failure is the only
    /// state that brings its own colour.
    public struct CopyMark: View {
        let state: CopyFeedback.State

        public init(_ state: CopyFeedback.State) { self.state = state }

        public var body: some View {
            Image(systemName: symbol)
                .contentTransition(.symbolEffect(.replace))
                .foregroundStyle(
                    state == .failed ? AnyShapeStyle(.red) : AnyShapeStyle(.foreground)
                )
                .accessibilityHidden(true)
        }

        private var symbol: String {
            switch state {
            case .idle: "doc.on.doc"
            case .copied: "checkmark"
            case .failed: "exclamationmark.circle"
            }
        }
    }

    /// The text itself is the button: an address, a hash, an order number in a row.
    /// The mark waits beside it, shown under the pointer and while it confirms, so a
    /// column of values reads as values and not as a column of buttons; on a touch
    /// screen, where nothing hovers, it stays shown, a step dimmer. Any label works,
    /// `MiddleTruncate` for a value too long for its column:
    ///
    ///     Copy(address) { MiddleTruncate(address, tail: 6) }
    ///
    /// The same as ui's `<Copy value={…}>{…}</Copy>`.
    public struct Copy<Label: View>: View {
        let value: String
        let label: Label
        @State private var feedback = CopyFeedback()
        @State private var hovering = false

        public init(_ value: String, @ViewBuilder label: () -> Label) {
            self.value = value
            self.label = label()
        }

        public var body: some View {
            Button {
                feedback.copy(value)
            } label: {
                HStack(spacing: .inkTight) {
                    label
                    CopyMark(feedback.state)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .opacity(markOpacity)
                }
                .padding(.horizontal, .inkTight)
                .padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: .inkChip)
                        .fill(.quaternary.opacity(hovering ? 0.8 : 0))
                )
                .padding(.horizontal, -.inkTight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .animation(.inkFlick, value: hovering)
            .onChange(of: value) { _, _ in feedback.reset() }
            .onDisappear { feedback.reset() }
            .accessibilityValue(spoken)
            .accessibilityHint(String(localized: "Copy to clipboard", bundle: .module))
            .help(String(localized: "Copy to clipboard", bundle: .module))
        }

        private var markOpacity: Double {
            if feedback.state != .idle || hovering { return 1 }
            #if os(iOS)
                return 0.6
            #else
                return 0
            #endif
        }

        private var spoken: String {
            switch feedback.state {
            case .idle: ""
            case .copied: String(localized: "Copied", bundle: .module)
            case .failed: String(localized: "Copy failed. Try again", bundle: .module)
            }
        }
    }

    extension Copy where Label == Text {
        /// The value as its own label.
        public init(_ value: String) {
            self.init(value) { Text(verbatim: value) }
        }
    }
#endif
