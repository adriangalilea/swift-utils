// since: what changed in a SwiftPM dependency for the code that uses it.
//
// Run inside an app: it reads the version the app's Package.resolved holds,
// finds the modules the app imports from the package (and the targets they
// build on, read from the package's own manifest), and prints, per module,
// every commit between that version and the latest release that touched it:
// the breaks first with what to write instead (the commit body's
// `BREAKING CHANGE:`), then features and fixes. Nothing is cut: the commits it
// does not list are the ones that touched none of the modules the app uses.
//
//   since [dir]                  the app in dir (default: here)
//   since --all <dir>            every app under dir, one line each
//   --package <identity>         the dependency (default: swift-utils)
//   --json                       the answer as data
//
// The package's history comes from a bare clone cached under
// ~/Library/Caches/since, fetched on every run. Commits are read as
// conventional (`type(scope)!: subject`); one that is not is listed as other.
import Foundation
import Terminal

setvbuf(stdout, nil, _IOLBF, 0)

// MARK: - the shell

@MainActor func die(_ message: String) -> Never {
    FileHandle.standardError.write(Data("since: \(message)\n".utf8))
    exit(1)
}

/// Runs a command and returns its output; a failure stops the program with
/// the command's own words.
@discardableResult
@MainActor func run(_ argv: [String], in dir: URL? = nil) -> String {
    let p = Process()
    p.executableURL = URL(filePath: "/usr/bin/env")
    p.arguments = argv
    if let dir { p.currentDirectoryURL = dir }
    let out = Pipe()
    let err = Pipe()
    p.standardOutput = out
    p.standardError = err
    do { try p.run() } catch { die("\(argv[0]): \(error.localizedDescription)") }
    let data = out.fileHandleForReading.readDataToEndOfFile()
    let errData = err.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    guard p.terminationStatus == 0 else {
        die(
            "\(argv.joined(separator: " ")) exited \(p.terminationStatus): \(String(decoding: errData, as: UTF8.self))"
        )
    }
    return String(decoding: data, as: UTF8.self)
}

// MARK: - the arguments

var arguments = Array(CommandLine.arguments.dropFirst())
@MainActor func flag(_ name: String) -> Bool {
    guard let i = arguments.firstIndex(of: name) else { return false }
    arguments.remove(at: i)
    return true
}
@MainActor func option(_ name: String) -> String? {
    guard let i = arguments.firstIndex(of: name) else { return nil }
    guard i + 1 < arguments.count else { die("\(name) takes a value") }
    let value = arguments[i + 1]
    arguments.removeSubrange(i...(i + 1))
    return value
}

if flag("--help") || flag("-h") {
    print(
        """
        since: what changed in a SwiftPM dependency for the code that uses it

          since [dir]               the app in dir (default: here)
          since --all <dir>         every app under dir, one line each
          --package <identity>      the dependency (default: swift-utils)
          --json                    the answer as data
        """)
    exit(0)
}
let json = flag("--json")
let all = flag("--all")
let identity = option("--package") ?? "swift-utils"
guard arguments.count <= 1 else { die("one directory at most, got \(arguments)") }
let root = URL(filePath: arguments.first ?? ".").standardizedFileURL

// MARK: - what an app holds

struct Pin {
    let location: String
    /// The tag, or nil when the app pins a branch or a revision.
    let version: String?
    let revision: String
}

/// The app's resolved pin of the package, or nil when it does not depend on it
/// through a pin (it may by `path:`, which SwiftPM does not record).
@MainActor func pin(in resolved: URL) -> Pin? {
    guard let data = try? Data(contentsOf: resolved),
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let pins = object["pins"] as? [[String: Any]]
    else { die("\(resolved.path) is not a Package.resolved") }
    guard let entry = pins.first(where: { ($0["identity"] as? String) == identity }) else {
        return nil
    }
    guard let location = entry["location"] as? String, let state = entry["state"] as? [String: Any],
        let revision = state["revision"] as? String
    else { die("\(resolved.path): the \(identity) pin has no location or revision") }
    return Pin(location: location, version: state["version"] as? String, revision: revision)
}

/// Where an app's sources live, given its Package.resolved: beside it for a
/// SwiftPM package, beside the .xcodeproj/.xcworkspace that holds it otherwise.
@MainActor func appRoot(of resolved: URL) -> URL {
    let beside = resolved.deletingLastPathComponent()
    // Xcode keeps it at X.xcodeproj/project.xcworkspace/xcshareddata/swiftpm:
    // the project wins over the workspace inside it, a standalone workspace
    // over nothing.
    let ancestors = sequence(first: beside) {
        $0.path == "/" ? nil : $0.deletingLastPathComponent()
    }
    if let project = ancestors.first(where: { $0.pathExtension == "xcodeproj" }) {
        return project.deletingLastPathComponent()
    }
    if let workspace = ancestors.first(where: { $0.pathExtension == "xcworkspace" }) {
        return workspace.deletingLastPathComponent()
    }
    return beside
}

