import GitKit

/// One row of a drawn file. Lines are indices into `RenderedFile.lines`.
enum DiffRow: Hashable, Sendable {
    /// A hunk's header (where it is, the function around it); taps fold the hunk.
    case hunk(Int)
    /// One line, unified.
    case line(Int)
    /// Old beside new, split; a side is nil where the other side has no partner.
    case pair(old: Int?, new: Int?)
    /// Unchanged lines folded away: `lines` is the range in `RenderedFile.lines`.
    case fold(Range<Int>)
    /// The preview stops here; `hidden` lines follow.
    case more(hidden: Int)
    /// What a file without lines changed (binary, a mode, a submodule, a pure rename).
    case notice
    /// The selection's actions, right under its last line.
    case actions
}

/// Which rows a file draws, from what the reader has folded, expanded and selected.
struct DiffRowPlan: Sendable {
    var split: Bool
    var context: Int
    var collapsedHunks: Set<Int> = []
    var expandedFolds: Set<Int> = []
    /// Line rows still allowed (a preview's budget); nil is no limit.
    var budget: Int?
    /// Lines of later files the preview leaves out, told in this file's "more" row.
    var after = 0
    /// The selected lines and whether the actions row goes under them.
    var selection: ClosedRange<Int>?
    var actions = false

    /// The rows, and how many line rows the budget left out.
    func rows(_ file: RenderedFile) -> (rows: [DiffRow], hidden: Int) {
        var rows: [DiffRow] = []
        if file.lines.isEmpty {
            return (after > 0 ? [.notice, .more(hidden: after)] : [.notice], after)
        }
        var shown = 0
        var hidden = 0
        var cut = false
        for h in file.file.hunks.indices {
            let range = file.range(of: h)
            if cut {
                hidden += range.count
                continue
            }
            if showsHeader(file, h) { rows.append(.hunk(h)) }
            if collapsedHunks.contains(h) { continue }
            var body: [DiffRow] = []
            for item in visible(file, range) {
                body.append(item)
            }
            let paired = split ? pair(body, file) : body
            for row in paired {
                if let budget, isLine(row) {
                    if shown >= budget {
                        cut = true
                        hidden += lineCount(row)
                        continue
                    }
                    shown += 1
                }
                if cut {
                    hidden += lineCount(row)
                    continue
                }
                rows.append(row)
                if actions, let selection, contains(row, selection.upperBound) {
                    rows.append(.actions)
                }
            }
        }
        hidden += after
        if hidden > 0 { rows.append(.more(hidden: hidden)) }
        return (rows, hidden)
    }

    /// Every hunk has its header, but one that starts the file and names nothing: it
    /// would only say "line 1".
    func showsHeader(_ file: RenderedFile, _ h: Int) -> Bool {
        let hunk = file.file.hunks[h]
        if !hunk.section.isEmpty { return true }
        guard file.hasNumbers else { return file.file.hunks.count > 1 }
        return file.file.hunks.count > 1 || hunk.oldStart > 1 || hunk.newStart > 1
    }

    /// A hunk's lines with long runs of unchanged ones folded to `context` on each side.
    func visible(_ file: RenderedFile, _ range: Range<Int>) -> [DiffRow] {
        var out: [DiffRow] = []
        var index = range.lowerBound
        while index < range.upperBound {
            guard file.lines[index].line.kind == .context else {
                out.append(.line(index))
                index += 1
                continue
            }
            var end = index
            while end < range.upperBound, file.lines[end].line.kind == .context { end += 1 }
            let head = index == range.lowerBound ? 0 : context
            let tail = end == range.upperBound ? 0 : context
            if end - index > head + tail + 1, !expandedFolds.contains(index + head) {
                for line in index..<(index + head) { out.append(.line(line)) }
                out.append(.fold((index + head)..<(end - tail)))
                for line in (end - tail)..<end { out.append(.line(line)) }
            } else {
                for line in index..<end { out.append(.line(line)) }
            }
            index = end
        }
        return out
    }

    /// Unified rows as split ones: unchanged lines on both sides, a run of removed lines
    /// beside the run of added lines that follows it.
    func pair(_ rows: [DiffRow], _ file: RenderedFile) -> [DiffRow] {
        var out: [DiffRow] = []
        var removed: [Int] = []
        var added: [Int] = []
        func flush() {
            for offset in 0..<max(removed.count, added.count) {
                out.append(
                    .pair(
                        old: offset < removed.count ? removed[offset] : nil,
                        new: offset < added.count ? added[offset] : nil))
            }
            removed = []
            added = []
        }
        for row in rows {
            guard case .line(let index) = row else {
                flush()
                out.append(row)
                continue
            }
            switch file.lines[index].line.kind {
            case .removed:
                if !added.isEmpty { flush() }
                removed.append(index)
            case .added:
                added.append(index)
            case .context:
                flush()
                out.append(.pair(old: index, new: index))
            }
        }
        flush()
        return out
    }

    private func isLine(_ row: DiffRow) -> Bool {
        switch row {
        case .line, .pair: true
        default: false
        }
    }

    private func lineCount(_ row: DiffRow) -> Int {
        switch row {
        case .line: 1
        case .pair(let old, let new): old == new ? 1 : (old == nil ? 0 : 1) + (new == nil ? 0 : 1)
        case .fold(let range): range.count
        default: 0
        }
    }

    private func contains(_ row: DiffRow, _ line: Int) -> Bool {
        switch row {
        case .line(let index): index == line
        case .pair(let old, let new):
            // The actions go under the row holding the selection's last line, or the last
            // row whose lines fall inside the selection (a removed line's partner row).
            old == line || new == line
        default: false
        }
    }
}
