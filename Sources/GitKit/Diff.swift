import Foundation

extension Git {
    /// A unified diff: one `FileDiff` per file, in git's order. Read from `git diff` /
    /// `git show` output (`init(parsing:)`), from a fragment someone wrote by hand
    /// (`FileDiff(snippet:)`), or computed from two texts (`FileDiff(old:new:)`).
    public struct Diff: Codable, Sendable, Hashable {
        public var files: [FileDiff]

        public init(files: [FileDiff]) { self.files = files }

        public var additions: Int { files.reduce(0) { $0 + $1.additions } }
        public var deletions: Int { files.reduce(0) { $0 + $1.deletions } }
        public var isEmpty: Bool { files.isEmpty }

        /// The files whose path (either side) is one of `paths` or lies under one of them
        /// (`Sources/` holds `Sources/a.swift`). Nil keeps everything.
        public func filtered(to paths: [String]?) -> Diff {
            guard let paths else { return self }
            return Diff(files: files.filter { $0.matches(paths) })
        }
    }

    /// One file's change.
    public struct FileDiff: Codable, Sendable, Hashable, Identifiable {
        public enum Change: String, Codable, Sendable, Hashable {
            case added, deleted, modified, renamed, copied
        }

        /// Where a submodule pointed before and after (`Subproject commit` lines). Nil on
        /// a side that did not exist; `dirty` when the checkout has changes of its own.
        public struct Pointer: Codable, Sendable, Hashable {
            public var old: String?
            public var new: String?
            public var dirty: Bool
            public init(old: String?, new: String?, dirty: Bool = false) {
                self.old = old
                self.new = new
                self.dirty = dirty
            }
        }

        /// Nil when the file is new.
        public var oldPath: String?
        /// Nil when the file was deleted.
        public var newPath: String?
        public var change: Change
        /// A rename's or copy's similarity, 0...100.
        public var similarity: Int?
        /// Modes as git writes them (`100644`, `100755`, `120000` a link, `160000` a
        /// submodule).
        public var oldMode: String?
        public var newMode: String?
        /// The blob ids of the `index` line, abbreviated as git printed them.
        public var oldBlob: String?
        public var newBlob: String?
        /// Git did not show the content: `Binary files … differ`.
        public var isBinary: Bool
        /// Set when the file is a submodule (mode 160000): its pointer change.
        public var submodule: Pointer?
        public var hunks: [Hunk]
        public private(set) var additions: Int
        public private(set) var deletions: Int

        public init(
            oldPath: String?, newPath: String?, change: Change, similarity: Int? = nil,
            oldMode: String? = nil, newMode: String? = nil, oldBlob: String? = nil,
            newBlob: String? = nil, isBinary: Bool = false, submodule: Pointer? = nil,
            hunks: [Hunk]
        ) {
            self.oldPath = oldPath
            self.newPath = newPath
            self.change = change
            self.similarity = similarity
            self.oldMode = oldMode
            self.newMode = newMode
            self.oldBlob = oldBlob
            self.newBlob = newBlob
            self.isBinary = isBinary
            self.submodule = submodule
            self.hunks = hunks
            var added = 0
            var removed = 0
            for hunk in hunks {
                for line in hunk.lines {
                    switch line.kind {
                    case .added: added += 1
                    case .removed: removed += 1
                    case .context: break
                    }
                }
            }
            additions = added
            deletions = removed
        }

        /// The path a person calls the file by: its new one, or the old one when deleted.
        public var path: String { newPath ?? oldPath ?? "" }
        public var id: String { "\(oldPath ?? "")\u{0}\(newPath ?? "")" }
        /// Only the mode changed, or the mode changed alongside the content.
        public var modeChanged: Bool {
            if let oldMode, let newMode { return oldMode != newMode }
            return false
        }
        public var lineCount: Int { hunks.reduce(0) { $0 + $1.lines.count } }

        func matches(_ paths: [String]) -> Bool {
            [oldPath, newPath].compactMap { $0 }.contains { path in
                paths.contains { path == $0 || path.hasPrefix($0.hasSuffix("/") ? $0 : $0 + "/") }
            }
        }
    }

    /// `@@ -oldStart,oldCount +newStart,newCount @@ section` and its lines.
    public struct Hunk: Codable, Sendable, Hashable {
        public var oldStart: Int
        public var oldCount: Int
        public var newStart: Int
        public var newCount: Int
        /// What git printed after the second `@@`: usually the enclosing function.
        public var section: String
        public var lines: [Line]

        public init(
            oldStart: Int, oldCount: Int, newStart: Int, newCount: Int, section: String = "",
            lines: [Line]
        ) {
            self.oldStart = oldStart
            self.oldCount = oldCount
            self.newStart = newStart
            self.newCount = newCount
            self.section = section
            self.lines = lines
        }

        /// The header as git wrote it.
        public var header: String {
            let old = oldCount == 1 ? "\(oldStart)" : "\(oldStart),\(oldCount)"
            let new = newCount == 1 ? "\(newStart)" : "\(newStart),\(newCount)"
            return "@@ -\(old) +\(new) @@" + (section.isEmpty ? "" : " \(section)")
        }
    }

    /// One line of a hunk, its text without the `+`/`-`/space git put before it.
    public struct Line: Codable, Sendable, Hashable {
        public enum Kind: String, Codable, Sendable, Hashable { case context, added, removed }
        public var kind: Kind
        /// The line's number on each side; nil on the side it is not on, or when the text
        /// it came from carried no numbers (a fragment without `@@ -a,b +c,d @@`).
        public var old: Int?
        public var new: Int?
        public var text: String
        /// Followed by `\ No newline at end of file`.
        public var noNewline: Bool

        public init(kind: Kind, old: Int?, new: Int?, text: String, noNewline: Bool = false) {
            self.kind = kind
            self.old = old
            self.new = new
            self.text = text
            self.noNewline = noNewline
        }

        /// The line as a unified diff writes it.
        public var unified: String {
            switch kind {
            case .context: " " + text
            case .added: "+" + text
            case .removed: "-" + text
            }
        }
    }
}
