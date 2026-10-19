// ship: a Mac app's release outside the App Store, one implementation for
// every app, holding no key. The signing keys live in a vault and reach a
// release only after a person approves its exact commits (`authz release`,
// github.com/adriangalilea/authz.space release/README.md): `ship build` runs
// inside that release, `ship publish` afterwards from the app's checkout.
//
//   ship identity --team <T>   the signing identity's SHA-1: inside a release,
//                              the one Developer ID its keychain holds;
//                              anywhere else, the team's valid Apple
//                              Development identity that expires last
//   ship check                 every gate publishing needs, ok or blocked,
//                              each blocked one with the answer of the command
//                              behind it; changes nothing
//   ship build                 inside `authz release` only: assemble, sign,
//                              notarize, the dmg (signed, notarized, stapled)
//   ship publish               from the checkout, once `authz release` made
//                              the dmg of exactly its commits: the tag pushed
//                              with its branch, then the channels
//   ship released              whether the last `authz release` of the
//                              manifest here (release.json) is of exactly the
//                              checkout's commits, Markdown aside: exit 0 or 1
//                              with the reason (anything that publishes
//                              without `ship publish` asks this first)
//
//   --team <T>           the Apple team whose identity signs (identity, build)
//   --name <slug>        the dmg, its volume and the cask are named by it
//   --app <dir/X.app>    where --assemble leaves the bundle, in a repo subdirectory
//   --assemble <shell>   builds the bundle (build)
//   --sign <path>        inner code to sign first, relative to the bundle (build, repeatable)
//   --signed             --assemble leaves the bundle signed already (an Xcode
//                        export, which embeds the provisioning profiles
//                        restricted entitlements need): verified, never re-signed
//   --tag <name>         the tag publish pushes (default: VERSION), for a
//                        repo that releases more than one app
//   --github             a GitHub release with the notes and the dmg (gh)
//   --after <shell>      runs once the dmg is public, before the cask, with
//                        DMG and VERSION in its environment (publishing elsewhere)
//   --cask               bumps Casks/<name>.rb in the tap checkout at $TAP
//                        (unset: skipped, as for a fork without the tap)
//
// VERSION comes from the environment (the app's mise.toml), the release body
// from notes/$VERSION.md. Inside a release, the environment names the
// release's own keychain (AUTHZ_RELEASE_KEYCHAIN) and the App Store Connect
// key it wrote for this release (APPSTORE_KEY, APPSTORE_KEY_ID,
// APPSTORE_ISSUER).
import CryptoKit
import Foundation
import Security

// MARK: - the shell

// Line-buffered even into a pipe (mise, a log): every step header lands
// before the output of the commands it introduces.
setvbuf(stdout, nil, _IOLBF, 0)

struct Ran {
    let code: Int32
    let out: String
}

