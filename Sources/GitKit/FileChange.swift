import Foundation

extension Git {
    /// A file in a list: what happened to it, whatever said so (a diff, a status entry).
    public struct FileChange: Codable, Sendable, Hashable, Identifiable {
        public enum Kind: String, Codable, Sendable, Hashable, CaseIterable {
            case added, modified, deleted, renamed, copied, typeChanged, untracked, conflicted

            /// The one letter lazygit and `git status -s` use.
            public var letter: String {
                switch self {
                case .added: "A"
                case .modified: "M"
                case .deleted: "D"
                case .renamed: "R"
                case .copied: "C"
                case .typeChanged: "T"
                case .untracked: "?"
                case .conflicted: "U"
                }
            }
        }

        /// Which part of a status a file is listed under.
        public enum Group: String, Codable, Sendable, Hashable, CaseIterable {
            case conflicted, staged, unstaged, untracked, changed
        }

        public var path: String
        public var oldPath: String?
        public var kind: Kind
        public var group: Group
        public var additions: Int?
        public var deletions: Int?
        public var similarity: Int?
        public var isSubmodule: Bool
        public var isBinary: Bool

        public init(
            path: String, oldPath: String? = nil, kind: Kind, group: Group = .changed, additions: Int? = nil,
            deletions: Int? = nil, similarity: Int? = nil, isSubmodule: Bool = false, isBinary: Bool = false
        ) {
            self.path = path
            self.oldPath = oldPath
            self.kind = kind
            self.group = group
            self.additions = additions
            self.deletions = deletions
            self.similarity = similarity
            self.isSubmodule = isSubmodule
            self.isBinary = isBinary
        }

        public var id: String { "\(group.rawValue):\(path)" }
        /// The file's name and the folder it is in (`""` at the root).
        public var name: String { path.split(separator: "/").last.map(String.init) ?? path }
        public var folder: String {
            guard let slash = path.lastIndex(of: "/") else { return "" }
            return String(path[..<slash])
        }

        public init(_ file: FileDiff) {
            let kind: Kind =
                switch file.change {
                case .added: .added
                case .deleted: .deleted
                case .renamed: .renamed
                case .copied: .copied
                case .modified: .modified
                }
            self.init(
                path: file.path, oldPath: file.change == .renamed || file.change == .copied ? file.oldPath : nil,
                kind: kind, additions: file.isBinary ? nil : file.additions,
                deletions: file.isBinary ? nil : file.deletions, similarity: file.similarity,
                isSubmodule: file.submodule != nil, isBinary: file.isBinary)
        }

        /// A status entry as listed in `group` (an entry both staged and changed again is
        /// listed in both, each with its own side's letter).
        public init(_ entry: Status.Entry, group: Group) {
            let code: Status.Code = group == .staged ? entry.index : entry.worktree
            let kind: Kind =
                switch entry.kind {
                case .unmerged: .conflicted
                case .untracked, .ignored: .untracked
                case .renamed, .copied, .ordinary:
                    switch code {
                    case .added: .added
                    case .deleted: .deleted
                    case .renamed: .renamed
                    case .copied: .copied
                    case .typeChanged: .typeChanged
                    case .unmerged: .conflicted
                    case .modified, .unmodified: .modified
                    }
                }
            self.init(
                path: entry.path, oldPath: group == .staged ? entry.origPath : nil, kind: kind, group: group,
                similarity: group == .staged ? entry.score : nil,
                isSubmodule: entry.submodule != nil || entry.modes.contains("160000"))
        }
    }
}

extension Git.Status {
    /// The status as lazygit lists it: conflicts first, then staged, then changed, then
    /// untracked; empty groups left out.
    public var groups: [(group: Git.FileChange.Group, files: [Git.FileChange])] {
        let all: [(Git.FileChange.Group, [Git.FileChange])] = [
            (.conflicted, conflicted.map { Git.FileChange($0, group: .conflicted) }),
            (.staged, staged.map { Git.FileChange($0, group: .staged) }),
            (.unstaged, unstaged.map { Git.FileChange($0, group: .unstaged) }),
            (.untracked, untracked.map { Git.FileChange($0, group: .untracked) }),
        ]
        return all.filter { !$0.1.isEmpty }.map { (group: $0.0, files: $0.1) }
    }
}
