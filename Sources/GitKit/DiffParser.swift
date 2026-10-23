import Foundation

extension Git.Diff {
    /// `git diff` / `git show` output (`-p`, any `-M`/`-C`, `--submodule=short`, the
    /// default): every file, renames and copies with their similarity, mode changes, new
    /// and deleted files, binary files, `\ No newline at end of file`, submodule pointer
    /// changes. A combined diff (`diff --cc`, a merge against all its parents) throws
    /// `Git.ParseError.combinedDiff`: it has one column per parent, and a column per
    /// parent is not a unified diff. Anything before the first file header (a commit
    /// message from `git show`) is skipped.
    public init(parsing data: Data) throws {
        try self.init(lines: Git.lines(data))
    }

    public init(parsing text: String) throws {
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        if lines.last?.isEmpty == true { lines.removeLast() }
        try self.init(lines: lines)
    }

    init(lines: [Substring]) throws {
        var parser = DiffParser()
        for (index, line) in lines.enumerated() {
            try parser.feed(line, number: index + 1)
        }
        self.init(files: parser.finish())
    }
}

extension Git.FileDiff {
    /// A diff someone wrote rather than git: an agent's answer, a review comment, a
    /// patch pasted in a chat. Lenient by design: `@@` headers are optional (lines are
    /// then unnumbered) and their counts are not trusted, `diff`/`index`/`---`/`+++`
    /// header lines are skipped (a `+++ b/path` names the file when `path` is nil), a
    /// line with no `+`, `-` or space before it is context. Never throws.
    public init(snippet text: String, path: String? = nil) {
        var source = text.split(separator: "\n", omittingEmptySubsequences: false)
        if source.last?.isEmpty == true { source.removeLast() }
        var named = path
        var change = Change.modified
        var hunks: [Git.Hunk] = []
        var body: [Git.Line] = []
        var header: (oldStart: Int, newStart: Int, section: String)?
        var old: Int?
        var new: Int?
        var inBody = false
        func close() {
            guard !body.isEmpty || header != nil else { return }
            hunks.append(
                Git.Hunk(
                    oldStart: header?.oldStart ?? 0,
                    oldCount: body.filter { $0.kind != .added }.count,
                    newStart: header?.newStart ?? 0,
                    newCount: body.filter { $0.kind != .removed }.count,
                    section: header?.section ?? "", lines: body))
            body = []
            header = nil
        }
        for line in source {
            if line.hasPrefix("diff --git ") {
                close()
                inBody = false
                continue
            }
            if !inBody {
                if line.hasPrefix("--- ") {
                    if DiffParser.path(line.dropFirst(4), side: "a/") == nil { change = .added }
                    continue
                }
                if line.hasPrefix("+++ ") {
                    let target = DiffParser.path(line.dropFirst(4), side: "b/")
                    if target == nil { change = .deleted }
                    if named == nil { named = target }
                    continue
                }
                if ["index ", "similarity ", "rename ", "new file mode", "deleted file mode",
                    "old mode", "new mode"].contains(where: { line.hasPrefix($0) })
                {
                    continue
                }
            }
            if line.hasPrefix("@@") {
                close()
                inBody = true
                if let parsed = DiffParser.hunkHeader(line) {
                    header = (parsed.oldStart, parsed.newStart, parsed.section)
                    old = parsed.oldStart
                    new = parsed.newStart
                } else {
                    // An `@@` an author wrote without numbers: its words are the section.
                    let words = line.trimmingCharacters(in: CharacterSet(charactersIn: "@ "))
                    header = (0, 0, words)
                    old = nil
                    new = nil
                }
                continue
            }
            inBody = true
            if line.hasPrefix("\\") {
                if !body.isEmpty { body[body.count - 1].noNewline = true }
                continue
            }
            let kind: Git.Line.Kind
            let text: Substring
            switch line.first {
            case "+": (kind, text) = (.added, line.dropFirst())
            case "-": (kind, text) = (.removed, line.dropFirst())
            case " ": (kind, text) = (.context, line.dropFirst())
            default: (kind, text) = (.context, line)
            }
            body.append(
                Git.Line(
                    kind: kind, old: kind == .added ? nil : old, new: kind == .removed ? nil : new,
                    text: String(text)))
            if kind != .added { old = old.map { $0 + 1 } }
            if kind != .removed { new = new.map { $0 + 1 } }
        }
        close()
        self.init(
            oldPath: change == .added ? nil : named ?? "",
            newPath: change == .deleted ? nil : named ?? "", change: change, hunks: hunks)
    }
}

