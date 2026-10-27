# `ship release`: nothing is signed without a person's yes

`ship release [release.json…]` builds, signs and notarizes one or more Mac apps, each from exactly the commits a person approved. ship holds no key and knows no vault: the keys reach a release only through an **approver**, and only after that person's verified yes.

## The rule, and how far it goes

A build signed by the team's Developer ID is made only after a person approved exactly what goes into it. The keys that sign it live in a vault and reach that one release, through its standard input, never its environment or its command line. Every release keeps what a postmortem needs.

That is the whole design, on purpose. It guards against forgetting (a build nobody approved, a key left on a disk, a release nobody can reconstruct), not against a determined attacker already running as the person: such a process can edit a working folder mid-build or use the release's keychain in the minutes it is open. Closing that would take building as another user or the key never leaving the vault (a smart-card token), machinery whose cost in review attention is better spent elsewhere for now. Revisit before releasing an app whose users are a target.

## The approver

`SHIP_APPROVE` names a shell command. `ship release` writes one JSON request on its stdin (`ApprovalRequest` in `Release.swift`):

```json
{
  "title": "Release MyApp and Helper?",
  "lines": ["Helper: helper at 9c1d2e3…, no release to compare with"],
  "changes": [
    {"app": "MyApp", "tree": "myapp", "own": true, "count": 3, "since": "5f4b9e4…", "commits": ["a1b2c3d feat: …", "…"]},
    {"app": "MyApp", "tree": "swift-utils", "own": false, "count": 2, "since": "77ab01…", "commits": ["…"]}
  ],
  "secrets": {"identity": "<reference>", "identityPassword": "<reference>", "appStoreKey": "<reference>"},
  "run": {
    "argv": ["/…/ship", "release-run", "/…/MyApp/2026-10-21T201500/plan.json", "<the plan's sha256>"],
    "env": {"APPSTORE_KEY_ID": "…", "APPSTORE_ISSUER": "…"},
    "stdin": {"identity": "{identity}", "identityPassword": "{identityPassword}", "appStoreKey": "{appStoreKey}"}
  }
}
```

The approver must:

