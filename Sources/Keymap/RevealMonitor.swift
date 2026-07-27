import AppKit
import SwiftUI

/// App-wide modifier state. ONE monitor lives at the window root and
/// publishes what's held; every reveal badge reads it from the environment.
/// This is what makes discoverability structural rather than per-view:
/// a single source of "which modifiers are down right now", so badges can
/// paint the instant a prefix goes down, everywhere at once.
///
/// The which-key rule, generalized: ANY held modifier combination is a
/// prefix, and the reveal shows the minimal completions of exactly that
/// prefix (⌘ reveals the ⌘ layer, ⇧ the shift layer, ⌥⌘ that plane). The
/// bare-key layer has no prefix to hold, so it rides explicit reveals:
/// `?` in-app, and the "from anywhere" global-forms reveal (`⇧⌘?` by
/// convention).
@MainActor @Observable
public final class RevealMonitor {
    public var flags: EventModifiers = []
    /// Whether the main app is active. In-app menu combos fire only then.
    public var appActive: Bool = NSApplication.shared.isActive
    /// A nonactivating panel of this app is key: it routes registry combos
    /// via its own keyDown even while the app is inactive, so in-app combos
    /// ARE reachable from it - the reveal must show them there.
    public var panelKey = false
    /// `?` reveal: the modifier-less layer (bare keys), sticky until toggled.
    public var bareReveal = false
    /// The "from anywhere" reveal: same layer, global forms only.
    public var globalReveal = false
    /// A modal owns the screen: every reveal is silenced so unrelated hints
    /// don't float over it - the modal carries its own.
    public var suppressed = false

    /// Only Carbon globals fire when nothing on-screen can route in-app
    /// keys - the app is inactive AND no panel is key.
    public var globalsOnly: Bool { !(appActive || panelKey) }

    /// What the discoverability layer shows right now, as a which-key
    /// prefix: the minimal completion of `required` per action, and only
    /// global forms when `globalsOnly`.
    public struct Reveal: Sendable {
        public let required: EventModifiers
        public let globalsOnly: Bool
    }

    public var reveal: Reveal? {
        if suppressed { return nil }
        if !flags.isEmpty { return Reveal(required: flags, globalsOnly: globalsOnly) }
        if globalReveal { return Reveal(required: [], globalsOnly: true) }
        if bareReveal { return Reveal(required: [], globalsOnly: false) }
        return nil
    }
    public var revealing: Bool { reveal != nil }
    /// In-app combos are reachable and being revealed (hidden in the
    /// globals-only state) - the layer inline badges belong to.
    public var revealingInApp: Bool { revealing && !globalsOnly }

    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    public init() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.appActive = true }
        })
        observers.append(center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            // Dropping active also clears held flags - a reveal that began
            // in-app shouldn't linger after focus leaves.
            MainActor.assumeIsolated { self?.appActive = false; self?.flags = [] }
        })
    }

    isolated deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    /// Map AppKit's flags onto SwiftUI's set - for a panel's flagsChanged,
    /// which is how a nonactivating surface detects prefixes while the app
    /// is not key.
    public func update(from appKitFlags: NSEvent.ModifierFlags) {
        var mapped: EventModifiers = []
        if appKitFlags.contains(.command) { mapped.insert(.command) }
        if appKitFlags.contains(.shift) { mapped.insert(.shift) }
        if appKitFlags.contains(.option) { mapped.insert(.option) }
        if appKitFlags.contains(.control) { mapped.insert(.control) }
        flags = mapped
    }
}
