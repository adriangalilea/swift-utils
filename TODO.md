# TODO

- [ ] **AppSettings scaffold (next product after Keymap settles).** One drop-in Settings shape: a tabbed scene with the standard panes pre-wired - Shortcuts (KeymapGrid), General, and a credits/support pane (app version, links, tip jar) - so support surfaces exist in every app without per-app work. Module name must NOT be `Settings` (collides with SwiftUI.Settings).
- [ ] **Entitlement/feature-flag pattern.** The reusable shape of "this feature is paid": LOCAL dev overrides designed first (force flags on/off in dev builds, never shippable), a license check pluggable per app, gating affordances (locked badge, upgrade prompt). Extracted from the second real implementation, never speculatively.
