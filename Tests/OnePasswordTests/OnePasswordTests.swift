import Foundation
import Testing

@testable import OnePassword

typealias CLI = OnePasswordCLI

private let home = FileManager.default.temporaryDirectory.appending(path: "onepassword-tests-home")
private let token = "ops_eyJzaWduSW5BZGRyZXNzIjoibXkuMXBhc3N3b3JkLmNvbSJ9secret"

/// An Apple tool run through the very spawn path `op` takes, under Apple's
/// requirement for that tool: the plumbing proven without a real `op`.
private func apple(
    _ path: String, _ id: String, _ arguments: [String] = [], environment: [String: String] = [:],
    token: String? = nil
) -> CLI.Launch {
    CLI.Launch(
        path: path, arguments: arguments, environment: environment,
        requirement: #"anchor apple and identifier "\#(id)""#, access: .serviceAccount, token: token
    )
}

private func run(_ launch: CLI.Launch, input: Data? = nil, timeout: Duration = .seconds(10))
    throws(CLI.Failure)
    -> Data
{
    let child = try launch.spawn(stdin: input == nil ? .null : .pipe, stdout: .pipe)
    return try child.finish(input: input, timeout: timeout, launch: launch)
}

// MARK: The environment: built whole, nothing inherited

@Test func serviceAccountEnvironmentIsExactly() {
    setenv("OP_SESSION_inherited", "leak", 1)
    setenv("HTTPS_PROXY", "http://leak", 1)
    let environment = CLI.Mode.serviceAccount(token: token, home: home).environment
    #expect(
        Set(environment.keys)
            == [
                "HOME", "XDG_CONFIG_HOME", "PATH", "USER", "LOGNAME", "TMPDIR", "LANG",
                "OP_SERVICE_ACCOUNT_TOKEN", "OP_CACHE",
            ])
    #expect(environment["OP_SERVICE_ACCOUNT_TOKEN"] == token)
    #expect(environment["OP_CACHE"] == "false")
    #expect(environment["HOME"] == home.path)
    #expect(environment["XDG_CONFIG_HOME"] == home.appending(path: ".config").path)
    #expect(environment["PATH"] == "/usr/bin:/bin:/usr/sbin:/sbin")
    #expect(environment["LANG"] == "en_US.UTF-8")
    #expect(environment["USER"] == NSUserName())
    #expect(environment["TMPDIR"]?.hasPrefix("/var/folders/") == true)
}

@Test func appEnvironmentIsExactly() {
    let environment = CLI.Mode.app(home: home).environment
    #expect(
        Set(environment.keys)
            == [
                "HOME", "XDG_CONFIG_HOME", "PATH", "USER", "LOGNAME", "TMPDIR", "LANG",
                "OP_BIOMETRIC_UNLOCK_ENABLED",
            ])
    #expect(environment["OP_BIOMETRIC_UNLOCK_ENABLED"] == "true")
}

/// What the child really receives, read back by /usr/bin/env.
@Test func childGetsOnlyThatEnvironment() throws {
    setenv("OP_SESSION_inherited", "leak", 1)
    let mode = CLI.Mode.app(home: home)
    let printed = try run(apple("/usr/bin/env", "com.apple.env", environment: mode.environment))
    let lines = Set(
        String(decoding: printed, as: UTF8.self).split(separator: "\n").map(String.init))
    #expect(lines == Set(mode.environment.map { "\($0.key)=\($0.value)" }))
}

@Test func modeNeverShowsItsToken() {
    let mode = CLI.Mode.serviceAccount(token: token, home: home)
    var dumped = ""
    dump(mode, to: &dumped)
    for shown in ["\(mode)", String(reflecting: mode), dumped] {
        #expect(!shown.contains(token))
        #expect(!shown.contains("ops_"))
    }
}

@Test func realHomeIsRefused() async {
    await #expect(processExitsWith: .failure) {
        _ = OnePasswordCLI.Mode.app(home: FileManager.default.homeDirectoryForCurrentUser)
    }
    await #expect(processExitsWith: .failure) {
        _ = OnePasswordCLI.Mode.serviceAccount(
            token: "", home: FileManager.default.temporaryDirectory)
    }
}

