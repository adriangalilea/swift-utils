import Foundation

extension Git {
    /// Everything a repository's front page shows, read at one moment.
    public struct Snapshot: Codable, Sendable, Hashable {
        public var status: Status
        public var branches: [Branch]
        public var worktrees: [Worktree]
        public var submodules: [Submodule]
        /// The newest commits on HEAD.
        public var commits: [Commit]

        public init(
            status: Status, branches: [Branch], worktrees: [Worktree], submodules: [Submodule],
            commits: [Commit]
        ) {
            self.status = status
            self.branches = branches
            self.worktrees = worktrees
            self.submodules = submodules
            self.commits = commits
        }
    }

    /// Where a repository's values come from. A host plugs in its transport: the Mac's
    /// own git (`GitLocal`'s `LocalSource`), a capture (`FixtureSource`), a phone asking a
    /// Mac over the network. Every method only reads.
    public protocol Source: Sendable {
        /// What a person calls the repository (its folder's name).
        var name: String { get }
        func snapshot() async throws -> Snapshot
        func diff(_ scope: ChangeScope) async throws -> Diff
        /// Commits reachable from `revision` (HEAD when nil; a range like `a..b` works),
        /// newest first.
        func log(_ revision: String?, limit: Int) async throws -> [Commit]
        /// The repository checked out at a submodule's path, to drill into.
        func submodule(_ path: String) -> (any Source)?
        /// A file's text as `target` has it (the side a diff of that target shows as
        /// new): the lines a diff folded away between its hunks come from here.
        func contents(_ path: String, in target: ChangeScope.Target) async throws -> String
    }

    /// A read a source could not answer.
    public enum SourceError: Error, Hashable, Sendable, CustomStringConvertible {
        /// git exited with an error; its own words.
        case git(arguments: [String], status: Int32, message: String)
        /// A capture holds no answer for this question.
        case notCaptured(String)

        public var description: String {
            switch self {
            case .git(let arguments, let status, let message):
                let command = arguments.drop { $0.hasPrefix("-") || $0.contains("=") }.prefix(2)
                    .joined(separator: " ")
                return
                    "git \(command) failed (\(status)): \(message.trimmingCharacters(in: .whitespacesAndNewlines))"
            case .notCaptured(let what): return "Not in this capture: \(what)"
            }
        }
    }
}

extension Git.Source {
    /// One commit against its first parent.
    public func show(_ hash: String) async throws -> Git.Diff {
        try await diff(.commit(hash))
    }
}

extension Git {
    /// A repository read back from a folder `gitkit-capture` wrote: git's own bytes,
    /// each file named for the read that made it (`manifest.json` says which). For a
    /// phone without the repository, previews and tests. A scope asked for with a path
    /// filter is answered from its unfiltered capture.
    public struct FixtureSource: Source {
        public struct Manifest: Codable, Sendable, Hashable {
            public struct Captured<Key: Codable & Sendable & Hashable>: Codable, Sendable, Hashable
            {
                public var key: Key
                public var file: String
                public init(key: Key, file: String) {
                    self.key = key
                    self.file = file
                }
            }
            public struct LogKey: Codable, Sendable, Hashable {
                public var revision: String?
                public var limit: Int
                public init(revision: String?, limit: Int) {
                    self.revision = revision
                    self.limit = limit
                }
            }
            /// An agent's session as the capture recorded it: where it started and what it
            /// touched.
            public struct Agent: Codable, Sendable, Hashable {
                public var base: String
                public var touched: [String]
                public init(base: String, touched: [String]) {
                    self.base = base
                    self.touched = touched
                }
                public var scope: ChangeScope { .since(base, touched: touched) }
            }

            public var name: String
            public var status = "status.z"
            public var branches = "branches.txt"
            public var worktrees = "worktrees.txt"
            public var submodules = "submodules.txt"
            public var log = "log.txt"
            public var diffs: [Captured<ChangeScope>] = []
            public var logs: [Captured<LogKey>] = []
            /// Submodule path → its own capture folder, relative to this one.
            public var nested: [String: String] = [:]
            public var agent: Agent?

            public init(name: String) { self.name = name }
        }

        public let folder: URL
        public let manifest: Manifest

        public init(folder: URL) throws {
            self.folder = folder
            manifest = try JSONDecoder().decode(
                Manifest.self, from: Data(contentsOf: folder.appending(path: "manifest.json")))
        }

        public var name: String { manifest.name }

        private func read(_ file: String) throws -> Data {
            try Data(contentsOf: folder.appending(path: file))
        }

        public func snapshot() async throws -> Snapshot {
            Snapshot(
                status: try Status(parsing: read(manifest.status)),
                branches: try Branch.parse(read(manifest.branches)),
                worktrees: Worktree.parse(try read(manifest.worktrees)),
                submodules: Submodule.parseStatus(try read(manifest.submodules)),
                commits: try Commit.parse(read(manifest.log)))
        }

        public func diff(_ scope: ChangeScope) async throws -> Diff {
            if let hit = manifest.diffs.first(where: { $0.key == scope }) {
                return try Diff(parsing: read(hit.file))
            }
            if let whole = manifest.diffs.first(where: { $0.key == scope.only(nil) }) {
                return try Diff(parsing: read(whole.file)).filtered(to: scope.paths)
            }
            throw SourceError.notCaptured("the diff of \(scope)")
        }

        public func log(_ revision: String?, limit: Int) async throws -> [Commit] {
            if revision == nil {
                return Array(try Commit.parse(read(manifest.log)).prefix(limit))
            }
            guard let hit = manifest.logs.first(where: { $0.key.revision == revision }) else {
                throw SourceError.notCaptured("the log of \(revision ?? "HEAD")")
            }
            return Array(try Commit.parse(read(hit.file)).prefix(limit))
        }

        public func submodule(_ path: String) -> (any Source)? {
            guard let relative = manifest.nested[path] else { return nil }
            return try? FixtureSource(folder: folder.appending(path: relative))
        }

        /// A capture keeps diffs, not files.
        public func contents(_ path: String, in target: ChangeScope.Target) async throws -> String {
            throw SourceError.notCaptured("the text of \(path)")
        }
    }
}
