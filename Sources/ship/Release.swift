// `ship release` and `ship release-run`: building, signing and notarizing
// one or more apps, after one approval of exactly their commits.
//
// ship holds no key and knows no vault. The keys reach a release only
// through an APPROVER: the command `SHIP_APPROVE` names, given a request
// (JSON on stdin, `ApprovalRequest`) that it shows a person, and that it
// carries out only after their verified yes: it resolves the request's
// secrets (by the opaque references the request names) into the command's
// environment and nowhere else, runs the command, and exits with its
// status. Anything that does that is an approver; ship never asks which.
//
// What the yes covers is pinned by hashes the approver shows: the command
// names the build plan's SHA-256, and `release-run` refuses a plan that
// does not match it; the plan names each tree's commit and each build
// script's SHA-256, and `release-run` refuses a clone or a script that does
// not match them.
//
// Builds keep their caches: each app's trees are cloned once into its
// working folder (~/.local/state/ship/releases/<app>/work) and moved to the
// approved commits at every release, so cargo, SwiftPM, Zig and Xcode
// reuse what they built. What a release signed is observed instead of a
// cache being refused: its record names the commits and every artifact's
// digest.
import CryptoKit
import Foundation
import Security

// MARK: - the manifest and the record

/// An app's `release.json`.
struct Manifest: Decodable {
    struct Tree: Decodable {
        let name: String
        /// From the manifest's directory.
        let path: String
        /// Submodules the build needs, initialized in the clone from the local ones.
        let submodules: [String]?
    }
    let app: String
    /// The first tree is the app's own; `script` and `artifacts` are in it.
    let trees: [Tree]
    /// Run as `script <clone of the first tree>`.
    let script: String
    /// What the release makes, copied back to the same paths in the tree.
    let artifacts: [String]
    /// Further secrets the build reads: the variable naming the file the
    /// script reads → the reference the approver resolves.
    let secrets: [String: String]?
}

/// An app's last release: the commits the next one is compared with, and
/// the digest of each artifact it made.
struct Record: Codable {
    var sources: [String: String]
    var at: Double
    var artifacts: [String: String]?
}

let releases = URL(filePath: NSHomeDirectory()).appending(path: ".local/state/ship/releases")

func recordFile(_ app: String) -> URL { releases.appending(path: "\(app).json") }

/// The keys every release signs with, named by the releasing machine's
/// environment (each an opaque reference the approver resolves), and the
/// two App Store Connect values that are not secret.
let releaseKeys = [
    "SHIP_RELEASE_IDENTITY", "SHIP_RELEASE_IDENTITY_PASSWORD", "SHIP_RELEASE_APPSTORE_KEY",
]
let releaseValues = ["APPSTORE_KEY_ID", "APPSTORE_ISSUER"]

/// Variables a release sets itself: a manifest's secret may not take them.
let reserved: Set<String> =
    Set(releaseKeys + releaseValues).union([
        "APPSTORE_KEY", "SHIP_KEYCHAIN", "SHIP_RELEASE_SOURCES", "SHIP_RELEASE_HEADS",
    ])

// MARK: - the approval contract

/// What `SHIP_APPROVE` reads on stdin.
struct ApprovalRequest: Codable {
    /// What is asked ("Release Vigil?").
    let title: String
    /// What the person reads: per tree, the commits since its last release.
    let lines: [String]
    /// Secret name → opaque reference. The approver resolves each one only
    /// after the yes, and only into `run.env`, where `{name}` stands for it.
    let secrets: [String: String]
    let run: Run
    struct Run: Codable {
        let argv: [String]
        /// Literal values, and `{name}` for a secret.
        let env: [String: String]
    }
}

// MARK: - the build plan (what release-run builds)

struct Plan: Codable {
    struct App: Codable {
        let app: String
        /// The app's own repo, where its artifacts are copied back.
        let repo: String
        /// The clone of the app's own tree, where the script and artifacts are.
        let root: String
        let script: String
        let scriptSHA256: String
        /// Tree name → its clone and the approved commit.
        let trees: [String: Tree]
        let artifacts: [String]
        /// The manifest's own secrets: variable names.
        let secrets: [String]
        let sources: String
        let heads: String
        let log: String
    }
    struct Tree: Codable {
        let clone: String
        let head: String
    }
    let apps: [App]
    /// Where release-run writes what it made (`Built`).
    let result: String
}

