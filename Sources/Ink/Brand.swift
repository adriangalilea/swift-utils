import SwiftUI

// The hand-written half of the brand vocabulary (the enum beside it is
// generated - `swift run brandgen`). A mark is a TEMPLATE image, so it
// carries shape and never color: `tint` overrides the brand's own hex
// when the color must speak semantically instead (a rotten tomato going
// green), and a brand whose official color is unusable on a dark surface
// - Metacritic's black, Letterboxd's near-black - is a case for a
// shape-based chip, not for silently repainting its logo.

public struct BrandMark: View {
    let brand: Brand
    let height: CGFloat
    let tint: Color?

    public init(_ brand: Brand, height: CGFloat = 24, tint: Color? = nil) {
        self.brand = brand
        self.height = height
        self.tint = tint
    }

    public var body: some View {
        brand.image
            .resizable()
            .scaledToFit()
            .frame(height: height)
            .foregroundStyle(tint ?? brand.color)
            .accessibilityLabel(brand.title)
    }
}
