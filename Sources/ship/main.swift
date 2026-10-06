// ship: a Mac app's release outside the App Store, one implementation for
// every app. Run from the app's own repo. The app builds its bundle
// (`--assemble`); ship does everything after it: the gates, Developer ID
// signing (inner code first, then the bundle), notarization judged by the
// staple, the dmg, the branch and its tag pushed, and the channels the app
// asks for.
//
//   ship check    every gate, ok or blocked, each blocked one with the answer
//                 of the command behind it; changes nothing
//   ship release  the gates (any blocked one stops it), then the release
//
//   --name <slug>        the dmg, the notary profile and the cask are named by it
//   --app <dir/X.app>    where --assemble leaves the bundle, in a repo subdirectory
//   --assemble <shell>   builds the bundle; runs after the gates pass
//   --sign <path>        inner code to sign first, relative to the bundle (repeatable)
//   --notary <profile>   the notarytool keychain profile (default: --name)
//   --github             a GitHub release with the notes and the dmg (gh)
//   --after <shell>      runs once the dmg is public, before the cask, with
//                        DMG and VERSION in its environment (publishing elsewhere)
//   --cask               bumps Casks/<name>.rb in the tap checkout at $TAP
//                        (unset: skipped, as for a fork without the tap)
//
// VERSION comes from the environment (the app's mise.toml), the release body
// from notes/$VERSION.md.
import Foundation

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

// MARK: - the arguments

