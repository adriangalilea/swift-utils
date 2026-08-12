import SwiftUI

// The brand-mark MACHINERY, and deliberately not a single brand asset.
//
// Asset catalogs are resources, not code: the linker dead-strips unused
// code, but a resource ships whether or not anything renders it (asset
// names resolve by string at runtime, so per-asset usage is undecidable).
// So brands cannot live in the base layer every app links - a calendar
// app importing Ink for its tokens would carry IMDb's logo forever.
//
// The rule that follows: BRANDS LIVE WITH THEIR CONSUMER. Ink owns the
// protocol and the view; each domain module (or app) owns the catalog it
// actually renders and generates its own conforming enum with
// `swift run brandgen` (see Scores for the in-repo example). Zero brand
// bytes by CONSTRUCTION, not by discipline.

public protocol BrandMarkable: Sendable {
    /// The brand's own name, as its owner writes it.
    var title: String { get }
    /// The official brand color.
    var color: Color { get }
    /// Relative luminance of `color` (0 black … 1 white) - the fact a
    /// dark-surface consumer needs before tinting anything.
    var luminance: Double { get }
    /// The mark, template-rendered, from the OWNING module's bundle.
    var image: Image { get }
}

/// A brand's mark. Template-rendered, so it carries shape and never
/// color: `tint` overrides the brand's own hex where color must speak
/// semantically (a rotten tomato going green), and a brand whose official
/// color is unusable on the surface - a near-black logo on dark - wants a
/// shape-based treatment or an explicit tint, never a silent repaint of
/// someone's logo.
/// Generic over the owning module's brand enum, so call sites name the
/// brand outright (`BrandMark(Brand.imdb)`): a leading dot cannot infer
/// its own base, and an existential would only trade that for boxing.
public struct BrandMark<B: BrandMarkable>: View {
    let brand: B
    let height: CGFloat
    let tint: Color?

    public init(_ brand: B, height: CGFloat = 24, tint: Color? = nil) {
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