/// Runs a command; `quiet` captures its output instead of streaming it.
@discardableResult
func run(_ argv: [String], quiet: Bool = false, env extra: [String: String] = [:]) -> Ran {
    let p = Process()
    p.executableURL = URL(filePath: "/usr/bin/env")
    p.arguments = argv
    if !extra.isEmpty {
        p.environment = ProcessInfo.processInfo.environment.merging(extra) { $1 }
    }
    let pipe = Pipe()
    if quiet {
        p.standardOutput = pipe
        p.standardError = pipe
    }
    do { try p.run() } catch { die("\(argv[0]): \(error.localizedDescription)") }
    let data = quiet ? pipe.fileHandleForReading.readDataToEndOfFile() : Data()
    p.waitUntilExit()
    return Ran(
        code: p.terminationStatus,
        out: String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
}

/// A step that must succeed: its output streams, a failure stops the release.
func must(_ argv: [String], env: [String: String] = [:]) {
    let r = run(argv, env: env)
    if r.code != 0 { die("\(argv.joined(separator: " ")) exited \(r.code)") }
}

func shell(_ script: String, env: [String: String] = [:]) {
    must(["/bin/sh", "-c", script], env: env)
}

func die(_ message: String) -> Never {
    FileHandle.standardError.write(Data("ship: \(message)\n".utf8))
    exit(1)
}

func step(_ name: String) { print("\n→ \(name)") }

// MARK: - the signing identity

/// A code-signing identity: found in a keychain, never named, since a
/// certificate renews and the old one stays beside the new until it expires.
struct Identity {
    let sha1: String
    let name: String
    let teams: [String]
    let notAfter: Date
}

/// Every code-signing identity valid today, in `keychain` (a path) or the
/// user's search list.
func identities(in keychain: String?) -> [Identity] {
    var query: [String: Any] = [
        kSecClass as String: kSecClassIdentity,
        kSecMatchLimit as String: kSecMatchLimitAll,
        kSecReturnRef as String: true,
        kSecMatchValidOnDate as String: Date(),
    ]
    if let keychain {
        var opened: SecKeychain?
        guard SecKeychainOpen(keychain, &opened) == errSecSuccess, let opened else {
            die("cannot open the keychain at \(keychain)")
        }
        query[kSecMatchSearchList as String] = [opened]
    }
    var found: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &found)
    guard status != errSecItemNotFound else { return [] }
    guard status == errSecSuccess, let refs = found as? [SecIdentity] else {
        die("cannot list signing identities (OSStatus \(status))")
    }
    return refs.compactMap { identity in
        var certificate: SecCertificate?
        guard SecIdentityCopyCertificate(identity, &certificate) == errSecSuccess, let certificate,
            let name = SecCertificateCopySubjectSummary(certificate) as String?,
            let notAfter = SecCertificateCopyNotValidAfterDate(certificate) as Date?
        else { return nil }
        let der = SecCertificateCopyData(certificate) as Data
        let sha1 = Insecure.SHA1.hash(data: der).map { String(format: "%02X", $0) }.joined()
        return Identity(sha1: sha1, name: name, teams: units(of: certificate), notAfter: notAfter)
    }
}

/// The subject's organizational units: an Apple certificate's team.
func units(of certificate: SecCertificate) -> [String] {
    let subject = kSecOIDX509V1SubjectName as String
    guard
        let values = SecCertificateCopyValues(certificate, [subject] as CFArray, nil)
            as? [String: Any],
        let name = values[subject] as? [String: Any],
        let parts = name[kSecPropertyKeyValue as String] as? [[String: Any]]
    else { return [] }
    return parts.compactMap { part in
        part[kSecPropertyKeyLabel as String] as? String == kSecOIDOrganizationalUnitName as String
            ? part[kSecPropertyKeyValue as String] as? String : nil
    }
}

/// The identity this context signs with: inside a release ($AUTHZ_RELEASE_KEYCHAIN),
/// the one Developer ID Application identity of `team` its keychain holds;
/// anywhere else, `team`'s Apple Development identity that expires last.
func signingIdentity(team: String) -> Identity {
    if let keychain = ProcessInfo.processInfo.environment["AUTHZ_RELEASE_KEYCHAIN"],
        !keychain.isEmpty
    {
        let found = identities(in: keychain).filter {
            $0.name.hasPrefix("Developer ID Application: ") && $0.teams.contains(team)
        }
        guard found.count == 1, let one = found.first else {
            die(
                "the release keychain holds \(found.count) Developer ID identities of team \(team), not one"
            )
        }
        return one
    }
    let found = identities(in: nil).filter {
        $0.name.hasPrefix("Apple Development: ") && $0.teams.contains(team)
    }
    guard let newest = found.max(by: { $0.notAfter < $1.notAfter }) else {
        die("no valid Apple Development identity of team \(team) in the keychain")
    }
    return newest
}

// MARK: - the install window

