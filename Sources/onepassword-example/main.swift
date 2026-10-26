import Foundation
import OnePassword

// OnePassword by hand. `swift run onepassword-example` runs `op --version`
// through the runner: found, proven AgileBits' on the suspended process,
// started with nothing inherited. `--interactive` runs `op account list`
// through the person's own 1Password app (it may ask for Touch ID), the
// mode a GUI app uses. Each run's log line goes to stderr (scope
// `onepassword`).

let interactive = CommandLine.arguments.dropFirst().contains("--interactive")
let home = FileManager.default.temporaryDirectory.appending(path: "onepassword-example-home")
let mode = OnePasswordCLI.Mode.app(home: home)

do {
    print("op: \(try OnePasswordCLI.locate())")
    let version = try await OnePasswordCLI.run(["--version"], as: mode, timeout: .seconds(10))
    print(
        "version: \(String(decoding: version, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))"
    )
    if interactive {
        print("asking 1Password for its accounts (it may ask you to approve)…")
        let accounts = try await OnePasswordCLI.run(
            ["account", "list", "--format", "json"], as: mode, timeout: .seconds(120))
        print(String(decoding: accounts, as: UTF8.self))
    }
} catch {
    FileHandle.standardError.write(Data("onepassword-example: \(error)\n".utf8))
    exit(1)
}
