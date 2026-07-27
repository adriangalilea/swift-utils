import SwiftUI

/// Which focus region holds the keyboard right now, as observable DATA.
/// The library routes with it (`KeymapStore.match` honors `Reach.regions`);
/// it never decides focus itself - SwiftUI's own focus system does, and the
/// app reports transitions here. This is the no-stranded-zones mechanism:
/// every surface belongs to a registered region, focus moves under SwiftUI's
/// native rules (`.focusSection`, `@FocusState`), and routing follows the
/// report. Arbitration POLICY beyond "who holds focus" stays in the app's
/// `canPerform`.
@MainActor @Observable
public final class FocusMap {
    public private(set) var registered: Set<String> = []
    public private(set) var active: String?

    public init() {}

    public func register(_ region: String) {
        registered.insert(region)
    }

    /// A region gained focus. Unregistered ids are programmer error - the
    /// registry and the map must agree, so a typo screams instead of
    /// silently never matching.
    public func activate(_ region: String) {
        precondition(registered.contains(region), "unregistered focus region '\(region)'")
        active = region
    }

    /// A region lost focus with nothing gaining it (the focus walked out to
    /// no-region chrome). Only clears if the leaver still holds the map, so
    /// an out-of-order lose-after-gain can't erase the new holder.
    public func deactivate(_ region: String) {
        if active == region { active = nil }
    }
}

extension View {
    /// Sugar for the report: registers the region and mirrors a focus flag
    /// into the map. `isFocused` is the app's own `@FocusState`-derived
    /// truth - the map never invents focus.
    public func keymapRegion(_ id: String, isFocused: Bool, in map: FocusMap) -> some View {
        onAppear { map.register(id) }
            .onChange(of: isFocused) { _, focused in
                if focused { map.activate(id) } else { map.deactivate(id) }
            }
    }
}
