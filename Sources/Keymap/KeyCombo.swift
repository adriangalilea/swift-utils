import AppKit
import SwiftUI

/// The AppKit keycodes structural monitors speak - named ONCE, public,
/// so no consumer scatters 53/123/36 magic through its own monitors.
public enum KeyCode {
    public static let `return`: UInt16 = 36
    public static let tab: UInt16 = 48
    public static let space: UInt16 = 49
    public static let delete: UInt16 = 51
    public static let escape: UInt16 = 53
    public static let left: UInt16 = 123
    public static let right: UInt16 = 124
    public static let down: UInt16 = 125
    public static let up: UInt16 = 126
}

/// One key press, stored as SwiftUI-shaped data: a key name plus
/// EventModifiers. Named keys ("space", "left", …) map to KeyEquivalent
/// statics; anything else is a single character.
public struct KeyCombo: Codable, Equatable, Hashable, Sendable {
    public let key: String
    public let modifiers: Int  // EventModifiers.rawValue

    public init(_ key: String, _ modifiers: EventModifiers = []) {
        self.key = key
        self.modifiers = modifiers.rawValue
    }

    private static let named: [String: KeyEquivalent] = [
        "space": .space, "left": .leftArrow, "right": .rightArrow,
        "up": .upArrow, "down": .downArrow, "return": .return,
        "tab": .tab, "delete": .delete, "escape": .escape,
    ]
    private static let keyCodeNames: [UInt16: String] = [
        49: "space", 123: "left", 124: "right", 125: "down", 126: "up",
        36: "return", 48: "tab", 51: "delete", 53: "escape",
    ]
    private static let glyphs: [String: String] = [
        "space": "Space", "left": "←", "right": "→", "up": "↑", "down": "↓",
        "return": "↩", "tab": "⇥", "delete": "⌫", "escape": "⎋",
    ]

    /// The physical key the user pressed, normalized; nil for bare
    /// modifiers and anything unprintable.
    public init?(event: NSEvent) {
        if let name = Self.keyCodeNames[event.keyCode] {
            key = name
        } else if let chars = event.charactersIgnoringModifiers?.lowercased(),
            chars.count == 1, let char = chars.first, !char.isWhitespace, char.isASCII,
            char.asciiValue! > 32
        {
            key = String(char)
        } else {
            return nil
        }
        var mods: EventModifiers = []
        if event.modifierFlags.contains(.command) { mods.insert(.command) }
        if event.modifierFlags.contains(.shift) { mods.insert(.shift) }
        if event.modifierFlags.contains(.option) { mods.insert(.option) }
        if event.modifierFlags.contains(.control) { mods.insert(.control) }
        // Shifted symbols ("?", "@", …) already carry shift in the
        // character itself - the canonical form drops the flag, matching
        // how AppKit treats key equivalents.
        if let char = key.first, key.count == 1, !char.isLetter {
            mods.remove(.shift)
        }
        modifiers = mods.rawValue
    }

    public var keyEquivalent: KeyEquivalent {
        Self.named[key] ?? KeyEquivalent(Character(key))
    }

    public var eventModifiers: EventModifiers { EventModifiers(rawValue: modifiers) }

    /// "⌃⌥⇧⌘X" - the order macOS renders modifiers in.
    public var display: String {
        eventModifiers.glyphs + (Self.glyphs[key] ?? key.uppercased())
    }
}

extension EventModifiers {
    /// "⌃⌥⇧⌘" - the modifier glyphs in the order macOS renders them.
    public var glyphs: String {
        var out = ""
        if contains(.control) { out += "⌃" }
        if contains(.option) { out += "⌥" }
        if contains(.shift) { out += "⇧" }
        if contains(.command) { out += "⌘" }
        return out
    }
}