/// Directories never searched: build products and other packages' checkouts.
let skipped: Set<String> = [".build", "checkouts", "node_modules", "DerivedData", ".git", "Pods"]

@MainActor func files(under dir: URL, where keep: (URL) -> Bool) -> [URL] {
    guard
        let walk = FileManager.default.enumerator(
            at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [])
    else { return [] }
    var found: [URL] = []
    for case let url as URL in walk {
        if skipped.contains(url.lastPathComponent) {
            walk.skipDescendants()
            continue
        }
        if keep(url) { found.append(url) }
    }
    return found
}

@MainActor func modulesImported(under dir: URL) -> Set<String> {
    let line =
        /^\s*(?:@_exported\s+|@testable\s+|@preconcurrency\s+)*import\s+(?:struct\s+|class\s+|enum\s+|protocol\s+|func\s+)?(\w+)/
        .anchorsMatchLineEndings()
    var found: Set<String> = []
    for file in files(under: dir, where: { $0.pathExtension == "swift" }) {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
        for match in text.matches(of: line) { found.insert(String(match.1)) }
    }
    return found
}

/// A `.package(path:` to the package: a local checkout, which pins nothing.
@MainActor func pathDependency(in dir: URL) -> Bool {
    let manifests =
        files(
            under: dir, where: { ["Package.swift", "project.yml"].contains($0.lastPathComponent) })
    return manifests.contains { url in
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return false }
        return text.contains("path:")
            && text.range(of: "path:[^\\n]*\(identity)", options: .regularExpression) != nil
    }
}

// MARK: - the package's history

let cache = URL(filePath: NSHomeDirectory()).appending(path: "Library/Caches/since/\(identity).git")

/// Fetched once per run, however many apps ask.
var fetched = false

@MainActor func history(from location: String) -> URL {
    if fetched { return cache }
    fetched = true
    if FileManager.default.fileExists(atPath: cache.path) {
        run([
            "git", "-C", cache.path, "fetch", "--quiet", "--tags", "--force", location,
            "+refs/heads/*:refs/heads/*",
        ])
    } else {
        try? FileManager.default.createDirectory(
            at: cache.deletingLastPathComponent(), withIntermediateDirectories: true)
        run(["git", "clone", "--quiet", "--bare", location, cache.path])
    }
    return cache
}

struct Version: Comparable {
    let parts: [Int]
    let tag: String
    init?(_ tag: String) {
        let parts = tag.drop(while: { $0 == "v" }).split(separator: ".").compactMap { Int($0) }
        guard parts.count == 3, tag.allSatisfy({ $0.isNumber || $0 == "." || $0 == "v" }) else {
            return nil
        }
        self.parts = parts
        self.tag = tag
    }
    static func < (a: Version, b: Version) -> Bool { a.parts.lexicographicallyPrecedes(b.parts) }
}

@MainActor func releases(in repo: URL) -> [Version] {
    run(["git", "-C", repo.path, "tag"]).split(separator: "\n").compactMap { Version(String($0)) }
        .sorted()
}

/// The package's targets at `tag`, read from the manifest itself: each one's
/// directory, and every target it builds on (itself included).
struct Targets {
    let path: [String: String]
    let closure: [String: Set<String>]
}

/// Each tag's manifest is read once per run.
var manifests: [String: Targets] = [:]

@MainActor func targets(in repo: URL, at tag: String) -> Targets {
    if let known = manifests[tag] { return known }
    let read = readTargets(in: repo, at: tag)
    manifests[tag] = read
    return read
}