// MARK: The log's verb: never a ref, never a name

@Test func verbs() {
    #expect(CLI.verb(["read", "op://vault/item/password"]) == "read")
    #expect(CLI.verb(["item", "create", "-", "--format", "json"]) == "item create")
    #expect(CLI.verb(["item", "get", "Bank login", "--vault", "x"]) == "item get")
    #expect(
        CLI.verb(["service-account", "create", "authz-secrets-mbp"]) == "service-account create")
    #expect(CLI.verb(["--version"]) == "--version")
    #expect(CLI.verb([]) == "op")
}

// MARK: What op said, read into a case (op 2.39.0's own phrases)

@Test func readingStderr() {
    let cases: [(String, CLI.Failure)] = [
        (
            "No accounts configured for use with 1Password CLI.",
            .noAccount(.app, said: "No accounts configured for use with 1Password CLI.")
        ),
        (
            "You are not currently signed in. Please run `op signin --help` for instructions",
            .noAccount(
                .app,
                said:
                    "You are not currently signed in. Please run `op signin --help` for instructions"
            )
        ),
        (
            "authorization prompt dismissed, please try again",
            .refused(said: "authorization prompt dismissed, please try again")
        ),
        ("authorization timeout", .refused(said: "authorization timeout")),
        ("Too many requests", .rateLimited(said: "Too many requests")),
        (
            "Your client has been rate-limited",
            .rateLimited(said: "Your client has been rate-limited")
        ),
        (
            #""Bank" isn't an item in the "Private" vault. Specify the item with its UUID, name, or domain."#,
            .notFound(
                said:
                    #""Bank" isn't an item in the "Private" vault. Specify the item with its UUID, name, or domain."#
            )
        ),
        (
            #""abc" isn't a vault in this account."#,
            .notFound(said: #""abc" isn't a vault in this account."#)
        ),
        ("something else entirely", .failed(said: "something else entirely")),
    ]
    for (said, expected) in cases {
        #expect(CLI.Failure.reading(said, access: .app) == expected)
    }
    #expect(
        CLI.Failure.reading("bad service account token, please rotate it", access: .serviceAccount)
            == .noAccount(.serviceAccount, said: "bad service account token, please rotate it"))
    // A rate limit wins over anything else in the same words.
    #expect(
        CLI.Failure.reading("account is not signed in: Too many requests", access: .app)
            == .rateLimited(said: "account is not signed in: Too many requests"))
}

@Test func stderrCleanedAndRedacted() {
    let stderr = Data("[ERROR] 2026/10/26 12:00:00 bad service account token \(token)\n".utf8)
    #expect(
        CLI.Failure.cleaned(stderr, token: token, input: nil)
            == "bad service account token <redacted>")
    // Any service account token, not only this run's.
    #expect(
        CLI.Failure.redacted("token ops_AAAAAAAAAAAAAAAA was refused", token: nil, input: nil)
            == "token <redacted> was refused")
    // A passage quoted back from what was handed to op on its stdin.
    let input = Data(#"{"fields":[{"id":"password","value":"hunter2-correct-horse"}]}"#.utf8)
    #expect(
        CLI.Failure.redacted(
            #"invalid value "hunter2-correct-horse" for field "x""#, token: nil, input: input)
            == #"invalid value <redacted> for field "x""#)
    // Every failure's words go through it: none carries the token.
    for failure in [
        CLI.Failure.reading(
            CLI.Failure.cleaned(stderr, token: token, input: nil), access: .serviceAccount)
    ] {
        #expect(!failure.description.contains(token))
    }
}

@Test func everyFailureSaysWhatToDo() {
    let all: [CLI.Failure] = [
        .notInstalled(searched: ["/opt/homebrew/bin/op"]), .notAgileBits(path: "/x/op", why: "w"),
        .couldNotStart(path: "/x/op", why: "w"), .noAccount(.app, said: "s"),
        .noAccount(.serviceAccount, said: "s"),
        .refused(said: "s"), .rateLimited(said: "s"), .notFound(said: "s"),
        .timedOut(after: .seconds(90)),
        .failed(said: "s"),
    ]
    for failure in all { #expect(!failure.description.isEmpty) }
    #expect(CLI.Failure.timedOut(after: .seconds(90)).description.contains("1 min"))
}

// MARK: The signature, checked on the suspended process

/// Not AgileBits' (an Apple tool under op's requirement): killed before it
/// ran. `touch` would have made the file; it never exists.
@Test func nonAgileBitsIsKilledBeforeItRuns() throws {
    let file = FileManager.default.temporaryDirectory.appending(
        path: "onepassword-should-not-exist-\(UUID())")
    let launch = CLI.Launch(
        path: "/usr/bin/touch", arguments: [file.path], environment: [:], requirement: CLI.signedBy,
        access: .serviceAccount, token: nil)
    #expect {
        _ = try run(launch)
    } throws: { error in
        guard case CLI.Failure.notAgileBits(let path, let why) = error else { return false }
        return path == "/usr/bin/touch" && why.contains("does not satisfy AgileBits' requirement")
    }
    #expect(!FileManager.default.fileExists(atPath: file.path))
}

@Test func lsIsNotAgileBits() {
    #expect(throws: CLI.Failure.self) {
        _ = try run(
            CLI.Launch(
                path: "/bin/ls", arguments: [], environment: [:], requirement: CLI.signedBy,
                access: .app, token: nil))
    }
}

