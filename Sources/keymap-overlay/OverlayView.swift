import Keymap
import SwiftUI

/// The overlay's window dressing around the library's KeymapCard: dark
/// glass, the no-manifest fallback. All rendering lives in Keymap/Ink -
/// this file owns nothing that could drift from the in-app surfaces.
struct OverlayView: View {
    let manifest: KeymapManifest?
    let appName: String

    var body: some View {
        Group {
            if let manifest {
                KeymapCard(manifest: manifest, hint: "⌃⌘/ to dismiss")
            } else {
                Text("\(appName) publishes no keymap")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(24)
            }
        }
        .background(.black.opacity(0.55))
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .environment(\.colorScheme, .dark)
    }
}
