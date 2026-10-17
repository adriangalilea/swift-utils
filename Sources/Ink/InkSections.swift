import SwiftUI

// A surface in two parts, designed once: what it says, and below it a band
// for what you do about it (the answers, the actions, the quiet line of
// keys and time). The band is the same surface a step deeper, a faint
// shade under a hairline, reaching the edges: one material, two sections,
// never a second glass laid over the first (stacked glass smears).
//
// The host gives the material (`inkGlass()` for a floating HUD, a card's
// own background) and no padding of its own: the sections pad themselves,
// so the band can run to the rounded edge.

public struct InkSections<Content: View, Footer: View>: View {
    let cornerRadius: CGFloat
    let content: Content
    let footer: Footer

    public init(
        cornerRadius: CGFloat = .inkPanel,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) {
        self.cornerRadius = cornerRadius
        self.content = content()
        self.footer = footer()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
                .padding(.horizontal, 18)
                .padding(.top, 15)
                .padding(.bottom, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
            footer
                .padding(.horizontal, 18)
                .padding(.vertical, 11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    Color.black.opacity(0.2)
                        .overlay(alignment: .top) {
                            Rectangle().fill(.white.opacity(0.08)).frame(height: 1)
                        }
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

extension View {
    /// The floating HUD's Liquid Glass for content that pads itself (an
    /// `InkSections`): clear glass, faintly darkened so words read over
    /// anything, on the panel's continuous rounded rect.
    public func inkGlass(cornerRadius: CGFloat = .inkPanel) -> some View {
        glassEffect(
            .clear.tint(Color.black.opacity(0.22)),
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}
