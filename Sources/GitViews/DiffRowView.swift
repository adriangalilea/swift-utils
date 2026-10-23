import GitKit
import Ink
import SwiftUI

/// One row of a file: a line, a pair of lines, a hunk's header, a fold, the preview's end,
/// a notice, or the selection's actions.
struct DiffRowView: View {
    let row: DiffRow
    let file: RenderedFile
    let painted: [AttributedString]?
    let selected: ClosedRange<Int>?
    let layout: DiffLayout
    let metrics: DiffMetrics
    let palette: DiffPalette
    let gutter: CGFloat
    let state: DiffState
    @Environment(\.diffQuote) private var quote
    @Environment(\.diffOpenSubmodule) private var openSubmodule
    @Environment(\.diffOptions) private var options

    var body: some View {
        switch row {
        case .line(let index):
            line(index)
        case .pair(let old, let new):
            HStack(spacing: 0) {
                side(old, on: .old)
                Rectangle().fill(palette.hairline).frame(width: 1)
                side(new, on: .new)
            }
            .fixedSize(horizontal: false, vertical: true)
        case .hunk(let h):
            hunkHeader(h)
        case .fold(let range):
            fold(range)
        case .more(let hidden):
            more(hidden)
        case .notice:
            notice
        case .actions:
            actions
        }
    }

    // MARK: - lines

    private func text(_ index: Int) -> AttributedString {
        if let painted, index < painted.count { return painted[index] }
        return AttributedString(file.lines[index].display)
    }

    private func marker(_ kind: Git.Line.Kind) -> String {
        switch kind {
        case .added: "+"
        case .removed: "−"
        case .context: " "
        }
    }

    private var numbered: Bool { layout.numbers && file.hasNumbers }

    private func number(_ value: Int?, _ kind: Git.Line.Kind) -> some View {
        Text(verbatim: value.map(String.init) ?? "")
            .font(metrics.smallFont)
            .monospacedDigit()
            .foregroundStyle(palette.numberInk(kind))
            .lineLimit(1)
            .frame(width: layout.numberWidth(file.digits, metrics) - metrics.advance, alignment: .trailing)
            .padding(.trailing, metrics.advance)
    }

