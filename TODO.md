# TODO

- [ ] **keymap-overlay: WIP, parked (2026-07-27).** Only adopting apps publish manifests, so on any other frontmost app the chord shows nothing - worthless until coverage exists. The unlock to design before resuming: derive a card for ARBITRARY apps (walk the frontmost app's menu bar via accessibility, and/or its published App Intents) so ⌃⌘/ answers everywhere, with published manifests as the rich path. Not running anywhere meanwhile.

- [ ] **AppSettings scaffold (when a third app makes the shape obvious).** One drop-in Settings scene with the standard panes pre-wired - Shortcuts (KeymapGrid), General, About (ColophonPane) - so support surfaces exist in every app without per-app assembly. Module name must NOT be `Settings` (collides with SwiftUI.Settings). Colophon and Entitlement ship; this is the composition layer over them.
- [ ] **Entitlement gating affordances.** The gate ships (one boolean, sealed/dev construction, `EntitlementDevToggle`). Still unextracted, waiting on a second real paywall: the locked badge, the upgrade prompt, the paywall sheet shape.
