import AppKit
import SwiftUI
import Testing
@testable import Keymap

// A miniature registry shaped like a real app's.
enum Act: String, CaseIterable, ActionSet {
    case play, search, favorite

    var spec: Spec {
        switch self {
        case .play: Spec(title: "Play", symbol: "play", local: [KeyCombo("space")], global: [KeyCombo("space", [.command, .shift])])
        case .search: Spec(title: "Search", symbol: "magnifyingglass", local: [KeyCombo("f", .command)])
        case .favorite: Spec(title: "Favorite", symbol: "heart", local: [KeyCombo("d", .command)], reach: .regions(["library"]))
        }
    }

    static let sections = [ActionSection<Act>("All", [.play, .search, .favorite])]
}

private func freshDefaults() -> UserDefaults {
    let suite = "keymap.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
}

private let jump = ComboFamily(
    id: "jump", name: "the numbered jumps", keys: (1...9).map(String.init),
    localModifier: .command, globalModifier: [.command, .option]
)

@Suite @MainActor struct KeyComboTests {
    @Test func displayRendersMacOSOrder() {
        #expect(KeyCombo("k", [.shift, .command]).display == "⇧⌘K")
        #expect(KeyCombo("space").display == "Space")
        #expect(KeyCombo("left", .option).display == "⌥←")
    }

    @Test func shiftedSymbolCanonicalizesWithoutShift() {
        let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [.shift, .command],
            timestamp: 0, windowNumber: 0, context: nil,
            characters: "?", charactersIgnoringModifiers: "?", isARepeat: false, keyCode: 44
        )!
        let combo = KeyCombo(event: event)
        #expect(combo == KeyCombo("?", .command))
    }

    @Test func letterKeepsItsShift() {
        let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [.shift, .command],
            timestamp: 0, windowNumber: 0, context: nil,
            characters: "K", charactersIgnoringModifiers: "k", isARepeat: false, keyCode: 40
        )!
        #expect(KeyCombo(event: event) == KeyCombo("k", [.shift, .command]))
    }
}

@Suite @MainActor struct KeymapStoreTests {
    @Test func specsAreTheDefaults() {
        let store = KeymapStore<Act>(defaults: freshDefaults())
        #expect(store.combos(for: .play, .local) == [KeyCombo("space")])
        #expect(store.combos(for: .play, .global) == [KeyCombo("space", [.command, .shift])])
        #expect(!store.isCustomized(.play))
    }

    @Test func conflictIsRejectedWithOwnerName() {
        let store = KeymapStore<Act>(defaults: freshDefaults())
        #expect(store.add(KeyCombo("f", .command), plane: .local, to: .play) == "Search")
        #expect(store.combos(for: .play, .local) == [KeyCombo("space")])
    }

    @Test func planesDoNotCollide() {
        let store = KeymapStore<Act>(defaults: freshDefaults())
        // Search's ⌘F is local; the same combo is free on the global plane.
        #expect(store.add(KeyCombo("f", .command), plane: .global, to: .play) == nil)
    }

    @Test func familyReservesItsPrefix() {
        let store = KeymapStore<Act>(families: [jump], defaults: freshDefaults())
        #expect(store.add(KeyCombo("3", .command), plane: .local, to: .play) == "the numbered jumps")
        // Moving the family's modifier frees the old prefix.
        store.setFamilyModifier("jump", .local, to: [.command, .control])
        #expect(store.add(KeyCombo("3", .command), plane: .local, to: .play) == nil)
    }

    @Test func overridesPersistAndReload() {
        let defaults = freshDefaults()
        do {
            let store = KeymapStore<Act>(defaults: defaults)
            #expect(store.add(KeyCombo("p"), plane: .local, to: .play) == nil)
        }
        let reloaded = KeymapStore<Act>(defaults: defaults)
        #expect(reloaded.combos(for: .play, .local) == [KeyCombo("space"), KeyCombo("p")])
        #expect(reloaded.isCustomized(.play))
        reloaded.reset(.play)
        #expect(reloaded.combos(for: .play, .local) == [KeyCombo("space")])
    }

    @Test func matchHonorsReach() {
        let store = KeymapStore<Act>(defaults: freshDefaults())
        let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [.command],
            timestamp: 0, windowNumber: 0, context: nil,
            characters: "d", charactersIgnoringModifiers: "d", isARepeat: false, keyCode: 2
        )!
        // favorite reaches only the library region.
        #expect(store.match(event) == nil)
        #expect(store.match(event, focusedRegion: "browser") == nil)
        #expect(store.match(event, focusedRegion: "library") == .favorite)
    }

    @Test func legacyRemapsMigrate() throws {
        let defaults = freshDefaults()
        // A lore-shaped legacy blob: play remapped to bare "p", plus a moved
        // jump modifier stored as a raw int.
        let legacyOverrides = ["play": ActionCombos(local: [KeyCombo("p")], global: [])]
        defaults.set(try JSONEncoder().encode(legacyOverrides), forKey: "shortcutBindings")
        defaults.set(EventModifiers([.command, .control]).rawValue, forKey: "jumpModifier")

        let store = KeymapStore<Act>(
            families: [jump], defaults: defaults,
            legacy: LegacyKeys(
                overrides: "shortcutBindings",
                familyModifiers: ["jump": (local: "jumpModifier", global: "globalJumpModifier")]
            )
        )
        #expect(store.combos(for: .play, .local) == [KeyCombo("p")])
        #expect(store.familyModifier("jump", .local) == [.command, .control])
        // Untouched plane keeps the family default.
        #expect(store.familyModifier("jump", .global) == [.command, .option])
    }
}