/// Writes the dmg volume's .DS_Store (argv: the mount point, the app's file
/// name): what Finder itself stores after arranging the window, with the keys
/// dmgbuild writes. Window {400, 200} 660×400 without toolbar or status bar,
/// icon view at 128 pt with 13 pt labels, nothing auto-arranged, the app at
/// (165, 180) and the Applications link at (495, 180).
let layout = """
    import sys
    from ds_store import DSStore
    mount, app = sys.argv[1], sys.argv[2]
    with DSStore.open(mount + "/.DS_Store", "w+") as d:
        d["."]["vSrn"] = ("long", 1)
        d["."]["bwsp"] = {
            "WindowBounds": "{{400, 200}, {660, 400}}",
            "ShowStatusBar": False, "ShowToolbar": False, "ShowPathbar": False,
            "ShowSidebar": False, "ShowTabView": False, "ContainerShowSidebar": False,
            "PreviewPaneVisibility": False, "SidebarWidth": 0,
        }
        d["."]["icvp"] = {
            "viewOptionsVersion": 1, "backgroundType": 0,
            "backgroundColorRed": 1.0, "backgroundColorGreen": 1.0, "backgroundColorBlue": 1.0,
            "gridOffsetX": 0.0, "gridOffsetY": 0.0, "gridSpacing": 100.0, "arrangeBy": "none",
            "showIconPreview": True, "showItemInfo": False, "labelOnBottom": True,
            "textSize": 13.0, "iconSize": 128.0, "scrollPositionX": 0.0, "scrollPositionY": 0.0,
        }
        d["."]["icvl"] = (b"type", "icnv")
        d[app]["Iloc"] = (165, 180)
        d["Applications"]["Iloc"] = (495, 180)
    """

// MARK: - the arguments

let verbs = ["identity", "check", "build", "publish", "released"]
guard let verb = CommandLine.arguments.dropFirst().first, verbs.contains(verb) else {
    die(
        """
        usage: ship identity --team <T>
               ship check   --name <slug> --app <dir/X.app> [--github] [--cask]
               ship build   --team <T> --name <slug> --app <dir/X.app> --assemble <shell> [--sign <path>]… [--signed]
               ship publish --name <slug> --app <dir/X.app> [--tag <name>] [--github] [--after <shell>] [--cask]
               ship released
        """
    )
}
let args = Array(CommandLine.arguments.dropFirst(2))

func value(_ flag: String) -> String? {
    guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
    return args[i + 1]
}
func values(_ flag: String) -> [String] {
    args.indices.filter { args[$0] == flag && $0 + 1 < args.count }.map { args[$0 + 1] }
}
func has(_ flag: String) -> Bool { args.contains(flag) }

if verb == "identity" {
    guard let team = value("--team") else { die("--team <T> is required") }
    print(signingIdentity(team: team).sha1)
    exit(0)
}

if verb == "released" {
    let released = releasedHere()
    print(
        released.ok
            ? "released: the last authz release is of these commits"
            : "not released: \(released.answer)")
    exit(released.ok ? 0 : 1)
}

let env = ProcessInfo.processInfo.environment
guard let name = value("--name") else { die("--name <slug> is required") }
guard let app = value("--app"), app.hasSuffix(".app") else { die("--app <dir/X.app> is required") }
guard let version = env["VERSION"], !version.isEmpty else {
    die("VERSION is not set: it comes from the app's mise.toml [env]")
}
let notes = "notes/\(version).md"
let dist = (app as NSString).deletingLastPathComponent
let dmg = "\(dist)/\(name)-\(version).dmg"
// The build clears this directory before assembling: it must be a scratch
// subdirectory of the repo, never /Applications or the repo itself.
guard !dist.isEmpty, dist != ".", !dist.hasPrefix("/"), !dist.contains("..") else {
    die("--app must sit in a subdirectory of the repo (dist/\(name).app), not \(app)")
}

// MARK: - the build (inside `authz release`)