/// The state machine behind `Git.Diff(parsing:)`: one line at a time, a file open from
/// its `diff --git` header, a hunk open while its counts say lines remain.
struct DiffParser {
    struct File {
        var headerOld: String?
        var headerNew: String?
        var oldPath: String?
        var newPath: String?
        var minusSeen = false
        var plusSeen = false
        var added = false
        var deleted = false
        var renamed = false
        var copied = false
        var similarity: Int?
        var oldMode: String?
        var newMode: String?
        var oldBlob: String?
        var newBlob: String?
        var binary = false
        var hunks: [Git.Hunk] = []
    }

    struct OpenHunk {
        var hunk: Git.Hunk
        var oldLeft: Int
        var newLeft: Int
        var old: Int
        var new: Int
    }

    private var files: [Git.FileDiff] = []
    private var file: File?
    private var hunk: OpenHunk?

    mutating func feed(_ line: Substring, number: Int) throws {
        if var open = hunk {
            if line.hasPrefix("\\") {
                if !open.hunk.lines.isEmpty {
                    open.hunk.lines[open.hunk.lines.count - 1].noNewline = true
                }
                hunk = open
                return
            }
            if open.oldLeft > 0 || open.newLeft > 0 {
                let first = line.first
                if first == " " || (line.isEmpty && open.oldLeft > 0 && open.newLeft > 0) {
                    open.hunk.lines.append(
                        Git.Line(kind: .context, old: open.old, new: open.new, text: String(line.dropFirst())))
                    open.old += 1
                    open.new += 1
                    open.oldLeft -= 1
                    open.newLeft -= 1
                    hunk = open
                    return
                }
                if first == "-", open.oldLeft > 0 {
                    open.hunk.lines.append(
                        Git.Line(kind: .removed, old: open.old, new: nil, text: String(line.dropFirst())))
                    open.old += 1
                    open.oldLeft -= 1
                    hunk = open
                    return
                }
                if first == "+", open.newLeft > 0 {
                    open.hunk.lines.append(
                        Git.Line(kind: .added, old: nil, new: open.new, text: String(line.dropFirst())))
                    open.new += 1
                    open.newLeft -= 1
                    hunk = open
                    return
                }
            }
            closeHunk()
        }

        if line.hasPrefix("diff --git ") {
            closeFile()
            var opened = File()
            (opened.headerOld, opened.headerNew) = Self.headerPaths(line.dropFirst("diff --git ".count))
            file = opened
            return
        }
        if line.hasPrefix("diff --cc ") || line.hasPrefix("diff --combined ") {
            throw Git.ParseError.combinedDiff(line: number)
        }
        if line.hasPrefix("@@ ") || line == "@@" {
            guard let parsed = Self.hunkHeader(line) else {
                throw Git.ParseError.hunkHeader(line: number, text: String(line))
            }
            if file == nil { file = File() }
            hunk = OpenHunk(
                hunk: Git.Hunk(
                    oldStart: parsed.oldStart, oldCount: parsed.oldCount, newStart: parsed.newStart,
                    newCount: parsed.newCount, section: parsed.section, lines: []),
                oldLeft: parsed.oldCount, newLeft: parsed.newCount,
                old: parsed.oldStart, new: parsed.newStart)
            return
        }
        // `--- ` opens a file of its own in a diff without git's header (`diff -u`).
        if line.hasPrefix("--- "), file == nil || file?.hunks.isEmpty == false {
            closeFile()
            file = File()
        }
        guard var current = file else { return }
        defer { file = current }

        if line.hasPrefix("--- ") {
            current.minusSeen = true
            current.oldPath = Self.path(line.dropFirst(4), side: "a/")
            if current.oldPath == nil { current.added = true }
        } else if line.hasPrefix("+++ ") {
            current.plusSeen = true
            current.newPath = Self.path(line.dropFirst(4), side: "b/")
            if current.newPath == nil { current.deleted = true }
        } else if let mode = line.after("new file mode ") {
            current.added = true
            current.newMode = String(mode)
        } else if let mode = line.after("deleted file mode ") {
            current.deleted = true
            current.oldMode = String(mode)
        } else if let mode = line.after("old mode ") {
            current.oldMode = String(mode)
        } else if let mode = line.after("new mode ") {
            current.newMode = String(mode)
        } else if let path = line.after("rename from ") {
            current.renamed = true
            current.oldPath = Git.unquote(path)
        } else if let path = line.after("rename to ") {
            current.renamed = true
            current.newPath = Git.unquote(path)
        } else if let path = line.after("copy from ") {
            current.copied = true
            current.oldPath = Git.unquote(path)
        } else if let path = line.after("copy to ") {
            current.copied = true
            current.newPath = Git.unquote(path)
        } else if let value = line.after("similarity index ") {
            current.similarity = Int(value.dropLast())
        } else if let value = line.after("index ") {
            // `index abc..def 100644`, or without the mode when it changed.
            let parts = value.split(separator: " ")
            let blobs = parts.first?.split(separator: ".", omittingEmptySubsequences: true) ?? []
            if blobs.count == 2 {
                current.oldBlob = String(blobs[0])
                current.newBlob = String(blobs[1])
            }
            if parts.count > 1 {
                let mode = String(parts[1])
                if current.oldMode == nil { current.oldMode = mode }
                if current.newMode == nil { current.newMode = mode }
            }
        } else if line.hasPrefix("Binary files ") || line == "GIT binary patch" {
            current.binary = true
        }
    }

