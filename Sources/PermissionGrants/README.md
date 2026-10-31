# PermissionGrants

Every permission an app needs, declared once by name and read live on every screen and in every line of code. A Privacy & Security switch, a background service, notifications or anything of the app's own is one `PermissionGrant`, and its `Standing` is the one answer every surface renders: no surface re-derives "is this a problem?", so a settings row and a banner can never disagree.

`PermissionGrant` is the module's one top-level name; everything else is nested in it (`PermissionGrant.Standing`, `.Privacy`, `.Section`, `.Claim`, …), so no app's own `Grant`, `Permission`, `Standing` or `Claim` collides with it, and `PermissionGrants.PermissionGrant` qualifies it if anything ever does.

## Declare once, use by name

```swift
import PermissionGrants

extension PermissionGrant {
    static let systemAudio = PermissionGrant.privacy(.systemAudio,
        title: "System Audio", why: "Records the other side of the call.")
    static let microphone = PermissionGrant.privacy(.microphone,
        title: "Microphone", why: "Records your side of the call.", required: false)
    static let helper = PermissionGrant.backgroundService(.agent(plist: "garden.untitled.x.plist"),
        title: "Background helper", why: "Keeps running when the window is closed.")
    static let alerts = PermissionGrant.notifications(why: "Says when a call is saved.")
}

// Screens
PermissionGrant.Section("Permissions", [.systemAudio, .microphone, .helper, .alerts])

// Code
guard PermissionGrant.systemAudio.isAllowed else { throw … }  // the gate
guard await PermissionGrant.microphone.ask() else { return }  // ask, and wait for the answer
PermissionGrant.microphone.observe { standing in … }          // the hook
```

The kinds:

- `.privacy(_:title:why:)`: a switch in System Settings › Privacy & Security: `.accessibility`, `.postEvents` (typing into other apps, listed under Accessibility), `.inputMonitoring`, `.systemAudio`, `.screenRecording`, `.microphone`, `.camera`, `.speechRecognition`, `.motion` (headphone motion), `.fullDiskAccess`, `.calendars`, `.reminders` (EventKit's full access; add-only counts as off). On an iPhone and an Apple Watch the same call takes the switches those platforms have: `.calendars`, `.reminders`, and on the iPhone `.alarms` (AlarmKit). They answer a running app live, so their standing is the public status, read when a surface appears, after an ask and when the app comes forward; a denied one opens the app's Settings page on the iPhone, and on the watch, which can open none, its note is the fix.
- `.automation(of:title:why:)`: Privacy & Security › Automation, Apple Events to one app.
- `.backgroundService(job, title:why:installFor:)`: a process the app runs beside itself, an `AppInstallation.Job` (swift-utils `AppInstallations`, whose README holds the rules). The row renders the job's state with its one fix: running is good; off turns it on; awaiting approval opens Login Items (approving a daemon is an admin's act, so a standard account is told to ask one); silent restarts it; an app running from outside an install the job allows moves itself (`installFor`: one scope moves there, `[.everyone, .me]` asks for whom first); with no plist inside, the build is bare. A failed act is the row's note until the next try.
- `.notifications(why:)`: notifications posted from the app's own process (macOS, iOS, watchOS; a watch app's notification settings live in the Watch app on the iPhone, which the note says).
- `PermissionGrant(title:why:symbol:standing:act:)`: the app's own, two closures run on the main thread (hollow's file-system module, a helper's recorded notification reach).

