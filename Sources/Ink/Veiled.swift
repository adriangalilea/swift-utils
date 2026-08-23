import SwiftUI

/// A value that identifies its owner - a serial, an install id, a
/// license - shown VEILED: bullets, so a shared screenshot brags
/// without doxxing. `keep` leading characters may stay legible
/// (default 0: fully hidden). At rest it is just text: the eye that
/// toggles a peek exists only under the pointer, and a peek veils
/// itself again after a beat.
///
/// The geometry is static BY CONSTRUCTION: the text renders monospaced
/// (a bullet's advance equals any glyph's) and the eye lives in a
/// fixed slot whether or not it is visible, so neither hover nor the
/// peek can reflow the line. VoiceOver never reads the hidden value:
/// the accessibility value is "hidden" until the owner peeks.
public struct Veiled: View {
    let text: String
    let keep: Int
    @State private var shown = false
    @State private var hovering = false
    @State private var reveil: Task<Void, Never>?

    public init(_ text: String, keep: Int = 0) {
        self.text = text
        self.keep = keep
    }

    private var veiled: String {
        String(text.prefix(keep)) + String(repeating: "\u{2022}", count: max(0, text.count - keep))
    }

    public var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.12)) { shown.toggle() }
            reveil?.cancel()
            guard shown else { return }
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
                    .opacity(hovering ? 0.9 : 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(Text("veiled value", bundle: .module))
        .accessibilityValue(Text(verbatim: shown ? text : "hidden"))
        .accessibilityHint(Text("reveals for five seconds", bundle: .module))
    }
}
