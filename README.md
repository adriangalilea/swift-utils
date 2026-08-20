# swift-utils

Swift utilities for mac apps. The sibling of [ts-utils](https://github.com/adriangalilea/ts-utils), py-utils, and go-utils: one repo, multiple products, each module links only if imported.

## Ink

The styling atoms every product builds on: the `ink*` fill ladder for dark-glass surfaces (five semantic roles), the radius ladder (`.inkChip/.inkRow/.inkField/.inkPanel`), the motion ladder (`.inkFlick/.inkSettle`), the spacing ladder (`.inkTight/.inkGap/.inkLane/.inkBlock`) - no raw values at call sites - plus `planeHeaderStyle` and the micro-components: `ShortcutBadge` (the one key-cap), `ComboChip` (keycap with hover-✕ remove), `AddSlot` (the pressable ＋), `CursorScrollView` (the center-locked law of navigable surfaces). No dependencies; other products consume it without the keymap machine.

Ink also carries the pieces every surface repeats: `Pill` / `PersonPill` / `PillButtonStyle` (the leading slot - avatar or icon, always - is a circle whose diameter is the pill's height, flush at the left end, so its curvature IS the cap's curvature), `inkEdgeFade` (the law of scrolling regions: content near a scroll edge fades, never cuts mid-element; mask-based, so it works over any background), and the brand-mark machinery below.

## Brands (`brandgen`)

Any brand mark, natively, with no runtime SVG engine and no dependency. Swift has nothing like react-icons: SF Symbols excludes brands by trademark policy, and every third-party option is either an icon-font relic or a runtime parser. But asset catalogs compile SVG with vector preservation and template rendering, so the only missing piece was a way to GET the artwork.

```bash
swift run brandgen add spotify netflix          # into Scores (the default target)
swift run brandgen add figma --into MyProduct   # another target in this package
swift run brandgen add acme \                   # ...or any app, anywhere
  --catalog ~/app/Assets.xcassets --out ~/app/Brands.generated.swift
```

Upstream is [simple-icons](https://simpleicons.org) (CC0, ~3.4k brands): one SVG per slug, plus a data file carrying each brand's OFFICIAL hex - so colors are the brand's own, never hand-transcribed by whoever added the icon. **The catalog is the manifest**: one imageset per brand on disk, committed, and `Brand` is generated from it - no second list to drift, and a fresh clone builds offline (the network is only for adding a brand).

**BRANDS LIVE WITH THEIR CONSUMER, and Ink ships none.** Resources are not code: the linker dead-strips unused code, but a resource ships whether or not anything renders it (asset names resolve by string at runtime, so per-asset usage is undecidable). A brand added to the base layer every app links would ride along forever - so Ink owns only `BrandMarkable` + `BrandMark`, and each module generates the catalog it actually renders. Zero brand bytes by construction, not by discipline.

```swift
BrandMark(Brand.imdb, height: 26)                          // official color
BrandMark(Brand.rottentomatoes, height: 22, tint: .green)  // semantic override
Brand.metacritic.luminance                                 // 0.0 - vanishes on dark
```

Marks are template images: they carry shape, never color. `luminance` is the fact a dark-surface consumer needs, resolved at generation time - a brand whose official color is near-black (Metacritic's #000000, GitHub's #181717) wants a shape-based treatment or an explicit tint, never a silent repaint of someone's logo.

## Scores

The media-ratings vocabulary and the only place the ratings brands ship: `ScoreChip` / `ScoreStrip`, one chip per source with each value in that source's own scale (IMDb 0-10, RT and Metacritic 0-100, Letterboxd pre-scaled 0-10). Two sources get shape-based chips rather than a logo, and they are exactly the two whose official color is unusable on dark: Metacritic's colored box that IS the number, and Letterboxd's tri-color dots. An app that shows no ratings links no ratings logos.

## Gallery

The library-grid product: a framework-free layout kernel plus the SwiftUI shell, cross-platform by design - macOS binds keyboards to the kernels, tvOS lets the focus engine drive the same geometry.

- `GalleryPack.justifiedRows` - greedy justified rows (every row fills the width, each item at its TRUE aspect). **Prefix-stable**: a row is emitted the moment it fills, on its own items alone, so appending a page can only re-pack the old last row - the property paging stands on when nothing may reflow under a cursor or a focus engine.
- `GallerySelection` - the 3-mode selection verb (replace / toggle / range) with anchor+cursor discipline and the 2D ragged-row walk. Pure state over `(orderedItems, Set)`, zero UI: the host binds the inputs.
- `GalleryView` - observation-agnostic (plain values + closures, never a god-object), with `rowFocusSections` as the tvOS focus fallback and `galleryZoomSource`/`galleryZoomDestination` wrapping the system zoom navigation transition, so a card expands into its page and collapses back.

Gate: `swift run gallery-example --check` asserts the kernel invariants headless (row fill, append stability, every selection law); without the flag it opens a demo window with the keyboard walk wired.

## Colophon

The about/support Settings tab, designed once: app identity (name, version, build, icon) derived from the running bundle so it can never drift, the author byline, external links, the support ask, and an optional check-for-updates hook (Sparkle stays app-side, pass a closure).

```swift
ColophonPane(
    author: ColophonLink("Adrian Galilea", symbol: "person", url: URL(string: "https://adriangalilea.com")!),
    links: [ColophonLink("Website", symbol: "globe", url: URL(string: "https://untitled.garden")!)],
    support: [ColophonLink("GitHub Sponsors", symbol: "heart", url: URL(string: "https://github.com/sponsors/adriangalilea")!)],
    ask: String(localized: "If this app earns its keep, this is where to say so."),
    checkForUpdates: { updater.checkForUpdates() }
)
```

## Entitlement

The premium-gate shape: every gated feature reads ONE boolean, and every non-release build can flip it. The app chooses the construction at its own release seam (a release-pipeline-only `-D` flag, never `#if DEBUG` - a Release-config dev build defines no DEBUG):

```swift
#if MYAPP_RELEASE
let entitlement = Entitlement { realCheck() }   // sealed: StoreKit 2 / signed license
#else
let entitlement = Entitlement()                 // dev: persisted free ⇄ premium toggle
#endif
```

`EntitlementDevToggle(entitlement)` is the Diagnostics-row UI; it renders nothing on a sealed instance.

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

Idea, not built (2026-08-20): a **hyper key** - Caps Lock remapped to
⌃⌥⌘⇧-at-once, opening a global shortcut namespace that can never collide
with any app's combos. Prior art: Hyperkey.app (Knollsoft). Keymap's
`GlobalHotkeys` would be the natural consumer (hyper+key registry combos);
the caps-lock remap itself needs `hidutil`/IOKit, which Keymap doesn't
touch today.

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

The library owns routing primitives; policy stays in the app: `canPerform`/`shouldRoute` decide whether an action fires right now - focus arbitration is deliberately NOT a library concept (a real app's rules proved it unabstractable).

## keymap-overlay (WIP - parked)

The system-wide shortcut window: one chord - ⌃⌘/ - shows the frontmost app's published keymap as an accent-tinted glass card; the chord again, any click, or switching apps dismisses. Apps opt in by calling `store.publish(appName:accent:)`.

PARKED: today only Keymap-adopting apps publish a manifest, so for everything else the chord answers with nothing - worthless until coverage exists. The interesting future is deriving cards for arbitrary apps (menu-bar accessibility trees, published App Intents) so the overlay answers everywhere; until that design happens, don't run it.

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

Tag and push: `git tag 0.1.2 && git push --tags`. Git is the registry. Push the tag ON ITS OWN: a tag pushed in the same command as a branch produces no tag event, so the release silently never fires. SwiftPM has no manifest version field, so the tag is not a record of the version, it IS the version, and any file claiming otherwise is a second source of truth that will eventually disagree. Pushing the tag publishes the changelog and the GitHub Release.

Mac apps invert this: an app bundle has a native version (`CFBundleShortVersionString`), so there the manifest is truth and CI derives the tag from it.

The pipeline is itself a product here. `lib-release.yml` is reusable (`workflow_call`); any Swift library repo consumes it by ref:

```yaml
jobs:
  release:
    uses: adriangalilea/swift-utils/.github/workflows/lib-release.yml@ci-v1
    permissions: { contents: write }
```

`ci-v1` is a moving major tag, deliberately NOT the library's semver: a Keymap patch and a pipeline change must never share a version number. Advance it for compatible pipeline changes, cut `ci-v2` when a consumer's call would break. Never pin a consumer to `@main`; a bad push here would then break their releases silently.

The changelog format is `.github/cliff.toml`, which the workflow checks out into `.ci/` at `ci-v1`, so consuming repos inherit format fixes without copying the file. swift-utils calls its own workflow through `./` rather than `@ci-v1`, so the pipeline is always tested by the commit that changes it.

Verify runs on `macos-26` (the package targets macOS 26); the release job runs on Linux, because a library release ships no binaries and git-cliff-action is a Docker action, which cannot run on macOS runners.
