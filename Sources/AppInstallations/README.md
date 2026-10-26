# AppInstallations

An app's whole life on the Mac, owned by the app: where its bundle lives and moving it into Applications, the processes it runs beside itself (a launch agent, a root daemon, the app as a login item), an upgrade landing under it, and its removal when the bundle is deleted. One top-level name, `AppInstallation`; everything else is nested in it. macOS only.

**No AppKit, so every process of the app links it:** the app, and the agents and root daemons that deliberately carry none (chilld, authzd). What an app does to itself goes through the system's own tools: opening a copy is `/usr/bin/open`; "is THE app already running there" is every process's image (`proc_pidpath`); copies of the app by bundle id come from Spotlight (`mdfind`) and the Applications folders; the app quits itself with a Quit Apple Event to its own process, sent from the main thread, which AppKit answers with a normal terminate (state saved). A process with no event loop to answer it exits after ten seconds.

```swift
import AppInstallations

extension AppInstallation.Job {
    static let chilld = AppInstallation.Job(
        .daemon(plist: "garden.untitled.chilld.plist"), name: "chilld",
        answers: { (try? Client().hello()) != nil })
}

try await AppInstallation.Job.chilld.install()   // registers, waits for approval, waits for it to answer
AppInstallation.Job.chilld.state                 // .running, .off, .awaitingApproval, .silent, .misplaced, .bare
```

## Where the app lives

- An install is for a `Scope`, macOS Installer's own question: `.everyone` (/Applications) or `.me` (~/Applications). Which to offer is the app's call, the choice the person's. Data never follows the bundle: settings, records, caches and XDG dirs are per account wherever the app lives, so an install for everyone still keeps each account's data apart. What does follow it is any path into the bundle: a CLI symlinked onto PATH dangles once the app moves between scopes, until the install it moved to opens and re-points it (`ImageWatch`, below).
- `AppInstallation.home` is `.installed(scope)`, `.elsewhere(url, origin)` (a disk image, a translocated download, a folder) or `.noBundle` (a `swift build` binary). `home.words` names the place for a person.
- `moveHome(to: scope)` opens an install already in that scope's folder when it is the same build or newer (`CFBundleVersion`, compared as numbers), replaces it when it is older (the old one to the Trash, this bundle copied in its place through a fresh path, logged "replaced an older install" with both builds; an older copy still running follows its replaced bundle through its `ImageWatch`, as on any upgrade), or copies the bundle there and opens the copy; this one quits. `installedCopy(in:)` finds an existing install. `reopen(why)` opens a fresh instance of this bundle and quits.

## Jobs

A `Job` is declared once, by name, like a permission. Its `state` is read now, every time, and is the one answer every surface and verb renders:

| State | Means | The fix |
|---|---|---|
| `running` | the job answers | none |
| `off` | installable, not installed | `install()` |
| `awaitingApproval(needsAdmin:)` | registered, held in Login Items | the person's OK at `Job.approvalPath` |
| `silent` | registered and approved, not answering here (stopped, or registered for another copy) | `install()` unregisters and registers afresh |
| `misplaced(home)` | the app runs from an install the job cannot (`scopes`) | `moveHome(to:)` |
| `bare(missing:)` | this build has no such plist | a build problem |

The rules, each a failure an app met:

- **The place is judged first.** A registration is bound to the bundle's path, and macOS's record can outlive the copy it was made for (a deleted app's stays enabled). An app outside the job's `scopes` is `misplaced` whatever the record says.
- **A root daemon runs only from an install for everyone.** From a folder the person can write to, replacing its binary would run anyone's code as root, so a daemon's `scopes` is `[.everyone]`; an agent or a login item runs as the person, from either.
- **`.enabled` is not running.** It is Background Task Management's record. A job can be enabled and not loaded, or loaded and stuck. The truth is the job answering: `answers` is the app's own probe (an XPC ping, a socket, with its own short timeout); without one, launchd is asked (`launchctl print`, state running).
- **Registering right after unregistering fails** (EPERM) until BTM settles, for seconds: `install()` retries.
- **A stray plist** under the agent's label in ~/Library/LaunchAgents (an older install's) is removed before registering.
- `uninstall()` unregisters; `restart()` kicks an agent.

`PermissionGrants` renders a job as a grant: `PermissionGrant.backgroundService(job, title:, why:, installFor:)` shows its state as a row, a chip or a page, with the state's one fix as the action. `installFor` is what a misplaced app offers (`[.everyone]` by default): one scope moves there, `[.everyone, .me]` asks the Installer's question first ("Move to Applications…").