In a target that is MainActor by default (`-default-isolation MainActor`), declare them `nonisolated static let`: a `PermissionGrant` is Sendable, and an actor that gates on one (steno's recorder) must reach it.

A library declares its grants with a name no app will take (`listenMicrophone`, not `microphone`): every importer shares the one `PermissionGrant` namespace.

Every grant answers the same five things: `standing`, `isAllowed` (the gate: `standing` is good), `blocking` (required and broken: the one banner/preflight predicate), `ask()` and `act()` (its button: `ask` without waiting), and `observe`. A background service also has `unregister()`.

## Standing

`good` (checkmark, nothing warns) · `askable` (one click asks: an offer, not a failure) · `broken` (every surface warns with the SAME note and action) · `unknown` (the app cannot see it: a quiet "unknown", no checkmark, no button, never warns, never blocks). `Grade.needsUser` is the one predicate for "something to ask or fix".

**Two lines per grant, never three**: what it is (`title`) and ONE short line under it, the standing's note when it has one (it says what to do now), the `why` otherwise.

## Shapes, none forced

Every surface composes from the same grants; the app picks the one that fits the moment:

- `PermissionGrant.Row(grant)`: one row (`.row`, or `.card` for a device-list card).
- `PermissionGrant.Section(title?, grants, footer:)`: a Settings section, required first; untitled inside a host's own `Section`.
- `PermissionGrant.Sheet(title:, subtitle:, grants, optionalNote:) { done }`: everything on one sheet, required and optional apart, "later" while a required one needs the person, "done" after (hollow's).
- `PermissionGrant.Steps(grants, welcome: { … }) { done }`: a page per grant that moves on by itself the moment its grant is good; an optional one can be skipped, a required one waits (steno's onboarding). `PermissionGrant.Page(grant)` is one page alone.
- `PermissionGrant.Chip(grant, label: "can't type into apps yet", fill:)`: the warning that is its own fix, for a menu or a toolbar: the grant action saying what is not working; hovered or focused, the same box says the fix; a click acts. The resting words say it all (no tooltip). Truly nothing once good, no gap in a stack. `fill` takes the host's width (a menu row aligned with its neighbours), otherwise it hugs its words; `.controlSize(.small)` for a dense line.

**One design language, the studio's.** Every grant action, a row's, a card's, a page's and a chip's, is Ink's tinted button (`.inkTinted`): its words and a ↗ in the standing's hue (orange to fix, yellow to ask; a card's icon wears it too), never a filled slab. A good standing is Ink's status mark, a green check in a circle the actions' height: plainly a status, not a button. Both stand on the host's material: Liquid Glass by default (interactive from rest, as Apple's own glass buttons), `.inkMaterial(.flat)` for a quiet neutral fill.
- `PermissionGrant.LaunchAtLogin(label)`: "open at login" as the choice it is, never a requirement.

The words this library writes on buttons and headings ("Open Settings…", "Later", "Required") are Title Case, macOS's; an app with a lowercase voice sets `.permissionGrantCase(.lower)` once on its host and every one follows. Notes are sentences and keep their case.

Every standing is observable, for every kind, so a surface repaints the moment what it shows changes and never otherwise: no timer, no stale state, no loading state. A surface appearing asks for a fresh read (on a Mac it opens the hub's settings window, below).

## Asking

`ask()` asks the way each grant asks. A Privacy switch: allowed, nothing; allowed on reopen, the app reopens; denied, its pane opens (macOS never prompts twice); never asked, the app comes forward (macOS asks only an active app) and the request is made by one rule: Apple's public ask where one exists (AVFoundation, `CGRequest…`, `AXIsProcessTrustedWithOptions`, `SFSpeechRecognizer`), TCC.framework's `TCCAccessRequest` where none does (System Audio, Motion), the pane where macOS has no prompt at all (Full Disk Access, after one refused read of the system TCC database: macOS lists an app there, switched off, only once it has been refused such a read, so the person flips a switch instead of adding the app with +). Where a prompt answers, `ask` returns that answer; where the answer is a switch in System Settings, it returns at once and `observe` reports the flip.

## The Privacy hub: one live answer

**What macOS tells a running app is as of its launch.** The public checks (`CGPreflightPostEventAccess`, `AXIsProcessTrusted`) keep their first answer for the life of the process, and tccd, asked directly (`TCCAccessPreflight`), answers a running process as it stood at launch too: Accessibility read "denied" while macOS already let grant-example type into TextEdit; the microphone read "allowed" after it was reset (2026-10-21). The truth after a change lives only in a NEW process. So:

- **First read**: synchronous, in-process, so a surface's first frame is the truth (at launch the two agree).
- **Idle otherwise**: nothing is read while nothing can change.
- **The settings window**: two minutes after the app comes forward, an ask, a pane opened, a grant surface appearing (a menu opening counts: a menu bar app never "comes forward"), or macOS's Accessibility-change notification (each opening logged with its reason). Every 2 s in it, ONE fresh process of the app's own binary (`--grant-probe`, spawned disowned with `responsibility_spawnattrs_setdisclaim` so tccd judges it as itself) answers every watched switch, grants and revocations alike.
- **Live or on reopen**: where macOS enforces a switch on the running app at once (Accessibility, posting events: measured), the fresh answer is the answer; where it does not (Input Monitoring, Screen Recording: macOS's own "Quit & Reopen"), a fresh "allowed" reads "Reopen" (a new instance opened, this one quit; macOS's own "Quit & Reopen" once quit and never reopened). Unmeasured switches stay on the reopen side.

**One line per app**, first in `main`: `PermissionGrant.answerProbeIfAsked()`. Without it there is no probe, and a change shows only when the app reopens.

## The hook

`grant.observe { standing in }` runs on the main thread with each change of that grant's standing, for every kind: it is Observation over the same standing every view reads. A Privacy switch publishes through the hub; what macOS does not announce (a background service's registration, a notification setting, Apple Events consent) is re-read after an ask, when a surface appears, when the app comes forward, and on a Mac every 2 s inside the settings window; an app's own grant publishes through the observable state its closure reads. Outside those moments nothing is read. No app writes a polling loop.

## The fallback, one source at a time

The hub's source is chosen once at launch and never mixed: `tccd` (TCC.framework's private preflight) or, on an OS without it, `public API` (`AXIsProcessTrusted`, `CGPreflight…`, AVFoundation's, Speech's and CoreMotion's status), where never-asked and denied look alike until this run's first ask, and System Audio Recording and Full Disk Access read `.unknown` ("macOS doesn't tell apps this one"). Without the disowning spawn the probe switches off and changes show on reopen. Each loss is one logged error, never a crash; every reading logs its source. `GRANT_PUBLIC_API=1` forces the fallback, so it stays exercised.

Local Network has no grant: macOS gives apps no way to read or ask for it.

## Signing, the trap behind "switch on, reads denied"

One bundle id has ONE record per switch, bound to the signature of the build that received it. A Developer ID release and an Apple Development build of the same app do not share it: the other one reads denied with its switch shown ON (utter, 2026-10-20). Under the hardened runtime the microphone and the camera also need `com.apple.security.device.audio-input` / `com.apple.security.device.camera` in the entitlements, or macOS denies without asking; the ask logs that as an error.

## Instrumentation and the `grant` CLI

Every reading is logged in the app's unified log, scope `grant`, the first time and at each change, with its source and raw code; so is every ask, every pane opened, and every settings window with its reason.

- `grant status <app>`: the latest reading of each permission, every copy of the bundle id on disk with its signer, and a warning when copies are signed differently.
- `grant reset <app>`: quits it, clears every record macOS holds for the bundle id, reopens it.

## Notifications

`PermissionGrant.Notifications.reach()` answers `Reach`: `notAsked` / `denied` / `silenced` (allowed, but alerts off, style None, or quiet delivery: nothing appears, which for a message that matters is denied) / `allowed`, and `Notifications.standing(_:)` is the one mapping to a Standing. Asking prompts once, then opens the app's own row in System Settings › Notifications. A launchd agent or bare binary cannot use UNUserNotificationCenter: it posts through a nested helper app, the helper records the reach, and the agent declares a custom grant whose standing is `Notifications.standing(recorded)` and whose act is `Notifications.openSettings(bundleID:)` with the HELPER's bundle id (the row belongs to whoever posts).

## Claim

`PermissionGrant.Claim` is the proof machine for capabilities whose system readout can lie (a settings plist that records intent while the daemon serves nothing): intent is a claim, a real outcome is the only witness, the verdict reconciles them, and every prediction/reality disagreement is a journaled CONTRADICTION. `evaluate(intent:live:)` takes the switch as the consumer read it (`.on`, `.off(reason)`, `.unreadable`), and the machine adds only what IT learned, a failure under a switch that claims on (`whenFailing`). An unproven claim renders `good`; an unreadable switch is `unknown`: only the capability seen live right now vouches for it. A custom grant renders its verdict.

## Try it

`mise run grant-example` builds `grant-example.app` (its own bundle id, signed, with a launch agent inside) and opens it: every shape over real permissions, plus `type a test word` and `listen test`, which check what macOS lets the running process do whatever any check answers. `grant reset grant-example` starts it over.
