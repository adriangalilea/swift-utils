import Foundation
import GitKit

#if os(macOS)
    extension Git {
        /// A repository on this Mac, read by /usr/bin/git: `Git.Command`'s fixed argv, run
        /// as a process with the repository as its working directory, never through a
        /// shell, so no path or ref can become a command. Every read is a read: no
        /// optional locks, nothing staged, nothing checked out.
        public struct LocalSource: Source {
            public let repository: URL
            /// How many commits a snapshot lists.
            public var logLimit: Int
            /// How many untracked files a scope turns into added ones, at most: a tree
            /// with a build folder nobody ignored would otherwise diff every file in it.
            public var untrackedLimit: Int

            public init(repository: URL, logLimit: Int = 200, untrackedLimit: Int = 200) {
                self.repository = repository
                self.logLimit = logLimit
                self.untrackedLimit = untrackedLimit
            }

            public var name: String { repository.lastPathComponent }

            /// git's output for `arguments` (after `git`). `allowing` lists exit codes that are
            /// answers rather than failures (`diff --no-index` exits 1 when files differ).
            public func run(_ arguments: [String], allowing: Set<Int32> = []) async throws -> Data {
                let repository = repository
                return try await Task.detached(priority: .userInitiated) {
                    try Self.run(arguments, in: repository, allowing: allowing)
                }.value
            }

            static func run(_ arguments: [String], in folder: URL, allowing: Set<Int32>) throws
                -> Data
            {
                let process = Process()
                process.executableURL = URL(filePath: "/usr/bin/git")
                process.arguments = arguments
                process.currentDirectoryURL = folder
                var environment = ProcessInfo.processInfo.environment
                // A prompt would hang a read forever, and a pager would wait for a terminal.
                environment["GIT_TERMINAL_PROMPT"] = "0"
                environment["GIT_PAGER"] = "cat"
                environment["GIT_OPTIONAL_LOCKS"] = "0"
                environment["LC_ALL"] = "C"
                process.environment = environment
                let output = Pipe()
                let errors = Pipe()
                process.standardOutput = output
                process.standardError = errors
                process.standardInput = FileHandle.nullDevice
                try process.run()
                // Read both pipes while git runs: a diff larger than the pipe's buffer
                // would otherwise block git and this wait forever.
                let errorData = Locked(Data())
                let read = DispatchSemaphore(value: 0)
                Thread {
                    errorData.set(errors.fileHandleForReading.readDataToEndOfFile())
                    read.signal()
                }.start()
                let data = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                read.wait()
                let status = process.terminationStatus
                guard status == 0 || allowing.contains(status) else {
                    throw SourceError.git(
                        arguments: arguments, status: status,
                        message: String(decoding: errorData.value, as: UTF8.self))
                }
                return data
            }

            public func snapshot() async throws -> Snapshot {
                async let status = run(Command.status())
                async let branches = run(Command.branches())
                async let worktrees = run(Command.worktrees())
                async let submodules = run(Command.submodules())
                async let log = log(nil, limit: logLimit)
                return Snapshot(
                    status: try Status(parsing: await status),
                    branches: try Branch.parse(await branches),
                    worktrees: Worktree.parse(try await worktrees),
                    submodules: Submodule.parseStatus(try await submodules),
                    commits: try await log)
            }

            /// HEAD has a commit: a repository just made has none, and git's log of it
            /// fails where its history is simply empty.
            func born() async throws -> Bool {
                try await !run(Command.head(), allowing: [1]).isEmpty
            }

            public func diff(_ scope: ChangeScope) async throws -> Diff {
                var diff = try Diff(parsing: await run(Command.diff(scope)))
                guard scope.untracked, scope.target == .worktree else { return diff }
                let listed = Git.records(try await run(Command.untracked(scope))).filter {
                    !$0.isEmpty
                }
                for path in listed.prefix(untrackedLimit) {
                    let added = try Diff(
                        parsing: await run(
                            Command.newFile(path, context: scope.context), allowing: [1]))
                    diff.files += added.files
                }
                return diff
            }

            public func log(_ revision: String?, limit: Int) async throws -> [Commit] {
                if revision == nil, try await !born() { return [] }
                return try Commit.parse(await run(Command.log(revision, limit: limit)))
            }

            public func contents(_ path: String, in target: ChangeScope.Target) async throws
                -> String
            {
                guard !path.hasPrefix("/"), !path.split(separator: "/").contains("..") else {
                    throw SourceError.git(
                        arguments: ["show", path], status: -1,
                        message: "not a path inside the repository")
                }
                guard let arguments = Command.contents(path, in: target) else {
                    return try String(
                        contentsOf: repository.appending(path: path), encoding: .utf8)
                }
                return String(decoding: try await run(arguments), as: UTF8.self)
            }

            public func submodule(_ path: String) -> (any Source)? {
                let folder = repository.appending(path: path)
                guard FileManager.default.fileExists(atPath: folder.appending(path: ".git").path)
                else { return nil }
                return LocalSource(
                    repository: folder, logLimit: logLimit, untrackedLimit: untrackedLimit)
            }
        }
    }

    /// A value one thread writes and another reads.
    final class Locked<Value: Sendable>: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: Value
        init(_ value: Value) { stored = value }
        func set(_ value: Value) { lock.withLock { stored = value } }
        var value: Value { lock.withLock { stored } }
    }
#endif