struct Built: Codable {
    /// App → artifact path → digest.
    var artifacts: [String: [String: String]]
    /// App → seconds its build took.
    var seconds: [String: Double]
}

// MARK: - git and hashes

func git(_ arguments: [String], in directory: String) -> String {
    let r = run(["git", "-C", directory] + arguments, quiet: true)
    if r.code != 0 { die("git \(arguments.first ?? "") in \(directory) failed: \(r.out)") }
    return r.out
}

func sha256(file path: String) -> String {
    guard let data = FileManager.default.contents(atPath: path) else { die("cannot read \(path)") }
    return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

/// A bundle's or a file's digest: every regular file and link under it, by
/// relative path, sorted, each with its content's (a link: its target's)
/// SHA-256, hashed together. The same artifact always gives the same digest.
func digest(_ path: String) -> String {
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
        die("no artifact at \(path)")
    }
    guard isDirectory.boolValue else { return sha256(file: path) }
    let root = URL(filePath: path)
    var entries: [String] = []
    let walker = FileManager.default.enumerator(
        at: root, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], options: [])
    while let url = walker?.nextObject() as? URL {
        let relative = String(url.path.dropFirst(root.path.count))
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        if values?.isSymbolicLink == true {
            let target =
                (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) ?? ""
            entries.append("\(relative) -> \(target)")
        } else if values?.isRegularFile == true {
            entries.append("\(relative) \(sha256(file: url.path))")
        }
    }
    let joined = entries.sorted().joined(separator: "\n")
    return SHA256.hash(data: Data(joined.utf8)).map { String(format: "%02x", $0) }.joined()
}

func realPath(_ path: String) -> String {
    URL(filePath: path).resolvingSymlinksInPath().standardizedFileURL.path
}

// MARK: - ship release

