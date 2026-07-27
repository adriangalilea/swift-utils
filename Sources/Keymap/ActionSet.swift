import SwiftUI

/// THE registry contract. An app declares one enum conforming to this and
/// everything derives from it: native menus with live key display, the remap
/// Settings pane, tooltips, the cheat-sheet panel, the which-key tips,
/// system-wide
/// hotkeys, the App Intents surface, and the published keymap JSON the
/// system-wide overlay reads. Adding a command = one case + one spec + one
/// branch in the app's perform funnel (the exhaustive switch is the compiler
/// screaming when a branch is missing).
///
/// The library owns routing PRIMITIVES only. Policy stays in the app:
/// whether an action can fire right now (`canPerform` at the app's funnel),
/// and every focus-arbitration rule beyond "which region holds focus".
public protocol ActionSet: RawRepresentable<String>, CaseIterable, Hashable, Sendable {
    var spec: Spec { get }
    /// Display grouping, in order - drives the native menu and the cheat sheet.
    static var sections: [ActionSection<Self>] { get }
}

/// Identity, naming, symbol, default keys, and reach for one action.
/// The spec IS the default; user remaps overlay it sparsely in KeymapStore.
public struct Spec: Sendable {
    /// Already-localized display title. Declare it with a LITERAL
    /// `String(localized:)` - that's a localizable API, so compiler
    /// extraction (SWIFT_EMIT_LOC_STRINGS) lands the title in the app's
    /// string catalog by itself; a plain literal would be invisible to it
    /// and ship untranslatable.
    public let title: String
    /// SF Symbol name.
    public let symbol: String
    /// In-app accelerators, in order. The FIRST is the menu representative
    /// (the one `.keyboardShortcut` carries); the rest ride the alternate
    /// monitor. Empty = ships unbound.
    public var local: [KeyCombo]
    /// System-wide (Carbon) accelerators. Empty = no system-wide reach.
    ///
    /// The modifier doctrine: LOCALS go modifier-light (bare letters, the
    /// app owns its own keyboard - they cannot collide with other apps;
    /// that's where the ergonomics live). GLOBALS are where modifiers
    /// belong: a registered global steals its combo from EVERY app on the
    /// system while yours runs, so a default must be a deliberate, heavy
    /// chord (⌃⌥⌘-class) unlikely to be anyone else's key. Two default
    /// shapes have earned the blessing as studio convention: SUMMON (bring
    /// the app forward from anywhere - ⌃⌥⌘+initial) and the app's single
    /// identity verb (a security app's panic lock). Everything else is the
    /// user's opt-in. The grid warns live on combos macOS itself uses and dims
    /// registrations another app already owns.
    public var global: [KeyCombo]
    public init(
        title: String, symbol: String,
        local: [KeyCombo] = [], global: [KeyCombo] = []
    ) {
        self.title = title
        self.symbol = symbol
        self.local = local
        self.global = global
    }
}

/// One display group of the registry (menu section, cheat-sheet block).
/// Name the group with a literal `String(localized:)`, same as titles.
public struct ActionSection<A: ActionSet>: Sendable {
    public let name: String
    public let actions: [A]
    public init(_ name: String, _ actions: [A]) {
        self.name = name
        self.actions = actions
    }
}

/// Every accelerator bound to one action, across both reach planes. EITHER
/// list may be empty; the planes are fully independent - bind one, both, or
/// neither.
public struct ActionCombos: Codable, Equatable, Sendable {
    public var local: [KeyCombo]
    public var global: [KeyCombo]
    public init(local: [KeyCombo], global: [KeyCombo]) {
        self.local = local
        self.global = global
    }
    public var isEmpty: Bool { local.isEmpty && global.isEmpty }
}

/// Which reach plane an edit or match targets.
public enum ComboPlane: Sendable { case local, global }