if verb == "build" {
    guard let assemble = value("--assemble") else { die("--assemble <shell> is required") }
    guard let keychain = env["AUTHZ_RELEASE_KEYCHAIN"], !keychain.isEmpty,
        let keyPath = env["APPSTORE_KEY"], let keyID = env["APPSTORE_KEY_ID"],
        let issuer = env["APPSTORE_ISSUER"]
    else {
        die(
            "ship build runs inside `authz release` (its keychain and App Store Connect key are in the environment)"
        )
    }
    guard let team = value("--team") else { die("--team <T> is required") }
    let notary = ["--key", keyPath, "--key-id", keyID, "--issuer", issuer]
    let identity = signingIdentity(team: team)
    let sign = [
        "codesign", "--force", "--keychain", keychain, "--timestamp", "--sign", identity.sha1,
    ]

    step("assemble \(app)")
    try? FileManager.default.removeItem(atPath: dist)
    shell(assemble)
    guard FileManager.default.fileExists(atPath: app) else { die("--assemble left no \(app)") }

    if has("--signed") {
        // Signed by the assembly (an Xcode export embeds the provisioning
        // profiles restricted entitlements need; re-signing here would drop
        // them): only verified, and it must be this release's Developer ID.
        step("verify the signature")
        must(["codesign", "--verify", "--strict", "--deep", app])
        let signer = run(["codesign", "-dvv", app], quiet: true).out
        guard signer.contains("Authority=\(identity.name)") else {
            die("\(app) is not signed by \(identity.name):\n\(signer)")
        }
    } else {
        // Inner code first: a second executable or a nested app is outside
        // the bundle's seal. Hardened runtime and a secure timestamp, or
        // notarization refuses. Entitlements already on a piece stay
        // (Sparkle's Downloader.xpc carries its own; unsigned code has none
        // to keep).
        step("sign (\(identity.name))")
        for path in values("--sign").map({ "\(app)/\($0)" }) + [app] {
            must(sign + ["--options", "runtime", "--preserve-metadata=entitlements", path])
        }
    }

    step("notarize")
    let zip = "\(dist)/\(name).zip"
    must(["ditto", "-c", "-k", "--keepParent", app, zip])
    must(["xcrun", "notarytool", "submit", zip] + notary + ["--wait"])
    // The real verdict: stapling fails unless a ticket was issued, so this is
    // the check, not notarytool's exit status.
    must(["xcrun", "stapler", "staple", app])
    try? FileManager.default.removeItem(atPath: zip)

    // The install window is designed, not defaulted: a fixed 660×400 window,
    // 128 pt icons, the app left and Applications right, and the app's own
    // icon becomes the volume's. The layout IS the volume's .DS_Store, written
    // directly (`layout`, the ds_store library dmgbuild uses) into a scratch
    // image mounted out of Finder's sight: no Finder window opens, no
    // Automation permission, no logged-in session needed. Then compressed to
    // the shipping UDZO. All image work goes through `diskutil image`
    // (hdiutil is deprecated in macOS 27).
    step("dmg")
    let appName = (app as NSString).lastPathComponent
    let work = "\(dist)/dmg"
    let scratch = "\(work)/scratch.asif"
    do {
        try FileManager.default.createDirectory(atPath: work, withIntermediateDirectories: true)
    } catch { die("create \(work): \(error.localizedDescription)") }
    guard
        let appMB = Int(
            run(["du", "-sm", app], quiet: true).out.split(separator: "\t").first ?? ""),
        appMB > 0
    else { die("cannot size \(app) for the disk image") }
    must([
        "diskutil", "image", "create", "blank", "--format", "ASIF", "--fs", "APFS", "--volumeName",
        name, "--size", "\(appMB + 64)m", scratch,
    ])
    let attached = run(
        ["diskutil", "image", "attach", "--nobrowse", "--plist", scratch], quiet: true
    ).out
    guard
        let mountKey = attached.range(of: "<key>mount-point</key>"),
        let open = attached.range(of: "<string>", range: mountKey.upperBound..<attached.endIndex),
        let close = attached.range(of: "</string>", range: open.upperBound..<attached.endIndex)
    else { die("diskutil attach gave no mount point:\n\(attached)") }
    let mount = String(attached[open.upperBound..<close.lowerBound])
    must(["cp", "-R", app, mount])
    must(["ln", "-s", "/Applications", "\(mount)/Applications"])
    must([
        "uv", "run", "--no-project", "--with", "ds-store==1.3.3", "python", "-c", layout, mount,
        appName,
    ])
    let iconFile = run(
        ["/usr/libexec/PlistBuddy", "-c", "Print :CFBundleIconFile", "\(app)/Contents/Info.plist"],
        quiet: true
    ).out
    let icns =
        "\(app)/Contents/Resources/\(iconFile.hasSuffix(".icns") ? iconFile : "\(iconFile).icns")"
    must(["cp", icns, "\(mount)/.VolumeIcon.icns"])
    must(["SetFile", "-a", "C", mount])
    must(["SetFile", "-a", "E", "\(mount)/\(appName)"])
    must(["sync"])
    must(["diskutil", "eject", mount])
    must(["diskutil", "image", "create", "from", "--format", "UDZO", scratch, dmg])
    try? FileManager.default.removeItem(atPath: work)
    // The download itself is signed, notarized and stapled too: Gatekeeper
    // judges the disk image before the app inside it, and a ticket stapled to
    // each holds offline.
    must(sign + [dmg])
    must(["xcrun", "notarytool", "submit", dmg] + notary + ["--wait"])
    must(["xcrun", "stapler", "staple", dmg])
    print("\nbuilt \(name) \(version): \(dmg)")
    exit(0)
}

