import SwiftUI

// The platform HERO MORPH - the "card becomes the page" move. Each platform
// gets its own native version, deliberately: tvOS/iOS ride the system zoom
// navigation transition (the exact expansion the platform's flagship
// streaming apps use - buttery because the system owns every frame of it),
// while macOS has no system zoom transition and gets the pointer-shaped
// charge-and-takeover peek as its own future product. One vocabulary, per-
// platform realizations.
//
// Contract: the source id must be UNIQUE within its namespace - one card
// per identity per surface. A surface that can show the same identity
// twice (two rails sharing a work) keeps the standard push instead of
// registering two sources for one id.
#if !os(macOS)
extension View {
    /// Mark a gallery cell as the zoom SOURCE for a navigation value.
    public func galleryZoomSource(id: some Hashable, in ns: Namespace.ID) -> some View {
        matchedTransitionSource(id: id, in: ns)
    }

    /// Apply on the pushed DESTINATION view: it expands out of the marked
    /// card and collapses back into it on pop.
    public func galleryZoomDestination(id: some Hashable, in ns: Namespace.ID) -> some View {
        navigationTransition(.zoom(sourceID: id, in: ns))
    }
}
#endif
