// grant: an app's permissions from outside it, for development.
//
//   grant status <app>   what the app last read for each permission (its own
//                        log, scope `grant`, written by Grant's Permissions
//                        hub), and who signed the build installed
//   grant reset <app>    quit it, clear every permission record macOS holds for
//                        its bundle id (`tccutil reset All`), and reopen it: the
//                        next ask records the build that runs now
//
// <app> is a bundle id, a path to a .app, or an app's name. An app can only ask
// tccd about itself, so status reads what the app recorded, never tccd.

import Foundation
import Grant

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("grant: \(message)\n".utf8))
    exit(1)
}

@discardableResult
func run(_ tool: String, _ args: [String]) -> (status: Int32, out: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: tool)
    process.arguments = args
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    do { try process.run() } catch { fail("\(tool) did not start: \(error)") }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return (process.terminationStatus, String(decoding: data, as: UTF8.self))
}

struct App {
    let id: String
    /// Every copy of the bundle id on disk: tccd holds ONE record per bundle
    /// id, bound to one signature, so copies signed differently fight over it.
    let copies: [String]
    /// The executable's name, for quitting and finding it running.
    var name: String? {
        copies.first.map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent }
    }
}

/// A bundle id, a .app path, or an app's name (as its .app is called).
func resolve(_ argument: String) -> App {
    let id: String
    if argument.hasSuffix(".app") || argument.contains("/") {
        let url = URL(fileURLWithPath: (argument as NSString).expandingTildeInPath)
        guard let found = Bundle(url: url)?.bundleIdentifier else {
            fail("no bundle id in \(url.path)")
        }
        id = found
    } else if argument.contains(".") {
        id = argument
    } else {
        let found = run("/usr/bin/mdfind", ["kMDItemFSName == '\(argument).app'"]).out
        guard let path = found.split(separator: "\n").first.map(String.init),
            let found = Bundle(url: URL(fileURLWithPath: path))?.bundleIdentifier
        else { fail("no app named \(argument)") }
        id = found
    }
    let copies = run("/usr/bin/mdfind", ["kMDItemCFBundleIdentifier == '\(id)'"]).out
        .split(separator: "\n").map(String.init)
    return App(id: id, copies: copies)
}

/// The latest reading of each permission, from the app's unified log.
func readings(of app: App) -> [(grant: String, word: String, tccd: Int?, at: String)] {
    let predicate = "subsystem == \"\(app.id)\" AND category == \"grant\""
    let out = run(
        "/usr/bin/log",
        ["show", "--last", "3d", "--info", "--style", "ndjson", "--predicate", predicate]
    ).out
    var latest: [String: (word: String, tccd: Int?, at: String)] = [:]
    for line in out.split(separator: "\n") {
        guard
            let entry = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
            let message = entry["eventMessage"] as? String,
            let event = try? JSONSerialization.jsonObject(with: Data(message.utf8))
                as? [String: Any],
            let msg = event["msg"] as? String,
            let fields = event["fields"] as? [String: Any],
            let grant = fields["grant"] as? String,
            msg.hasPrefix("reads ") || msg.hasPrefix("changed to ")
        else { continue }
        let word = msg.replacingOccurrences(of: "reads ", with: "")
            .replacingOccurrences(of: "changed to ", with: "")
        latest[grant] = (
            word, fields["tccd"] as? Int, String((entry["timestamp"] as? String ?? "").prefix(19))
        )
    }
    return latest.sorted { $0.key < $1.key }.map {
        ($0.key, $0.value.word, $0.value.tccd, $0.value.at)
    }
}

func signer(of path: String) -> String {
    let out = run("/usr/bin/codesign", ["-dvv", path]).out
    return out.split(separator: "\n").first { $0.hasPrefix("Authority=") }
        .map { String($0.dropFirst("Authority=".count)) } ?? "unsigned or ad hoc"
}

func status(_ app: App) {
    print(app.id)
    if app.copies.isEmpty { print("  no copy on disk") }
    let signers = app.copies.map { signer(of: $0) }
    for (path, by) in zip(app.copies, signers) { print("  \(path)\n    signed by \(by)") }
    if Set(signers).count > 1 {
        print(
            "  ! copies signed differently: tccd binds the one record to one signer, the other copy reads denied with its switch on (grant reset after removing it)"
        )
    }
    let rows = readings(of: app)
    guard !rows.isEmpty else {
        print(
            "no readings in its log for 3 days (not on Grant's Permissions hub, or not run since)")
        return
    }
    for row in rows {
        let code = row.tccd.map { " (tccd \($0))" } ?? ""
        print(
            "  \(row.grant.padding(toLength: 24, withPad: " ", startingAt: 0)) \(row.word)\(code)  \(row.at)"
        )
    }
}

func reset(_ app: App, reopen: Bool) {
    // The breadcrumb first: what the app read before the records went.
    status(app)
    let name = app.name
    let wasRunning = name.map { run("/usr/bin/pgrep", ["-x", $0]).status == 0 } ?? false
    if wasRunning, let name {
        run("/usr/bin/pkill", ["-x", name])
        while run("/usr/bin/pgrep", ["-x", name]).status == 0 { usleep(100_000) }
    }
    let result = run("/usr/bin/tccutil", ["reset", "All", app.id])
    guard result.status == 0 else { fail("tccutil reset All \(app.id): \(result.out)") }
    print("cleared every permission record for \(app.id)")
    print(
        "  (the hub's services: \(Permissions.Service.allCases.map(\.rawValue).joined(separator: ", ")), and all others)"
    )
    if reopen, wasRunning {
        run("/usr/bin/open", ["-b", app.id])
        print("reopened \(app.id): its next ask records this build")
    }
}

let args = Array(CommandLine.arguments.dropFirst())
switch args.first {
case "status" where args.count == 2:
    status(resolve(args[1]))
case "reset" where args.count >= 2:
    reset(resolve(args[1]), reopen: !args.contains("--no-reopen"))
default:
    print(
        """
        usage: grant status <app>                 what it last read for each permission, and its signer
               grant reset <app> [--no-reopen]    quit, clear its permission records, reopen
        <app>: a bundle id, a .app path, or an app's name
        """)
    exit(args.isEmpty || args.first == "help" ? 0 : 1)
}
