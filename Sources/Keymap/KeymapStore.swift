import AppKit
import SwiftUI

/// A parameterized combo family the registry can't hold as flat verbs:
/// N sibling targets sharing one customizable modifier prefix (the ⌘1-9
/// collection jumps). The KEYS are the semantic targets and never remap;
/// only the MODIFIER is customizable, per plane. The conflict checker
/// consults families so a remap can't silently shadow them.
public struct ComboFamily: Sendable {
    public let id: String
    /// Catalog key naming the family in conflict messages ("the numbered jumps").
    public let name: String
    public let keys: [String]
    public let defaultLocalModifier: EventModifiers
    public let defaultGlobalModifier: EventModifiers

    public init(
        id: String, name: String, keys: [String],
        localModifier: EventModifiers, globalModifier: EventModifiers
    ) {
        self.id = id
        self.name = name
        self.keys = keys
        defaultLocalModifier = localModifier
        defaultGlobalModifier = globalModifier
    }
}

/// Keys lore-era apps persisted remaps under, so adoption migrates users'
/// customizations instead of losing them. Read once on first init (the new
/// store key absent, a legacy key present), rewritten into the new shape;
/// the legacy values are left in place as a rollback breadcrumb.
public struct LegacyKeys: Sendable {
    /// UserDefaults key holding JSON `[rawValue: ActionCombos]`.
    public let overrides: String?
    /// UserDefaults keys holding EventModifiers rawValue ints, per family id
    /// and plane.
    public let familyModifiers: [String: (local: String, global: String)]

    public init(overrides: String?, familyModifiers: [String: (local: String, global: String)] = [:]) {
        self.overrides = overrides
        self.familyModifiers = familyModifiers
    }
}

/// Why an `add` was refused. The store owns EVERY binding rule - the UIs
/// (settings grid, cheat panel, anything else) just render the verdict, so
/// they can never diverge on what's bindable.
public enum AddRejection: Equatable, Sendable {
    /// The combo is already bound on that plane - by this action's named owner.
    case taken(by: String)
    /// A system-wide combo needs a real modifier (⌘, ⌥, or ⌃) to register.
    case needsModifier
    /// macOS owns this combo system-wide (screenshots, Spotlight, …) -
    /// registering it would fight the OS and lose.
    case systemReserved

    /// The one user-facing sentence for this verdict.
    public func message(for combo: KeyCombo) -> String {
        switch self {
        case .taken(let owner):
            String(localized: "\(combo.display) is already \(owner)", bundle: .module)
        case .needsModifier:
            String(localized: "System-wide shortcuts need ⌘, ⌥, or ⌃", bundle: .module)
        case .systemReserved:
            String(localized: "\(combo.display) belongs to macOS system-wide", bundle: .module)
        }
    }
}

/// User-remappable combos over the registry defaults, persisted as a sparse
/// override map. Each action carries a LIST per plane (multiple accelerators,
/// add/remove freely; empty = unbound). Conflicts are rejected per-plane,
/// never silently stolen - `add` reports the owner instead.
@MainActor @Observable
public final class KeymapStore<A: ActionSet> {
    private static var overridesKey: String { "keymap.overrides" }
    private static func familyKey(_ id: String, _ plane: ComboPlane) -> String {
        "keymap.family.\(id).\(plane == .local ? "local" : "global")"
    }

    public private(set) var overrides: [A: ActionCombos] = [:]
    public let families: [ComboFamily]
    private var familyOverrides: [String: (local: EventModifiers?, global: EventModifiers?)] = [:]
    private let defaults: UserDefaults

    /// Fired after any change so dependents rebuild - Carbon registrations
    /// re-register live, the published keymap JSON rewrites. Multiple
    /// subscribers; none can unsubscribe (dependents live as long as the
    /// store does).
    @ObservationIgnored private var changeHandlers: [() -> Void] = []
    public func onChange(_ handler: @escaping () -> Void) {
        changeHandlers.append(handler)
    }
    private func notifyChange() {
        for handler in changeHandlers { handler() }
    }