## Moved, upgraded, deleted: `ImageWatch`

A bundle moved, replaced or deleted under a running process announces nothing and runs no hook (a Finder drag, a cask's sandboxed steps, an updater swapping the bundle). Every process of the app keeps its whole life, the app and each job alike, from one call at the top of `main`:

```swift
let watch = AppInstallation.ImageWatch.start(
    jobs: [.chilld],                               // the app's own declarations: their probes are the witnesses
    keeps: [logs],                                 // state beyond the standard places by bundle id
    links: [.init(home.appending(path: ".local/bin/chill"), to: "Contents/MacOS/chill")])
withExtendedLifetime(watch) { App.main() }
```

**At launch (the app):** jobs named stale or asked for by a move are registered here, and so is every job that is on but not answering from this copy; when this copy is an install (an Applications folder), command-line links into another copy (or dangling, shaped like this app's) are re-pointed here; a copy opened from a dmg, Downloads or a build folder leaves them alone. A link is the person's install: never created, only kept pointing at THE app.

**The fact everything turns on:** launchd follows the bundle it registered, never the path. Measured: after a replace-style upgrade (old bundle to the Trash, new one copied in) a job restarted from the copy in the Trash, running the old code silently; after a move it respawned from the vanished path and failed (EX_CONFIG) forever. A job belongs to this copy only when the process launchd runs for it lives inside this copy (`proc_pidpath`, readable for root's processes too); otherwise it reads `.silent` ("registered for another copy") and installing it unregisters first, then registers from here, which also stops the other copy's process.

**Then each process watches its executable:**

- **Replaced** and whole (the new executable holds this process's designated requirement, read at the start while the old image still exists, and the whole bundle is valid, nested code included): the app reopens into it. An upgrade that deletes the old image outright (a cask, `rm -rf`) leaves nothing to read a requirement from, which is why it is read once. A job is the witness that its registration is stale: it opens the copy at its path headless (`open -n -g -j`, no window) naming itself, and that copy registers it afresh and exits.
- **Gone** `goneAfter` ticks in a row (one missing tick is an upgrade mid-copy), then judged:
  - **Moved** when a copy is the very files that vanished (its executable is the same inode: a rename, the Finder drag on one disk) or an install in an Applications folder (a move across disks). Nothing is forgotten. A job hands itself to the moved copy the same headless way; the app reopens from the moved copy. A leftover copy anywhere else (a download, a build folder) is neither, so it never blocks an uninstall.
  - **Deleted** otherwise: `forget`: the standard places by bundle id (Application Support, Caches, HTTPStorages, WebKit, Saved Application State) and `keeps` go to the Trash, the preferences file with them (never cleared through cfprefsd, which then rewrites an empty file), and the links into the deleted bundle are removed. Every move is logged with its path. The app and each job all run it, idempotently; the app at its exit, after its last save. As root, only `keeps`, by exact name: a file is removed, a directory only when empty, never recursively. The person's side is the app's own declarations' to forget, so when no process of the app is alive in the person's session (the app quit before the delete, the daemon alone left) the root job runs the deleted copy, still in the Trash, as the person at the console (`launchctl asuser` + `sudo -u`) with `--app-installation-forget <old path>`; that copy forgets and exits before any window. An app that parses verbs reads `AppInstallation.appArguments(_:)`, its launch arguments without this module's own, and treats `AppInstallation.isInstallationLaunch(_:)` as the app's own launch whatever its parent: a hand-over runs the new copy's executable as a child of the old job, never through LaunchServices, so "no verb and `getppid() == 1`" misreads it as the command line (awake engaged an indefinite claim on every upgrade that way, 2026-10-22). With the Trash already emptied, or nobody at the console, the person's side stays.
- **Leaving:** a job boots its label out of launchd only while launchd's process for it is this one (a newer copy may hold the label by now), else it just exits; the app quits.

**Handing back, on every stop.** Unregistering stops a job without a SIGTERM, and a job that holds hardware (chilld forcing the fans) must give it back first, or it stays held. Two hooks, so no path forgets it: `ImageWatch.start(beforeLeaving:)` runs inside the process before the watch stops it, whatever the reason (deleted, moved, replaced), and before any cleanup or hand-over; `Job(…, handBack:)` is what the app asks of the job (an XPC call) before every unregister this module makes: `uninstall`, a fresh registration, a move's hand-over. Handed back means unable to take it again until the process stops: the job freezes whatever would re-arm it. awake's first hand-back released its lid claim, and its next tick read its own release as an outside writer and dropped every claim; it now parks its state machine for good once handed back.

A root daemon cannot open apps in the person's session: on a move or a replace it only leaves, and the app registers it afresh at its next launch (until then its row offers Restart).

- **One press ends with the job working.** A move that was the first step of turning a job on (`moveHome(to:turningOn:)`, what a background service's "Move to Applications" passes) hands the job to the new copy as a launch argument, and the new copy installs it at launch, the OS's approval included. Only jobs the copy's bundle declares are turned on; a name it does not declare is logged and ignored. When THE app is already running in that folder it is brought forward instead of joined by a second instance, and the job stays its to turn on (launch arguments only reach a launch). Installs are one per job at a time in the process: a press while the launch turns the job on joins that install instead of racing it. The hand-off is received by the app's `ImageWatch`; an app without one is still moved, and its person presses Turn On there.
- **Moving between Applications folders leaves nothing behind** (`moveHome` from an install, a daemon needing the install for everyone): the jobs this copy has on go with it (unregistered here, which stops them, then turned on there) and this copy goes to the Trash once the new one is open. A download or a build folder is never touched.
- **A new copy keeps the person's choice.** A job turned off, or held for approval, is never touched; one still silent after its launch is a real failure and offers its Restart.

A process is a job only when one of the bundle's own job plists declares the label launchd gave it (`ownJobLabel`). launchd names every process it starts, an app opened from Finder included, so the name alone proves nothing. The label is read when the watch starts, while the bundle can still vouch for it.

## The installed copy is the only record

LaunchServices picks, among the records of a bundle identifier, the highest version; between two of the same version an installed copy does not win (measured 2026-10-26: a stray registered first beat `~/Applications`). Records of an app's own build pile up on a developer's Mac: Xcode registers every app it builds (no setting turns it off: swift-build's `addAppProductRegistrationTasks`), and Finder registers any app it shows. A release's artifact or archive is that very build, so a file-system module, a login item or a URL scheme can resolve to a copy that is not installed (hollow's FSKit mount failed with 72). The Trash is no part of it: its copies are older, and LaunchServices never offers them.

- **An installed app claims its records at launch** (`claimRecords()`, which `ImageWatch.start` calls): run from an Applications folder, it makes itself the only record of every bundle it carries (the app, each `.app` inside it, each `.appex`), in the background, each removed record logged. However it was installed (an installer, a kit, a Sparkle update, a drag) and whatever registered a copy since, the next launch ends with the installed copy. `claim(_:)` does it for apps a program serves that do not link this module (vigil-agent for Vigil and vigild).
- **A release leaves no runnable copy at rest** (`ship release`): an app artifact comes back as `<name>.app.zip`, and every record of the built identifiers outside an Applications folder is removed (`removeStrays(of:)`).
- **`onlyRecord(installed:)`** is the step itself, and `ship installed <X.app>` runs it from a shell. The installed path is never unregistered, not even to register it again: an extension's enable switch follows its record, and doing so turned hollow's file-system module off until the person turned it on in System Settings. Each extension is added again until pluginkit lists it (one add was seen to take nothing for 10 s, the next to land in under a second); never listed after 20 adds is an error.

## Proof

`swift-utils`' `grant-example` is the testbed: `mise run grant-example` builds a signed app with a launch agent (offering both scopes), a root daemon (everyone only) and a command line linked in the temporary folder (`$TMPDIR/grant-example-cli`). Move it into Applications from its row; `launchctl print gui/$(id -u)/garden.untitled.grant-example.helper` gives the helper's pid, and its executable (`proc_pidpath`) says which copy runs it. Each case, proven:

- **Replace** (old bundle to the Trash, the build copied in), app closed: the helper hands itself to the new copy headless, no window; it runs the new bundle.
- **Replace**, a helper already running from the Trash: the app's launch registers it afresh from this copy.
- **Move** (`mv` between the Applications folders), app closed: "moved, nothing forgotten"; the helper and the link follow.
- **Move** with the app open: both converge, one instance, the app reopened from the moved copy.
- **Delete** (the build copy still present): the helper leaves launchd, the preferences go to the Trash, the link is removed; nothing left.
- **Delete** with the root daemon alone alive (chill, the app quit first): the daemon hands back, removes its own files and leaves; the copy in the Trash runs as the person and moves the state, caches and preferences to the Trash and removes the link; a reinstall starts fresh, its approval kept.

The unified log scope `install` traces every step, every path it moves.
