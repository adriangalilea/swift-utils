import Foundation

extension Git.FileDiff {
    /// The diff of two texts, computed here (Myers' O(ND) over lines, git's default
    /// algorithm): what an editor's old and new strings became, with `context` unchanged
    /// lines around each change as `git diff -U<context>` keeps them. Line numbers count
    /// from `startLine` on both sides, for a fragment that sits further down its file. A
    /// last line without a newline is marked as git marks it.
    public init(old: String, new: String, path: String? = nil, context: Int = 3, startLine: Int = 1)
    {
        let a = Self.split(old)
        let b = Self.split(new)
        let ops = LineDiff.ops(a.map(\.key), b.map(\.key))
        let hunks = LineDiff.hunks(ops, a, b, context: max(0, context), startLine: startLine)
        let change: Change =
            old.isEmpty && !new.isEmpty
            ? .added : !old.isEmpty && new.isEmpty ? .deleted : .modified
        self.init(
            oldPath: change == .added ? nil : path ?? "",
            newPath: change == .deleted ? nil : path ?? "",
            change: change, hunks: hunks)
    }

    struct Source {
        var text: Substring
        var noNewline: Bool
        var key: Int { noNewline ? (text.hashValue &+ 1) : text.hashValue }
    }

    static func split(_ text: String) -> [Source] {
        guard !text.isEmpty else { return [] }
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let terminated = lines.last?.isEmpty == true
        if terminated { lines.removeLast() }
        return lines.enumerated().map { index, line in
            Source(text: line, noNewline: !terminated && index == lines.count - 1)
        }
    }
}

/// Myers' diff over integer keys and the hunks it makes.
enum LineDiff {
    enum Op: Equatable { case equal(Int, Int), delete(Int), insert(Int) }

    /// Past this many edits the middle is given up as replaced: the greedy pass keeps a
    /// slice per edit, and two unrelated texts are better read as one block out and one
    /// in than as a scatter of coincidences.
    static let editLimit = 4000

    static func ops(_ a: [Int], _ b: [Int]) -> [Op] {
        var prefix = 0
        while prefix < a.count, prefix < b.count, a[prefix] == b[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < a.count - prefix, suffix < b.count - prefix,
            a[a.count - 1 - suffix] == b[b.count - 1 - suffix]
        {
            suffix += 1
        }
        var out: [Op] = (0..<prefix).map { .equal($0, $0) }
        let midA = Array(a[prefix..<(a.count - suffix)])
        let midB = Array(b[prefix..<(b.count - suffix)])
        let middle =
            myers(midA, midB)
            ?? (midA.indices.map { Op.delete($0) } + midB.indices.map { Op.insert($0) })
        for op in middle {
            switch op {
            case .equal(let x, let y): out.append(.equal(x + prefix, y + prefix))
            case .delete(let x): out.append(.delete(x + prefix))
            case .insert(let y): out.append(.insert(y + prefix))
            }
        }
        for offset in 0..<suffix {
            out.append(.equal(a.count - suffix + offset, b.count - suffix + offset))
        }
        return out
    }

    /// The shortest edit script, or nil past `editLimit` edits.
    static func myers(_ a: [Int], _ b: [Int]) -> [Op]? {
        let n = a.count
        let m = b.count
        if n == 0 { return b.indices.map { .insert($0) } }
        if m == 0 { return a.indices.map { .delete($0) } }
        let most = min(n + m, editLimit)
        let offset = most + 1
        var v = [Int](repeating: 0, count: 2 * most + 3)
        var trace: [[Int]] = []
        var found: Int?
        search: for d in 0...most {
            trace.append(Array(v[(offset - d - 1)...(offset + d + 1)]))
            for k in stride(from: -d, through: d, by: 2) {
                var x =
                    (k == -d || (k != d && v[offset + k - 1] < v[offset + k + 1]))
                    ? v[offset + k + 1] : v[offset + k - 1] + 1
                var y = x - k
                while x < n, y < m, a[x] == b[y] {
                    x += 1
                    y += 1
                }
                v[offset + k] = x
                if x >= n, y >= m {
                    found = d
                    break search
                }
            }
        }
        guard let edits = found else { return nil }
        var ops: [Op] = []
        var x = n
        var y = m
        for d in stride(from: edits, through: 0, by: -1) {
            let slice = trace[d]
            func at(_ k: Int) -> Int { slice[k + d + 1] }
            let k = x - y
            let previousK = (k == -d || (k != d && at(k - 1) < at(k + 1))) ? k + 1 : k - 1
            let previousX = d == 0 ? 0 : at(previousK)
            let previousY = d == 0 ? 0 : previousX - previousK
            while x > previousX, y > previousY {
                ops.append(.equal(x - 1, y - 1))
                x -= 1
                y -= 1
            }
            if d > 0 {
                ops.append(x == previousX ? .insert(y - 1) : .delete(x - 1))
            }
            x = previousX
            y = previousY
        }
        return ops.reversed()
    }

    static func hunks(
        _ ops: [Op], _ a: [Git.FileDiff.Source], _ b: [Git.FileDiff.Source], context: Int,
        startLine: Int
    ) -> [Git.Hunk] {
        let changed = ops.indices.filter {
            if case .equal = ops[$0] { return false }
            return true
        }
        guard !changed.isEmpty else { return [] }
        // Changes closer than two contexts apart share a hunk, as git joins them.
        var groups: [(Int, Int)] = []
        for index in changed {
            if let last = groups.last, index - last.1 <= 2 * context + 1 {
                groups[groups.count - 1].1 = index
            } else {
                groups.append((index, index))
            }
        }
        // Where each op stands on each side, counting from the text's first line.
        var oldAt = [Int](repeating: 0, count: ops.count + 1)
        var newAt = [Int](repeating: 0, count: ops.count + 1)
        for (index, op) in ops.enumerated() {
            oldAt[index + 1] = oldAt[index] + (isInsert(op) ? 0 : 1)
            newAt[index + 1] = newAt[index] + (isDelete(op) ? 0 : 1)
        }
        return groups.map { first, last in
            let from = max(0, first - context)
            let to = min(ops.count - 1, last + context)
            var lines: [Git.Line] = []
            for index in from...to {
                let old = startLine + oldAt[index]
                let new = startLine + newAt[index]
                switch ops[index] {
                case .equal(let x, _):
                    lines.append(
                        Git.Line(
                            kind: .context, old: old, new: new, text: String(a[x].text),
                            noNewline: a[x].noNewline))
                case .delete(let x):
                    lines.append(
                        Git.Line(
                            kind: .removed, old: old, new: nil, text: String(a[x].text),
                            noNewline: a[x].noNewline))
                case .insert(let y):
                    lines.append(
                        Git.Line(
                            kind: .added, old: nil, new: new, text: String(b[y].text),
                            noNewline: b[y].noNewline))
                }
            }
            let oldCount = lines.filter { $0.kind != .added }.count
            let newCount = lines.filter { $0.kind != .removed }.count
            // git numbers an empty side by the line before it.
            let oldStart = startLine + oldAt[from] - (oldCount == 0 ? 1 : 0)
            let newStart = startLine + newAt[from] - (newCount == 0 ? 1 : 0)
            return Git.Hunk(
                oldStart: oldStart, oldCount: oldCount, newStart: newStart, newCount: newCount,
                lines: lines)
        }
    }

    private static func isInsert(_ op: Op) -> Bool {
        if case .insert = op { return true }
        return false
    }

    private static func isDelete(_ op: Op) -> Bool {
        if case .delete = op { return true }
        return false
    }
}