    public init(
        families: [ComboFamily] = [],
        defaults: UserDefaults = .standard,
        legacy: LegacyKeys? = nil
    ) {
        self.families = families
        self.defaults = defaults
        migrate(legacy)
        if let data = defaults.data(forKey: Self.overridesKey),
           let decoded = try? JSONDecoder().decode([String: ActionCombos].self, from: data) {
            // Raw values that no longer name an action are dropped silently:
            // renaming a case sheds its override, which is the correct decay.
            overrides = Dictionary(uniqueKeysWithValues: decoded.compactMap { raw, combos in
                A(rawValue: raw).map { ($0, combos) }
            })
        }
        for family in families {
            let local = defaults.object(forKey: Self.familyKey(family.id, .local))
                .map { _ in EventModifiers(rawValue: defaults.integer(forKey: Self.familyKey(family.id, .local))) }
            let global = defaults.object(forKey: Self.familyKey(family.id, .global))
                .map { _ in EventModifiers(rawValue: defaults.integer(forKey: Self.familyKey(family.id, .global))) }
            familyOverrides[family.id] = (local, global)
        }
    }

    /// One-time move from an app's pre-Keymap storage into the new keys.
    private func migrate(_ legacy: LegacyKeys?) {
        guard let legacy, defaults.data(forKey: Self.overridesKey) == nil else { return }
        if let key = legacy.overrides, let data = defaults.data(forKey: key) {
            defaults.set(data, forKey: Self.overridesKey)
        }
        for (familyID, keys) in legacy.familyModifiers {
            if defaults.object(forKey: keys.local) != nil {
                defaults.set(defaults.integer(forKey: keys.local), forKey: Self.familyKey(familyID, .local))
            }
            if defaults.object(forKey: keys.global) != nil {
                defaults.set(defaults.integer(forKey: keys.global), forKey: Self.familyKey(familyID, .global))
            }
        }
    }

    private func persist() {
        defaults.set(
            try! JSONEncoder().encode(Dictionary(uniqueKeysWithValues: overrides.map { ($0.rawValue, $1) })),
            forKey: Self.overridesKey
        )
        notifyChange()
    }

    // MARK: - Reads

    /// The registry default for an action - the spec IS the default, same shape.
    private func specDefaults(_ action: A) -> ActionCombos {
        ActionCombos(local: action.spec.local, global: action.spec.global)
    }

    public func effective(for action: A) -> ActionCombos { overrides[action] ?? specDefaults(action) }
    public func combos(for action: A, _ plane: ComboPlane) -> [KeyCombo] {
        plane == .local ? effective(for: action).local : effective(for: action).global
    }

    /// The one in-app accelerator a SwiftUI control / menu item carries.
    public func menuCombo(for action: A) -> KeyCombo? { combos(for: action, .local).first }
    public func menuShortcut(for action: A) -> KeyboardShortcut? {
        menuCombo(for: action).map { KeyboardShortcut($0.keyEquivalent, modifiers: $0.eventModifiers) }
    }

    /// One representative combo for inline display (tooltips, badges): the
    /// in-app key if there is one, else the system-wide form, else nothing.
    public func displayPrimary(for action: A) -> String {
        (combos(for: action, .local).first ?? combos(for: action, .global).first)?.display ?? ""
    }

    public func isCustomized(_ action: A) -> Bool { overrides[action] != nil }

    /// The live modifier prefix for a combo family on a plane.
    public func familyModifier(_ id: String, _ plane: ComboPlane) -> EventModifiers {
        guard let family = families.first(where: { $0.id == id }) else {
            preconditionFailure("unknown combo family '\(id)'")
        }
        let override = familyOverrides[id]
        return (plane == .local ? override?.local : override?.global)
            ?? (plane == .local ? family.defaultLocalModifier : family.defaultGlobalModifier)
    }

    // MARK: - Writes

    private func store(_ combos: ActionCombos, for action: A) {
        overrides[action] = combos == specDefaults(action) ? nil : combos
        persist()
    }