// MARK: - the gates (check, publish)

/// Every gate is reported before any stops publishing, so one run shows all
/// that is wrong. A blocked gate prints the answer of the command behind it,
/// never a guess at why.
var blocked = false
@MainActor func gate(_ what: String, _ ok: Bool, answer: String = "", hint: String? = nil) {
    print(ok ? "  ok       \(what)" : "  blocked  \(what)")
    guard !ok else { return }
    blocked = true
    if !answer.isEmpty {
        for line in answer.split(separator: "\n") { print("           \(line)") }
    }
    if let hint { print("           \(hint)") }
}

/// Whether the last `authz release` of this repo was of exactly its commits:
/// its manifest (`release.json`) names the trees, its record
/// (~/.local/state/authz/releases/<app>.json) what each was released at. A
/// tree may have moved since by documentation alone (Markdown: the notes).
func releasedHere() -> (ok: Bool, answer: String) {
    guard let manifest = try? Data(contentsOf: URL(filePath: "release.json")),
        let m = try? JSONSerialization.jsonObject(with: manifest) as? [String: Any],
        let appName = m["app"] as? String, let trees = m["trees"] as? [[String: Any]]
    else { return (false, "no release.json at the repo root") }
    let recordPath = "\(NSHomeDirectory())/.local/state/authz/releases/\(appName).json"
    guard let record = try? Data(contentsOf: URL(filePath: recordPath)),
        let r = try? JSONSerialization.jsonObject(with: record) as? [String: Any],
        let sources = r["sources"] as? [String: String]
    else { return (false, "no release of \(appName) yet: authz release") }
    for tree in trees {
        guard let tree = tree["name"] as? String, let path = treePath(trees, tree) else { continue }
        guard let released = sources[tree] else {
            return (false, "\(tree) is not in the last release")
        }
        let head = run(["git", "-C", path, "rev-parse", "HEAD"], quiet: true).out
        if head == released { continue }
        let diff = run(["git", "-C", path, "diff", "--name-only", released, "HEAD"], quiet: true)
        guard diff.code == 0 else { return (false, "\(tree) is not after its last release") }
        let built = diff.out.split(separator: "\n").filter { !$0.hasSuffix(".md") }
        if let first = built.first {
            return (false, "\(tree) changed since the last release (\(first))")
        }
    }
    return (true, "")
}

func treePath(_ trees: [[String: Any]], _ name: String) -> String? {
    trees.first { $0["name"] as? String == name }?["path"] as? String
}

let tap = has("--cask") ? env["TAP"].flatMap { $0.isEmpty ? nil : $0 } : nil

print("\(name) \(version): the gates")
let top = run(["git", "rev-parse", "--show-toplevel"], quiet: true).out
gate(
    "run from the root of \(name)'s own repo", top == FileManager.default.currentDirectoryPath,
    hint: "the tag and the push land in whatever repo holds this directory")
let dirty = run(["git", "status", "--porcelain"], quiet: true).out
gate("clean working tree", dirty.isEmpty, answer: dirty)
let tag = value("--tag") ?? version
let tagged =
    run(["git", "rev-parse", "-q", "--verify", "refs/tags/\(tag)"], quiet: true).code == 0