1. Show the person the title, the lines, the changes and the command (`run.argv`: the plan's SHA-256 is in it). The changes are data so the card can be skimmed: per app its own tree's commits (`own`), and apart from them the shared trees' (a library another session works on ships inside the app too: they must never pass unseen). Commits are `<short hash> <subject>`, at most 25 per tree, `count` the whole number.
2. Wait for their **verified** yes (a fingerprint, a face, a password: proof it is them).
3. Only then resolve each secret by its reference (opaque to ship: whatever the approver's vault understands), fill `run.stdin` with them, run `run.argv` with `run.env` added to its environment, write `run.stdin` to its standard input as one JSON object and close it, and exit with its status. A secret never goes into the environment: on macOS any process of the same user can read another's.
4. Refuse, or time out, as a no: a non-zero exit, and nothing runs.

What the approver prints is kept with the release (`approval.txt`): its receipt of the yes belongs there.

Without `SHIP_APPROVE`, `ship release` refuses. The keys are named by the releasing machine's environment, each a reference the approver resolves: `SHIP_RELEASE_IDENTITY` (the Developer ID identity, its `.p12` as base64), `SHIP_RELEASE_IDENTITY_PASSWORD`, `SHIP_RELEASE_APPSTORE_KEY` (the App Store Connect `.p8`); and two values that are not secret, `APPSTORE_KEY_ID` and `APPSTORE_ISSUER`.

## What runs, in order

1. **Committed, or nothing.** Every tree each app is built from (its manifest names them) has no uncommitted or untracked change.
2. **The working folders.** Each app's trees are cloned once into `~/.local/state/ship/releases/<app>/work`, laid out as the originals are, and moved to the commits being released (`checkout --force`, `clean`, submodules from the local ones). Ignored files stay: they are the build caches, so an unchanged dependency is never compiled twice. A build script keeps its tools' caches inside the clone, in ignored folders.
3. **What comes from outside the trees, read once.** Each app's release notes and, when its manifest names one, its published feed are read in the checkout, with the person's own tools and credentials (the clone has neither), into the release's folder (`notes.md`, `feed.xml`). The request lists the versions they carry notes for and the feed's items.
4. **The plan, pinned.** What will be built (each app's clones, commits, build script, notes and feed, each with its SHA-256, artifacts) is written to `plan.json` in the release's folder; its SHA-256 is in the command the person approves.
5. **One request for every app.** Per tree, the commits since the app's last release; the build script's hash; the keys by reference. One yes covers the apps released together.
6. **`ship release-run`, after the yes.** It refuses unless the plan matches its approved hash, every clone is at its approved commit and clean, and every script, the notes and the feed match their hashes. It reads the keys from its standard input, makes a keychain of the release's own (a random password, Apple's import API, exactly one Developer ID identity or it refuses), puts it first on the search list, writes the App Store Connect key and any further secret to private files, and runs every app's script at once (`script <clone>`) with `SHIP_KEYCHAIN`, `APPSTORE_KEY` (the key's path), `APPSTORE_KEY_ID`, `APPSTORE_ISSUER`, `SHIP_RELEASE_SOURCES`, `SHIP_RELEASE_HEADS`, `SHIP_MANIFEST` (the manifest in the clone), `SHIP_NOTES` and `SHIP_FEED` (the pinned notes and feed) and each further secret's path. Notarizations of different apps overlap. However it ends, the keychain, the files and the search-list entry are removed.
7. **Recorded.** Each app's artifacts are copied back into its repo (an `.app` as `<name>.app.zip`, and so is every app inside a folder artifact: a runnable copy of the very build, at rest beside its installed copy, ties with it in LaunchServices and can win, and Finder registers any app it shows; installers unpack the zip straight into place), every record of what it built outside an Applications folder is removed (Xcode registers its archive), and the release's folder keeps everything.

## The manifest

What is the app's, not one command's, is said once, in its `release.json`; every verb reads it there (inside a release, the clone's copy, named by `SHIP_MANIFEST`):

```json
{
  "app": "MyApp",
  "trees": [{"name": "myapp", "path": "."}],
  "script": "scripts/release",
  "artifacts": ["dist"],
  "secrets": {"SPARKLE_ED_KEY": "<reference>"},
  "notes": ["scripts/notes"],
  "feed": ["curl", "-fsS", "https://example.com/myapp/appcast.xml"],
  "downloads": "https://example.com/releases/",
  "homepage": "https://example.com/myapp",
  "requests": "https://github.com/me/myapp/issues/{number}"
}
```

| Key | What |
|---|---|
| `app` | the app's name: its releases' folder and record |
| `trees` | the repositories it is built from, the app's own first; `path` from this file's folder, `submodules` the build needs |
| `script` | the build, run as `script <clone of the first tree>` |
| `artifacts` | what the build makes, copied back into the repo |
| `secrets` | further keys the build signs with (a Sparkle update key): the variable that will name the key's file → the reference the approver resolves. On the same request, released by the same yes, written beside the App Store Connect key |
| `notes` | where the release notes are. Absent: `notes/<version>.md` beside this file. Present: a program (argv, run from this file's folder) that prints every version's notes, each under a `## <version>` heading, for notes kept anywhere else (a database, a CMS) |
| `feed` | a program that prints the app's published Sparkle feed, nothing when none is published yet (`appcast` needs it): a `curl` of a public feed, a read of a private one with the person's credentials |
| `downloads` | the folder URL the dmgs are downloaded from (`appcast`'s enclosure, `cask`'s url: it plus the dmg's name) |
| `homepage` | the app's web page (`cask`) |
| `requests` | the URL of the app's request N, `{number}` in it: a notes item citing `<app>#N` links there. Absent, the citation stays text |

Notes keep one grammar wherever they come from: `### <Group>` headings over `- ` items, `**bold**` for an item's headline, `` `code` `` for literals.

### What a release reads from outside its trees

A build runs in a clean clone with no credentials and no network it may count on, so what it needs from elsewhere, the notes and the published feed, is read before the yes: by `ship release`, in the checkout, with the person's tools and credentials, into the release's folder, each file pinned in the plan by its SHA-256 and listed on the request. A program that fails stops the release. Inside the release, `appcast` reads those copies (`SHIP_NOTES`, `SHIP_FEED`); afterwards `publish` reads the notes the last release pinned. The words checked, approved and published are the same words. `check` reads the notes live, as the next release will.

## The Sparkle feed

`ship appcast --name <slug> --app <dir/X.app>`, run by the build script after `ship build`, makes `dist/appcast.xml` with the update key at `$SPARKLE_ED_KEY` (the manifest's secret of that name), and refuses anywhere else. It extends the published feed the release read before the yes (the manifest's `feed`; empty, the first release). The new item's build is the app's `CFBundleVersion`; a feed that already carries that build or a later one is refused, since no installed copy would take the update. The app must carry `SUPublicEDKey`: without it generate_appcast writes the item unsigned and says nothing.

The update dialog's notes are one HTML document, `dist/<slug>-<version>.html` beside the dmg, embedded as the new item's description. It holds a block for each version the feed keeps (`--maximum-versions`, 3 by default, the same number the feed keeps), newest first, each tagged with its build as the feed records it. Sparkle marks the block of the installed build and the document hides it and every older one, so each person reads only what is new to them. The released version's notes are required; an older version without notes is left out, and said. The enclosure's URL is the manifest's `downloads` followed by the dmg's name. Sparkle's `generate_appcast` must be on `PATH`.

## What a release keeps

Every release has a folder per app, `~/.local/state/ship/releases/<app>/<date>T<time>/`, kept for good (a few hundred KB):

| File | What |
|---|---|
| `plan.json` | the plan approved, byte for byte (its SHA-256 is in `record.json` and in the approver's own record) |
| `approval.txt` | what the approver said: its receipt of the yes |
| `release.log` | the build's whole output, every step's time, Apple's notarization verdicts |
| `notes.md`, `feed.xml` | the notes and the feed read before the yes, as pinned (`publish` reads the notes from here) |
| `toolchain.txt` | macOS, Xcode, Swift, Rust, Zig, Node, as each says its version, and the `ship` that ran |
| `record.json` | the commits per tree, every artifact's digest (every file under it by path and content), the certificate that signed (SHA-1 and name), Apple's notarization submission ids (`xcrun notarytool log <id>` reads Apple's own account), the plan's SHA-256 |

`<app>.json` beside the folders is the last record: what the next release compares with, and what `ship released` reads.

What is never kept: a key or its value, anything read from the approver's stdin.

## Where it lives

| What | Where |
|---|---|
| `ship release`, `ship release-run`, the keychain | `Release.swift`, beside this file |
| An app's manifest ("The manifest") | `release.json` in the app's repo |
| Every release of each app | `~/.local/state/ship/releases/<app>/<date>T<time>/`; the last record at `<app>.json`, which `ship released` compares a checkout with |
| The mechanics after signing (dmg, zip, GitHub release, cask) | `ship build` and `ship publish`, in `main.swift` |
| The Sparkle feed and the update dialog's notes | `ship appcast`, in `Appcast.swift` |