/// `ship release [release.json…]`: each app's trees committed, cloned or
/// moved to those commits in its working folder, one request for all of
/// them to the approver, then the artifacts back into each repo and the
/// records written.
func release(_ manifests: [String]) -> Never {
    guard let approver = ProcessInfo.processInfo.environment["SHIP_APPROVE"], !approver.isEmpty
    else {
        die(
            "SHIP_APPROVE names no approver: the command that shows a release to a person and runs it after their verified yes (Sources/ship/RELEASE.md)"
        )
    }
    let environment = ProcessInfo.processInfo.environment
    let missing = (releaseKeys + releaseValues).filter { (environment[$0] ?? "").isEmpty }
    guard missing.isEmpty else {
        die(
            "the release keys are named by this machine's environment; missing: \(missing.joined(separator: ", "))"
        )
    }

    var secrets: [String: String] = [
        "identity": environment["SHIP_RELEASE_IDENTITY"]!,
        "identityPassword": environment["SHIP_RELEASE_IDENTITY_PASSWORD"]!,
        "appStoreKey": environment["SHIP_RELEASE_APPSTORE_KEY"]!,
    ]
    var lines: [String] = []
    var apps: [Plan.App] = []
    let began = Date()

    for path in manifests {
        let manifestPath = realPath(path)
        let root = (manifestPath as NSString).deletingLastPathComponent
        guard let data = FileManager.default.contents(atPath: manifestPath),
            let manifest = try? JSONDecoder().decode(Manifest.self, from: data)
        else { die("\(path): not a release manifest") }
        guard let own = manifest.trees.first else { die("\(path): no trees") }
        for (name, reference) in manifest.secrets ?? [:] {
            guard name.allSatisfy({ $0.isASCII && ($0.isUppercase || $0.isNumber || $0 == "_") }),
                name.first?.isLetter == true, !reserved.contains(name), !reference.isEmpty
            else {
                die("\(path): secret \(name) must be an UPPER_CASE variable a release does not set")
            }
            if let known = secrets[name], known != reference {
                die("\(name) names two different secrets across the apps released together")
            }
            secrets[name] = reference
        }

        // Committed, or nothing.
        var sources: [String: String] = [:]
        var heads: [String: String] = [:]
        for tree in manifest.trees {
            let source = realPath(root + "/" + tree.path)
            sources[tree.name] = source
            let dirty = git(["status", "--porcelain"], in: source)
            guard dirty.isEmpty else {
                die(
                    "\(manifest.app): \(tree.name) has uncommitted changes; commit them first:\n\(dirty)"
                )
            }
            heads[tree.name] = git(["rev-parse", "HEAD"], in: source)
        }

        // What changed since the last release, per tree.
        let last =
            (try? JSONDecoder().decode(
                Record.self, from: Data(contentsOf: recordFile(manifest.app))))?.sources ?? [:]
        lines.append("\(manifest.app):")
        var changed = false
        for tree in manifest.trees {
            let source = sources[tree.name]!
            let head = heads[tree.name]!
            guard last[tree.name] != head else { continue }
            changed = true
            if let was = last[tree.name],
                run(["git", "-C", source, "merge-base", "--is-ancestor", was, head], quiet: true)
                    .code == 0
            {
                let count = Int(git(["rev-list", "--count", "\(was)..\(head)"], in: source)) ?? 0
                lines.append(
                    "  \(tree.name): \(count) commit\(count == 1 ? "" : "s") since the last release (\(was.prefix(12)))"
                )
                let log = git(
                    ["log", "--format=%h %s (%an, %ar)", "-25", "\(was)..\(head)"], in: source)
                lines += log.split(separator: "\n").map { "    \($0)" }
                if count > 25 { lines.append("    and \(count - 25) more") }
            } else {
                lines.append(
                    last[tree.name] == nil
                        ? "  \(tree.name) at \(head.prefix(12)): no release to compare with"
                        : "  \(tree.name) at \(head.prefix(12)): not after the last release (\(last[tree.name]!.prefix(12))), its history was rewritten"
                )
            }
        }
        if !changed { lines.append("  the same commits as the last release, built again") }

        // The working folder: cloned once, laid out as the trees are
        // (relative paths still hold), moved to the approved commits at
        // every release; ignored files (build output) stay, the caches.
        let work = releases.appending(path: "\(manifest.app)/work").path
        let parents = sources.values.map { ($0 as NSString).deletingLastPathComponent }
        let ancestor = commonAncestor(parents)
        var trees: [String: Plan.Tree] = [:]
        for tree in manifest.trees {
            let source = sources[tree.name]!
            let clone = work + String(source.dropFirst(ancestor.count))
            if !FileManager.default.fileExists(atPath: clone + "/.git") {
                try? FileManager.default.createDirectory(
                    atPath: (clone as NSString).deletingLastPathComponent,
                    withIntermediateDirectories: true)
                must(["git", "clone", "-q", source, clone])
            }
            _ = git(["remote", "set-url", "origin", source], in: clone)
            // The source's HEAD itself: a branch fetch misses a detached commit.
            _ = git(["fetch", "-q", "origin", "HEAD"], in: clone)
            _ = git(["checkout", "-q", "--force", "--detach", heads[tree.name]!], in: clone)
            _ = git(["clean", "-q", "-f", "-d"], in: clone)
            for submodule in tree.submodules ?? [] {
                _ = git(
                    ["config", "submodule.\(submodule).url", source + "/" + submodule], in: clone)
                _ = git(
                    [
                        "-c", "protocol.file.allow=always", "submodule", "update", "-q", "--init",
                        "--force", submodule,
                    ], in: clone)
                _ = git(["clean", "-q", "-f", "-d"], in: clone + "/" + submodule)
            }
            trees[tree.name] = Plan.Tree(clone: clone, head: heads[tree.name]!)
        }
        let appRoot = trees[own.name]!.clone
        let script = appRoot + "/" + manifest.script
        let sourcesSaid = manifest.trees.map { "\($0.name)@\(heads[$0.name]!.prefix(12))" }.joined(
            separator: " ")
        let scriptSHA = sha256(file: script)
        lines.append("  builds with \(manifest.script) (sha256 \(scriptSHA.prefix(16)))")
        apps.append(
            Plan.App(
                app: manifest.app, repo: sources[own.name]!, root: appRoot, script: script,
                scriptSHA256: scriptSHA, trees: trees,
                artifacts: manifest.artifacts, secrets: (manifest.secrets ?? [:]).keys.sorted(),
                sources: sourcesSaid,
                heads: manifest.trees.map { "\($0.name)=\(heads[$0.name]!)" }.joined(
                    separator: " "),
                log: releases.appending(path: "\(manifest.app)/release.log").path))
    }

    // The plan, written once and pinned by its hash in the command the
    // person approves.
    try? FileManager.default.createDirectory(at: releases, withIntermediateDirectories: true)
    let stamp = Int(Date().timeIntervalSince1970)
    let planPath = releases.appending(path: "plan-\(stamp).json").path
    let resultPath = releases.appending(path: "result-\(stamp).json").path
    guard let planData = try? JSONEncoder().encode(Plan(apps: apps, result: resultPath)),
        FileManager.default.createFile(
            atPath: planPath, contents: planData, attributes: [.posixPermissions: 0o600])
    else { die("cannot write the build plan") }
    let planSHA = sha256(file: planPath)

    var env = [
        "SHIP_RELEASE_IDENTITY": "{identity}",
        "SHIP_RELEASE_IDENTITY_PASSWORD": "{identityPassword}",
        "SHIP_RELEASE_APPSTORE_KEY": "{appStoreKey}",
    ]
    for name in releaseValues { env[name] = environment[name]! }
    for app in apps { for name in app.secrets { env[name] = "{\(name)}" } }
    let names = apps.map(\.app)
    let request = ApprovalRequest(
        title:
            "Release \(names.count == 1 ? names[0] : names.dropLast().joined(separator: ", ") + " and " + names.last!)?",
        lines: lines, secrets: secrets,
        run: .init(
            argv: [realPath(CommandLine.arguments[0]), "release-run", planPath, planSHA], env: env))

    print("ship: asking to release \(names.joined(separator: ", ")) (plan \(planSHA.prefix(16)))")
    let approval = Process()
    approval.executableURL = URL(filePath: "/bin/sh")
    approval.arguments = ["-c", approver]
    let input = Pipe()
    approval.standardInput = input
    do { try approval.run() } catch {
        die("SHIP_APPROVE (\(approver)): \(error.localizedDescription)")
    }
    guard let body = try? JSONEncoder().encode(request) else { die("cannot encode the request") }
    input.fileHandleForWriting.write(body)
    try? input.fileHandleForWriting.close()
    approval.waitUntilExit()
    try? FileManager.default.removeItem(atPath: planPath)
    guard approval.terminationStatus == 0 else {
        try? FileManager.default.removeItem(atPath: resultPath)
        die("not released (the approver exited \(approval.terminationStatus))")
    }

    // Released: the artifacts where each manifest says, and the records.
    guard let resultData = FileManager.default.contents(atPath: resultPath),
        let result = try? JSONDecoder().decode(Built.self, from: resultData)
    else { die("the release ran but left no result at \(resultPath)") }
    try? FileManager.default.removeItem(atPath: resultPath)
    for app in apps {
        for artifact in app.artifacts {
            let built = app.root + "/" + artifact
            let destination = app.repo + "/" + artifact
            try? FileManager.default.removeItem(atPath: destination)
            try? FileManager.default.createDirectory(
                atPath: (destination as NSString).deletingLastPathComponent,
                withIntermediateDirectories: true)
            do { try FileManager.default.copyItem(atPath: built, toPath: destination) } catch {
                die("cannot copy \(built) to \(destination): \(error.localizedDescription)")
            }
            print(
                "ship: released \(app.app): \(destination) (\(result.artifacts[app.app]?[artifact]?.prefix(16) ?? "?"))"
            )
        }
        let record = Record(
            sources: app.trees.mapValues(\.head), at: Date().timeIntervalSince1970,
            artifacts: result.artifacts[app.app])
        guard let data = try? JSONEncoder().encode(record),
            (try? data.write(to: recordFile(app.app), options: .atomic)) != nil
        else { die("cannot write \(app.app)'s release record") }
        print("ship: \(app.app) built in \(Int(result.seconds[app.app] ?? 0)) s")
    }
    print(
        "ship: released \(names.joined(separator: ", ")) in \(Int(Date().timeIntervalSince(began))) s"
    )
    exit(0)
}