gate("no tag \(tag) yet", !tagged, hint: "bump VERSION in mise.toml")
let body = (try? String(contentsOfFile: notes, encoding: .utf8)) ?? ""
gate("\(notes) exists (the words gate)", !body.isEmpty)
// Notes render as designed releases (a glyph per group): a body without
// groups and items is a dated heading with nothing under it.
let lines = body.split(separator: "\n")
gate(
    "\(notes) keeps the grammar",
    lines.contains { $0.hasPrefix("### ") } && lines.contains { $0.hasPrefix("- ") },
    hint: "'### Added|Fixed|Changed|Performance|Polish' sections with '- ' items")
if has("--github") {
    let gh = run(["gh", "auth", "status"], quiet: true)
    gate("gh is signed in (the GitHub release)", gh.code == 0, answer: gh.out)
}
if has("--cask") {
    if let tap {
        gate(
            "the tap at $TAP holds Casks/\(name).rb",
            FileManager.default.fileExists(atPath: "\(tap)/Casks/\(name).rb"))
    } else {
        print("  skipped  the cask: TAP is not set")
    }
}
if verb == "publish" {
    let released = releasedHere()
    gate("the last authz release is of these commits", released.ok, answer: released.answer)
    let stapled = run(["xcrun", "stapler", "validate", dmg], quiet: true)
    gate("\(dmg) is notarized and stapled", stapled.code == 0, answer: stapled.out)
    let developerID = run(
        [
            "codesign", "--verify", "-R",
            "=anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.13] exists",
            dmg,
        ], quiet: true)
    gate("\(dmg) is signed with Developer ID", developerID.code == 0, answer: developerID.out)
}

if verb == "check" {
    print(blocked ? "\nblocked" : "\nready: authz release, then ship publish")
    exit(blocked ? 1 : 0)
}
if blocked { die("a gate is blocked") }

// MARK: - publish

let after = value("--after")

// The branch with its tag: a tag pushed alone leaves the branch on the remote
// behind the release it names.
step("tag \(tag) and push")
must(["git", "tag", "-a", tag, "-m", "\(name) \(version)"])
must(["git", "push", "origin", run(["git", "branch", "--show-current"], quiet: true).out, tag])

if has("--github") {
    step("GitHub release")
    must(["gh", "release", "create", tag, "--title", version, "--notes-file", notes, dmg])
}

// Before the cask: a cask can point at what this publishes, and brew fetches
// it the moment the tap updates.
if let after {
    step("after: \(after)")
    shell(after, env: ["DMG": dmg, "VERSION": version])
}

// The tap is its own repo: Homebrew discovers taps only by the `homebrew-`
// prefix.
if let tap {
    step("cask")
    let sum = run(["shasum", "-a", "256", dmg], quiet: true).out.split(separator: " ").first.map(
        String.init)
    guard let sha = sum, sha.count == 64 else { die("could not hash \(dmg)") }
    let cask = "\(tap)/Casks/\(name).rb"
    guard let recipe = try? String(contentsOfFile: cask, encoding: .utf8) else {
        die("cannot read \(cask)")
    }
    let bumped = recipe.split(separator: "\n", omittingEmptySubsequences: false).map { line in
        line.hasPrefix("  version ")
            ? "  version \"\(version)\""
            : line.hasPrefix("  sha256 ") ? "  sha256 \"\(sha)\"" : String(line)
    }.joined(separator: "\n")
    do { try bumped.write(toFile: cask, atomically: true, encoding: .utf8) } catch {
        die("write \(cask): \(error.localizedDescription)")
    }
    must(["git", "-C", tap, "add", "Casks/\(name).rb"])
    must(["git", "-C", tap, "commit", "-q", "-m", "\(name) \(version)"])
    must(["git", "-C", tap, "push", "-q", "origin", "main"])
    print("  \(name) \(version), sha256 \(sha)")
}

print("\npublished \(name) \(version): \(dmg)")
