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
        // Markdown read and drawn: one parse (cmark-gfm: CommonMark and
        // GitHub's extensions) into a Sendable tree that keeps every node's
        // source position, and one SwiftUI page drawn from it. Its own
        // product so only consumers that import it link the parser.
        .library(name: "MarkdownText", targets: ["MarkdownText"]),
        // A repository as values, read from git's own machine output: unified
        // diffs, porcelain v2 status, a log, refs, worktrees, submodules, the
        // words that changed inside a line, a line diff of two texts. No UI,
        // no process: a host brings the bytes (`Git.Source`).
        .library(name: "GitKit", targets: ["GitKit"]),
        // The Mac's own repositories through /usr/bin/git, a fixed argv and
        // never a shell: `Git.LocalSource`. Read-only by construction.
        .library(name: "GitLocal", targets: ["GitLocal"]),
        // GitKit drawn: `DiffView` (one line of code anywhere: a markdown
        // fence, a card, a page), the file list, commits, refs, worktrees,
        // submodules, a status header; selection hands the host a `DiffQuote`.
        .library(name: "GitViews", targets: ["GitViews"]),
        .library(name: "Keymap", targets: ["Keymap"]),
        // Command-line output: the semantic palette (TTY + NO_COLOR /
        // FORCE_COLOR gated), ANSI-aware width/clip/pad, table/kv/tree.
        // ts-utils `cli` and py-utils `cli` by the same names.
        .library(name: "Terminal", targets: ["Terminal"]),
        // A command-line program described once (an enum of its commands,
        // typed flags and arguments, guides, exits), and everything a person
        // or an agent meets read from it: the parse and its refusals,
        // `--help`, `help <command|guide>`, `help --json` and the Claude
        // Code skill. ts-utils `cli`'s `program`, with skills.
        .library(name: "TerminalPrograms", targets: ["TerminalPrograms"]),
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
        // Every permission an app needs as one `PermissionGrant`, declared
        // once and used by name on every screen and in every gate: Privacy &
        // Security switches read live (tccd, Apple's public calls as the
        // fallback), background services, notifications, the app's own.
        // One top-level name; everything else nested in it.
        .library(name: "PermissionGrants", targets: ["PermissionGrants"]),
        // An app's whole life on the Mac, the app's own job: where its bundle
        // lives and moving it home, the agents and daemons it runs beside
        // itself (installed, approved, answering, restarted into a new
        // image), and its removal when the bundle is deleted. One top-level
        // name, `AppInstallation`.
        .library(name: "AppInstallations", targets: ["AppInstallations"]),
        // 1Password's command line (`op`) run one way: found, proven
        // AgileBits' on the suspended process before it runs, as a service
        // account or through the person's 1Password app, with an environment
        // built whole and secrets only on its stdin or that environment.
        // Typed failures. macOS only. One top-level name, `OnePasswordCLI`.
        .library(name: "OnePassword", targets: ["OnePassword"]),
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
        // `ship identity|check|build|appcast|publish|released`, installed by
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
        // OnePassword by hand: `op --version` through the runner, and with
        // `--interactive` `op account list` through the person's 1Password app.
        .executable(name: "onepassword-example", targets: ["onepassword-example"]),
        // MediaSpec's gate + demo: `--check` pins the vocabulary, the label
        // rules and the lenient-decode law; without the flag, every chip
        // variant in a window on black.
        .executable(name: "mediaspec-example", targets: ["mediaspec-example"]),
        // Keymap's which-key tips in a window, tipped controls along every
        // edge; `--check` runs the completion and placement laws headless.
        .executable(name: "keymap-example", targets: ["keymap-example"]),
        // A repository's state written to a folder, every file named for the
        // command that made it: what `Git.FixtureSource` reads back.
        .executable(name: "gitkit-capture", targets: ["gitkit-capture"]),
    ],
    dependencies: [
        // Syntax's engine: highlight.js run in JavaScriptCore, packaged.
        // The one third-party dependency in the repo; only the Syntax
        // product drags it, and only consumers that import Syntax link it.
        .package(url: "https://github.com/raspu/Highlightr", from: "2.3.0"),
        // MarkdownText's parser: cmark-gfm as swiftlang packages it, the one
        // swift-markdown wraps. Read directly because swift-markdown attaches
        // only tables, strikethrough and task lists: autolinks and footnotes
        // are GitHub's too, and agent text is full of bare URLs. Only the
        // MarkdownText product drags it.
        .package(url: "https://github.com/swiftlang/swift-cmark", exact: "0.9.0"),
    ],
    targets: [
        .target(name: "Ink", resources: [.process("Resources")]),
        .executableTarget(name: "ink-example", dependencies: ["Ink"]),
        .target(name: "SyntaxLines"),
        .target(
            name: "Syntax",
            dependencies: ["SyntaxLines", .product(name: "Highlightr", package: "Highlightr")]),
        .testTarget(name: "SyntaxTests", dependencies: ["Syntax"]),
        .target(name: "GitKit"),
        // Real output of real repositories (git's own bytes, NULs included).
        .testTarget(
            name: "GitKitTests", dependencies: ["GitKit", "GitLocal"], resources: [.copy("Fixtures")]),
        .target(name: "GitLocal", dependencies: ["GitKit"]),
        .executableTarget(name: "gitkit-capture", dependencies: ["GitLocal"]),
        .target(name: "GitViews", dependencies: ["GitKit", "Ink", "Syntax"]),
        .testTarget(name: "GitViewsTests", dependencies: ["GitViews"], resources: [.copy("Fixtures")]),
        // A fence named `diff` (or `patch`) is drawn by GitViews' DiffView.
        .target(
            name: "MarkdownText",
            dependencies: [
                "Ink", "Syntax", "GitViews",
                .product(name: "cmark-gfm", package: "swift-cmark"),
                .product(name: "cmark-gfm-extensions", package: "swift-cmark"),
            ]),
        // The fixtures (real agent answers and the edge cases) live with
        // the tests; `mise run markdown-snapshots` draws each one light and
        // dark on the Mac and in the iPhone simulator.
        .testTarget(
            name: "MarkdownTextTests", dependencies: ["MarkdownText"],
            resources: [.copy("Fixtures")]),
        // The fixtures in a window, the page and its two variants side by side.
        .executableTarget(name: "markdown-example", dependencies: ["MarkdownText"]),
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
        // AppInstallations: a background service's grant renders a job's state.
        // Ink: the studio's controls (the tinted action, the status mark).
        .target(
            name: "PermissionGrants", dependencies: ["Log", "Ink", "AppInstallations"],
            exclude: ["README.md", "CLAUDE.md"]),
        .target(
            name: "AppInstallations", dependencies: ["Log"], exclude: ["README.md", "CLAUDE.md"]),
        .target(name: "OnePassword", dependencies: ["Log"]),
        .testTarget(name: "OnePasswordTests", dependencies: ["OnePassword"]),
        .executableTarget(name: "onepassword-example", dependencies: ["OnePassword"]),
        .executableTarget(name: "biometrics-example", dependencies: ["Biometrics"]),
        // Every shape live over real permissions: `mise run grant-example`.
        .executableTarget(name: "grant-example", dependencies: ["PermissionGrants", "Ink"]),
        .target(name: "Scores", dependencies: ["Ink"], resources: [.process("Resources")]),
        .executableTarget(name: "keymap-overlay", dependencies: ["Keymap", "Ink"]),
        .executableTarget(name: "keymap-example", dependencies: ["Keymap", "Ink"]),
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
        .executableTarget(name: "ship", dependencies: ["AppInstallations"], exclude: ["RELEASE.md"]),
        .executableTarget(name: "mark"),
        .executableTarget(name: "since", dependencies: ["Terminal", "TerminalPrograms"]),
        .executableTarget(name: "grant-cli", dependencies: ["PermissionGrants"]),
        .testTarget(name: "KeymapTests", dependencies: ["Keymap"]),
        .testTarget(name: "InkTests", dependencies: ["Ink"]),
        .testTarget(name: "PermissionGrantsTests", dependencies: ["PermissionGrants"]),
        .target(name: "Terminal"),
        .target(name: "TerminalPrograms", dependencies: ["Terminal"]),
        .testTarget(name: "TerminalProgramsTests", dependencies: ["TerminalPrograms"]),
        .testTarget(name: "TerminalTests", dependencies: ["Terminal"]),
        // Terminal's `ANSI.colorAsked`: the one colour rule its `ui` keeps too.
        .target(name: "Log", dependencies: ["Terminal"]),
        .testTarget(name: "LogTests", dependencies: ["Log"]),
    ]
)