@MainActor func readTargets(in repo: URL, at tag: String) -> Targets {
    let tree = FileManager.default.temporaryDirectory.appending(path: "since-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: tree, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tree) }
    let archive = tree.appending(path: "manifest.tar")
    run(["git", "-C", repo.path, "archive", "--output", archive.path, tag, "Package.swift"])
    run(["tar", "-xf", archive.path, "-C", tree.path])
    let dump = run(["swift", "package", "dump-package", "--package-path", tree.path])
    guard let manifest = try? JSONSerialization.jsonObject(with: Data(dump.utf8)) as? [String: Any],
        let targets = manifest["targets"] as? [[String: Any]]
    else { die("\(identity) \(tag): its manifest did not dump") }

    var path: [String: String] = [:]
    var needs: [String: [String]] = [:]
    for target in targets {
        guard let name = target["name"] as? String, (target["type"] as? String) != "test" else {
            continue
        }
        path[name] = target["path"] as? String ?? "Sources/\(name)"
        needs[name] = (target["dependencies"] as? [[String: Any]] ?? []).compactMap { dependency in
            ((dependency["byName"] ?? dependency["target"]) as? [Any])?.first as? String
        }
    }
    var closure: [String: Set<String>] = [:]
    for name in path.keys {
        var seen: Set<String> = []
        var stack = [name]
        while let next = stack.popLast() {
            guard path[next] != nil, seen.insert(next).inserted else { continue }
            stack += needs[next] ?? []
        }
        closure[name] = seen
    }
    return Targets(path: path, closure: closure)
}

struct Change: Codable {
    enum Kind: String, Codable { case breaking, feature, fix, other }
    let kind: Kind
    let subject: String
    let commit: String
    /// What a break asks of the code that uses it: its `BREAKING CHANGE:` note.
    let migration: String?
}

@MainActor func changes(in repo: URL, from: String, to: String, paths: [String]) -> [Change] {
    let log = run(
        ["git", "-C", repo.path, "log", "--format=%h%x1f%s%x1f%b%x1e", "\(from)..\(to)", "--"]
            + paths)
    let conventional = #/^(\w+)(\([^)]*\))?(!)?: /#
    return log.split(separator: "\u{1e}").compactMap { record in
        let fields = record.trimmingCharacters(in: .newlines).split(
            separator: "\u{1f}", omittingEmptySubsequences: false)
        guard fields.count >= 2 else { return nil }
        let subject = String(fields[1])
        let body = fields.count > 2 ? String(fields[2]) : ""
        let note = body.range(of: "BREAKING[ -]CHANGE:\\s*", options: .regularExpression).map {
            String(body[$0.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let kind: Change.Kind
        if let m = subject.firstMatch(of: conventional) {
            if m.3 != nil || note != nil {
                kind = .breaking
            } else {
                switch m.1 {
                case "feat": kind = .feature
                case "fix": kind = .fix
                case "docs", "style", "test", "ci", "chore", "build": return nil
                default: kind = .other
                }
            }
        } else {
            kind = .other
        }
        return Change(kind: kind, subject: subject, commit: String(fields[0]), migration: note)
    }
}

// MARK: - one app

/// One module the app's code depends on, listed once, with the changes made
/// to it alone: imported by the app, or built on by modules it imports.
struct ModuleReport: Codable {
    let module: String
    let imported: Bool
    /// The imported modules that build on it, when the app does not import it.
    let under: [String]
    let changes: [Change]
}

struct AppReport: Codable {
    let app: String
    let resolved: String?
    let latest: String?
    /// Releases between the resolved one and the latest.
    let behind: Int?
    let modules: [ModuleReport]
    /// Why there is nothing to compare: a path dependency, no pin, a branch.
    let note: String?
}

@MainActor func report(resolvedFile: URL) -> AppReport? {
    let app = appRoot(of: resolvedFile)
    let label =
        app == root
        ? app.lastPathComponent : app.path.replacingOccurrences(of: root.path + "/", with: "")
    guard let pin = pin(in: resolvedFile) else { return nil }
    let repo = history(from: pin.location)
    let tags = releases(in: repo)
    guard let latest = tags.last else { die("\(identity) has no release tag") }
    let from = pin.version ?? pin.revision
    let behind = pin.version.flatMap { v in Version(v).map { r in tags.filter { $0 > r }.count } }
    let package = targets(in: repo, at: latest.tag)
    let imported = modulesImported(under: app).filter { package.path[$0] != nil }
    let involved = imported.reduce(into: Set<String>()) { $0.formUnion(package.closure[$1] ?? []) }
    let modules = involved.sorted {
        (imported.contains($0) ? 0 : 1, $0) < (imported.contains($1) ? 0 : 1, $1)
    }
    .map { module in
        ModuleReport(
            module: module, imported: imported.contains(module),
            under: imported.filter { $0 != module && package.closure[$0]?.contains(module) == true }
                .sorted(),
            changes: changes(in: repo, from: from, to: latest.tag, paths: [package.path[module]!]))
    }
    return AppReport(
        app: label, resolved: pin.version ?? String(pin.revision.prefix(7)), latest: latest.tag,
        behind: behind,
        modules: modules, note: pin.version == nil ? "pinned to a revision, not a release" : nil)
}

@MainActor func resolvedFiles(under dir: URL) -> [URL] {
    files(under: dir, where: { $0.lastPathComponent == "Package.resolved" })
}

@MainActor func printApp(_ r: AppReport) {
    let behind =
        r.behind.map { $0 == 0 ? "up to date" : "\($0) release\($0 == 1 ? "" : "s") behind" } ?? ""
    print(
        "\(ui.accent(r.app))  \(identity) \(r.resolved ?? "?") → \(r.latest ?? "?")  \(ui.muted(behind))"
    )
    if let note = r.note { print(ui.warn("  \(note)")) }
    let quiet = r.modules.filter(\.changes.isEmpty).map(\.module)
    for m in r.modules where !m.changes.isEmpty {
        let how = m.imported ? "" : "  under \(m.under.joined(separator: ", "))"
        print(
            "\n  \(ui.head(m.module))  \(ui.muted("\(m.changes.count) change\(m.changes.count == 1 ? "" : "s")\(how)"))"
        )
        for (kind, title) in [
            (Change.Kind.breaking, "breaking"), (.feature, "features"), (.fix, "fixes"),
            (.other, "other"),
        ] {
            let these = m.changes.filter { $0.kind == kind }
            guard !these.isEmpty else { continue }
            print("    \(kind == .breaking ? ui.bad(title) : ui.muted(title))")
            for c in these {
                print("      \(c.subject)  \(ui.muted(c.commit))")
                if let migration = c.migration { print(ui.warn(indent(migration, 8))) }
            }
        }
    }
    if !quiet.isEmpty { print("\n  \(ui.ok("unchanged:")) \(quiet.joined(separator: ", "))") }
    // Said, never left blank: no import found is a fact about the scan.
    if r.modules.isEmpty {
        print(ui.warn("  imports none of \(identity)'s modules (scanned \(r.app))"))
    }
}

// MARK: - run

@MainActor func encode(_ value: some Encodable) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    print(String(decoding: try! encoder.encode(value), as: UTF8.self))
}

if all {
    var reports: [AppReport] = []
    var unpinned: [String] = []
    for file in resolvedFiles(under: root) {
        if let r = report(resolvedFile: file) { reports.append(r) }
    }
    // A manifest that names the package by path pins nothing: it builds
    // against whatever that checkout holds today.
    for manifest in files(
        under: root, where: { ["Package.swift", "project.yml"].contains($0.lastPathComponent) })
    {
        let dir = manifest.deletingLastPathComponent()
        if pathDependency(in: dir),
            !reports.contains(where: { root.appending(path: $0.app).path == dir.path })
        {
            unpinned.append(dir.path.replacingOccurrences(of: root.path + "/", with: ""))
        }
    }
    if json {
        struct All: Codable {
            let apps: [AppReport]
            let pathDependencies: [String]
        }
        encode(All(apps: reports, pathDependencies: Array(Set(unpinned)).sorted()))
        exit(0)
    }
    let rows = reports.sorted { $0.app < $1.app }.map { r -> [String] in
        let breaks = r.modules.flatMap(\.changes).filter { $0.kind == .breaking }
        let hit = r.modules.filter { $0.changes.contains { $0.kind == .breaking } }.map(\.module)
        return [
            r.app, r.resolved ?? "?", r.behind.map(String.init) ?? "-",
            breaks.isEmpty
                ? ui.ok("none") : ui.bad("\(breaks.count) in \(hit.joined(separator: ", "))"),
            r.modules.map(\.module).joined(separator: " "),
        ]
    }
    let latest = reports.first?.latest ?? "?"
    print("\(identity) latest \(latest)\n")
    print(
        table(
            rows, head: ["app", "resolved", "behind", "breaking", "uses"], align: ["l", "l", "r"]))
    for dir in Set(unpinned).sorted() {
        print(ui.warn("\(dir): \(identity) by path, pinned to no release"))
    }
    exit(0)
}

let found = resolvedFiles(under: root)
guard !found.isEmpty else {
    if pathDependency(in: root) { die("\(identity) is a path dependency here: it pins no release") }
    die(
        "no Package.resolved under \(root.path): resolve the package first (swift package resolve, or open it in Xcode)"
    )
}
let reports = found.compactMap(report(resolvedFile:))
guard !reports.isEmpty else { die("nothing under \(root.path) pins \(identity)") }
if json {
    encode(reports)
} else {
    for (i, r) in reports.enumerated() {
        if i > 0 { print("") }
        printApp(r)
    }
}
