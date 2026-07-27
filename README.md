# swift-utils

Swift utilities for mac apps. The sibling of [ts-utils](https://github.com/adriangalilea/ts-utils), py-utils, and go-utils: one repo, multiple products, each module links only if imported.

## Ink

The styling atoms every product builds on: the `ink*` token ladder for dark-glass surfaces (five semantic roles, no raw values at call sites), `planeHeaderStyle`, and the micro-components - `ShortcutBadge` (the one key-cap), `ComboChip` (keycap with hover-✕ remove), `AddSlot` (the pressable ＋). No dependencies; future products (AppSettings, the credits pane) consume it without the keymap machine.

## Keymap

The registry spine behind the studio keyboard rule: every app fully keyboard navigable, the pointer a fallback, never the only path. Register every user-invocable action once; everything else derives from the registry and can never drift from it:

- native menus with live key display (`KeymapMenu`)
- the remap settings surface: aligned two-plane grid, keycap chips with hover-x remove, in-place recording, family modifier pickers, conflicts rejected by name and reported inline (`KeymapGrid` + `KeymapRestoreDefaults`)
- the filterable cheat sheet with press-to-flash and inline remapping, embeddable in Settings or floating (`CheatSheetPanel`, with `StaticShortcut` rows for structural keys)
- which-key discoverability: anchored floating tips that show the minimal completion of whatever prefix is held (`shortcutTipLayer` / `.shortcutTip`), fed by the ONE `RevealMonitor`
- system-wide hotkeys - registry combos AND family combos (⌥⌘1-9 style) - re-registered live on remap and keyboard-layout change, no accessibility permission (`GlobalHotkeys`)
- in-app routing for alternate combos, families, and panel surfaces, skipping menu-carried representatives (`LocalKeyRouter`; apps with richer arbitration keep their own monitor and just use `store.match`)
- Spotlight / Siri / Shortcuts / Apple Intelligence via App Intents (`KeymapAppEnum`) - the macOS command palette is the OS, so Keymap ships none
- a published keymap manifest (JSON with a versioned `$schema`, per bundle id) rendered by `KeymapCard` - the overlay windows the same card any in-app surface can show
- one stand-down signal: the cheat panel raises `store.keyboardCaptured` while it owns the keyboard; `LocalKeyRouter` and any app-side monitor check that one flag

### Usage

```swift
import Keymap

enum Act: String, CaseIterable, ActionSet {
    case playPause, search

    var spec: Spec {
        switch self {
        case .playPause: Spec(title: String(localized: "Play/Pause"), symbol: "playpause.fill", local: [KeyCombo("space")], global: [KeyCombo("space", [.command, .shift])])
        case .search: Spec(title: String(localized: "Search"), symbol: "magnifyingglass", local: [KeyCombo("f", .command)])
        }
    }

    static let sections = [ActionSection<Act>(String(localized: "Playback"), [.playPause, .search])]
}

// The app's funnel - the exhaustive switch is the point: add a case,
// the compiler demands its branch.
func perform(_ action: Act) {
    guard canPerform(action) else { return }
    switch action { /* ... */ }
}

let store = KeymapStore<Act>()
let hotkeys = GlobalHotkeys(store: store, perform: perform)
let router = LocalKeyRouter(store: store, perform: perform)
store.publish(appName: "myapp", accent: "#8FA98C")
```

Titles are declared with literal `String(localized:)` so compiler extraction (`SWIFT_EMIT_LOC_STRINGS`) lands them in the app's string catalog - a plain literal would ship untranslatable.

The library owns routing primitives; policy stays in the app: `canPerform`/`shouldRoute` decide whether an action fires right now - focus arbitration is deliberately NOT a library concept (lore's rules proved it unabstractable).

## keymap-overlay

The system-wide shortcut window: `swift run keymap-overlay` (or install the built binary as a login item). One chord - ⌃⌘/ - shows the frontmost app's published keymap as an accent-tinted glass card; the chord again, any click, or switching apps dismisses. Apps opt in simply by calling `store.publish(appName:accent:)`.

## Consuming

```yaml
# project.yml (xcodegen)
packages:
  swift-utils:
    url: git@github.com:adriangalilea/swift-utils.git
    from: "0.1.0"
```

Local development: swap `url` for `path: ../../swift-utils`.

## Release

Tag and push: `git tag 0.1.0 && git push --tags`. Git is the registry.
