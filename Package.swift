// swift-tools-version: 6.2
// The Swift sibling of ts-utils/py-utils/go-utils: one repo, many products,
// each module links only if imported. The README says what each one is.
import PackageDescription

let package = Package(
    name: "swift-utils",
    // One version floor on every platform - the 26-era SwiftUI API surface
    // everywhere, so cross-platform products never carry availability checks.
    // Which product builds where is `mise run platforms`' table, checked on
    // every push (Keymap is macOS only, Biometrics has no tvOS); SwiftPM
    // builds only the products a consumer requests.
    platforms: [.macOS(.v26), .tvOS(.v26), .iOS(.v26)],
    products: [
        // The styling atoms: the Ink token ladder + the studio's
        // micro-components (keycaps, chips, slots). No dependencies -
        // future products (AppSettings, credits) build on it without
        // dragging the keymap machine.
        .library(name: "Ink", targets: ["Ink"]),
        // Code the user reads before approving it: real grammars
        // (highlight.js via Highlightr), one component, colors only - the
        // host brings font and chrome. Its own product so Ink stays
        // dependency-free.
        .library(name: "Syntax", targets: ["Syntax"]),
        // Syntax without its engine: the format vocabulary, diff line
        // coloring and a short excerpt view, for surfaces that cannot run
        // JavaScriptCore (a widget, a Live Activity). No dependencies.
        .library(name: "SyntaxLines", targets: ["SyntaxLines"]),
        .library(name: "Keymap", targets: ["Keymap"]),
        // Command-line output: the semantic palette (TTY + NO_COLOR /
        // FORCE_COLOR gated), ANSI-aware width/clip/pad, table/kv/tree.
        // ts-utils `cli` and py-utils `cli` by the same names.
        .library(name: "Terminal", targets: ["Terminal"]),
        // The logging and tracing contract of github.com/adriangalilea/utils
        // (go-utils, ts-utils, py-utils by the same verbs and the same
        // bytes): one stream of events, spans as start/end, W3C traceparent
        // across processes, LOG_* variables, LOG_SHIP; Apple's unified log as
        // a second sink. No dependencies.
        .library(name: "Log", targets: ["Log"]),
        // The about/support tab every app drops into its Settings: bundle
        // identity + author + links + the support ask, designed once.
        .library(name: "Colophon", targets: ["Colophon"]),
        // The premium gate shape: one boolean the app reads, dev-toggleable
        // in every non-release build, compile-time sealed in release.
        .library(name: "Entitlement", targets: ["Entitlement"]),
        // In-window biometrics, no popup: the Safari-private-mode lock
        // (embedded Touch ID sensor + inline secret field), the secret field
        // and the button a finger can press, over the BiometricSensor
        // primitive. The evaluated LAContext rides the verdict, so
        // biometry-gated keychain reads need no second prompt.
        .library(name: "Biometrics", targets: ["Biometrics"]),
        // Permission standing, split-brain-proof: every grant resolves to
        // ONE Standing (good / askable / broken) that carries its own
        // presentation, so no two surfaces can disagree on "is this a
        // problem?". Ships the Claim proof machine (for capabilities
        // whose system readout lies), the TCC and notification probes,
        // and the live row.
        .library(name: "Grant", targets: ["Grant"]),
        // The system-wide shortcut overlay: a tiny background agent showing
        // the frontmost app's published keymap on one global chord (⌃⌘/).
        // Dogfood-first: `swift run keymap-overlay`.
        .executable(name: "keymap-overlay", targets: ["keymap-overlay"]),
        // The media-ratings vocabulary: score chips per source, each in
        // its own scale, and the brand catalog they render. Brands live
        // with their CONSUMER, never in Ink - an app that shows no ratings
        // links no ratings logos.
        .library(name: "Scores", targets: ["Scores"]),
        // Generic media format chips: picture, sound, source tier, language
        // and cut as VALUES the chips know how to say, with the real marks
        // (Dolby, DTS, Blu-ray, IMAX…) in its own catalog - brands ship
        // with their consumer, and this is the consumer. Owns labels and
        // marks; meaning (certainty, comparison, house spellings) is the
        // consumer's mapping. `swift run mediaspec-example --check` pins the
        // wire literals shared with the React twin and the catalog against
        // its manifest.
        .library(name: "MediaSpec", targets: ["MediaSpec"]),
        // Any brand mark, natively: fetches simple-icons artwork (CC0) -
        // or imports a reviewed local SVG - into a target's catalog and
        // regenerates its typed enum with each brand's OFFICIAL color.
        // `swift run brandgen add <slug>` / `brandgen import <slug> --svg …`.
        .executable(name: "brandgen", targets: ["brandgen"]),
        // A Mac app's release outside the App Store: gates with honest
        // answers, Developer ID signing, notarization judged by the staple,
        // the dmg, the branch and tag, and the channels the app asks for.
        // `ship identity|check|build|publish|released`, installed by
        // mise's spm backend.
        .executable(name: "ship", targets: ["ship"]),
        // A Mac app's icon from its one source, the Icon Composer package
        // (`<Name>.icon`: icon.json + SVG layers): `mark build` compiles the
        // glass Assets.car, the flat icns and a 512 png; `mark preview`
        // shows Apple's own rendering of every appearance on a page.
        .executable(name: "mark", targets: ["mark"]),
        // What changed in a SwiftPM dependency for the code that uses it: run
        // in an app, per imported module, the breaks first. Any package, any
        // app; installed by mise's spm backend like ship and mark.
        .executable(name: "since", targets: ["since"]),
        // An app's permissions from outside it, for development: what it last
        // read (its own log) and a reset of its records (`grant help`).
        .executable(name: "grant", targets: ["grant-cli"]),
        // MediaSpec's gate + demo: `--check` pins the vocabulary, the label
        // rules and the lenient-decode law; without the flag, every chip
        // variant in a window on black.
        .executable(name: "mediaspec-example", targets: ["mediaspec-example"]),
    ],
    dependencies: [
        // Syntax's engine: highlight.js run in JavaScriptCore, packaged.
        // The one third-party dependency in the repo; only the Syntax
        // product drags it, and only consumers that import Syntax link it.
        .package(url: "https://github.com/raspu/Highlightr", from: "2.3.0")
    ],
    targets: [
        .target(name: "Ink", resources: [.process("Resources")]),
        .executableTarget(name: "ink-example", dependencies: ["Ink"]),
        .target(name: "SyntaxLines"),
        .target(
            name: "Syntax",
            dependencies: ["SyntaxLines", .product(name: "Highlightr", package: "Highlightr")]),
        .testTarget(name: "SyntaxTests", dependencies: ["Syntax"]),
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
        // The yes it draws wears Ink's prominent button.
        .target(name: "Biometrics", dependencies: ["Ink"]),
        .target(name: "Grant", dependencies: ["Log"], exclude: ["README.md", "CLAUDE.md"]),
        .executableTarget(name: "biometrics-example", dependencies: ["Biometrics"]),
        // Every Grant shape live, one set of grants: `swift run grant-example`.
        .executableTarget(name: "grant-example", dependencies: ["Grant"]),
        .target(name: "Scores", dependencies: ["Ink"], resources: [.process("Resources")]),
        .executableTarget(name: "keymap-overlay", dependencies: ["Keymap", "Ink"]),
        .target(
            name: "MediaSpec",
            dependencies: ["Ink"],
            // brandgen's local-mark ledger sits beside the catalog so the
            // generator can find it; it is a build input, never a resource.
            exclude: ["Resources/brandgen.local.json", "Resources/PROVENANCE.md"],
            resources: [.process("Resources")]
        ),
        .executableTarget(name: "mediaspec-example", dependencies: ["MediaSpec"]),
        .executableTarget(name: "brandgen"),
        .executableTarget(name: "ship"),
        .executableTarget(name: "mark"),
        .executableTarget(name: "since", dependencies: ["Terminal"]),
        // Its own directory name: `Sources/grant` IS `Sources/Grant` on a
        // case-insensitive disk.
        .executableTarget(name: "grant-cli", dependencies: ["Grant"]),
        .testTarget(name: "KeymapTests", dependencies: ["Keymap"]),
        .testTarget(name: "InkTests", dependencies: ["Ink"]),
        .testTarget(name: "GrantTests", dependencies: ["Grant"]),
        .target(name: "Terminal"),
        .testTarget(name: "TerminalTests", dependencies: ["Terminal"]),
        .target(name: "Log"),
        .testTarget(name: "LogTests", dependencies: ["Log"]),
    ]
)
