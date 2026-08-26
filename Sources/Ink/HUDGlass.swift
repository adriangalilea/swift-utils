import SwiftUI

// The floating-HUD chrome, designed once: Liquid Glass (the native
// macOS 26 register - never a material approximation) on a continuous
// rounded rect that HUGS its content. Hosts float it in a transparent
// click-through panel; embedded consumers apply it inline. Every senses
// surface (live captions, the ask prompt) wears exactly this.

extension View {
    public func hudGlass() -> some View {
        self
            .padding(.horizontal, 18)
            .padding(.vertical, 13)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