    /// The code of a line. Wrapped, its continuation lines hang at the line's own
    /// indentation, as an editor wraps code, never back at the gutter.
    @ViewBuilder private func code(_ index: Int) -> some View {
        let indent = layout.wrap ? min(48, file.lines[index].display.prefix { $0 == " " }.count) : 0
        if indent > 0, indent < file.lines[index].display.count {
            let whole = text(index)
            let start = whole.characters.index(whole.startIndex, offsetBy: indent)
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Color.clear.frame(width: metrics.width(indent), height: 1)
                styled(AttributedString(whole[start...]))
            }
        } else {
            styled(text(index))
        }
    }

    private func styled(_ text: AttributedString) -> some View {
        Text(text)
            .font(metrics.font)
            .foregroundStyle(palette.text)
            .lineSpacing(metrics.size * 0.32)
            .fixedSize(horizontal: !layout.wrap, vertical: true)
            .frame(maxWidth: layout.wrap ? .infinity : nil, alignment: .leading)
            .padding(.trailing, metrics.advance * 2)
    }

    /// The row's vertical breathing room: a single line sits centered in `lineHeight`.
    private var inset: CGFloat { max(1, (metrics.lineHeight - metrics.size * 1.22) / 2) }

    private func line(_ index: Int) -> some View {
        let entry = file.lines[index]
        let kind = entry.line.kind
        let isSelected = selected?.contains(index) == true
        return HStack(alignment: .firstTextBaseline, spacing: 0) {
            if numbered {
                if layout.twoColumns {
                    number(entry.line.old, kind)
                    number(entry.line.new, kind)
                } else {
                    number(kind == .removed ? entry.line.old : entry.line.new, kind)
                }
            } else {
                Color.clear.frame(width: gutter, height: 1)
            }
            Text(verbatim: marker(kind))
                .font(metrics.font)
                .foregroundStyle(kind == .context ? palette.marker : palette.numberInk(kind))
                .frame(width: metrics.advance * DiffLayout.markerColumns, alignment: .center)
            code(index)
        }
        .padding(.vertical, inset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .leading) {
            HStack(spacing: 0) {
                palette.gutterWash(kind).frame(width: gutter)
                palette.lineWash(kind)
            }
        }
        .overlay(alignment: .leading) { selectionMark(isSelected) }
        .contentShape(Rectangle())
        .onTapGesture { tap(index) }
        .contextMenu { lineMenu(index) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.spoken(entry))
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    private func side(_ index: Int?, on side: DiffQuote.Side) -> some View {
        Group {
            if let index {
                let entry = file.lines[index]
                let kind = entry.line.kind
                let isSelected = selected?.contains(index) == true
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    if numbered {
                        number(side == .old ? entry.line.old : entry.line.new, kind)
                    }
                    Text(verbatim: marker(kind))
                        .font(metrics.font)
                        .foregroundStyle(kind == .context ? palette.marker : palette.numberInk(kind))
                        .frame(width: metrics.advance * DiffLayout.markerColumns, alignment: .center)
                    code(index)
                }
                .padding(.vertical, inset)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(alignment: .leading) {
                    HStack(spacing: 0) {
                        palette.gutterWash(kind).frame(width: numbered ? layout.numberWidth(file.digits, metrics) : 0)
                        palette.lineWash(kind)
                    }
                }
                .overlay(alignment: .leading) { selectionMark(isSelected) }
                .contentShape(Rectangle())
                .onTapGesture { tap(index) }
                .contextMenu { lineMenu(index) }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Self.spoken(entry))
            } else {
                palette.emptySide
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityHidden(true)
            }
        }
    }

    @ViewBuilder private func selectionMark(_ on: Bool) -> some View {
        if on {
            ZStack(alignment: .leading) {
                palette.selection
                palette.selectionEdge.frame(width: 2)
            }
            .allowsHitTesting(false)
        }
    }

    static func spoken(_ entry: RenderedFile.Line) -> String {
        let text = entry.line.text.trimmingCharacters(in: .whitespaces)
        let said = text.isEmpty ? "empty" : text
        switch entry.line.kind {
        case .added: return "added line \(entry.line.new.map(String.init) ?? ""): \(said)"
        case .removed: return "removed line \(entry.line.old.map(String.init) ?? ""): \(said)"
        case .context: return "line \(entry.line.new.map(String.init) ?? ""): \(said)"
        }
    }

    // MARK: - selection

    private func tap(_ index: Int) {
        var extend = false
        #if os(macOS)
            extend = NSEvent.modifierFlags.contains(.shift)
        #endif
        withAnimation(.inkFlick) {
            guard var selection = state.selection, selection.file == file.id else {
                state.selection = DiffSelection(file: file.id, anchor: index, head: index)
                return
            }
            if extend {
                selection.head = index
            } else if selection.anchor == selection.head {
                #if os(macOS)
                    // A click is a new selection on a Mac; shift extends it.
                    selection = DiffSelection(file: file.id, anchor: index, head: index)
                    if index == state.selection?.anchor {
                        state.selection = nil
                        return
                    }
                #else
                    // On a touch screen the second tap extends: there is no shift.
                    if index == selection.anchor {
                        state.selection = nil
                        return
                    }
                    selection.head = index
                #endif
            } else if selection.range.contains(index) {
                selection = DiffSelection(file: file.id, anchor: index, head: index)
            } else {
                selection.head = index
            }
            state.selection = selection
        }
    }

    private func lines(_ range: ClosedRange<Int>) -> [Git.Line] {
        range.clamped(to: 0...(file.lines.count - 1)).map { file.lines[$0].line }
    }

    @ViewBuilder private func lineMenu(_ index: Int) -> some View {
        let range = selected.flatMap { $0.contains(index) ? $0 : nil } ?? index...index
        let chosen = lines(range)
        let count = chosen.count
        let hunk = file.lines[index].hunk
        DiffMenuItems(
            copy: [
                (count == 1 ? "Copy Line" : "Copy \(count) Lines", chosen.map(\.text).joined(separator: "\n"))
            ],
            quote: DiffQuote(file: file.file, lines: chosen),
            quoteTitle: count == 1 ? "Quote Line" : "Quote \(count) Lines", action: quote)
        Divider()
        DiffMenuItems(
            copy: [], quote: DiffQuote.hunk(file.file.hunks[hunk], of: file.file), quoteTitle: "Quote Hunk",
            action: quote)
        Button("Copy Path", systemImage: "link") { DiffPasteboard.copy(file.file.path) }
    }

    @ViewBuilder private var actions: some View {
        if let range = selected {
            let chosen = lines(range)
            let made = DiffQuote(file: file.file, lines: chosen)
            HStack(spacing: .inkGap) {
                Text(verbatim: made.reference)
                    .font(metrics.smallFont)
                    .foregroundStyle(palette.quiet)
                    .lineLimit(1)
                    .truncationMode(.head)
                Spacer(minLength: .inkGap)
                Button {
                    #if os(macOS) || os(iOS)
                        state.copy.copy(chosen.map(\.text).joined(separator: "\n"))
                    #endif
                } label: {
                    #if os(macOS) || os(iOS)
                        Label(state.copy.state == .copied ? "Copied" : "Copy", systemImage: state.copy.state == .copied ? "checkmark" : "doc.on.doc")
                    #else
                        Label("Copy", systemImage: "doc.on.doc")
                    #endif
                }
                .buttonStyle(.ink)
                Button {
                    if let quote {
                        quote(made)
                    } else {
                        DiffPasteboard.copy(made.markdown)
                    }
                    withAnimation(.inkFlick) { state.selection = nil }
                } label: {
                    Label(quote == nil ? "Copy as Markdown" : "Quote", systemImage: "text.quote")
                }
                .buttonStyle(.inkProminent)
                Button {
                    withAnimation(.inkFlick) { state.selection = nil }
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.inkTool)
                .accessibilityLabel("Clear selection")
            }
            .labelStyle(.titleAndIcon)
            .controlSize(.small)
            .font(.callout)
            .padding(.horizontal, metrics.advance * 2)
            .padding(.vertical, 6)
            .frame(maxWidth: layout.page && !layout.wrap ? layout.width : .infinity, alignment: .leading)
            .background(palette.selection.opacity(0.6))
            .overlay(alignment: .leading) { palette.selectionEdge.frame(width: 2) }
            .transition(.opacity)
        }
    }

    // MARK: - the rest

    private func hunkHeader(_ h: Int) -> some View {
        let hunk = file.file.hunks[h]
        let collapsed = state.collapsedHunks[file.id]?.contains(h) == true
        let previous = h > 0 ? file.file.hunks[h - 1] : nil
        let skipped = previous.map { hunk.newStart - ($0.newStart + $0.newCount) } ?? (hunk.newStart - 1)
        return HStack(alignment: .firstTextBaseline, spacing: metrics.advance) {
            Image(systemName: "chevron.down")
                .font(.system(size: metrics.size * 0.7, weight: .semibold))
                .foregroundStyle(palette.quiet)
                .rotationEffect(.degrees(collapsed ? -90 : 0))
                .frame(width: max(gutter - metrics.advance, metrics.advance * 2), alignment: .trailing)
            if file.hasNumbers {
                Text(verbatim: rangeLabel(hunk))
                    .font(metrics.smallFont)
                    .foregroundStyle(palette.quiet)
            }
            if !hunk.section.isEmpty {
                Text(verbatim: hunk.section.trimmingCharacters(in: .whitespaces))
                    .font(metrics.smallFont)
                    .foregroundStyle(palette.text.opacity(0.75))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if file.hasNumbers, skipped > 0 {
                Text(verbatim: skipped == 1 ? "1 line above" : "\(skipped) lines above")
                    .font(.system(size: metrics.size * 0.85))
                    .foregroundStyle(palette.number)
                    .lineLimit(1)
                    .padding(.trailing, metrics.advance * 2)
            }
        }
        .padding(.vertical, 5)
        .frame(maxWidth: layout.page && !layout.wrap ? layout.width : .infinity, alignment: .leading)
        .background(palette.wash)
        .overlay(alignment: .top) { Rectangle().fill(palette.hairline).frame(height: h == 0 ? 0 : 1) }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.inkSettle) {
                var set = state.collapsedHunks[file.id] ?? []
                if set.contains(h) { set.remove(h) } else { set.insert(h) }
                state.collapsedHunks[file.id] = set
            }
        }
        .contextMenu {
            DiffMenuItems(
                copy: [("Copy Hunk", ([hunk.header] + hunk.lines.map(\.unified)).joined(separator: "\n"))],
                quote: DiffQuote.hunk(hunk, of: file.file), quoteTitle: "Quote Hunk", action: quote)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Hunk at line \(hunk.newStart)\(hunk.section.isEmpty ? "" : ", \(hunk.section)")")
        .accessibilityHint(collapsed ? "Shows its lines" : "Hides its lines")
        .accessibilityAddTraits(.isButton)
    }

    private func rangeLabel(_ hunk: Git.Hunk) -> String {
        let end = hunk.newStart + max(0, hunk.newCount - 1)
        if hunk.newCount == 0 { return "removed at \(hunk.oldStart)" }
        return hunk.newCount == 1 ? "line \(hunk.newStart)" : "lines \(hunk.newStart)–\(end)"
    }

    private func fold(_ range: Range<Int>) -> some View {
        quietRow(symbol: "arrow.up.and.down", text: range.count == 1 ? "1 unchanged line" : "\(range.count) unchanged lines") {
            var set = state.expandedFolds[file.id] ?? []
            set.insert(range.lowerBound)
            state.expandedFolds[file.id] = set
        }
    }

    private func more(_ hidden: Int) -> some View {
        quietRow(symbol: "chevron.down", text: hidden == 1 ? "Show 1 more line" : "Show \(hidden) more lines") {
            state.showAll = true
        }
    }

    private func quietRow(symbol: String, text: String, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.inkSettle, action)
        } label: {
            HStack(spacing: metrics.advance) {
                Image(systemName: symbol)
                    .font(.system(size: metrics.size * 0.75, weight: .semibold))
                    .frame(width: max(gutter - metrics.advance, metrics.advance * 2), alignment: .trailing)
                Text(verbatim: text)
                    .font(.system(size: metrics.size * 0.9))
                Spacer(minLength: 0)
            }
            .foregroundStyle(palette.quiet)
            .padding(.vertical, 5)
            .frame(maxWidth: layout.page && !layout.wrap ? layout.width : .infinity, alignment: .leading)
            .background(palette.wash)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var notice: some View {
        let f = file.file
        HStack(spacing: metrics.advance) {
            if let pointer = f.submodule {
                Image(systemName: "shippingbox")
                Text(verbatim: "Submodule")
                Text(verbatim: short(pointer.old) + " → " + short(pointer.new) + (pointer.dirty ? " (dirty)" : ""))
                    .font(metrics.smallFont)
                    .foregroundStyle(palette.text)
                Spacer(minLength: 0)
                if let openSubmodule, pointer.old != pointer.new {
                    Button("Open") { openSubmodule.perform(f.path, pointer) }
                        .buttonStyle(.ink)
                        .controlSize(.small)
                }
            } else {
                Image(systemName: f.isBinary ? "doc.zipper" : f.modeChanged ? "lock.open" : "arrow.right")
                Text(verbatim: noticeText(f))
                Spacer(minLength: 0)
            }
        }
        .font(.system(size: metrics.size * 0.95))
        .foregroundStyle(palette.quiet)
        .padding(.horizontal, metrics.advance * 2)
        .padding(.vertical, 10)
        .frame(maxWidth: layout.page && !layout.wrap ? layout.width : .infinity, alignment: .leading)
    }

    private func short(_ hash: String?) -> String { hash.map { String($0.prefix(7)) } ?? "none" }

    private func noticeText(_ f: Git.FileDiff) -> String {
        if f.isBinary {
            return switch f.change {
            case .added: "Binary file added"
            case .deleted: "Binary file deleted"
            default: "Binary file changed"
            }
        }
        if f.modeChanged {
            let mode = { (m: String?) in
                switch m {
                case "100755": "executable"
                case "100644": "not executable"
                case "120000": "a symbolic link"
                default: m ?? ""
                }
            }
            return "Now \(mode(f.newMode)) (\(f.oldMode ?? "") → \(f.newMode ?? ""))"
        }
        switch f.change {
        case .renamed: return "Renamed, content unchanged"
        case .copied: return "Copied, content unchanged"
        case .added: return "Empty file added"
        case .deleted: return "Empty file deleted"
        case .modified: return "No changes to show"
        }
    }
}
