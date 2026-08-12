import AppKit
import SwiftUI

/// The in-app routing half the menu bar can't do: alternate combos beyond
/// each action's menu representative, and any combo pressed on surfaces
/// menus don't reach (nonactivating panels). One NSEvent local monitor,
/// installed once at launch.
///
/// Routing order per keyDown:
/// 1. The capture signal - a cheat panel that owns the keyboard wins.
/// 2. Typing guard - a focused text input owns the keyboard; bare-key and
///    plain-shift combos never fire over it (⌘-chords still do).
/// 3. `store.match`, then the app's policy hook - `shouldRoute` decides if
///    the action fires RIGHT NOW (a needs-media gate, list-nav cession,
///    modal state). Return false to pass the event to the responder chain.
@MainActor
public final class LocalKeyRouter<A: ActionSet> {
    private var monitor: Any?

    /// `performFamily` receives (family id, key) when the pressed combo is
    /// the family's live local modifier + a member key (the in-app ⌘1-9).
    /// Family presses pass the same policy hook with a nil action.
    ///
    /// `alternatesOnly` skips each action's FIRST local combo - the menu
    /// representative a `.keyboardShortcut` already fires - so an app whose
    /// menus carry the representatives routes only the extras here and
    /// nothing fires twice.
    public init(
        store: KeymapStore<A>,
        alternatesOnly: Bool = false,
        shouldRoute: @escaping (A?, NSEvent) -> Bool = { _, _ in true },
        perform: @escaping (A) -> Void,
        performFamily: @escaping (String, String) -> Void = { _, _ in }
    ) {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // The local monitor always delivers on the main thread; NSEvent
            // itself isn't Sendable, so only the handled verdict crosses.
            let handled = MainActor.assumeIsolated { () -> Bool in
                // A capture surface (the cheat panel) owns the keyboard -
                // routing stands down wholesale while it's up.
                if store.keyboardCaptured { return false }
                guard let pressed = KeyCombo(event: event) else { return false }
                if Self.textInputIsFocused(event.window), pressed.eventModifiers.isDisjoint(with: [.command, .control]) {
                    return false
                }
                if let action = store.match(event) {
                    if alternatesOnly, store.menuCombo(for: action) == pressed { return false }
                    guard shouldRoute(action, event) else { return false }
                    perform(action)
                    return true
                }
                for family in store.families {
                    let modifier = store.familyModifier(family.id, .local)
                    guard !modifier.isEmpty, pressed.eventModifiers == modifier,
                          family.keys.contains(pressed.key),
                          shouldRoute(nil, event)
                    else { continue }
                    performFamily(family.id, pressed.key)
                    return true
                }
                return false
            }
            return handled ? nil : event
        }
    }

    isolated deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }

    /// A text view or editable field holds first responder in this window -
    /// the keyboard belongs to typing, not to bare-key accelerators.
    private static func textInputIsFocused(_ window: NSWindow?) -> Bool {
        guard let responder = window?.firstResponder else { return false }
        if let text = responder as? NSTextView { return text.isEditable }
        return responder is NSTextField
    }
}
