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
    // One version floor on every platform - the 26-era SwiftUI API surface
    // everywhere, so cross-platform products (Gallery) never carry
    // availability checks. Keymap (Carbon/AppKit) stays mac-only de facto -
    // SwiftPM builds only the products a consumer requests, so a tvOS app
    // importing Gallery never compiles it.
    platforms: [.macOS(.v26), .tvOS(.v26), .iOS(.v26)],
    products: [
        // The styling atoms: the Ink token ladder + the studio's
        // micro-components (keycaps, chips, slots). No dependencies -
        // future products (AppSettings, credits) build on it without
        // dragging the keymap machine.
        .library(name: "Ink", targets: ["Ink"]),
        .library(name: "Keymap", targets: ["Keymap"]),
        // The about/support tab every app drops into its Settings: bundle
        // identity + author + links + the support ask, designed once.
        .library(name: "Colophon", targets: ["Colophon"]),
        // The premium gate shape: one boolean the app reads, dev-toggleable
        // in every non-release build, compile-time sealed in release.
        .library(name: "Entitlement", targets: ["Entitlement"]),
        // The library-grid product: framework-free layout + selection
        // kernels (justified rows, the 2D cursor walk, the 3-mode
        // selection verb) and the GalleryView shell. Cross-platform by
        // design - macOS binds keyboards to the kernels, tvOS lets the
        // focus engine drive the same geometry.
        .library(name: "Gallery", targets: ["Gallery"]),
        // The system-wide shortcut overlay: a tiny background agent showing
        // the frontmost app's published keymap on one global chord (⌃⌘/).
        // Dogfood-first: `swift run keymap-overlay`.
        .executable(name: "keymap-overlay", targets: ["keymap-overlay"]),
        // Gallery's gate + demo: `swift run gallery-example --check` runs
        // the kernel invariants headless (nonzero exit on failure);
        // without the flag it opens a demo window with the keyboard walk
        // wired. The tvOS gate is the first tvOS consumer app.
        .executable(name: "gallery-example", targets: ["gallery-example"]),
    ],
    targets: [
        .target(name: "Ink", resources: [.process("Resources")]),
        .target(
            name: "Keymap",
            dependencies: ["Ink"],
            resources: [.process("Resources")]
        ),
        .target(
            name: "Colophon",
            dependencies: ["Ink"],
            resources: [.process("Resources")]
        ),
        .target(name: "Entitlement", resources: [.process("Resources")]),
        .target(name: "Gallery", dependencies: ["Ink"]),
        .executableTarget(name: "keymap-overlay", dependencies: ["Keymap"]),
        .executableTarget(name: "gallery-example", dependencies: ["Gallery"]),
        .testTarget(name: "KeymapTests", dependencies: ["Keymap"]),
    ]
)
