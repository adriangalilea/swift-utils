// swift-tools-version: 6.2
// The Swift sibling of ts-utils/py-utils/go-utils: one repo, many products,
// each module links only if imported. First product: Keymap - the registry
// spine behind the studio keyboard decree (every app fully keyboard
// navigable). Register actions once; menus, cheat sheet, remap pane, reveal
// badges, system-wide hotkeys, App Intents surface, and the overlay keymap
// JSON all derive from the registry and can never drift from it.
import PackageDescription

let package = Package(
    name: "swift-utils",
    platforms: [.macOS(.v26)],
    products: [
        // The styling atoms: the Ink token ladder + the studio's
        // micro-components (keycaps, chips, slots). No dependencies -
        // future products (AppSettings, credits) build on it without
        // dragging the keymap machine.
        .library(name: "Ink", targets: ["Ink"]),
        .library(name: "Keymap", targets: ["Keymap"]),
        // The system-wide shortcut overlay: a tiny background agent showing
        // the frontmost app's published keymap on one global chord (⌃⌘/).
        // Dogfood-first: `swift run keymap-overlay`.
        .executable(name: "keymap-overlay", targets: ["keymap-overlay"]),
    ],
    targets: [
        .target(name: "Ink", resources: [.process("Resources")]),
        .target(
            name: "Keymap",
            dependencies: ["Ink"],
            resources: [.process("Resources")]
        ),
        .executableTarget(name: "keymap-overlay", dependencies: ["Keymap"]),
        .testTarget(name: "KeymapTests", dependencies: ["Keymap"]),
    ]
)
