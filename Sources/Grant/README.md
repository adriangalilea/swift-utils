# Grant

Every permission an app needs, read live and drawn the same way on every surface. A TCC permission, a background service, a notification setting or a capability claim each resolves to ONE `Standing`, and every surface renders it mechanically: no surface re-derives "is this a problem?", so a settings row and a banner can never disagree.

## Standing

`good` (checkmark, nothing warns) · `askable` (one click asks: an offer, not a failure) · `broken` (every surface warns with the SAME note and action) · `unknown` (the app cannot see it: a quiet "unknown", no checkmark, no button, never warns, never blocks). `Grade.needsUser` is the one predicate for "something to ask or fix"; `grant.blocking` (required and broken) is the one banner/preflight predicate.

**Two lines per grant, never three**: what it is (`title`) and ONE short line under it, the standing's note when it has one (it says what to do now), the `why` otherwise. Notes are a short sentence; nothing stacks.

## Ready grants

- `TCCGrant(.microphone, title:, why:, required:)`: any TCC permission the hub reads, in one line. The app writes what it is for; the standing and the ask are `TCC`'s.
- `BackgroundServiceGrant(.agent(plist:) | .daemon(plist:) | .loginItem, title:, why:)`: a process the app runs beside itself through `SMAppService`. `.notFound` alone means three things, so the status is read against where the bundle stands (`Placement`): in /Applications it registers; from the disk image or translocated it moves the app into /Applications and reopens it there; with no plist inside, the build is bare. `.requiresApproval` opens Login Items, and approving a daemon is an admin's act, so a standard account is told to ask one. A failed register is the row's note until the next try. Each status is logged when read and at every change.
- `NotificationGrant(why:)`: notifications for an app that posts from its own process (below).
- A custom grant conforms to `Grant` (`symbol`, `title`, `why`, `required`, `standing`, `act()`).

```swift
let typing = TCCGrant(.postEvents, title: "Accessibility", why: "Types what you say into other apps.")
let agent = BackgroundServiceGrant(.agent(plist: "garden.untitled.awake.plist"), title: "awake", why: "Keeps the Mac awake with the lid closed.")
```

## Shapes, none forced

Every surface composes from the same grants; the app picks the one that fits the moment:

