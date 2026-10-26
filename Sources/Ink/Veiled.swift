import SwiftUI

/// A value that identifies its owner - a serial, an install id, a
/// license, a recovery key - shown VEILED: bullets, so a shared screenshot
/// brags without doxxing. `keep` leading characters may stay legible
/// (default 0: fully hidden).
///
/// How it is revealed is `reveal`:
/// - `.peek` (the default): at rest it is just text, the eye exists only
///   under the pointer, and a peek veils itself again after a beat. For a
///   value glanced at.
/// - `.toggle`: the eye is always there, and the value shows until it is
///   pressed again. For a value read on purpose, copied by hand character
///   by character, which a timed peek would hide mid-copy. It veils itself
///   when its window stops being the key window (an app switch), when the
///   app leaves the foreground (a screen lock) and when it disappears, so a
///   revealed value is never left behind.
///
/// The geometry is static BY CONSTRUCTION: the text renders monospaced
/// (a bullet's advance equals any glyph's) and the eye lives in a fixed
/// slot whether or not it is visible, so neither hover nor a reveal can
/// reflow the line. VoiceOver never reads the hidden value: the
/// accessibility value is "hidden" until the owner reveals it.
public struct Veiled: View {
    /// How a veiled value is revealed (see `Veiled`).
    public enum Reveal: Sendable {
        case peek
        case toggle
    }

    let text: String
    let keep: Int
    let reveal: Reveal
    @State private var shown = false
    @State private var hovering = false
    @State private var reveil: Task<Void, Never>?
    @Environment(\.scenePhase) private var scenePhase
    #if os(macOS)
        @Environment(\.controlActiveState) private var controlActiveState
    #endif

    public init(_ text: String, keep: Int = 0, reveal: Reveal = .peek) {
        self.text = text
        self.keep = keep
        self.reveal = reveal
    }

    private var veiled: String {
        String(text.prefix(keep)) + String(repeating: "\u{2022}", count: max(0, text.count - keep))
    }

    private func hide() {
        reveil?.cancel()
        guard shown else { return }
        withAnimation(.easeOut(duration: 0.25)) { shown = false }
    }

    public var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.12)) { shown.toggle() }
            reveil?.cancel()
            guard shown, reveal == .peek else { return }
            reveil = Task {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.25)) { shown = false }
            }
        } label: {
            HStack(spacing: 5) {
                Text(shown ? text : veiled)
                    .monospaced()
                Image(systemName: shown ? "eye" : "eye.slash")
                    .font(.caption2.weight(.medium))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 14, height: 14)
                    .opacity(reveal == .toggle || hovering ? 0.9 : 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .inkHover($hovering)
        .onChange(of: scenePhase) { _, phase in if phase != .active { hide() } }
        #if os(macOS)
            .onChange(of: controlActiveState) { _, state in if state != .key { hide() } }
        #endif
        .onDisappear { hide() }
        .accessibilityLabel(Text("veiled value", bundle: .module))
        .accessibilityValue(Text(verbatim: shown ? text : "hidden"))
        .accessibilityHint(
            reveal == .peek
                ? Text("reveals for five seconds", bundle: .module)
                : Text("reveals until pressed again", bundle: .module))
    }
}