guard let verb = CommandLine.arguments.dropFirst().first, ["check", "release"].contains(verb) else {
    die(
        "usage: ship check|release --name <slug> --app <dir/X.app> --assemble <shell> [--sign <path>]… [--notary <profile>] [--github] [--after <shell>] [--cask]"
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

let env = ProcessInfo.processInfo.environment
guard let name = value("--name") else { die("--name <slug> is required") }
guard let app = value("--app"), app.hasSuffix(".app") else { die("--app <dir/X.app> is required") }
guard let assemble = value("--assemble") else { die("--assemble <shell> is required") }
guard let version = env["VERSION"], !version.isEmpty else {
    die("VERSION is not set: it comes from the app's mise.toml [env]")
}
let inner = values("--sign")
let notary = value("--notary") ?? name
let after = value("--after")
let tap = has("--cask") ? env["TAP"].flatMap { $0.isEmpty ? nil : $0 } : nil
let notes = "notes/\(version).md"
let dist = (app as NSString).deletingLastPathComponent
let dmg = "\(dist)/\(name)-\(version).dmg"
// The release clears this directory before assembling: it must be a scratch
// subdirectory of the repo, never /Applications or the repo itself.
guard !dist.isEmpty, dist != ".", !dist.hasPrefix("/"), !dist.contains("..") else {
    die("--app must sit in a subdirectory of the repo (dist/\(name).app), not \(app)")
}

// MARK: - the gates

/// Every gate is reported before any stops the release, so one run shows all
/// that is wrong. A blocked gate prints the answer of the command behind it,
/// never a guess at why: notarytool fails the same way for a missing profile,
/// a revoked key and an unsigned developer agreement, and each needs
/// different hands.
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

print("\(name) \(version): the gates")
let top = run(["git", "rev-parse", "--show-toplevel"], quiet: true).out
gate(
    "run from the root of \(name)'s own repo", top == FileManager.default.currentDirectoryPath,
    hint: "the tag and the push land in whatever repo holds this directory")
let dirty = run(["git", "status", "--porcelain"], quiet: true).out
gate("clean working tree", dirty.isEmpty, answer: dirty)
let tagged =
    run(["git", "rev-parse", "-q", "--verify", "refs/tags/\(version)"], quiet: true).code == 0
gate("no tag \(version) yet", !tagged, hint: "bump VERSION in mise.toml")
let body = (try? String(contentsOfFile: notes, encoding: .utf8)) ?? ""
gate("\(notes) exists (the words gate)", !body.isEmpty)
// Notes render as designed releases (a glyph per group): a body without
// groups and items is a dated heading with nothing under it.
let lines = body.split(separator: "\n")
gate(
    "\(notes) keeps the grammar",
    lines.contains { $0.hasPrefix("### ") } && lines.contains { $0.hasPrefix("- ") },
    hint: "'### Added|Fixed|Changed|Performance|Polish' sections with '- ' items")
let signer = run(["security", "find-identity", "-v", "-p", "codesigning"], quiet: true).out
    .split(separator: "\n")
    .compactMap { line -> String? in
        guard let r = line.firstRange(of: "\"Developer ID Application: ") else { return nil }
        return String(line[r.lowerBound...].dropFirst().dropLast())
    }.first
gate("a Developer ID Application certificate\(signer.map { ": \($0)" } ?? "")", signer != nil)
let notarized = run(["xcrun", "notarytool", "history", "--keychain-profile", notary], quiet: true)
gate(
    "notary keychain profile '\(notary)'", notarized.code == 0, answer: notarized.out,
    hint: notarized.out.contains("No Keychain password item found")
        ? "create it once: xcrun notarytool store-credentials \(notary) --key <p8> --key-id <id> --issuer <uuid>"
        : notarized.out.contains("agreement")
            ? "the Account Holder accepts the pending agreement at https://developer.apple.com/account, then rerun"
            : nil)
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

if verb == "check" {
    print(blocked ? "\nblocked" : "\nready: ship release")
    exit(blocked ? 1 : 0)
}
if blocked { die("a gate is blocked") }
guard let signer else { die("the certificate gate passed without a certificate") }

// MARK: - the release

step("assemble \(app)")
try? FileManager.default.removeItem(atPath: dist)
shell(assemble)
guard FileManager.default.fileExists(atPath: app) else { die("--assemble left no \(app)") }

// Inner code first: a second executable or a nested app is outside the
// bundle's seal. Hardened runtime and a secure timestamp, or notarization
// refuses.
step("sign")
for path in inner.map({ "\(app)/\($0)" }) + [app] {
    must(["codesign", "--force", "--options", "runtime", "--timestamp", "--sign", signer, path])
}

step("notarize")
let zip = "\(dist)/\(name).zip"
must(["ditto", "-c", "-k", "--keepParent", app, zip])
must(["xcrun", "notarytool", "submit", zip, "--keychain-profile", notary, "--wait"])
// The real verdict: stapling fails unless a ticket was issued, so this is the
// check, not notarytool's exit status.
must(["xcrun", "stapler", "staple", app])
try? FileManager.default.removeItem(atPath: zip)

step("dmg")
let stage = "\(dist)/stage"
do {
    try FileManager.default.createDirectory(atPath: stage, withIntermediateDirectories: true)
} catch { die("create \(stage): \(error.localizedDescription)") }
must(["cp", "-R", app, stage])
must(["ln", "-sf", "/Applications", "\(stage)/Applications"])
must(["diskutil", "image", "create", "from", "--format", "UDZO", "--volumeName", name, stage, dmg])
// The download itself is signed, notarized and stapled too: Gatekeeper
// judges the disk image before the app inside it, and a ticket stapled to
// each holds offline.
must(["codesign", "--force", "--timestamp", "--sign", signer, dmg])
must(["xcrun", "notarytool", "submit", dmg, "--keychain-profile", notary, "--wait"])
must(["xcrun", "stapler", "staple", dmg])

// The branch with its tag: a tag pushed alone leaves the branch on the remote
// behind the release it names.
step("tag \(version) and push")
must(["git", "tag", "-a", version, "-m", version])
must(["git", "push", "origin", run(["git", "branch", "--show-current"], quiet: true).out, version])

if has("--github") {
    step("GitHub release")
    must(["gh", "release", "create", version, "--title", version, "--notes-file", notes, dmg])
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

print("\nreleased \(name) \(version): \(dmg)")