    mutating func finish() -> [Git.FileDiff] {
        closeHunk()
        closeFile()
        return files
    }

    private mutating func closeHunk() {
        guard let open = hunk else { return }
        file?.hunks.append(open.hunk)
        hunk = nil
    }

    private mutating func closeFile() {
        closeHunk()
        guard let current = file else { return }
        file = nil
        let change: Git.FileDiff.Change =
            current.added
            ? .added
            : current.deleted
                ? .deleted : current.renamed ? .renamed : current.copied ? .copied : .modified
        var oldPath = current.minusSeen || current.renamed || current.copied ? current.oldPath : current.headerOld
        var newPath = current.plusSeen || current.renamed || current.copied ? current.newPath : current.headerNew
        if change == .added { oldPath = nil }
        if change == .deleted { newPath = nil }
        if change == .added, newPath == nil { newPath = current.headerNew }
        if change == .deleted, oldPath == nil { oldPath = current.headerOld }
        let isSubmodule = current.oldMode == "160000" || current.newMode == "160000"
        var pointer: Git.FileDiff.Pointer?
        if isSubmodule {
            var found = Git.FileDiff.Pointer(old: nil, new: nil)
            for line in current.hunks.flatMap(\.lines) {
                guard let commit = line.text.after("Subproject commit ") else { continue }
                var hash = String(commit)
                if hash.hasSuffix("-dirty") {
                    hash.removeLast("-dirty".count)
                    found.dirty = true
                }
                switch line.kind {
                case .removed: found.old = hash
                case .added: found.new = hash
                case .context: (found.old, found.new) = (hash, hash)
                }
            }
            pointer = found
        }
        files.append(
            Git.FileDiff(
                oldPath: oldPath, newPath: newPath, change: change, similarity: current.similarity,
                oldMode: current.oldMode, newMode: current.newMode, oldBlob: current.oldBlob,
                newBlob: current.newBlob, isBinary: current.binary, submodule: pointer,
                hunks: current.hunks))
    }

