// grant: an app's permissions from outside it, for development.
//
//   grant status <app>   what the app last read for each permission (its own
//                        log, scope `grant`, written by PermissionGrants'
//                        hub), and who signed the build installed
//   grant reset <app>    quit it, clear every permission record macOS holds for
//                        its bundle id (`tccutil reset All`), and reopen it: the
//                        next ask records the build that runs now
//   grant lint <dir>...  every Swift source under the dirs that reads or asks a
//                        permission, or installs a background job, through
//                        Apple's API instead of PermissionGrants and
//                        AppInstallations; exit 1 when any does (an app's
//                        `mise check` runs it; never swift-utils, which owns
//                        those calls). `// lock-in: allowed — <why>` on the
//                        line or the line above exempts it, the why in sight.
//
// <app> is a bundle id, a path to a .app, or an app's name. An app can only ask
// tccd about itself, so status reads what the app recorded, never tccd.

import Foundation
import PermissionGrants

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
func readings(of app: App) -> [(grant: String, word: String, from: String, at: String)] {
    let predicate = "subsystem == \"\(app.id)\" AND category == \"grant\""
    let out = run(
        "/usr/bin/log",
        ["show", "--last", "3d", "--info", "--style", "ndjson", "--predicate", predicate]
    ).out
    var latest: [String: (word: String, from: String, at: String)] = [:]
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
        // Where the answer came from (the hub's source, a fresh process or
        // this one) and its raw code; a background service has neither.
        let from = [fields["source"] as? String, (fields["code"] as? Int).map { "code \($0)" }]
            .compactMap { $0 }.joined(separator: ", ")
        latest[grant] = (word, from, String((entry["timestamp"] as? String ?? "").prefix(19)))
    }
    return latest.sorted { $0.key < $1.key }.map {
        ($0.key, $0.value.word, $0.value.from, $0.value.at)
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
            "no readings in its log for 3 days (not on PermissionGrants, or not run since)")
        return
    }
    for row in rows {
        let from = row.from.isEmpty ? "" : " (\(row.from))"
        print(
            "  \(row.grant.padding(toLength: 24, withPad: " ", startingAt: 0)) \(row.word)\(from)  \(row.at)"
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
        "  (the Privacy switches grants read: \(PermissionGrant.Privacy.allCases.map(\.rawValue).joined(separator: ", ")), and all others)"
    )
    if reopen, wasRunning {
        run("/usr/bin/open", ["-b", app.id])
        print("reopened \(app.id): its next ask records this build")
    }
}

/// Apple's permission and background-job API, each with what replaces it: the
/// one list every app's gate checks against.
let lockIn: [(api: String, pattern: String, use: String)] = [
    (
        "SMAppService", #"\bSMAppService\b"#,
        "AppInstallation.Job, PermissionGrant.backgroundService / .LaunchAtLogin"
    ),
    ("AXIsProcessTrusted", #"\bAXIsProcessTrusted"#, "PermissionGrant.privacy(.accessibility)"),
    (
        "CGPreflight/CGRequest…Access",
        #"\bCG(Preflight|Request)(ScreenCapture|PostEvent|ListenEvent)Access\b"#,
        "PermissionGrant.privacy(.screenRecording / .postEvents / .inputMonitoring)"
    ),
    (
        "IOHIDCheckAccess/IOHIDRequestAccess", #"\bIOHID(Check|Request)Access\b"#,
        "PermissionGrant.privacy(.inputMonitoring)"
    ),
    ("TCCAccess…", #"\bTCCAccess\w*"#, "PermissionGrant.privacy (its hub reads tccd)"),
    (
        "AVCaptureDevice authorization",
        #"\bAVCaptureDevice\.(authorizationStatus|requestAccess)\b"#,
        "PermissionGrant.privacy(.microphone / .camera)"
    ),
    (
        "AVAudioApplication record permission",
        #"\bAVAudioApplication\b.*\b(recordPermission|requestRecordPermission)\b"#,
        "PermissionGrant.privacy(.microphone)"
    ),
    (
        "SFSpeechRecognizer authorization",
        #"\bSFSpeechRecognizer\.(authorizationStatus|requestAuthorization)\b"#,
        "PermissionGrant.privacy(.speechRecognition)"
    ),
    (
        "CMHeadphoneMotionManager authorization",
        #"\bCMHeadphoneMotionManager\.authorizationStatus\b"#,
        "PermissionGrant.privacy(.motion)"
    ),
    (
        "notification authorization",
        #"\b(requestAuthorization\(options|getNotificationSettings|\.notificationSettings\(\))"#,
        "PermissionGrant.notifications"
    ),
    (
        "AEDeterminePermissionToAutomateTarget", #"\bAEDeterminePermissionToAutomateTarget\b"#,
        "PermissionGrant.automation(of:)"
    ),
    (
        "System Settings deep link", #"x-apple\.systempreferences"#,
        "the grant's own act (PermissionGrant.act)"
    ),
]

/// `grant lint`: prints each use with what to use instead; true when clean.
func lint(_ roots: [String]) -> Bool {
    // Build output and other repos' clones (a release's staging `out/`), never source.
    let skipped: Set<String> = [
        ".build", "build", "out", "Packages", "checkouts", "DerivedData", "node_modules", ".git",
    ]
    let rules = lockIn.map { rule in
        (rule, try! NSRegularExpression(pattern: rule.pattern))
    }
    var found = 0
    for root in roots {
        let base = URL(fileURLWithPath: (root as NSString).expandingTildeInPath)
        guard
            let walk = FileManager.default.enumerator(
                at: base, includingPropertiesForKeys: [.isDirectoryKey])
        else { fail("no such directory: \(root)") }
        for case let file as URL in walk {
            if skipped.contains(file.lastPathComponent) {
                walk.skipDescendants()
                continue
            }
            guard file.pathExtension == "swift",
                let text = try? String(contentsOf: file, encoding: .utf8)
            else { continue }
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            for (number, line) in lines.enumerated() {
                let code = line.trimmingCharacters(in: .whitespaces)
                // The marker exempts its own line, and the line under it when
                // it stands as a comment above the call.
                let marked =
                    line.contains("lock-in: allowed")
                    || (number > 0 && lines[number - 1].contains("lock-in: allowed"))
                guard !code.hasPrefix("//"), !marked else { continue }
                let range = NSRange(line.startIndex..., in: line)
                for (rule, regex) in rules
                where regex.firstMatch(in: String(line), range: range) != nil {
                    found += 1
                    print("\(file.path):\(number + 1): \(rule.api): use \(rule.use)")
                }
            }
        }
    }
    if found > 0 {
        print(
            "grant lint: \(found) direct use(s); mark a deliberate one `lock-in: allowed — <why>`")
    }
    return found == 0
}

let args = Array(CommandLine.arguments.dropFirst())
switch args.first {
case "status" where args.count == 2:
    status(resolve(args[1]))
case "reset" where args.count >= 2:
    reset(resolve(args[1]), reopen: !args.contains("--no-reopen"))
case "lint" where args.count >= 2:
    exit(lint(Array(args.dropFirst())) ? 0 : 1)
default:
    print(
        """
        usage: grant status <app>                 what it last read for each permission, and its signer
               grant reset <app> [--no-reopen]    quit, clear its permission records, reopen
               grant lint <dir>...                direct uses of Apple's permission and job API
        <app>: a bundle id, a .app path, or an app's name
        """)
    exit(args.isEmpty || args.first == "help" ? 0 : 1)
}