/// The deepest directory containing every path.
func commonAncestor(_ paths: [String]) -> String {
    let split = paths.map { $0.split(separator: "/").map(String.init) }
    var common = split.first ?? []
    for parts in split.dropFirst() {
        common = Array(zip(common, parts).prefix { $0 == $1 }.map(\.0))
    }
    return "/" + common.joined(separator: "/")
}

// MARK: - ship release-run (what the approver runs)

/// `ship release-run <plan> <sha256>`: run by the approver after the yes,
/// with the keys in its environment. The plan must be the one approved,
/// every clone at its approved commit and clean, every script the one
/// shown; then the keys go into a keychain of the release's own, every app
/// builds at once (each into its own log), and what they made is digested.
func releaseRun(_ arguments: [String]) -> Never {
    guard arguments.count == 2 else {
        die("usage: ship release-run <plan> <sha256> (run by the approver)")
    }
    let (planPath, approved) = (arguments[0], arguments[1])
    guard sha256(file: planPath) == approved,
        let plan = try? JSONDecoder().decode(
            Plan.self, from: FileManager.default.contents(atPath: planPath)!)
    else { die("the build plan is not the one approved") }
    let environment = ProcessInfo.processInfo.environment
    for app in plan.apps {
        for (name, tree) in app.trees {
            guard git(["rev-parse", "HEAD"], in: tree.clone) == tree.head,
                git(["status", "--porcelain"], in: tree.clone).isEmpty
            else { die("\(app.app): \(name)'s clone changed since it was approved") }
        }
        guard sha256(file: app.script) == app.scriptSHA256 else {
            die("\(app.app): \(app.script) changed since it was approved")
        }
    }
    let keys = releaseKeys.map { environment[$0] ?? "" }
    guard !keys.contains(where: \.isEmpty) else {
        die("the approver gave no keys (\(releaseKeys.joined(separator: ", ")))")
    }

    let keychain: ReleaseKeychain
    do {
        keychain = try ReleaseKeychain(identity: keys[0], password: keys[1], appStoreKey: keys[2])
    } catch { die("\(error)") }

    let outcome = Outcome()
    let group = DispatchGroup()
    for app in plan.apps {
        var built: [String: String] = [
            "APPSTORE_KEY": keychain.appStoreKeyPath, "SHIP_KEYCHAIN": keychain.path,
            "SHIP_RELEASE_SOURCES": app.sources, "SHIP_RELEASE_HEADS": app.heads,
        ]
        for name in releaseValues { built[name] = environment[name]! }
        for name in app.secrets {
            guard let value = environment[name], !value.isEmpty else {
                die("\(app.app): the approver gave no \(name)")
            }
            do { built[name] = try keychain.write(name, value) } catch { die("\(error)") }
        }
        let env = built
        group.enter()
        DispatchQueue.global().async {
            let began = Date()
            print("ship: \(app.app): building (log: \(app.log))")
            let process = Process()
            process.executableURL = URL(filePath: app.script)
            process.arguments = [app.root]
            process.currentDirectoryURL = URL(filePath: app.root)
            process.environment = environment.filter {
                !releaseKeys.contains($0.key) && !app.secrets.contains($0.key)
            }
            .merging(env) { $1 }
            FileManager.default.createFile(atPath: app.log, contents: nil)
            let log = FileHandle(forWritingAtPath: app.log)
            process.standardOutput = log
            process.standardError = log
            var status: Int32 = 1
            do {
                try process.run()
                process.waitUntilExit()
                status = process.terminationStatus
            } catch {
                log?.write(Data("ship: \(error.localizedDescription)\n".utf8))
            }
            try? log?.close()
            let seconds = Date().timeIntervalSince(began)
            var made: [String: String] = [:]
            if status == 0 {
                for artifact in app.artifacts { made[artifact] = digest(app.root + "/" + artifact) }
            }
            if status == 0 {
                print("ship: \(app.app): built in \(Int(seconds)) s")
            } else {
                let tail =
                    (try? String(contentsOfFile: app.log, encoding: .utf8))?
                    .split(separator: "\n").suffix(15).joined(separator: "\n") ?? ""
                print(
                    "ship: \(app.app): FAILED (exit \(status)) after \(Int(seconds)) s; the end of \(app.log):\n\(tail)"
                )
            }
            outcome.record(app.app, seconds: seconds, made: status == 0 ? made : nil)
            group.leave()
        }
    }
    group.wait()
    keychain.close()
    let (result, failed) = outcome.read()
    guard failed.isEmpty else { die("not released: \(failed.joined(separator: ", ")) failed") }
    guard let data = try? JSONEncoder().encode(result),
        FileManager.default.createFile(
            atPath: plan.result, contents: data, attributes: [.posixPermissions: 0o600])
    else { die("cannot write the result") }
    exit(0)
}

