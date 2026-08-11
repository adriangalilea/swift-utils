import SwiftUI

// THE law of scrolling regions: content near a scroll edge FADES OUT,
// never cuts mid-element - a hard clip reads as breakage, the fade reads
// as "there is more". Mask-based, so it works over ANY background (a
// backdrop image, glass, black) without inventing a scrim color; pair it
// with a layered background (material / tint) when the region should
// elevate or recede in the page's depth story.

public extension View {
    /// Fade this view's rendered content at its vertical scroll edges.
    func inkEdgeFade(top: CGFloat = 0, bottom: CGFloat = 0) -> some View {
        mask(
            VStack(spacing: 0) {
                if top > 0 {
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                        .frame(height: top)
                }
                Rectangle().fill(.black)
                if bottom > 0 {
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: bottom)
                }
            }
        )
    }

    /// The horizontal twin (rails, pill rows).
    func inkEdgeFade(leading: CGFloat = 0, trailing: CGFloat = 0) -> some View {
        mask(
            HStack(spacing: 0) {
                if leading > 0 {
                    LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                        .frame(width: leading)
                }
                Rectangle().fill(.black)
                if trailing > 0 {
                    LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: trailing)
                }
            }
        )
    }
}
