# AppInstallations

An app's whole life on the Mac, owned by the app: where its bundle lives and moving it into Applications, the processes it runs beside itself (a launch agent, a root daemon, the app as a login item), an upgrade landing under it, and its removal when the bundle is deleted. One top-level name, `AppInstallation`; everything else is nested in it. macOS only.

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

- An install is for a `Scope`, macOS Installer's own question: `.everyone` (/Applications) or `.me` (~/Applications). Which to offer is the app's call, the choice the person's. Data never follows the bundle: settings, records, caches and XDG dirs are per account wherever the app lives, so an install for everyone still keeps each account's data apart. What does follow it is any path into the bundle: a CLI symlinked onto PATH dangles once the app moves between scopes, and nothing here re-points it yet (TODO.md).
- `AppInstallation.home` is `.installed(scope)`, `.elsewhere(url, origin)` (a disk image, a translocated download, a folder) or `.noBundle` (a `swift build` binary). `home.words` names the place for a person.
- `moveHome(to: scope)` opens an install already in that scope's folder, or copies the bundle there and opens the copy; this one quits. `installedCopy(in:)` finds an existing install. `reopen(why)` opens a fresh instance of this bundle and quits.

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

**At launch (the app):** jobs named stale or asked for by a move are registered here, and so is every job that is on but not answering from this copy; command-line links into another copy (or dangling, shaped like this app's) are re-pointed here. A link is the person's install: never created, only kept pointing at THE app.

**The fact everything turns on:** launchd follows the bundle it registered, never the path. Measured: after a replace-style upgrade (old bundle to the Trash, new one copied in) a job restarted from the copy in the Trash, running the old code silently; after a move it respawned from the vanished path and failed (EX_CONFIG) forever. A job belongs to this copy only when the process launchd runs for it lives inside this copy (`proc_pidpath`, readable for root's processes too); otherwise it reads `.silent` ("registered for another copy") and installing it unregisters first, then registers from here, which also stops the other copy's process.

**Then each process watches its executable:**

- **Replaced** and whole (signed as this process is, its designated requirement holding): the app reopens into it. A job is the witness that its registration is stale: it opens the copy at its path headless (`open -n -g -j`, no window) naming itself, and that copy registers it afresh and exits.
- **Gone** `goneAfter` ticks in a row (one missing tick is an upgrade mid-copy), then judged:
  - **Moved** when a copy is the very files that vanished (its executable is the same inode: a rename, the Finder drag on one disk) or an install in an Applications folder (a move across disks). Nothing is forgotten. A job hands itself to the moved copy the same headless way; the app reopens from the moved copy. A leftover copy anywhere else (a download, a build folder) is neither, so it never blocks an uninstall.
  - **Deleted** otherwise: `onGone` runs (hand back what the process holds: chill's fans to Apple), then `forget`: the standard places by bundle id (Application Support, Caches, HTTPStorages, WebKit, Saved Application State) and `keeps` go to the Trash, the preferences domain is cleared through cfprefsd (a copy in the Trash when it held anything), and the links into the deleted bundle are removed. Every move is logged with its path. The app and each job all run it, idempotently. As root, only `keeps`, by exact name: a file is removed, a directory only when empty, never recursively.
- **Leaving:** a job boots its label out of launchd only while launchd's process for it is this one (a newer copy may hold the label by now), else it just exits; the app quits.

A root daemon cannot open apps in the person's session: on a move or a replace it only leaves, and the app registers it afresh at its next launch (until then its row offers Restart).

- **One press ends with the job working.** A move that was the first step of turning a job on (`moveHome(to:turningOn:)`, what a background service's "Move to Applications" passes) hands the job to the new copy as a launch argument, and the new copy installs it at launch, the OS's approval included. Only jobs the copy's bundle declares are turned on; a name it does not declare is logged and ignored. When THE app is already running in that folder it is brought forward instead of joined by a second instance, and the job stays its to turn on (launch arguments only reach a launch). Installs are one per job at a time in the process: a press while the launch turns the job on joins that install instead of racing it. The hand-off is received by the app's `ImageWatch`; an app without one is still moved, and its person presses Turn On there.
- **Moving between Applications folders leaves nothing behind** (`moveHome` from an install, a daemon needing the install for everyone): the jobs this copy has on go with it (unregistered here, which stops them, then turned on there) and this copy goes to the Trash once the new one is open. A download or a build folder is never touched.
- **A new copy keeps the person's choice.** A job turned off, or held for approval, is never touched; one still silent after its launch is a real failure and offers its Restart.

A process is a job only when one of the bundle's own job plists declares the label launchd gave it (`ownJobLabel`). launchd names every process it starts, an app opened from Finder included, so the name alone proves nothing. The label is read when the watch starts, while the bundle can still vouch for it.

## Proof

`swift-utils`' `grant-example` is the testbed: `mise run grant-example` builds a signed app with a launch agent (offering both scopes), a root daemon (everyone only) and a command line linked in the temporary folder (`$TMPDIR/grant-example-cli`). Move it into Applications from its row; `launchctl print gui/$(id -u)/garden.untitled.grant-example.helper` gives the helper's pid, and its executable (`proc_pidpath`) says which copy runs it. Each case, proven:

- **Replace** (old bundle to the Trash, the build copied in), app closed: the helper hands itself to the new copy headless, no window; it runs the new bundle.
- **Replace**, a helper already running from the Trash: the app's launch registers it afresh from this copy.
- **Move** (`mv` between the Applications folders), app closed: "moved, nothing forgotten"; the helper and the link follow.
- **Move** with the app open: both converge, one instance, the app reopened from the moved copy.
- **Delete** (the build copy still present): the helper leaves launchd, the preferences go to the Trash, the link is removed; nothing left.

The unified log scope `install` traces every step, every path it moves.
