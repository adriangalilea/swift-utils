import Keymap
import SwiftUI

// The registry the window and the checks share: bare keys where the app owns
// its keyboard, modifier chords for the rest, two forms for search (bare `/`
// and ⌘F, so each prefix shows a different one), and the heavy ⌃⌥⌘ chords on
// the global plane.
enum Command: String, CaseIterable, ActionSet {
    case play, previous, next, search, favorite, share, inspector, sidebar, reveal, revealGlobals

    var spec: Spec {
        switch self {
        case .play:
            Spec(
                title: "Play", symbol: "play.fill", local: [KeyCombo("space")],
                global: [KeyCombo("p", [.control, .option, .command])])
        case .previous: Spec(title: "Previous", symbol: "backward.fill", local: [KeyCombo("left")])
        case .next: Spec(title: "Next", symbol: "forward.fill", local: [KeyCombo("right")])
        case .search:
            Spec(
                title: "Search", symbol: "magnifyingglass",
                local: [KeyCombo("/"), KeyCombo("f", .command)])
        case .favorite: Spec(title: "Favorite", symbol: "heart", local: [KeyCombo("d", .command)])
        case .share:
            Spec(
                title: "Share", symbol: "square.and.arrow.up",
                local: [KeyCombo("s", [.shift, .command])])
        case .inspector:
            Spec(
                title: "Inspector", symbol: "sidebar.right",
                local: [KeyCombo("i", [.option, .command])])
        case .sidebar:
            Spec(
                title: "Sidebar", symbol: "sidebar.left",
                local: [KeyCombo("s", [.control, .command])])
        case .reveal: Spec(title: "Reveal Shortcuts", symbol: "keyboard", local: [KeyCombo("?")])
        case .revealGlobals:
            Spec(
                title: "Reveal Global Shortcuts", symbol: "globe",
                global: [KeyCombo("/", [.control, .option, .command])])
        }
    }

    static let sections = [
        ActionSection<Command>(
            "Playback", [.play, .previous, .next]),
        ActionSection<Command>("Library", [.search, .favorite, .share]),
        ActionSection<Command>("View", [.inspector, .sidebar, .reveal, .revealGlobals]),
    ]
}

/// The media key the play button also answers to: global, modifier-free.
let playMediaKey = ShortcutChord.mediaKey("⏯")
