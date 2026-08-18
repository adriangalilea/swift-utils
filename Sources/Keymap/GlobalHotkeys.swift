import AppKit
import Carbon.HIToolbox
import SwiftUI

/// System-wide hotkey via Carbon - works while any app is focused, and
/// unlike NSEvent global monitors it needs no accessibility permission.
/// Carbon is ancient but remains the ONLY permission-free path macOS
/// offers; it is quarantined to this file.
package final class GlobalHotkey {
    /// Whether Carbon accepted the registration - false means another app
    /// (or the OS) owns the combo and this instance is inert.
    package private(set) var registered = false

    nonisolated(unsafe) private static var nextID: UInt32 = 1
    // id → handler, the single routing table. One app-level Carbon handler
    // dispatches every press through it; instances add/remove their own
    // entry. Carbon delivers on the main run loop, so the static table is
    // touched main-thread-only.
    nonisolated(unsafe) private static var handlers: [UInt32: () -> Void] = [:]
    nonisolated(unsafe) private static var handlerInstalled = false

    private var hotKeyRef: EventHotKeyRef?
    private let id: UInt32

    package init(keyCode: UInt16, modifiers: UInt32, handler: @escaping () -> Void) {
        id = Self.nextID
        Self.nextID += 1
        Self.installHandlerIfNeeded()
        Self.handlers[id] = handler

        // Four bytes of the bundle id: distinct enough per app, and the
        // signature only disambiguates in debugging tools anyway.
        let signature = (Bundle.main.bundleIdentifier ?? "kmap").utf8.prefix(4)
            .reduce(OSType(0)) { $0 << 8 | OSType($1) }
        let hotKeyID = EventHotKeyID(signature: signature, id: id)
        let status = RegisterEventHotKey(
            UInt32(keyCode), modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef
        )
        // Another app may own this combo - that's their machine, not a bug.
        // The in-app combo still works; drop the dead routing entry so it
        // can't leak. The FAILURE is surfaced (GlobalHotkeys → store) so
        // the grid can say so instead of a binding silently not firing.
        if status != noErr || hotKeyRef == nil {
            Self.handlers[id] = nil
        } else {
            registered = true
        }
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        Self.handlers[id] = nil
    }

    private static func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ in
                var pressed = EventHotKeyID()
                GetEventParameter(
                    event, EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID), nil,
                    MemoryLayout<EventHotKeyID>.size, nil, &pressed
                )
                guard let handler = GlobalHotkey.handlers[pressed.id] else {
                    return OSStatus(eventNotHandledErr)
                }
                handler()
                return noErr
            }, 1, &eventType, nil, nil)
    }
}

/// KNOWN EDGE: Carbon swallows a registered global's keyDown before the
/// app's event stream sees it, so pressing a global-registered combo while
/// the cheat panel is open FIRES (via the Carbon handler) without flashing
/// the panel row. Suspending registrations while captured would fix the
/// flash but kill true system-wide reach for a backgrounded app with its
/// panel open - not worth it. The action still fires; only the flash is
/// missed.
///
/// The store's system-wide plane, kept live: registers every global combo,
/// re-registers when bindings change (the store's onChange) or the keyboard
/// layout changes (input source switch), and unregisters on deinit - an
/// instance IS the registration set, swapping the array is the teardown.
@MainActor
public final class GlobalHotkeys<A: ActionSet> {
    private var registrations: [GlobalHotkey] = []
    private let store: KeymapStore<A>
    private let perform: (A) -> Void
    private let performFamily: (String, String) -> Void
    private var inputSourceObserver: NSObjectProtocol?

    /// `performFamily` receives (family id, key) for each registered family
    /// combo - the ⌘⌥1-9 kind of press, where the key IS the parameter.
    public init(
        store: KeymapStore<A>,
        perform: @escaping (A) -> Void,
        performFamily: @escaping (String, String) -> Void = { _, _ in }
    ) {
        self.store = store
        self.perform = perform
        self.performFamily = performFamily
        rebuild()
        store.onChange { [weak self] in self?.rebuild() }
        inputSourceObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                KeyboardLayout.rebuild()
                self?.rebuild()
            }
        }
    }

    isolated deinit {
        if let inputSourceObserver {
            DistributedNotificationCenter.default().removeObserver(inputSourceObserver)
        }
    }

    private func rebuild() {
        var dead: [KeyCombo] = []
        var rebuilt = A.allCases.flatMap { action in
            store.combos(for: action, .global).compactMap { combo -> GlobalHotkey? in
                guard let keyCode = combo.carbonKeyCode else { return nil }
                let hotkey = GlobalHotkey(keyCode: keyCode, modifiers: combo.carbonModifiers) {
                    [perform] in
                    perform(action)
                }
                if !hotkey.registered { dead.append(combo) }
                return hotkey
            }
        }
        // Family combos: the live global modifier + each member key. An empty
        // modifier means the family has no system-wide reach.
        for family in store.families {
            let modifier = store.familyModifier(family.id, .global)
            guard !modifier.isEmpty else { continue }
            for key in family.keys {
                guard let keyCode = KeyCombo(key, modifier).carbonKeyCode else { continue }
                rebuilt.append(
                    GlobalHotkey(keyCode: keyCode, modifiers: modifier.carbonModifiers) {
                        [performFamily] in
                        performFamily(family.id, key)
                    })
            }
        }
        registrations = rebuilt
        store.deadGlobals = dead
    }
}