- `GrantRow(grant)`: one row (`.row`, or `.card` for a device-list card).
- `GrantSection(title?, grants, footer:)`: a Settings section, required first; untitled inside a host's own `Section`.
- `GrantSheet(title:, subtitle:, grants, optionalNote:) { done }`: everything on one sheet, required and optional apart, "later" while a required one needs the person, "done" after (hollow's).
- `GrantSteps(grants, welcome: { … }) { done }`: a page per grant that moves on by itself the moment its grant is good; an optional one can be skipped, a required one waits (steno's onboarding). `GrantPage(grant:)` is one page alone.
- `GrantChip(grant)`: inline, only while it needs the person, its note or name beside the button, nothing once good.
- `LaunchAtLoginToggle(label)`: "open at login" as the choice it is, never a requirement.

Each re-reads its grants every second and at once through the hub, so none can show a stale state or a loading one.

## Permissions: the one live answer

`Permissions.shared` reads Accessibility, posting events, Input Monitoring, System Audio Recording and the microphone. `TCC` is the vocabulary over it: `accessibility()`, `postEvents()`, `inputMonitoring()`, `systemAudio()`, `microphone()` (true / false / nil = never asked) and their `request…`. Every ask goes the same way: the app brought forward (macOS asks only an active app), the request made (with no record it prompts and lists the app), the pane opened when the person already said no, a "Reopen" relaunch when that is what applies it. Per-app Apple Events stay on `AEDeterminePermissionToAutomateTarget`.

**What macOS tells a running app is as of its launch.** The public checks (`CGPreflightPostEventAccess`, `AXIsProcessTrusted`) keep their first answer for the life of the process, and tccd, asked directly (`TCCAccessPreflight`), answers a running process as it stood at launch too: Accessibility read "denied" while macOS already let grant-example type into TextEdit; the microphone read "allowed" after it was reset (2026-10-21). The truth after a change lives only in a NEW process. So:

- **First read**: synchronous, in-process, so a surface's first frame is the truth (at launch the two agree).
- **Idle otherwise**: nothing is read while nothing can change.
- **The settings window**: two minutes after the app comes forward, an ask, a pane opened, or macOS's Accessibility-change notification (each opening logged with its reason). Every 2 s in it, ONE fresh process of the app's own binary (`--grant-probe`, spawned disowned with `responsibility_spawnattrs_setdisclaim` so tccd judges it as itself) answers every watched permission, grants and revocations alike.
- **Live or on reopen**: where macOS enforces a switch on the running app at once (Accessibility, posting events: measured), the fresh answer is the answer; where it does not (Input Monitoring: macOS's own "Quit & Reopen"), a fresh "allowed" is `.allowedOnReopen`, which `TCCGrant` shows as "Reopen" (a new instance opened, this one quit; macOS's own "Quit & Reopen" once quit and never reopened). Unmeasured services stay on the reopen side.

**One line per app**, first in `main`: `Permissions.answerProbeIfAsked()`. Without it there is no probe, and a change shows only when the app reopens.

Changes publish through Observation (a view that read one repaints) and to `Permissions.shared.observe { service, answer in }`, the hook: no app writes a polling loop.

## The fallback, one source at a time

`Permissions.source` is chosen once at launch and never mixed: `tccd` (TCC.framework's private preflight) or, on an OS without it, `publicAPI` (`AXIsProcessTrusted`, `CGPreflight…`, AVFoundation's status), where never-asked and denied look alike until this run's first ask and System Audio Recording reads `.unknown` ("macOS doesn't tell apps this one"). Without the disowning spawn the probe switches off and changes show on reopen. Each loss is one logged error, never a crash; every reading logs its source. `GRANT_PUBLIC_API=1` forces the fallback, so it stays exercised.

## Signing, the trap behind "switch on, reads denied"

One bundle id has ONE record per service, bound to the signature of the build that received it. A Developer ID release and an Apple Development build of the same app do not share it: the other one reads denied with its switch shown ON (utter, 2026-10-20). Under the hardened runtime, the microphone also needs `com.apple.security.device.audio-input` in the entitlements, or macOS denies it without asking; `requestMicrophone` logs that.

## Instrumentation and the `grant` CLI

Every reading is logged in the app's unified log, scope `grant`, the first time and at each change, with its source and raw code; so is every ask, every pane opened, and every settings window with its reason.

- `grant status <app>`: the latest reading of each permission, every copy of the bundle id on disk with its signer, and a warning when copies are signed differently.
- `grant reset <app>`: quits it, clears every record macOS holds for the bundle id, reopens it.

## Notifications

The same shape for the permission TCC doesn't own. `Notifications.reach()` answers `NotificationReach`: `notAsked` / `denied` / `silenced` (allowed, but alerts off, style None, or quiet delivery: nothing appears, which for a message that matters is denied) / `allowed`, and `Notifications.standing(_:)` is the one mapping to a Standing. `request()` asks once, then deep-links to the app's own row in System Settings › Notifications. A launchd agent or bare binary cannot use UNUserNotificationCenter: it posts through a nested helper app, the helper records the reach, and the agent renders `Notifications.standing(recorded)` and opens settings with the HELPER's bundle id (the row belongs to whoever posts).

## CapabilityClaim

The proof machine for capabilities whose system readout can lie (a settings plist that records intent while the daemon serves nothing): intent is a claim, a real outcome is the only witness, the verdict reconciles them, and every prediction/reality disagreement is a journaled CONTRADICTION. `evaluate(intent:live:)` takes the switch as the consumer read it (`.on`, `.off(reason)`, `.unreadable`), and the machine adds only what IT learned, a failure under a switch that claims on (`whenFailing`). An unproven claim renders `good`; an unreadable switch is `unknown`: only the capability seen live right now vouches for it.

## Try it

`mise run grant-example` builds `grant-example.app` (its own bundle id, signed, with a launch agent inside) and opens it: every shape over real permissions, plus `type a test word` and `listen test`, which check what macOS lets the running process do whatever any check answers. `grant reset grant-example` starts it over.
