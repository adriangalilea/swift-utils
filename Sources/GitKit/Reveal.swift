import Foundation

extension Git.FileDiff {
    /// The new side's line numbers the diff left out above hunk `h` (its `N lines
    /// above`): after the hunk before it, or from the file's first line.
    public func gap(above h: Int) -> ClosedRange<Int>? {
        guard hunks.indices.contains(h) else { return nil }
        let top = Self.first(hunks[h])
        let after = h == 0 ? 1 : Self.end(hunks[h - 1])
        return after < top ? after...(top - 1) : nil
    }

    /// The file with up to `limit` of the lines above hunk `h` joined to it, read from
    /// `newText`. Nil when there are none, or `newText` is not the text this diff was
    /// made against (the hunk's own first unchanged line is not where it says).
    public func revealing(above h: Int, in newText: String, limit: Int = 200) -> Git.FileDiff? {
        guard let gap = gap(above: h) else { return nil }
        let lines = newText.components(separatedBy: "\n")
        var hunk = hunks[h]
        let top = Self.first(hunk)
        if let lead = hunk.lines.first, lead.kind == .context {
            guard top - 1 < lines.count, lines[top - 1] == lead.text else { return nil }
        }
        let from = max(gap.lowerBound, top - limit)
        guard gap.upperBound - 1 < lines.count else { return nil }
        let delta = Self.firstOld(hunk) - top
        let shown = (from...gap.upperBound).map { number in
            Git.Line(kind: .context, old: number + delta, new: number, text: lines[number - 1])
        }
        hunk.lines = shown + hunk.lines
        hunk.oldStart = from + delta
        hunk.newStart = from
        hunk.oldCount += shown.count
        hunk.newCount += shown.count
        var copy = self
        copy.hunks[h] = hunk
        return Git.FileDiff(
            oldPath: copy.oldPath, newPath: copy.newPath, change: copy.change,
            similarity: copy.similarity, oldMode: copy.oldMode, newMode: copy.newMode,
            oldBlob: copy.oldBlob, newBlob: copy.newBlob, isBinary: copy.isBinary,
            submodule: copy.submodule, hunks: copy.hunks)
    }

    /// A hunk's first line on each side; a side with no lines names the line before.
    private static func first(_ hunk: Git.Hunk) -> Int {
        hunk.newCount == 0 ? hunk.newStart + 1 : hunk.newStart
    }

    private static func firstOld(_ hunk: Git.Hunk) -> Int {
        hunk.oldCount == 0 ? hunk.oldStart + 1 : hunk.oldStart
    }

    /// The new side's first line after a hunk.
    private static func end(_ hunk: Git.Hunk) -> Int {
        hunk.newCount == 0 ? hunk.newStart + 1 : hunk.newStart + hunk.newCount
    }
}
