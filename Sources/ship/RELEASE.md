# `ship release`: nothing is signed without a person's yes

`ship release [release.json…]` builds, signs and notarizes one or more Mac apps, each from exactly the commits a person approved. ship holds no key and knows no vault: the keys reach a release only through an **approver**, and only after that person's verified yes.

## The rule

A build signed by the team's Developer ID is made only after a person approved exactly what goes into it. The keys that sign it live in a vault, nowhere else, and reach that one release.

## The approver

`SHIP_APPROVE` names a shell command. `ship release` writes one JSON request on its stdin (`ApprovalRequest` in `Release.swift`):

```json
{
  "title": "Release Lore and Mach?",
  "lines": ["Lore:", "  lore: 3 commits since the last release (5f4b9e4…)", "    …", "  builds with scripts/release (sha256 1a2b…)"],
  "secrets": {"identity": "<reference>", "identityPassword": "<reference>", "appStoreKey": "<reference>"},
  "run": {
    "argv": ["/…/ship", "release-run", "/…/plan-1761070000.json", "<the plan's sha256>"],
    "env": {"SHIP_RELEASE_IDENTITY": "{identity}", "APPSTORE_KEY_ID": "…", "…": "…"}
  }
}
```

The approver must:

1. Show the person the title, the lines and the command (`run.argv`: the plan's SHA-256 is in it).
2. Wait for their **verified** yes (a fingerprint, a face, a password: proof it is them).
3. Only then resolve each secret by its reference (opaque to ship: whatever the approver's vault understands), put each where its `{name}` stands in `run.env` and nowhere else, run `run.argv` with that environment, and exit with its status.
4. Refuse, or time out, as a no: a non-zero exit, and nothing runs.

Without `SHIP_APPROVE`, `ship release` refuses. The keys are named by the releasing machine's environment, each a reference the approver resolves: `SHIP_RELEASE_IDENTITY` (the Developer ID identity, its `.p12` as base64), `SHIP_RELEASE_IDENTITY_PASSWORD`, `SHIP_RELEASE_APPSTORE_KEY` (the App Store Connect `.p8`); and two values that are not secret, `APPSTORE_KEY_ID` and `APPSTORE_ISSUER`.

## What runs, in order

1. **Committed, or nothing.** Every tree each app is built from (its manifest names them) has no uncommitted or untracked change.
2. **The working folders.** Each app's trees are cloned once into `~/.local/state/ship/releases/<app>/work`, laid out as the originals are, and moved to the commits being released (`checkout --force`, `clean`, submodules from the local ones). Ignored files stay: they are the build caches, so an unchanged dependency is never compiled twice.
3. **The plan, pinned.** What will be built (each app's clones, commits, build script and its SHA-256, artifacts) is written to a plan file; its SHA-256 is in the command the person approves.
4. **One request for every app.** Per tree, the commits since the app's last release; the build script's hash; the keys by reference. One yes covers the apps released together.
5. **`ship release-run`, after the yes.** It refuses unless the plan matches its approved hash, every clone is at its approved commit and clean, and every script matches its hash. Then it makes a keychain of the release's own (a random password, Apple's import API, exactly one Developer ID identity or it refuses), puts it first on the search list, writes the App Store Connect key and any further secret to private files, and runs every app's script at once (`script <clone>`, its output in `~/.local/state/ship/releases/<app>/release.log`), with `SHIP_KEYCHAIN`, `APPSTORE_KEY` (the key's path), `APPSTORE_KEY_ID`, `APPSTORE_ISSUER`, `SHIP_RELEASE_SOURCES`, `SHIP_RELEASE_HEADS` and each further secret's path. Notarizations of different apps overlap. However it ends, the keychain, the files and the search-list entry are removed.
6. **Recorded.** Each app's artifacts are copied back into its repo; its record (`~/.local/state/ship/releases/<app>.json`) keeps the commits and every artifact's digest (`digest`: every file under it by path and content), so what a release signed can be checked later.

A manifest names further secrets a build signs with (a Sparkle update key): `"secrets": {"SPARKLE_ED_KEY": "<reference>"}`. They are on the same request, released by the same yes, written beside the App Store Connect key, their path in that variable.

## What it does not stop

- A process running as the person can edit a working folder (a clone or a cache) while a release builds: `release-run` checks the clones and scripts when it starts, not every file as it compiles. Only building as another user closes it; the record's digests make it visible after.
- The release holds the keys for the minutes it takes: a process running as the person could use its keychain in that window. The target is that no key leaves the vault (signatures made by it), see the next section.

## Where it goes next

- Notarization through Apple's Notary REST API with its token signed by the vault, and the Sparkle feed signed by the vault: two of the three keys never reach a build.
- The Developer ID behind a CryptoTokenKit token, so `codesign` signs through it like a smart card and the key never leaves the vault.

## Where it lives

| What | Where |
|---|---|
| `ship release`, `ship release-run`, the keychain | `Release.swift`, beside this file |
| An app's manifest (its trees, its build script, its artifacts, further secrets) | `release.json` at the app's repo root |
| The last release of each app | `~/.local/state/ship/releases/<app>.json`; `ship released` compares a checkout with it |
| The mechanics after signing (dmg, zip, GitHub release, cask) | `ship build` and `ship publish`, in `main.swift` |
