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
| `silent` | registered and approved, not answering | `install()` registers again once |
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

## Deleted and upgraded: `ImageWatch`

A bundle deleted or replaced under a running process announces nothing and runs no hook (a Trash drag, a cask's sandboxed steps, an updater swapping the bundle). Every process of the app watches its own executable, the app and each job alike:

```swift
let watch = AppInstallation.ImageWatch.start { try? AppInstallation.Job.helper.uninstall() }
withExtendedLifetime(watch) { App.main() }
```

- **Gone** `goneAfter` ticks in a row (one missing tick is an upgrade mid-copy): `onGone` runs (hand back what the process holds, move its state to the Trash), then the process leaves. A job boots itself out of launchd, since a deleted app cannot unregister it and `KeepAlive` would retry the missing binary forever; the app quits.
- **Replaced** and whole (signed as this process is, its designated requirement holding): a job exits and launchd restarts it into the new image, which needs `KeepAlive` in its plist; the app reopens into it.

A process is a job only when one of the bundle's own job plists declares the label launchd gave it (`ownJobLabel`). launchd names every process it starts, an app opened from Finder included, so the name alone proves nothing. The label is read when the watch starts, while the bundle can still vouch for it.

## Proof

`swift-utils`' `grant-example` is the testbed: `mise run grant-example` builds a signed app with a launch agent, offering both scopes. Move it into Applications from its own row (the question picks the folder), turn the helper on, then:

- **Upgrade:** `ditto build/grant-example.app /Applications/grant-example.app`. The app reopens and the helper restarts into the new copy (`runs` grows in `launchctl print gui/$(id -u)/garden.untitled.grant-example.helper`).
- **Delete:** close the window, drag the app to the Trash. The helper leaves launchd within `goneAfter` seconds.

The unified log scope `install` traces every step.