/// What the apps building at once made, gathered from their threads.
final class Outcome: @unchecked Sendable {
    private let lock = NSLock()
    private var built = Built(artifacts: [:], seconds: [:])
    private var failed: [String] = []

    /// `made` nil: the app's build failed.
    func record(_ app: String, seconds: Double, made: [String: String]?) {
        lock.withLock {
            built.seconds[app] = seconds
            if let made { built.artifacts[app] = made } else { failed.append(app) }
        }
    }

    func read() -> (Built, [String]) { lock.withLock { (built, failed) } }
}

// MARK: - the release's keychain

/// The keys of one release, held where Apple's tools look and nowhere else:
/// the Developer ID identity in a keychain of the release's own (a random
/// password, never written anywhere, first on the search list while the
/// release runs), the App Store Connect key in a file only this user can
/// read. `close` removes both and puts the search list back as it was.
final class ReleaseKeychain: @unchecked Sendable {
    let appStoreKeyPath: String
    /// The keychain's file: a script that signs with codesign names it
    /// (`--keychain`), so a second copy of the identity elsewhere is never
    /// chosen. Its password is never shared.
    let path: String
    private let directory: URL
    private let keychain: SecKeychain
    private let searched: [SecKeychain]

    struct Failure: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }

    init(identity base64: String, password: String, appStoreKey: String) throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "ship-release-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700])
        // A step that fails takes everything before it with it, as `close` does.
        var made: SecKeychain?
        var previous: [SecKeychain]?
        var opened = false
        defer {
            if !opened {
                if let previous { SecKeychainSetSearchList(previous as CFArray) }
                if let made { SecKeychainDelete(made) }
                try? FileManager.default.removeItem(at: directory)
            }
        }
        let path = directory.appending(path: "release.keychain-db").path
        var random = [UInt8](repeating: 0, count: 24)
        guard SecRandomCopyBytes(kSecRandomDefault, random.count, &random) == errSecSuccess else {
            throw Failure("no randomness for the release keychain's password")
        }
        let secret = random.map { String(format: "%02x", $0) }.joined()
        guard
            SecKeychainCreate(path, UInt32(secret.utf8.count), secret, false, nil, &made)
                == errSecSuccess,
            let keychain = made
        else { throw Failure("the release keychain could not be created") }
        // Unlocked for the whole release however long it takes: no lock on
        // sleep, an interval longer than any release, unlocked explicitly
        // (a locked one makes macOS ask a person for a password nobody knows).
        var settings = SecKeychainSettings(
            version: UInt32(SEC_KEYCHAIN_SETTINGS_VERS1), lockOnSleep: false,
            useLockInterval: false,
            lockInterval: UInt32(Int32.max))
        SecKeychainSetSettings(keychain, &settings)
        guard SecKeychainUnlock(keychain, UInt32(secret.utf8.count), secret, true) == errSecSuccess
        else {
            throw Failure("the release keychain could not be unlocked")
        }

        guard let p12 = Data(base64Encoded: base64) else {
            throw Failure("the identity is not a base64 .p12")
        }
        var format = SecExternalFormat.formatPKCS12
        var type = SecExternalItemType.itemTypeAggregate
        var parameters = SecItemImportExportKeyParameters()
        parameters.version = UInt32(SEC_KEY_IMPORT_EXPORT_PARAMS_VERSION)
        parameters.passphrase = Unmanaged.passRetained(password as CFString as AnyObject)
        defer { parameters.passphrase?.release() }
        // Who may use the key without a question: codesign (what xcodebuild
        // signs through), and this program.
        var trusted: [SecTrustedApplication] = []
        for path in ["/usr/bin/codesign", CommandLine.arguments[0]] {
            var application: SecTrustedApplication?
            if SecTrustedApplicationCreateFromPath(path, &application) == errSecSuccess,
                let application
            {
                trusted.append(application)
            }
        }
        var access: SecAccess?
        guard
            SecAccessCreate("ship release" as CFString, trusted as CFArray, &access)
                == errSecSuccess, let access
        else { throw Failure("the identity's access list could not be made") }
        parameters.accessRef = Unmanaged.passRetained(access)
        defer { parameters.accessRef?.release() }
        var items: CFArray?
        let imported = SecItemImport(
            p12 as CFData, nil, &format, &type, [], &parameters, keychain, &items)
        guard imported == errSecSuccess else {
            throw Failure("the identity did not import (OSStatus \(imported))")
        }
        // Exactly the one identity a release signs with: a p12 exported from
        // a login keychain carries every identity in it, and those would ride
        // into the release's keychain on the same yes.
        let all = (items as? [AnyObject]) ?? []
        let identities = all.filter { CFGetTypeID($0) == SecIdentityGetTypeID() }.map {
            $0 as! SecIdentity
        }
        let names = identities.map { identity -> String in
            var certificate: SecCertificate?
            SecIdentityCopyCertificate(identity, &certificate)
            return certificate.flatMap { SecCertificateCopySubjectSummary($0) as String? } ?? "?"
        }
        guard identities.count == 1, all.count == 1,
            names[0].hasPrefix("Developer ID Application: ")
        else {
            throw Failure(
                "the release identity must be one Developer ID Application identity and nothing else; it holds \(all.count) item(s): \(names.joined(separator: ", "))"
            )
        }
        // codesign reads the key without a prompt; the keychain's password is
        // the throwaway one.
        let partition = run(
            [
                "security", "set-key-partition-list", "-S", "apple-tool:,apple:,codesign:", "-s",
                "-k", secret, path,
            ],
            quiet: true)
        guard partition.code == 0 else {
            throw Failure("the key's partition list could not be set")
        }

        var list: CFArray?
        SecKeychainCopySearchList(&list)
        let searched = (list as? [SecKeychain]) ?? []
        previous = searched
        guard SecKeychainSetSearchList(([keychain] + searched) as CFArray) == errSecSuccess else {
            throw Failure("the release keychain could not join the search list")
        }

        let keyPath = directory.appending(path: "AuthKey.p8").path
        guard
            FileManager.default.createFile(
                atPath: keyPath,
                contents: Data(
                    (appStoreKey.hasSuffix("\n") ? appStoreKey : appStoreKey + "\n").utf8),
                attributes: [.posixPermissions: 0o600])
        else { throw Failure("the App Store Connect key could not be written") }
        self.directory = directory
        self.keychain = keychain
        self.searched = searched
        self.path = path
        appStoreKeyPath = keyPath
        opened = true
    }

    /// Another secret the manifest names, written beside the App Store
    /// Connect key (owner-only, gone with `close`): its path.
    func write(_ name: String, _ value: String) throws -> String {
        let file = directory.appending(path: name).path
        guard
            FileManager.default.createFile(
                atPath: file, contents: Data(value.utf8), attributes: [.posixPermissions: 0o600])
        else { throw Failure("\(name) could not be written") }
        return file
    }

    /// Everything gone: the search list as it was, the keychain deleted, the
    /// keys' files removed.
    func close() {
        SecKeychainSetSearchList(searched as CFArray)
        SecKeychainDelete(keychain)
        try? FileManager.default.removeItem(at: directory)
    }
}