    /// A `---`/`+++` path: nil for `/dev/null`, else unquoted, the trailing tab git adds
    /// after a path with a space dropped (and a timestamp `diff -u` writes after it), the
    /// `a/` or `b/` prefix removed.
    static func path(_ text: Substring, side: String) -> String? {
        var raw = text
        if raw.first != "\"", let tab = raw.firstIndex(of: "\t") { raw = raw[..<tab] }
        if raw == "/dev/null" { return nil }
        let path = Git.unquote(raw)
        return path.hasPrefix(side) ? String(path.dropFirst(side.count)) : path
    }

    /// `diff --git a/X b/Y`'s two paths. Unambiguous when quoted or when both sides
    /// are the same path (the usual case, spaces and all); otherwise split at ` b/`.
    static func headerPaths(_ rest: Substring) -> (String?, String?) {
        func strip(_ path: String, _ side: String) -> String {
            path.hasPrefix(side) ? String(path.dropFirst(side.count)) : path
        }
        if rest.first == "\"", let close = rest.dropFirst().firstIndex(of: "\"") {
            let left = rest[...close]
            let right = rest[rest.index(after: close)...].drop { $0 == " " }
            return (strip(Git.unquote(left), "a/"), strip(Git.unquote(right), "b/"))
        }
        let count = rest.count
        if count % 2 == 1 {
            let half = count / 2
            let left = rest.prefix(half)
            let right = rest.suffix(half)
            if left.dropFirst(2) == right.dropFirst(2), left.hasPrefix("a/"), right.hasPrefix("b/") {
                return (String(left.dropFirst(2)), String(right.dropFirst(2)))
            }
        }
        if let split = rest.range(of: " \"b/") ?? rest.range(of: " b/") {
            return (
                strip(Git.unquote(rest[..<split.lowerBound]), "a/"),
                strip(Git.unquote(rest[rest.index(after: split.lowerBound)...]), "b/")
            )
        }
        return (nil, nil)
    }

    struct Header {
        var oldStart: Int
        var oldCount: Int
        var newStart: Int
        var newCount: Int
        var section: String
    }

    /// `@@ -a[,b] +c[,d] @@[ section]`; a count left out is 1.
    static func hunkHeader(_ line: Substring) -> Header? {
        guard line.hasPrefix("@@ -") else { return nil }
        var rest = line.dropFirst(4)
        func range(_ text: inout Substring) -> (Int, Int)? {
            let digits = text.prefix { $0.isNumber || $0 == "," }
            text = text.dropFirst(digits.count)
            let parts = digits.split(separator: ",", omittingEmptySubsequences: false)
            guard let start = parts.first.flatMap({ Int($0) }) else { return nil }
            if parts.count == 1 { return (start, 1) }
            guard parts.count == 2, let count = Int(parts[1]) else { return nil }
            return (start, count)
        }
        guard let old = range(&rest), rest.hasPrefix(" +") else { return nil }
        rest = rest.dropFirst(2)
        guard let new = range(&rest), rest.hasPrefix(" @@") else { return nil }
        rest = rest.dropFirst(3)
        let section = rest.first == " " ? rest.dropFirst() : rest
        return Header(
            oldStart: old.0, oldCount: old.1, newStart: new.0, newCount: new.1,
            section: String(section))
    }
}

extension StringProtocol {
    /// The rest after `prefix`, when it starts with it.
    func after(_ prefix: String) -> SubSequence? {
        hasPrefix(prefix) ? self[index(startIndex, offsetBy: prefix.count)...] : nil
    }
}