    /// Adds a combo on the given plane unless a binding rule refuses it:
    /// taken on that plane (by another action or a combo family, which
    /// reserves <modifier>+each key), or a system-wide combo without a real
    /// modifier. nil = added. (Planes don't collide: a key may be an in-app
    /// combo for one action and a system-wide form for another.)
    public func add(_ combo: KeyCombo, plane: ComboPlane, to action: A) -> AddRejection? {
        if plane == .global {
            if combo.eventModifiers.isDisjoint(with: [.command, .option, .control]) {
                return .needsModifier
            }
            if SystemHotkeys.owns(combo) { return .systemReserved }
        }
        if let owner = A.allCases.first(where: {
            $0 != action && combos(for: $0, plane).contains(combo)
        }) { return .taken(by: owner.spec.title) }
        for family in families {
            let modifier = familyModifier(family.id, plane)
            if !modifier.isEmpty, family.keys.contains(combo.key), combo.eventModifiers == modifier {
                return .taken(by: family.name)
            }
        }
        var edited = effective(for: action)
        if plane == .local { if !edited.local.contains(combo) { edited.local.append(combo) } }
        else { if !edited.global.contains(combo) { edited.global.append(combo) } }
        store(edited, for: action)
        return nil
    }

    public func remove(_ combo: KeyCombo, plane: ComboPlane, from action: A) {
        var edited = effective(for: action)
        if plane == .local { edited.local.removeAll { $0 == combo } }
        else { edited.global.removeAll { $0 == combo } }
        store(edited, for: action)
    }

    public func setFamilyModifier(_ id: String, _ plane: ComboPlane, to modifier: EventModifiers) {
        precondition(families.contains { $0.id == id }, "unknown combo family '\(id)'")
        var override = familyOverrides[id] ?? (nil, nil)
        if plane == .local { override.local = modifier } else { override.global = modifier }
        familyOverrides[id] = override
        defaults.set(modifier.rawValue, forKey: Self.familyKey(id, plane))
        notifyChange()
    }

    public func reset(_ action: A) {
        overrides[action] = nil
        persist()
    }

    public func resetAll() {
        overrides = [:]
        for family in families {
            familyOverrides[family.id] = (nil, nil)
            defaults.removeObject(forKey: Self.familyKey(family.id, .local))
            defaults.removeObject(forKey: Self.familyKey(family.id, .global))
        }
        persist()
    }

    // MARK: - Routing

    /// A capture surface (the cheat panel) owns the keyboard wholesale. The
    /// ONE stand-down signal: the panel raises it on appear, every routing
    /// engine - LocalKeyRouter here, an app's own monitors - checks it in
    /// one place instead of each host wiring its own yields. Settable by
    /// hosts too: a host tearing down a panel window force-clears it, so a
    /// missed onDisappear can never leave every shortcut dead.
    public var keyboardCaptured = false

    /// Global combos whose Carbon registration FAILED - another running app
    /// owns them system-wide, so they will not fire. GlobalHotkeys reports
    /// after every rebuild; the settings grid marks these so a silent dead
    /// binding can't masquerade as working.
    public internal(set) var deadGlobals: [KeyCombo] = []

    /// keyDown → action over the in-app combos. For surfaces the menu bar
    /// can't reach (nonactivating panels) and for alternate combos beyond
    /// the menu representative. Whether the matched action may fire RIGHT
    /// NOW is the app's policy hook, not the store's.
    public func match(_ event: NSEvent) -> A? {
        guard let pressed = KeyCombo(event: event) else { return nil }
        return A.allCases.first { combos(for: $0, .local).contains(pressed) }
    }

    /// Tooltip text that can never drift from the actual combo.
    public func help(for action: A, _ detail: String? = nil) -> String {
        let combo = displayPrimary(for: action)
        let label = detail ?? action.spec.title
        return combo.isEmpty ? label : "\(label) (\(combo))"
    }
}


extension KeymapStore {
    /// Every accelerator a command answers to - the in-app (remappable)
    /// combos and the global forms. The reveal walks these.
    public func chords(for action: A) -> [ShortcutChord] {
        combos(for: action, .local).map {
            ShortcutChord(modifiers: $0.eventModifiers, display: $0.display, isGlobal: false)
        } + combos(for: action, .global).map {
            ShortcutChord(modifiers: $0.eventModifiers, display: $0.display, isGlobal: true)
        }
    }
}
