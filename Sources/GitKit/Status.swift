import Foundation

extension Git {
    /// `git status --porcelain=v2 --branch -z`: the branch and every path that differs
    /// between HEAD, the index and the working tree.
    public struct Status: Codable, Sendable, Hashable {
        public struct Branch: Codable, Sendable, Hashable {
            /// The commit HEAD names; nil before the first commit.
            public var oid: String?
            /// The branch checked out; nil when HEAD is detached.
            public var head: String?
            public var upstream: String?
            /// Commits on this branch not on its upstream, and the reverse; nil without an
            /// upstream (or one that is gone).
            public var ahead: Int?
            public var behind: Int?
            public var stash: Int?

            public init(
                oid: String? = nil, head: String? = nil, upstream: String? = nil, ahead: Int? = nil,
                behind: Int? = nil, stash: Int? = nil
            ) {
                self.oid = oid
                self.head = head
                self.upstream = upstream
                self.ahead = ahead
                self.behind = behind
                self.stash = stash
            }

            public var isDetached: Bool { head == nil && oid != nil }
        }

        /// One side's state letter (`.` unmodified, `M`, `T` type changed, `A`, `D`, `R`,
        /// `C`, `U` unmerged).
        public enum Code: String, Codable, Sendable, Hashable {
            case unmodified = "."
            case modified = "M"
            case typeChanged = "T"
            case added = "A"
            case deleted = "D"
            case renamed = "R"
            case copied = "C"
            case unmerged = "U"
        }

        /// A submodule's own state: its commit moved, it has tracked changes, it has
        /// untracked files.
        public struct SubmoduleState: Codable, Sendable, Hashable {
            public var commitChanged: Bool
            public var modified: Bool
            public var untracked: Bool
        }

        public struct Entry: Codable, Sendable, Hashable, Identifiable {
            public enum Kind: String, Codable, Sendable, Hashable {
                case ordinary, renamed, copied, unmerged, untracked, ignored
            }
            public var kind: Kind
            public var path: String
            /// Where a rename or copy came from.
            public var origPath: String?
            /// The index against HEAD (`X`), the working tree against the index (`Y`).
            public var index: Code
            public var worktree: Code
            public var score: Int?
            public var submodule: SubmoduleState?
            /// HEAD's, the index's and the working tree's modes.
            public var modes: [String]

            public var id: String { path }
            public var isConflicted: Bool { kind == .unmerged }
            public var isUntracked: Bool { kind == .untracked }
            /// Something is staged: the index differs from HEAD.
            public var isStaged: Bool {
                (kind == .ordinary || kind == .renamed || kind == .copied) && index != .unmodified
            }
            /// Something is not staged: the working tree differs from the index.
            public var isUnstaged: Bool {
                (kind == .ordinary || kind == .renamed || kind == .copied)
                    && worktree != .unmodified
            }
        }

        public var branch: Branch
        public var entries: [Entry]

        public init(branch: Branch, entries: [Entry]) {
            self.branch = branch
            self.entries = entries
        }

        public var staged: [Entry] { entries.filter(\.isStaged) }
        public var unstaged: [Entry] { entries.filter(\.isUnstaged) }
        public var untracked: [Entry] { entries.filter(\.isUntracked) }
        public var conflicted: [Entry] { entries.filter(\.isConflicted) }
        public var isClean: Bool { entries.allSatisfy { $0.kind == .ignored } }
    }
}

extension Git.Status {
    /// `git status --porcelain=v2 --branch -z [--show-stash]`. Every field is read; an
    /// entry with fewer fields than its kind writes throws, naming the record.
    public init(parsing data: Data) throws {
        var branch = Branch()
        var entries: [Entry] = []
        var records = Git.records(data)[...]
        var number = 0
        func fail(_ kind: String, _ text: String) -> Git.ParseError {
            .record(kind: "status \(kind)", line: number, text: text)
        }
        while let record = records.popFirst() {
            number += 1
            if record.isEmpty { continue }
            if let header = record.after("# ") {
                let parts = header.split(separator: " ", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { continue }
                switch parts[0] {
                case "branch.oid": branch.oid = parts[1] == "(initial)" ? nil : parts[1]
                case "branch.head": branch.head = parts[1] == "(detached)" ? nil : parts[1]
                case "branch.upstream": branch.upstream = parts[1]
                case "branch.ab":
                    let numbers = parts[1].split(separator: " ")
                    branch.ahead = numbers.first.flatMap { Int($0.dropFirst()) }
                    branch.behind = numbers.last.flatMap { Int($0.dropFirst()) }
                case "stash": branch.stash = Int(parts[1])
                default: break
                }
                continue
            }
            let tag = record.first
            switch tag {
            case "1", "2":
                // 1 XY sub mH mI mW hH hI path / 2 XY sub mH mI mW hH hI Xscore path\0orig
                let fields = record.split(
                    separator: " ", maxSplits: tag == "1" ? 8 : 9, omittingEmptySubsequences: false)
                guard fields.count == (tag == "1" ? 9 : 10) else { throw fail("entry", record) }
                var entry = try Self.entry(
                    kind: .ordinary, xy: fields[1], sub: fields[2], modes: fields[3...5],
                    record: record, number: number)
                if tag == "2" {
                    let score = fields[8]
                    entry.kind = score.first == "C" ? .copied : .renamed
                    entry.score = Int(score.dropFirst())
                    entry.path = String(fields[9])
                    guard let orig = records.popFirst() else { throw fail("rename", record) }
                    number += 1
                    entry.origPath = orig
                } else {
                    entry.path = String(fields[8])
                }
                entries.append(entry)
            case "u":
                // u XY sub m1 m2 m3 mW h1 h2 h3 path
                let fields = record.split(
                    separator: " ", maxSplits: 10, omittingEmptySubsequences: false)
                guard fields.count == 11 else { throw fail("unmerged", record) }
                var entry = try Self.entry(
                    kind: .unmerged, xy: fields[1], sub: fields[2], modes: fields[3...6],
                    record: record,
                    number: number)
                entry.path = String(fields[10])
                entries.append(entry)
            case "?", "!":
                guard record.count > 2 else { throw fail("untracked", record) }
                entries.append(
                    Entry(
                        kind: tag == "?" ? .untracked : .ignored, path: String(record.dropFirst(2)),
                        origPath: nil, index: .unmodified, worktree: .unmodified, score: nil,
                        submodule: nil, modes: []))
            default:
                throw fail("unknown", record)
            }
        }
        self.init(branch: branch, entries: entries)
    }

    private static func entry(
        kind: Entry.Kind, xy: Substring, sub: Substring, modes: ArraySlice<Substring>,
        record: String,
        number: Int
    ) throws -> Entry {
        let codes = Array(xy)
        guard codes.count == 2, let x = Code(rawValue: String(codes[0])),
            let y = Code(rawValue: String(codes[1]))
        else { throw Git.ParseError.record(kind: "status code", line: number, text: record) }
        var submodule: SubmoduleState?
        let flags = Array(sub)
        if flags.count == 4, flags[0] == "S" {
            submodule = SubmoduleState(
                commitChanged: flags[1] == "C", modified: flags[2] == "M",
                untracked: flags[3] == "U")
        }
        return Entry(
            kind: kind, path: "", origPath: nil, index: x, worktree: y, score: nil,
            submodule: submodule,
            modes: modes.map(String.init))
    }
}
