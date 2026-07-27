import SwiftUI

/// THE premium gate. Every gated feature reads ONE boolean - `isPremium` -
/// and nothing else, written once: `if entitlement.isPremium { … } else { paywall }`.
/// New premium features inherit dev-testability for free: they gate on the
/// same boolean the dev toggle already flips.
///
/// Two constructions, chosen by the APP at its compile-time release seam
/// (a library cannot see your `-D` flags, so the `#if` lives with you):
///
/// ```swift
/// #if MYAPP_RELEASE   // set ONLY by the release pipeline
/// let entitlement = Entitlement { realCheck() }   // sealed
/// #else
/// let entitlement = Entitlement()                 // dev toggle
/// #endif
/// ```
///
/// The seam belongs on a release-pipeline-only flag, never `#if DEBUG`: a
/// Release-config dev build defines no DEBUG and would hide the toggle from
/// exactly the person who needs it. A sealed instance has no toggle path -
/// calling one is a program error and screams.
@MainActor @Observable
public final class Entitlement {
    public private(set) var isPremium: Bool

    /// nil = dev mode; the persisted toggle is the source.
    private let check: (() -> Bool)?
    private let defaults: UserDefaults
    private static let devKey = "dev.entitlement.premium"

    /// SEALED - release builds. `isPremium` is the real check (StoreKit 2,
    /// a signed license, whatever the app sells through); re-run it via
    /// `refresh()` after purchase or restore.
    public init(check: @escaping () -> Bool) {
        self.check = check
        defaults = .standard
        isPremium = check()
    }

    /// DEV - every non-release build: a persisted free ⇄ premium toggle so
    /// both variants of every gated feature are experienceable while
    /// building.
    public init(devDefaults: UserDefaults = .standard) {
        check = nil
        defaults = devDefaults
        isPremium = devDefaults.bool(forKey: Self.devKey)
    }

    public var isDev: Bool { check == nil }

    /// Re-read the source: the real check after purchase/restore, or the
    /// persisted toggle.
    public func refresh() {
        isPremium = check?() ?? defaults.bool(forKey: Self.devKey)
    }

    /// Dev-only: flip free ⇄ premium and feel both, persisted.
    public func setDevPremium(_ on: Bool) {
        precondition(check == nil, "setDevPremium on a sealed Entitlement - the release seam leaked")
        isPremium = on
        defaults.set(on, forKey: Self.devKey)
    }
}

/// The Diagnostics-row toggle: drop into any dev-visible Form. Renders
/// NOTHING on a sealed instance, so a host that forgets its own `#if`
/// still ships no toggle UI.
public struct EntitlementDevToggle: View {
    let entitlement: Entitlement

    public init(_ entitlement: Entitlement) { self.entitlement = entitlement }

    public var body: some View {
        if entitlement.isDev {
            Toggle(String(localized: "Premium (dev toggle)", bundle: .module), isOn: Binding(
                get: { entitlement.isPremium },
                set: { entitlement.setDevPremium($0) }
            ))
        }
    }
}
