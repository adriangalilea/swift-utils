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

    /// A copy in one of two faces, chosen by whether it has a label (ui's `<Copy>`
    /// takes the same two the same way):
    ///
    ///     Copy(address)                                       // the mark alone
    ///     Copy(address) { MiddleTruncate(address, tail: 6) }  // the text is the button
    ///
    /// The mark alone stands in a round well, for a value shown already beside it.
    /// With a label, the label is the button and the mark waits beside it, shown
    /// under the pointer and while it confirms, so a column of values reads as
    /// values and not as a column of buttons; on a touch screen, where nothing
    /// hovers, it stays shown, a step dimmer.
    ///
    /// `tip` is its tooltip (Ink's, `inkTip`), and the only one on its hover: a
    /// label's own goes quiet under it. `tip: address` shows the whole value even
    /// when it fits; without one, a cut `MiddleTruncate` shows the whole only when
    /// cut. For a command or a code on its own, `CopyableCommand`.
    public struct Copy<Label: View>: View {
        let value: String
        let tip: String?
        let label: Label
        let markOnly: Bool
        @State private var feedback = CopyFeedback()
        @State private var hovering = false

        public init(_ value: String, tip: String? = nil, @ViewBuilder label: () -> Label) {
            self.init(value, tip: tip, markOnly: false, label: label())
        }

        fileprivate init(_ value: String, tip: String?, markOnly: Bool, label: Label) {
            self.value = value
            self.tip = tip
            self.markOnly = markOnly
            self.label = label
        }

        public var body: some View {
            Button {
                feedback.copy(value)
            } label: {
                if markOnly { well } else { text }
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .animation(.inkFlick, value: hovering)
            .onChange(of: value) { _, _ in feedback.reset() }
            .onDisappear { feedback.reset() }
            .accessibilityValue(spoken)
            .accessibilityHint(String(localized: "Copy to clipboard", bundle: .module))
            .inkTip(tip)
        }

        private var well: some View {
            CopyMark(feedback.state)
                .font(.caption.weight(.semibold))
                .foregroundStyle(
                    feedback.state == .copied ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary)
                )
                .frame(width: 24, height: 24)
                .background(Circle().fill(.quaternary.opacity(hovering ? 0.9 : 0.45)))
                .contentShape(Circle())
                // A glyph alone names nothing: the well is called what it does.
                .accessibilityRepresentation { Text("Copy", bundle: .module) }
        }

        private var text: some View {
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

    extension Copy where Label == EmptyView {
        /// The mark alone, in a round well: the copy beside a value shown already.
        public init(_ value: String, tip: String? = nil) {
            self.init(value, tip: tip, markOnly: true, label: EmptyView())
        }
    }
#endif