// MARK: Bounded: concurrent pipes, a timeout, an exit read

/// 16 MiB in and out at once: far past any pipe's buffer, so a runner that
/// wrote before reading (or read one pipe before the other) would stall.
@Test func largeInputAndOutputNeverStall() throws {
    let input = Data((0..<(16 << 20)).map { UInt8(truncatingIfNeeded: $0 &* 31) })
    let output = try run(apple("/bin/cat", "com.apple.cat"), input: input)
    #expect(output == input)
}

@Test func timeoutStopsIt() {
    let started = ContinuousClock.now
    #expect(throws: CLI.Failure.timedOut(after: .milliseconds(300))) {
        _ = try run(apple("/bin/sleep", "com.apple.sleep", ["30"]), timeout: .milliseconds(300))
    }
    #expect(started.duration(to: .now) < .seconds(5))
}

@Test func failureIsReadFromStderr() {
    let script = #"echo "[ERROR] 2026/10/26 12:00:00 Too many requests" >&2; exit 1"#
    #expect(throws: CLI.Failure.rateLimited(said: "Too many requests")) {
        _ = try run(apple("/bin/sh", "com.apple.sh", ["-c", script]))
    }
    #expect(throws: CLI.Failure.failed(said: "op exited 3")) {
        _ = try run(apple("/bin/sh", "com.apple.sh", ["-c", "exit 3"]))
    }
}

@Test func tokenNeverInAFailure() {
    let script = #"echo "bad service account token: $OP_SERVICE_ACCOUNT_TOKEN" >&2; exit 1"#
    #expect {
        _ = try run(
            apple(
                "/bin/sh", "com.apple.sh", ["-c", script],
                environment: ["OP_SERVICE_ACCOUNT_TOKEN": token],
                token: token))
    } throws: { error in
        "\(error)".contains("<redacted>") && !"\(error)".contains(token)
    }
}

/// The caller's descriptors: what goes in and comes out never passes here.
@Test func descriptorsStayTheCallers() throws {
    var input: [Int32] = [0, 0]
    var output: [Int32] = [0, 0]
    #expect(pipe(&input) == 0 && pipe(&output) == 0)
    let launch = apple("/bin/cat", "com.apple.cat")
    let child = try launch.spawn(stdin: .descriptor(input[0]), stdout: .descriptor(output[1]))
    close(input[0])
    close(output[1])
    #expect(write(input[1], "through", 7) == 7)
    close(input[1])
    let read = FileHandle(fileDescriptor: output[0], closeOnDealloc: true).readDataToEndOfFile()
    _ = try child.finish(input: nil, timeout: .seconds(10), launch: launch)
    #expect(String(decoding: read, as: UTF8.self) == "through")
}
