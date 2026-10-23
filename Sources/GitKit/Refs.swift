import Foundation

extension Git {
    /// A local or remote branch as `Branch.format` writes it (`git for-each-ref`).
    public struct Branch: Codable, Sendable, Hashable, Identifiable {
        /// The full ref (`refs/heads/main`, `refs/remotes/origin/main`).
        public var ref: String
        /// The commit it points at.
        public var commit: String
        public var upstream: String?
        public var ahead: Int?
        public var behind: Int?
        /// Its upstream was deleted on the remote.
        public var upstreamGone: Bool
        /// HEAD is this branch.
        public var isCurrent: Bool
        public var date: Date?
        public var subject: String
        /// The worktree that has it checked out, if any.
        public var worktree: String?

        public var id: String { ref }
        public var isRemote: Bool { ref.hasPrefix("refs/remotes/") }
        /// `main`, `origin/main`.
        public var name: String {
            for prefix in ["refs/heads/", "refs/remotes/"] where ref.hasPrefix(prefix) {
                return String(ref.dropFirst(prefix.count))
            }
            return ref
        }

        /// `git for-each-ref --format=<this> refs/heads refs/remotes`: fields
        /// NUL-separated, a record a line.
        public static let format =
            "%(refname)%00%(objectname)%00%(upstream:short)%00%(upstream:track,nobracket)%00%(HEAD)%00%(committerdate:iso-strict)%00%(worktreepath)%00%(contents:subject)"

        public static func parse(_ data: Data) throws -> [Branch] {
            try Git.lines(data).enumerated().compactMap { index, line in
                if line.isEmpty { return nil }
                let fields = line.split(separator: "\0", omittingEmptySubsequences: false)
                guard fields.count >= 8 else {
                    throw ParseError.record(kind: "branch", line: index + 1, text: String(line))
                }
                // `refs/remotes/origin/HEAD` is an alias of a branch, not a branch.
                if fields[0].hasSuffix("/HEAD"), fields[0].hasPrefix("refs/remotes/") { return nil }
                var ahead: Int?
                var behind: Int?
                for part in fields[3].components(separatedBy: ", ") {
                    if let n = part.after("ahead ") { ahead = Int(n) }
                    if let n = part.after("behind ") { behind = Int(n) }
                }
                if !fields[2].isEmpty, fields[3] != "gone" {
                    ahead = ahead ?? 0
                    behind = behind ?? 0
                }
                return Branch(
                    ref: String(fields[0]), commit: String(fields[1]),
                    upstream: fields[2].isEmpty ? nil : String(fields[2]), ahead: ahead,
                    behind: behind,
                    upstreamGone: fields[3] == "gone", isCurrent: fields[4] == "*",
                    date: Commit.date(fields[5]), subject: fields[7...].joined(separator: "\0"),
                    worktree: fields[6].isEmpty ? nil : String(fields[6]))
            }
        }
    }

    /// One entry of `git worktree list --porcelain`.
    public struct Worktree: Codable, Sendable, Hashable, Identifiable {
        public var path: String
        public var head: String?
        /// `refs/heads/…`; nil when detached or bare.
        public var branch: String?
        public var isBare: Bool
        public var isDetached: Bool
        /// The reason given, or empty, when locked / prunable.
        public var locked: String?
        public var prunable: String?
        /// The first entry: the repository's own working tree.
        public var isMain: Bool

        public var id: String { path }
        public var branchName: String? {
            branch.map { $0.after("refs/heads/").map(String.init) ?? $0 }
        }

        public static func parse(_ data: Data) -> [Worktree] {
            var out: [Worktree] = []
            var current: Worktree?
            func close() {
                if let done = current { out.append(done) }
                current = nil
            }
            for line in Git.lines(data) {
                if line.isEmpty {
                    close()
                    continue
                }
                let parts = line.split(separator: " ", maxSplits: 1)
                let key = parts[0]
                let value = parts.count > 1 ? String(parts[1]) : ""
                if key == "worktree" {
                    close()
                    current = Worktree(
                        path: value, head: nil, branch: nil, isBare: false, isDetached: false,
                        locked: nil,
                        prunable: nil, isMain: out.isEmpty)
                    continue
                }
                switch key {
                case "HEAD": current?.head = value
                case "branch": current?.branch = value
                case "bare": current?.isBare = true
                case "detached": current?.isDetached = true
                case "locked": current?.locked = value
                case "prunable": current?.prunable = value
                default: break
                }
            }
            close()
            return out
        }
    }

    /// A submodule: where it lives and the commit the superproject records for it.
    public struct Submodule: Codable, Sendable, Hashable, Identifiable {
        public enum State: String, Codable, Sendable, Hashable {
            /// Checked out at the recorded commit.
            case current
            /// Not initialized (`-`).
            case uninitialized
            /// Checked out at another commit than the recorded one (`+`).
            case moved
            /// Merge conflicts (`U`).
            case conflicted
        }
        public var path: String
        /// The checked-out commit (or the recorded one when not initialized).
        public var commit: String
        public var state: State
        /// `git describe` of the commit, as `submodule status` adds it in parentheses.
        public var describe: String?

        public var id: String { path }

        /// `git submodule status` (recursive or not).
        public static func parseStatus(_ data: Data) -> [Submodule] {
            Git.lines(data).compactMap { line in
                guard let flag = line.first, line.count > 41 else { return nil }
                let state: State =
                    switch flag {
                    case "-": .uninitialized
                    case "+": .moved
                    case "U": .conflicted
                    default: .current
                    }
                let rest = line.dropFirst()
                let commit = rest.prefix { $0 != " " }
                var path = rest.dropFirst(commit.count + 1)
                var describe: String?
                if path.hasSuffix(")"), let open = path.range(of: " (", options: .backwards) {
                    describe = String(path[open.upperBound...].dropLast())
                    path = path[..<open.lowerBound]
                }
                return Submodule(
                    path: String(path), commit: String(commit), state: state, describe: describe)
            }
        }

        /// The gitlinks of `git ls-files --stage` (mode 160000), for a tree where
        /// `submodule status` cannot run (no checkout, a bare capture).
        public static func parseStage(_ data: Data) -> [Submodule] {
            Git.lines(data).compactMap { line in
                guard line.hasPrefix("160000 "), let tab = line.firstIndex(of: "\t") else {
                    return nil
                }
                let fields = line[..<tab].split(separator: " ")
                guard fields.count == 3 else { return nil }
                return Submodule(
                    path: Git.unquote(line[line.index(after: tab)...]), commit: String(fields[1]),
                    state: .current, describe: nil)
            }
        }
    }
}
