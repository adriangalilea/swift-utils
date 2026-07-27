# TODO

- [ ] **AppSettings scaffold (when a third app makes the shape obvious).** One drop-in Settings scene with the standard panes pre-wired - Shortcuts (KeymapGrid), General, About (ColophonPane) - so support surfaces exist in every app without per-app assembly. Module name must NOT be `Settings` (collides with SwiftUI.Settings). Colophon and Entitlement ship; this is the composition layer over them.
- [ ] **Entitlement gating affordances.** The gate ships (one boolean, sealed/dev construction, `EntitlementDevToggle`). Still unextracted, waiting on a second real paywall: the locked badge, the upgrade prompt, the paywall sheet shape.
