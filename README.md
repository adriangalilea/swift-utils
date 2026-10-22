# swift-utils

Swift utilities for mac apps. The sibling of [ts-utils](https://github.com/adriangalilea/ts-utils), py-utils, and go-utils: one repo, multiple products, each module links only if imported.

**A module never takes a common word at top level.** Whatever it makes public lands in every importer's namespace, where apps have their own `Answer`, `Claim`, `Grant`, `Permission`, `Session`, `State`: a module exports one compound name and nests everything else in it (`PermissionGrant.Standing`, `PermissionGrant.Claim`). The module is never named like its type: `Module.Type` is the escape hatch when two imports clash, and a type named like its module hides the module (`PermissionGrants.PermissionGrant` works, `Grant.Grant` did not). A top-level `Answer` in 0.30.6 broke Authz's build, whose voice card has its own.

## Ink

The styling atoms every product builds on: the `ink*` fill ladder for dark-glass surfaces (five semantic roles), the surface ladder (`.inkPane` beside the work, `.inkFloat` over it; `inkPane(top:)` lays a sidebar or inspector as the system does, inset and rounded on its own surface, so regions read as layers and never as cells cut by a line), the radius ladder (`.inkChip/.inkRow/.inkField/.inkPanel`), the motion ladder (`.inkFlick/.inkSettle`), the spacing ladder (`.inkTight/.inkGap/.inkLane/.inkBlock`) - no raw values at call sites - plus `planeHeaderStyle` and the micro-components: `InkKey` (the one key-cap, any shortcut, inline or alone; `InkKeyed` a label with its key after it), `ComboChip` (keycap with hover-✕ remove), `AddSlot` (the pressable ＋), `CursorScrollView` (the center-locked law of navigable surfaces), `MiddleTruncate` (text cut in the middle with its end kept whole, `tail: 6` characters or `tail: "/"` from a separator, the one rule every truncated address, hash or path follows; ui's `middle-truncate` is the same rule on the web). Copying is one action, `CopyFeedback` (the pasteboard write and its idle / copied / failed confirm, the contract of ui's `useCopy`), drawn by `CopyMark`, with three faces: `Copy(value)`, the mark alone in a round well beside a value shown already; `Copy(value) { label }`, the text itself as the button with the mark under the pointer (`Copy(address) { MiddleTruncate(address, tail: 6) }` for an address in a row); and `CopyableCommand`, a chip for a command or a code on its own. ui's `<Copy>` takes the same faces the same way. Each takes `tip:`, Ink's tooltip and the only one on its hover. `inkTip(text)` is the one tooltip call: on macOS one panel for the whole app, never clipped by a scroll view, so one tip shows at a time and words that change while shown change in place; on iPad a pointer's hover draws it; tvOS never hovers (`inkHover`, the one place that says so). It answers like the system's own: the first tip waits a beat so a sweep never strobes, the next ones follow at once, and a click puts it away. One look, a tinted Liquid Glass chip as wide as its longest line, below the element; `.inkTipEdge(.top)` turns a window or a section the other way (chrome along a window's bottom edge), a tip flips when the screen has no room, and `inkTip(text, edge:)` pins a side. The outermost tip with words claims the hover, so a cut `MiddleTruncate` inside a `Copy(value, tip:)` stays quiet. A value (an address, a hash, a path) stays whole on one line, never hyphenated; prose wraps a sentence per line. `swift run ink-example` shows them against SwiftUI's own truncation, at any width, and who speaks on the hover.

Secrets are three pieces that compose: `SecretField` types one (hidden as typed, an eye to check it, AutoFill's `.password` or `.newPassword`, an optional valid/invalid border; every platform); `Veiled` shows one (bullets, so a screenshot never leaks it; a click peeks it for five seconds); and `Copy(value)` beside a `Veiled` copies it without showing it. Siblings, never nested: a click on the value peeks, a click on the mark copies. ui's `veiled` and its `input`'s reveal are the same on the web. No dependencies; other products consume it without the keymap machine.

Ink also carries the pieces every surface repeats: `Pill` / `PersonPill` / `PillButtonStyle` (the leading slot - avatar or icon, always - is a circle whose diameter is the pill's height, flush at the left end, so its curvature IS the cap's curvature), `inkEdgeFade` (the law of scrolling regions: content near a scroll edge fades, never cuts mid-element; mask-based, so it works over any background), `MicButton` + `PushToTalk` (THE mic affordance, designed once: the messaging-app grammar - hold to talk, quick tap latches with a lock badge, next tap stops - one state machine shared by the pointer gesture and any key binding's press/release, a live Siri-family gradient waveform while hot (glowing mirrored ribbon, bright on voice activity - deliberately not red: a live mic is a state, not an error); the studio's signal source is listen's `AudioSpectrum` over `MicCapture` in github.com/adriangalilea/swift-senses - Ink owns the FEEL, listen owns the DSP), and the brand-mark machinery below.

A surface that asks something is two sections, designed once: `InkSections { what is asked } footer: { where it is answered }`, the footer a band of the same material a step deeper (a hairline, a faint shade) that runs to the rounded edge, never a second glass laid over the first; its host gives the material (`inkGlass()` for a floating HUD, a card's background) and no padding. Its buttons are `InkButtonStyle`: `.inkProminent` (the host's `.tint`, deepened so white text reads on any hue) and `.ink` (a faint fill), drawn by Ink rather than the platform's bordered styles, which grey out whenever their window does not hold the keyboard (a floating HUD before hover). A yes takes the accent, not green: a yes can delete. A toolbar's icons are `.inkTool` (one size, quiet at rest, a faint fill under the hand) and `.inkTool(on:)` for a mode that holds (a raised fill, the primary ink, never the accent), so a bar of a dozen controls, the host's among them, reads as one row. `InkToolGroup` holds the tools that belong together in one Liquid Glass capsule, as the system groups a toolbar's items; inside it the glass is the one shape and an icon says on by itself. `InkTabs` are ui's `tabs`, the same design: `segment` (a well, the chosen tab lifted out of it, the lift gliding to the tab you pick) or `line` (a rule, the chosen stretch lit), small, medium or large; never the platform's segmented control, which paints a choice among equals in the accent.

Every control follows one material: `.inkMaterial(.glass)` (the default: Liquid Glass, interactive from rest, so it reacts under the hand) or `.inkMaterial(.flat)` (a faint fill), set once on a host and obeyed by `.ink`, `.inkProminent`, `.inkTinted`, `InkTabs` and the page dots below it. `.inkTinted(color)` is the button whose words carry its hue (a fix to make, a warning that is also its own action); `InkStatusMark(symbol, tint:)` is a state that is not a button, a circle of faint tinted glass with the symbol in the hue (never white on a solid fill). Both size from the `controlSize` (`InkControlMetrics`). `InkPages` is a walk through pages (an onboarding, a setup): a real pager whose slide direction is the geometry's, Back always in its place, `InkPageDots` as markers coloured by each page's state and clickable (`.seen` or `.any`), the caller's one way on at the right in one width so a pointer clicking through never lands on empty space, ← → keys, the trackpad swipe on macOS, a drag on iOS, the remote on tvOS. An action about the page's own subject belongs in the page.

## Releases (`ship`)

A Mac app's release outside the App Store, one implementation for every app, holding no key. `ship release [release.json…]` builds one or more apps after one approval of their exact commits: the keys live in a vault and reach the release only through the approver `SHIP_APPROVE` names, after a person's verified yes; the apps' working folders keep their build caches, and each release records the digest of everything it signed ([Sources/ship/RELEASE.md](Sources/ship/RELEASE.md): the approver's contract, what runs, what it does not stop). `ship build` runs inside that release, `ship publish` afterwards from the app's checkout, with `VERSION` in the environment and the release body in `notes/$VERSION.md`.

```
ship release                     # from the app's repo (release.json), or several manifests at once
# release.json's script, run by the release in the app's working folder at the approved commits:
ship build   --team ABCDE12345 --name myapp --app dist/myapp.app \
             --assemble "scripts/assemble.sh dist/myapp.app" --sign Contents/MacOS/helper
# then, from the checkout:
ship check   --name myapp --app dist/myapp.app --github --cask
ship publish --name myapp --app dist/myapp.app --github --after "mise run publish" --cask
# any build that signs, release or not:
ship identity --team ABCDE12345
```

`identity` prints the SHA-1 to sign with, found in a keychain, never named (a renewed certificate sits beside the old one until it expires): inside a release (`SHIP_KEYCHAIN` set) the one Developer ID Application identity of the team that keychain holds; anywhere else the team's valid Apple Development identity that expires last, so development builds keep their privacy grants across rebuilds without ever holding a release key. `build` refuses outside a release, then: `--assemble`, signing from the release's keychain with hardened runtime and a secure timestamp (each `--sign` path inside the bundle first, then the bundle), notarization judged by `stapler` rather than notarytool's exit status, and a dmg that opens on a designed install window, the app beside an Applications link and the app's icon on the volume (itself signed, notarized and stapled). `check` reports every gate publishing needs (own repo root, clean tree, no tag yet, the notes and their grammar, each channel's prerequisite) and prints the real answer under a blocked one. `publish` adds three gates (the last release of this repo, by its `release.json` and the release's record, is of exactly these commits, Markdown aside; the dmg is stapled; it is signed with Developer ID), then pushes the tag with its branch and the channels asked for: `--github` (a release with the notes and the dmg), `--after` (any command, with `DMG` and `VERSION` set, run once the dmg is public), `--cask` (bumps `Casks/<name>.rb` in the tap checkout at `$TAP`, skipped when unset); `--tag <name>` names the tag when one repo releases several apps. A build whose assembly signs it already (an Xcode export, which embeds the provisioning profiles a restricted entitlement needs; re-signing would drop them) passes `--signed`: the signature is verified to be the release's Developer ID, never redone. `ship released` answers, from the manifest's directory, whether the last release is of exactly the checkout's commits (exit 0 or 1 with the reason): anything that publishes outside `ship publish` asks it first. Install it with mise: `"spm:adriangalilea/swift-utils" = "<tag>"`.

Libraries and packages (this one included) release from CI instead, through [adriangalilea/ci](https://github.com/adriangalilea/ci), which never signs.

## Icons (`mark`)

A Mac app's icon has one source: its Icon Composer package, `<Name>.icon` (the `icon.json` Icon Composer writes, and `Assets/` with each layer as SVG). Open it in Icon Composer to change the lighting, glass or layer order; diff it in git; and compile every icon file from it, so there is never a second drawing:

```
mark preview MyApp.icon [--all]                       # Apple's own rendering, 256 to 20 px, on a page
mark build   MyApp.icon --out Resources --png icon.png  # Assets.car + MyApp.icns (+ a 512 px png)
```

`build` runs `actool`: `Assets.car` is the glass icon macOS 26 draws in every appearance, `MyApp.icns` the flat fallback for Finder's older paths and the dmg's volume icon; the bundle names both (`CFBundleIconName` and `CFBundleIconFile`, each `MyApp`). `preview` renders with Icon Composer's `ictool`, the review before anything ships; `--all` adds the dark, clear and tinted appearances a person can pick. Layers are plain vector SVG: Icon Composer ignores SVG filters, so an effect is baked into the geometry, and a PNG layer is refused (a rendering, not the drawing). Install it with mise like `ship`.

## Brands (`brandgen`)

Any brand mark, natively, with no runtime SVG engine and no dependency. Swift has nothing like react-icons: SF Symbols excludes brands by trademark policy, and every third-party option is either an icon-font relic or a runtime parser. But asset catalogs compile SVG with vector preservation and template rendering, so the only missing piece was a way to GET the artwork.

```bash
swift run brandgen add spotify netflix          # into Scores (the default target)
swift run brandgen add figma --into MyProduct   # another target in this package
swift run brandgen add acme \                   # ...or any app, anywhere
  --catalog ~/app/Assets.xcassets --out ~/app/Brands.generated.swift
```

Upstream is [simple-icons](https://simpleicons.org) (CC0, ~3.4k brands): one SVG per slug, plus a data file carrying each brand's OFFICIAL hex - so colors are the brand's own, never hand-transcribed by whoever added the icon. **The catalog is the manifest**: one imageset per brand on disk, committed, and `Brand` is generated from it - no second list to drift, and a fresh clone builds offline (the network is only for adding a brand).

**Marks load under `swift run` too.** `swift build` copies a catalog into the resource bundle as a raw folder (only Xcode runs actool), so the generated `image` tries the compiled catalog first and otherwise reads the SVG straight from `<catalog>/<slug>.imageset/<slug>.svg` (macOS renders SVG natively; `nsImage` exposes it). On tvOS and iOS the catalog is compiled by xcodebuild and the named lookup answers.

**Local marks ride the same catalog.** `brandgen import` copies a reviewed SVG (single ink, `currentColor`, a viewBox) into an imageset and records `{title, hex, source, original}` in `brandgen.local.json` beside the catalog (exclude it in `Package.swift`; it is a build input, never a resource). Regeneration resolves a slug local-first, then upstream, else dies. `--original` keeps the artwork's own colours for the things that are not logos (a flag). `--enum` names the generated type, so a consumer importing Scores' `Brand` and MediaSpec's `Mark` never sees two `Brand`s. Every generated case also states its `aspect` (from the viewBox), the fact a consumer needs to lay a mark out beside text.

**BRANDS LIVE WITH THEIR CONSUMER, and Ink ships none.** Resources are not code: the linker dead-strips unused code, but a resource ships whether or not anything renders it (asset names resolve by string at runtime, so per-asset usage is undecidable). A brand added to the base layer every app links would ride along forever - so Ink owns only `BrandMarkable` + `BrandMark`, and each module generates the catalog it actually renders. Zero brand bytes by construction, not by discipline.

```swift
BrandMark(Brand.imdb, height: 26)                          // official color
BrandMark(Brand.rottentomatoes, height: 22, tint: .green)  // semantic override
Brand.metacritic.luminance                                 // 0.0 - vanishes on dark
```

Marks are template images: they carry shape, never color. `luminance` is the fact a dark-surface consumer needs, resolved at generation time - a brand whose official color is near-black (Metacritic's #000000, GitHub's #181717) wants a shape-based treatment or an explicit tint, never a silent repaint of someone's logo.

## Scores

The media-ratings vocabulary and the only place the ratings brands ship: `ScoreChip` / `ScoreStrip`, one chip per source with each value in that source's own scale (IMDb 0-10, RT and Metacritic 0-100, Letterboxd pre-scaled 0-10). Two sources get shape-based chips rather than a logo, and they are exactly the two whose official color is unusable on dark: Metacritic's colored box that IS the number, and Letterboxd's tri-color dots. An app that shows no ratings links no ratings logos.

## MediaSpec

Generic media format chips: `Resolution`, `DynamicRange`, `Audio` (codec + channels + object audio), `Tier`, `Lang`, `Cut` as VALUES, plus what the TITLE shows, which every copy shares: its `Rating` (a board, ISO 3166-1 alpha-2, and its value verbatim; `ratingAge` orders boards) and its `Advisory` (a `Severity` none … severe per `AdvisoryCategory`, an absent category unknown); and the chips (`PictureChip` / `SoundChip` / `TierChip` / `LangChip` / `CutChip` / `RatingChip` / `AdvisoryChip`, composed by `MediaSpecStrip`, which takes `rating:` and `advisory:` beside the file's spec) that own every label, short form and mark. An app passes values, never label strings; `pictureLabel`/`soundLabel` are the one spelling ("4K · Dolby Vision", "TrueHD Atmos 7.1"; SDR is the unmarked case and stays silent). A consumer that needs MEANING - what a value's certainty is, how two specs compare, a house spelling for a language - maps it in its own code onto `Emphasis`, a trailing slot, or a label override; this product carries none of it.

**The marks are real.** `Mark` (generated by `brandgen` into `Resources/Marks.xcassets`, origin per file in `Resources/PROVENANCE.md`) holds the Dolby double-D and the Dolby Vision / Atmos / TrueHD / Digital Plus / Digital lockups, the dts symbol and wordmark, DTS-HD Master Audio, the HDR10 and HDR10+ badges, ULTRA HD, FLAC, Opus, Blu-ray Disc (lockup and glyph), Ultra HD Blu-ray, DVD, IMAX, the tabler 4K / 8K / HD / SD badges (MIT), five tabler outline glyphs for the advisory categories (flame, sword, message-exclamation, glass-cocktail, ghost; MIT) and the Spanish civil flag - simple-icons (CC0) where it has them, Wikimedia Commons public-domain files everywhere else, all normalised to one ink, the flag alone keeping its colours. Trademarks, used nominatively: a chip says a spec carries the format the mark names. `Marks.swift` is the one binding from a value to its artwork; a value without an entry is drawn.

**Artwork first; a chip is one mark standing frameless.** The artwork IS the chip: a brand lockup keeps its shape, a brand symbol stands alone - no pill, no disc, no kind glyph around a mark. EVERY DRAWN BADGE IS THE DISC-CASE STICKER, one weight. A one-panel badge (HDR10 / HDR10+ / HLG, channels, Remux, WEB-DL / WEBRip / HDTV / CAM, DTS:X - its only vector is CC BY-NC-SA - TrueHD when the Atmos lockup already says Dolby, AAC / PCM / ALAC / MP3 / MP2 / Vorbis, a language's name, every cut but IMAX, HD and SD) is a near-black ground panel carrying the word at 0.62h semibold inside a true hairline, 0.05h in the badge ink at 70 % opacity (the frame present, never the loudest thing); box height = chip height h, radius 0.25h, side pad 0.26h. A two-panel badge (4K / 8K / 1080p - the "4K ULTRA HD" sticker; no free vector exists, it is typography below the originality threshold) is 1.75h tall, centred on the row, framed at 0.08h in full ink: an upper ground panel with the primary in the badge ink at 0.55 × box, `.black` weight, tight tracking, over a lower band 30 % of the box FILLED with the badge ink carrying "ULTRA HD" / "FULL HD" in the ground colour, uppercase, wide tracking, flush to the frame's inner edge. Under `.ink` that is white frame, black panel, white 4K, white band, black ULTRA HD; `.brand` identical; `.gold` every white becomes the gradient. The box is as wide as its widest line plus twice the side pad, measured by layout. Below the rail the two panels hold while the band text stays ≥ 5pt, else the primary alone. The tabler badges and the Commons HDR10 / HDR10+ badges stay in the catalog as reference and bind nothing. Per axis: picture = resolution badge + range mark (SDR unsaid); sound = object mark, then the codec (lockup, or a word when an object lockup leads), then the channels; tier = disc lockup (Ultra HD Blu-ray when the strip knows 2160p) + Remux; lang = flag (keyed by the REGION subtag) + the name at the rail; cut = IMAX or a word; rating = the board's flag (or its code as a word) + the value; advisory = one chip per stated category: its glyph at h, its name at the rail, then a three-step METER (pips the badge's height tall and a third as wide, filled in the ink, empty ones a hairline at 45 %, so none reads as a known zero). Two rungs, one threshold (`SpecChip.rail` = 32): lockups at and above it, brand symbols (Dolby D, dts, the Blu-ray glyph, the flag) below; drawn badges are the same at both. A strip packs an axis at `.inkTight` and separates axes at `.inkGap`.

**Emphasis is light, never geometry**: `ghost` (0.55 opacity), `plain` (the resting look), `lit` (a soft glow behind the chip in its own ink, radius 0.25h at 45 %), `vivid` (a stronger glow, radius 0.45h at 70 %, with the ink at full brightness - white, or the gold gradient's highlight). No capsule, no ring, no added shape at any level; marks, stickers, word badges and the flag glow the same way. **Tone is the consumer's call**: `.ink` (default) paints a mark in the axis's ink; `.brand` paints it its official hex - never for a brand whose official colour is near-black (Dolby, HDR10, DVD: black on a dark ground is a missing logo, not a brand statement); `.gold` is the disc-case metallic sticker and it is for the DRAWN badges only - frame, letters and band in the `Gold` gradient (≈135°, #FFF1A8 → #E6B422 at 0.45 → #9C7A1B → a thin #FFE680 highlight near the bottom edge) over `Gold.ground`, flat #E6B422 below the rail - while brand marks beside it stay in ink, white on dark, as disc cases print them; `Gold`'s stops, flat and ground are public statics a consumer retunes. The flag ignores tone by construction. **A trailing slot** (`trailing:` per chip, `adornments:` per axis on the strip) takes any view after an axis's last mark. **Languages** name their variety when a generic English name exists (`Lang.varieties`: "Castilian", "Latin American Spanish"), else the language of the subtag alone in the current locale ("Spanish" for es-MX - never the region-qualified "European Spanish"; the flag carries the region), else the tag; `LangChip(label:)` and the strip's `langLabel:` override. Below the rail a language with a flag is the flag alone; at the rail, flag + label.

**The lenient-decode law**: every axis on `MediaSpec` is `@Lenient` - an unknown raw value decodes that ONE field to nil, never throws, never blanks the row. A wire that grows a word this build does not know costs one chip. `Cut` is the exception by design: an unknown cut is carried verbatim as `.other`, because a cut is whatever the disc's spine says.

The raw values are the wire spellings, shared with the React `media-spec` item. `swift run mediaspec-example --check` prints every enum's vocabulary in declaration order and asserts it equals the pinned literal (the React item pins the same literal on its side, so a rename fails a gate instead of drawing a wrong chip), the label rules, the lenient-decode law, and the catalog against its manifest (every imageset is a `Mark`, every value's binding); without the flag it opens the sweep window - every resolution × range, every codec, the four looks, three heights, the trailing slot, the two rungs in both tones, the drawn badges beside the artwork, the whole catalog, and four recipes showing what the generic ergonomics allow.

## Terminal

Command-line output, by the same names as ts-utils `cli` and py-utils `cli`, so a tool reads the same in every language. `ui` is the semantic palette (`head`, `accent`, `muted`, `ok`, `warn`, `bad`, `ref`), decided once per process: FORCE_COLOR paints, NO_COLOR or TERM=dumb does not, else only when stdout and stderr are both terminals. `ANSI` is the always-on vocabulary underneath. `width` counts terminal cells (escapes free, wide and emoji clusters two), `clip` truncates without breaking styles or wide characters, `padEnd`/`padStart` align on visible width, and `table`, `kv`, `indent`, `tree` lay out blocks that stay aligned whether colored or plain.

## Syntax

Code colored for a person to read before they say yes to it, by what its sender SAID it is (`CodeFormat`: `shell`, `diff`, `text`; anything else is plain, never an error). `Syntax.highlight(text, as:)` runs real grammars (highlight.js in JavaScriptCore, through Highlightr, the repo's one third-party dependency), with the language detected where the format does not pin one; a diff is colored by line prefix. Coloring never changes a character: what is approved is what was shown. `SyntaxText` draws it; `Syntax.theme` picks the inks; above `Syntax.ceiling` the text stays plain.

**SyntaxLines** is the half with no engine, for where JavaScriptCore cannot run (a widget, a Live Activity): `CodeColors` is a coloring as data (a palette and runs, a few hundred bytes), computed by `Syntax.colors` where the engine runs and painted anywhere by `paint`; `CodeExcerpt` draws an excerpt. Syntax re-exports it.

## Log

The logging and tracing contract go-utils, ts-utils and py-utils share, in Swift, by the same verbs and the same bytes: [github.com/adriangalilea/utils](https://github.com/adriangalilea/utils) is the contract, and its conformance harness runs `probes/swift` against this module beside the other three. One stream of events, spans as start/end events, W3C `traceparent` across processes, the `LOG_*` variables, `LOG_SHIP`.

```swift
import Log

log.info("ready")
log.warn("retrying", ["attempt": 2])
log.error("charge failed", ["err": error])

try await log.span("charge", ["amount": amount]) { s in
    s.warn("retrying", ["attempt": 2])
    try await s.span("stripe") { c in … }
    s.set(["receipt": receipt])
}

let s = log.begin("upload")        // work that does not fit a block
request.traceparent = s.traceparent // hand the trace on
s.end()                             // or s.end(error), once

let handler = log.join(request.traceparent) // the other side: its spans are children
```

`LogWriter` and `Span` are the two loggers (`Logging`): every verb, `scope`, `begin`, `span`, `join`. Fields are `[String: any Sendable]` taken as an autoclosure, so a line below its threshold builds nothing; values become JSON by the contract's table (an `Error` as `{type, message, cause}`, `Date` as the event time, `Duration` in milliseconds, `Data` base64, anything `Encodable` by its own form, keys sorted at every depth). `Traceparent` is the W3C value as a type: `Traceparent(parsing:)` throws `Malformed` with the reason, and it is `Codable` the same way, so a message that carries one cannot decode with a broken one. `join` of a malformed string warns once and is ignored, as the contract asks of input from outside.

Two sinks: stderr (human at a terminal, JSON elsewhere, `LOG_FORMAT` to choose) and Apple's unified log, where a daemon and an iPhone app are read: subsystem the bundle identifier (else the service), category the scope path joined by dots, the message the event's JSON line at the matching `OSLogType`, so `log show --style ndjson` piped through `jq -r .eventMessage | logs` gives the stream back. `LOG_OSLOG=0` (or `setLogOSLog(false)`) turns it off. The record can also be a file, `LOG_RECORD_FILE` (or `setLogRecordFile(path)`): what the record takes, one JSON line per append, `<name>.1.<ext>` past 4 MiB, safe for several processes sharing it (the contract's "The record as a file"). A record read back on demand reads that file (milliseconds), never the unified log (seconds for an hour, a minute for a day). Shipping hooks `atexit` on its first event; a process leaving through `exec` or a signal calls `flushLog()` first.

## Liveness (a pattern, not yet a module)

Any externally-mutable status an app RENDERS — a TCC grant, an extension's
enable state, a dependency's presence (lore's yt-dlp probe is the origin) —
re-checks on every `didBecomeActive` and on a coarse periodic tick while the
surface showing it is visible. The user flips a toggle in System Settings,
comes back, and the app already agrees; a status read once at view-init is a
lie waiting to be screenshotted. Second lesson from the same hollow session:
check the SOURCE OF TRUTH, not a cache of it — pluginkit mirrors the FSKit
enable plist and the mirror stales, so polling the mirror faster just
refreshes the lie. References: hollow `PermissionsUI`/`SettingsView` (1s poll
+ app-active), lore's dependency probe. Extract into a module when a third
consumer appears.

Presentation corollary (Adrian's doctrine, 2026-08-20): live STATE updates
freely (a row flipping to its green check on grant is the point), but new
GUIDANCE — extra help text, a changed button label — may appear only when a
surface ARRIVES already in the state that needs it, or when the app regains
focus with the task still undone. Never at the moment a button is clicked:
status often flips the instant a prompt fires, and a row that sprouts a
paragraph as you click reads as background mutation, not help. Reference:
hollow `PermissionRow.showDenied`.

## Biometrics

In-window biometrics, no popup. The disease it cures: a gated app that
authenticates through a bare keychain read or `LAContext.evaluatePolicy`
gets macOS's floating system alert ("<app> is trying to unlock <app>… Use
Password / Cancel") thrown over its own window. Safari private mode proves
the right shape: the WINDOW is the prompt — a glyph wearing a fingerprint
badge, one title, one status line, an inline password field; resting a
finger unlocks, typing is the fallback, nothing floats.

```swift
BiometricLock(
    title: "This Vault Is Locked",
    subtitle: "Touch ID or enter the password to open it.",
    reason: "unlock the vault"
) { verdict in
    switch verdict {
    case .biometry(let context):  // evaluated LAContext: keychain reads with
        // kSecUseAuthenticationContext prompt nothing
        unlock(with: context)
        return .accepted
    case .secret(let typed) where verify(typed):
        unlock()
        return .accepted
    case .secret:
        return .rejected("That password didn\u{2019}t match.")
    }
}
```

How it works, and why there is no popup anywhere:

- **`BiometricSensor`** (the public primitive) wraps
  `LocalAuthenticationEmbeddedUI.LAAuthenticationView` (macOS 12+): the
  sensor pairs with ONE `LAContext`, and any `evaluatePolicy` /
  `evaluateAccessControl` on that context renders the Touch ID (or Watch)
  affordance inside the view instead of the system alert.
- **The lock owns the context and hands it back.** The classic popup is thrown
  by the KEYCHAIN when it reads a `.biometryCurrentSet` item. The lock
  evaluates on the paired context (in-window) and delivers it in the
  verdict; passing it to `SecItemCopyMatching` via
  `kSecUseAuthenticationContext` reads the gated item with no second
  prompt (LAContext.h states this contract verbatim). `BiometricAsk` picks what
  a touch authorizes: `.biometry` (a plain curtain) or
  `.accessControl(SecAccessControl, .useItem)` (evaluate the item's own
  ACL up front).
- **Finger-first, typing-seamless.** The sensor arms on appear — a resting
  finger authorizes with zero clicks; the field is focused from the start,
  no mode switch. A cancel stays quiet (no surprise re-prompt); touching
  the sensor glyph re-arms a fresh attempt; no biometry on the machine (or
  lockout) hides the sensor and the lock is password-only, Safari-style.
- **No layout shift, ever** (the presentation corollary above): subtitle
  and rejection messages share ONE fixed slot, a wrong secret shakes the
  field in place (geometry-only) and clears it. The consumer judges every
  verdict (`.accepted` / `.rejected(message)`) and owns dismissal.

- **The lock paints its own stage.** One `surface` color (default: the system
  window background) drives the self-painted full-bleed background AND
  the badge disc, so the fingerprint reads as a cutout of the lock's
  corner (Safari's trick) exactly, by construction. Solid on purpose:
  translucency/materials under the lock wash the system glyph into low
  contrast (learned live in a consumer). A consumer writes
  `BiometricLock(title:subtitle:reason:judge:)` and nothing else.

Demo: `swift run biometrics-example` — real Touch ID in-window, demo password
"sesame"; the open state shows the compact forms.

The compact form ships too: **`BiometricField`** — Ink's `SecretField`
with the Touch ID sensor built in. Three ways through: type, REST A FINGER
(the paired sensor rides invisibly over a quiet static glyph — red while
armed, the sensor's own semantic — recognizes in place, bounces green;
wrong finger shakes and re-arms), or click for the classic system prompt.
Generic over the key type: `BiometricUnlock(reason:unlock:)` says what a
finger opens (a nominal type - an inline tuple+closure defeats the type
checker; passed as `biometric:`), success
hands `unlock` the evaluated context, and `kSecUseAuthenticationContext`
keychain reads prompt nothing. `LoginPassword.verify` rounds it out: the
typed fallback for curtains that gate nothing keychain-bound - Safari's
own semantics (the user's LOGIN password, via OpenDirectory; unsandboxed
apps only).

**`BiometricButton`** is a press that needs biometrics, on every device:
Ink's prominent capsule (`InkButtonStyle`, colored by the host's `.tint`)
whose round well, concentric with the trailing cap, holds the biometric
glyph, so it reads as a finger or a face before anyone presses. On a Mac the
well IS the sensor (the field's invisible-sensor-under-the-glyph, the glyph
pulsing while armed), so a resting finger is the press and its proof in one
gesture; on an iPhone it holds Face ID's glyph and the press asks for it. `BiometricButton("Book it",
context: armed, onReady: { start($0) }) { click() }`; the lock, the field and
the sensor build on macOS alone, the button everywhere.

## PermissionGrants

Every permission an app needs as one `PermissionGrant`, declared once by name
(`static let microphone = PermissionGrant.privacy(.microphone, title:, why:)`)
and used by that name on every screen (`PermissionGrant.Section`, `.Sheet`,
`.Steps`, `.Chip`, `.LaunchAtLogin`) and in every line of code (`isAllowed`,
`await ask()`, `observe`): Privacy & Security switches read live (tccd, a
fresh process after a change, Apple's public calls as the fallback),
background services, notifications, the app's own. One line in every app's
`main`: `PermissionGrant.answerProbeIfAsked()`. The `grant` CLI reads and
resets an app's permissions from outside. The whole of it, measurements
included: [Sources/PermissionGrants/README.md](Sources/PermissionGrants/README.md).

## AppInstallations

An app's whole life on the Mac as `AppInstallation`: where the bundle lives and
moving it into Applications, for everyone or just this account as the app
offers and the person picks (`home`, `moveHome(to:)`), the jobs it runs beside
itself (`Job`: a launch agent, a root daemon, the login item; installed,
approved, answering a probe, read live as one `state`), and what happens when
the bundle is upgraded or deleted under it (`ImageWatch`: jobs restart into the
new image or leave launchd, the app reopens or quits). A background service's
grant is a job's state. The rules and how to prove them:
[Sources/AppInstallations/README.md](Sources/AppInstallations/README.md).

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
- which-key discoverability: anchored floating tips that show the minimal completion of whatever prefix is held (`shortcutTipLayer` / `.shortcutTip`), fed by the ONE `RevealMonitor`; a tip sits beside its control on the edge it asks for and flips to the other side when the window has no room there (`ShortcutTip.place`). `swift run keymap-example` shows them on controls along every edge; `--check` runs the completion and placement laws headless, in `mise run check`
- system-wide hotkeys - registry combos AND family combos (⌥⌘1-9 style) - re-registered live on remap and keyboard-layout change, no accessibility permission (`GlobalHotkeys`); press+release delivery for hold-shaped bindings via `PressReleaseHotkey` - the push-to-talk pair Ink's `PushToTalk`/`MicButton` consume
- in-app routing for alternate combos, families, and panel surfaces, skipping menu-carried representatives (`LocalKeyRouter`; apps with richer arbitration keep their own monitor and just use `store.match`)
- Spotlight / Siri / Shortcuts / Apple Intelligence via App Intents (the action set made an `AppEnum` too, its titles checked against the registry's at launch by `assertIntentDisplayMatchesRegistry()`) - the macOS command palette is the OS, so Keymap ships none
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

Pin the minor you built against; every release that can be taken safely is then taken by `swift package update`, and no break ever is:

```swift
// Package.swift
.package(url: "https://github.com/adriangalilea/swift-utils", .upToNextMinor(from: "0.26.0")),
```

```yaml
# project.yml (xcodegen)
packages:
  swift-utils:
    url: https://github.com/adriangalilea/swift-utils
    minorVersion: 0.26.0
```

`from:` reads "anything below 1.0" while the package is on 0.x, so it takes every break; `upToNextMinor` is the promise the version numbers below make.

**What changed for you: `since`.** Run inside an app, it reads the swift-utils its `Package.resolved` holds, finds the modules the app imports (and what they build on), and prints for each what changed between that version and the latest: the breaks first, with what to write instead, then the features and the fixes. Each break is judged against the app: the API its note names first in each clause (the old one, before its replacement) is looked for in the app's code, so it says "touches you: ShortcutBadge at Layers.swift:364", "doesn't touch you", or, when the note names no API, "may touch you". A migration note that names the old API is what makes this work. `since --all <dir>` does it for every app under a directory, one line each. `since --json` for a program. Install it with mise like `ship`.

**Iterate without a release.** Committed manifests always pin a version; a local checkout stands in only on your machine:

- an app built by SwiftPM: `swift package edit swift-utils --path ../swift-utils`, `swift package unedit swift-utils` to go back. Every package in the build sees the checkout, the ones that pin swift-utils themselves included.
- an Xcode project: add the local checkout to the project (File › Add Package Dependencies › Add Local); Xcode prefers a local package to the remote one of the same name. Remove it before committing.

**Pin a version, never a revision.** A revision is a release nobody can name, and SwiftPM needs every package in one build to ask for swift-utils the same way, so one revision pin spreads to every package built beside it. Work that is not released yet is released by pushing it (below).

## Release

Releasing is never a decision. Every push to main that passes the gate (format, release build, tests, every claimed platform) is released by CI, the version read from the commits since the last one:

| since the last release | while 0.x | from 1.0 |
|---|---|---|
| a break (`type!:` or `BREAKING CHANGE:` in the body, saying what to write instead) | minor: 0.26.0 → 0.27.0 | major |
| `feat` | patch: 0.26.0 → 0.26.1 | minor |
| `fix`, `perf`, `refactor`, `revert` | patch | patch |
| only `docs`, `style`, `test`, `ci`, `chore`, `build` | no release | no release |

A commit that is not conventional stops the release: the version cannot be read from it. So the commit message is the release: its type is the bump, its body the migration note `since` shows.

Git is the registry: SwiftPM has no manifest version field, so the tag IS the version, and any file claiming one is a second source of truth. Mac apps invert this: a bundle has a native version (`CFBundleShortVersionString`), so `ship` takes the version from the app.

The pipeline lives in [adriangalilea/ci](https://github.com/adriangalilea/ci) (`mise.yml`, `next-version.yml`, `release.yml`), called from `.github/workflows/ci.yml`; it is versioned there, so a Keymap patch and a pipeline change never share a version number.