/// The combos macOS itself CURRENTLY uses system-wide (screenshots,
/// Spotlight, Mission Control, …) via the symbolic-hotkeys registry - LIVE
/// state: it reflects the user's own remaps and disables in System
/// Settings. An ADVISORY, never a wall: the grid warns on these (the OS
/// intercepts before Carbon, so the binding may never fire), but the user
/// who moved Spotlight knows their own machine better than we do.
enum SystemHotkeys {
    static func owns(_ combo: KeyCombo) -> Bool {
        guard let keyCode = combo.carbonKeyCode else { return false }
        let modifiers = combo.carbonModifiers
        var hotkeys: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&hotkeys) == noErr,
            let list = hotkeys?.takeRetainedValue() as? [[String: Any]]
        else { return false }
        return list.contains { entry in
            (entry[kHISymbolicHotKeyEnabled as String] as? Bool) == true
                && (entry[kHISymbolicHotKeyCode as String] as? Int) == Int(keyCode)
                && (entry[kHISymbolicHotKeyModifiers as String] as? Int) == Int(modifiers)
        }
    }
}

// MARK: - KeyCombo → Carbon

extension KeyCombo {
    private static let namedKeyCodes: [String: Int] = [
        "space": kVK_Space, "left": kVK_LeftArrow, "right": kVK_RightArrow,
        "up": kVK_UpArrow, "down": kVK_DownArrow, "return": kVK_Return,
        "tab": kVK_Tab, "delete": kVK_Delete, "escape": kVK_Escape,
    ]

    /// The physical key code Carbon needs to register this combo system-wide.
    /// Named keys are fixed; printable keys resolve through the CURRENT
    /// keyboard layout, so a remapped global fires on AZERTY/Dvorak/etc,
    /// not just ANSI.
    package var carbonKeyCode: UInt16? {
        if let code = Self.namedKeyCodes[key] { return UInt16(code) }
        return KeyboardLayout.keyCode(for: key)
    }

    package var carbonModifiers: UInt32 { eventModifiers.carbonModifiers }
}

// Qualified: `import Carbon` also defines an `EventModifiers` (a UInt16
// typedef), so the bare name is ambiguous in this file.
extension SwiftUI.EventModifiers {
    /// Carbon's modifier mask for RegisterEventHotKey - the system-wide
    /// registrations and family prefixes both go through here.
    var carbonModifiers: UInt32 {
        var mask: UInt32 = 0
        if contains(.command) { mask |= UInt32(cmdKey) }
        if contains(.shift) { mask |= UInt32(shiftKey) }
        if contains(.option) { mask |= UInt32(optionKey) }
        if contains(.control) { mask |= UInt32(controlKey) }
        return mask
    }
}

/// char → physical key code for the current keyboard layout, built once via
/// UCKeyTranslate over every key code and cached; rebuilt on input-source
/// change (GlobalHotkeys observes it). Main-thread-only, like the rest of
/// hotkey setup.
enum KeyboardLayout {
    nonisolated(unsafe) private static var map = build()

    static func keyCode(for char: String) -> UInt16? { map[char] }
    static func rebuild() { map = build() }

    private static func build() -> [String: UInt16] {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
            let layoutPtr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return [:] }
        let data = Unmanaged<CFData>.fromOpaque(layoutPtr).takeUnretainedValue()
        let layout = unsafeBitCast(CFDataGetBytePtr(data), to: UnsafePointer<UCKeyboardLayout>.self)
        let kbdType = UInt32(LMGetKbdType())

        var map: [String: UInt16] = [:]
        for code in 0..<UInt16(128) {
            var deadKeyState: UInt32 = 0
            var length = 0
            var chars = [UniChar](repeating: 0, count: 4)
            let status = UCKeyTranslate(
                layout, code, UInt16(kUCKeyActionDisplay), 0, kbdType,
                OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeyState, 4, &length, &chars
            )
            guard status == noErr, length == 1 else { continue }
            let string = String(utf16CodeUnits: chars, count: 1).lowercased()
            guard let char = string.first, char.isASCII, !char.isWhitespace, char.asciiValue! > 32
            else { continue }
            // First wins: the main number row registers before the numpad's digits.
            if map[string] == nil { map[string] = code }
        }
        return map
    }
}
