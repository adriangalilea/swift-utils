import Foundation

extension Git {
    /// WHAT a diff shows, as a value a view can name and a source can run: a base, what
    /// it is compared to, and optionally which paths. The headline case is an agent's
    /// work: `since(base, touched:)`, the base commit it started from compared with the
    /// working tree, kept to the paths it touched.
    public struct ChangeScope: Codable, Sendable, Hashable {
        public enum Target: Codable, Sendable, Hashable {
            /// The files on disk.
            case worktree
            /// What is staged.
            case index
            /// A commit.
            case commit(String)
        }

        /// What the target is compared with: a commit-ish (`HEAD`, a hash, `main~3`). Nil
        /// means git's own default: the index for the working tree, HEAD for the index, a
        /// commit's first parent for a commit.
        public var base: String?
        public var target: Target
        /// Only these paths (and what is under them); nil is every path.
        public var paths: [String]?
        /// Untracked files count as added (the working tree only): an agent's new file is
        /// part of its work before anyone stages it.
        public var untracked: Bool
        /// Unchanged lines kept around each change (`-U`).
        public var context: Int

        public init(
            base: String? = nil, target: Target, paths: [String]? = nil, untracked: Bool = false,
            context: Int = 3
        ) {
            self.base = base
            self.target = target
            self.paths = paths
            self.untracked = untracked
            self.context = context
        }

        /// Changes not staged: the working tree against the index (`git diff`).
        public static let unstaged = ChangeScope(target: .worktree)
        /// Staged changes: the index against HEAD (`git diff --cached`).
        public static let staged = ChangeScope(target: .index)
        /// Everything not committed, untracked files included (`git diff HEAD`).
        public static let uncommitted = ChangeScope(
            base: "HEAD", target: .worktree, untracked: true)

        /// An agent's work: everything from `base` to the working tree (commits it made,
        /// staged and unstaged edits, new files), kept to `touched` when given.
        public static func since(_ base: String, touched: [String]? = nil) -> ChangeScope {
            ChangeScope(base: base, target: .worktree, paths: touched, untracked: true)
        }

        /// One commit against its first parent (`git show`).
        public static func commit(_ hash: String) -> ChangeScope {
            ChangeScope(target: .commit(hash))
        }

        /// The same scope kept to `paths`.
        public func only(_ paths: [String]?) -> ChangeScope {
            var copy = self
            copy.paths = paths
            return copy
        }
    }
}

extension Git {
    /// The argv of every read, after `git` itself, decided once so the Mac's source, a
    /// capture and a remote host run exactly the same thing. Every one is read-only and
    /// prints machine output: no pager, no color, no optional locks (`git status` would
    /// otherwise refresh the index), no external diff or textconv, paths unquoted, the
    /// `a/` `b/` prefixes forced whatever the user's config says.
    public enum Command {
        static let global = [
            "--no-pager", "--no-optional-locks", "-c", "core.quotepath=off", "-c", "color.ui=never",
            "-c", "log.showSignature=false",
        ]

        static func diffFlags(context: Int) -> [String] {
            [
                "--no-color", "--no-ext-diff", "--no-textconv", "--patch", "--find-renames",
                "--src-prefix=a/", "--dst-prefix=b/", "--submodule=short", "-U\(max(0, context))",
            ]
        }

        public static func status() -> [String] {
            global + ["status", "--porcelain=v2", "--branch", "--show-stash", "-z"]
        }

        public static func log(_ revision: String? = nil, limit: Int) -> [String] {
            global + ["log", "--format=\(Commit.format)", "-n", "\(limit)"]
                + (revision.map { [$0] } ?? [])
                + ["--"]
        }

        public static func branches() -> [String] {
            global + ["for-each-ref", "--format=\(Branch.format)", "refs/heads", "refs/remotes"]
        }

        public static func worktrees() -> [String] {
            global + ["worktree", "list", "--porcelain"]
        }

        public static func submodules() -> [String] {
            global + ["submodule", "status"]
        }

        /// The diff of a scope (untracked files are `untracked(_:)` + `newFile(_:)`).
        public static func diff(_ scope: ChangeScope) -> [String] {
            let flags = diffFlags(context: scope.context)
            let paths = ["--"] + (scope.paths ?? [])
            switch scope.target {
            case .worktree:
                return global + ["diff"] + flags + (scope.base.map { [$0] } ?? []) + paths
            case .index:
                return global + ["diff", "--cached"] + flags + (scope.base.map { [$0] } ?? [])
                    + paths
            case .commit(let hash):
                if let base = scope.base {
                    return global + ["diff"] + flags + [base, hash] + paths
                }
                return global + ["show", "--format=", "--diff-merges=first-parent"] + flags + [hash]
                    + paths
            }
        }

        /// Untracked paths of a scope, NUL-separated.
        public static func untracked(_ scope: ChangeScope) -> [String] {
            global + ["ls-files", "--others", "--exclude-standard", "-z", "--"]
                + (scope.paths ?? [])
        }

        /// An untracked file as an added one. Exits 1 when it has content: that is the
        /// answer, not a failure.
        public static func newFile(_ path: String, context: Int = 3) -> [String] {
            global + ["diff", "--no-index"] + diffFlags(context: context) + [
                "--", "/dev/null", path,
            ]
        }
    }
}
