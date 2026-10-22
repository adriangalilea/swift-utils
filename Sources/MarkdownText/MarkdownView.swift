import Ink
import SwiftUI
import Syntax

/// MARKDOWN, READ: a markdown text drawn as a page from its tree (`MarkdownDocument`).
/// The look carries ui's markdown over to the Apple platforms: the words at a regular
/// weight a step under full ink; headings a restrained hierarchy, set closer to what
/// they title than to what came before; inline code on a quiet chip; links told by a
/// hairline under them, not a hue; code blocks in a framed well, colored by the fence's
/// language (`Syntax`), scrolled sideways and never wrapped; tables with a quiet head
/// and hairline rows, scrolled sideways when wider than the column; quotes on a wash;
/// footnotes gathered at the foot. Front matter is not drawn.
///
/// How it is set is the environment's `MarkdownStyle`: a page (`.body`), a quiet aside
/// (`.footnote`), or a preview cut to a few lines (`.preview(lines:)`), the same view.
///
/// SAFE BY CONSTRUCTION. Raw HTML is drawn as its text; a link is live only to the web,
/// mail or a phone (`MarkdownDocument.link`), otherwise it is its words; an image is a
/// link to it, never loaded. Text anyone wrote is safe to draw.
public struct MarkdownView: View {
    private let document: MarkdownDocument
    @Environment(\.markdownStyle) private var style
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.colorScheme) private var scheme

    /// `streaming`: the text is still arriving; see `MarkdownDocument.init`.
    public init(_ text: String, streaming: Bool = false) {
        document = MarkdownDocument(text, streaming: streaming)
    }

    public init(_ document: MarkdownDocument) {
        self.document = document
    }

    public var body: some View {
        let metrics = Metrics.of(style.textStyle, typeSize)
        let page = Page(metrics: metrics, ink: style.ink, scheme: scheme)
        if let lines = style.lineLimit {
            page.preview(document, lines: lines)
        } else {
            page.document(document)
                .frame(
                    maxWidth: style.measure.map { metrics.em(metrics.ch) * CGFloat($0) },
                    alignment: .leading
                )
                #if !os(tvOS)
                    .textSelection(.enabled)
                #endif
        }
    }
}

/// One page's setting: its font's facts and its ink. A footnote is the same page at a
/// smaller size and a quieter ink (`aside`).
@MainActor struct Page {
    let metrics: Metrics
    let ink: MarkdownStyle.Ink
    let scheme: ColorScheme

    var aside: Page {
        Page(metrics: metrics.scaled(0.875), ink: .secondary, scheme: scheme)
    }

    // MARK: - the page

    @ViewBuilder func document(_ document: MarkdownDocument) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            blocks(document.blocks, tight: false, depth: 0)
            if !document.footnotes.isEmpty {
                aside.footnotes(document.footnotes)
                    .padding(.top, metrics.em(Rhythm.footnotes))
            }
        }
    }

    /// Blocks in a column, each set apart from the one above by the rhythm. A view of its
    /// own: blocks nest (a list holds blocks), and the nesting goes through this type.
    func blocks(_ blocks: [MarkdownDocument.Block], tight: Bool, depth: Int) -> Column {
        Column(page: self, blocks: blocks, tight: tight, depth: depth)
    }

    struct Column: View {
        let page: Page
        let blocks: [MarkdownDocument.Block]
        let tight: Bool
        let depth: Int

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                    page.block(block, depth: depth)
                        .padding(
                            .top,
                            index == 0
                                ? 0
                                : page.metrics.em(
                                    Rhythm.gap(blocks[index - 1].kind, block.kind, tight: tight)))
                }
            }
        }
    }

    @ViewBuilder func block(_ block: MarkdownDocument.Block, depth: Int) -> some View {
        switch block.kind {
        case .paragraph(let inlines):
            prose(text(inlines, Run(size: metrics.em, color: ink.words)), size: metrics.em)
        case .heading(let level, let inlines):
            let size = metrics.em(Rhythm.headingSize(level))
            prose(
                text(
                    inlines,
                    Run(size: size, weight: .semibold, color: level > 4 ? ink.quiet : ink.titles)),
                size: size, leading: Rhythm.headingLeading
            )
            .accessibilityAddTraits(.isHeader)
        case .quote(let inner):
            blocks(inner, tight: false, depth: depth)
                .padding(.vertical, metrics.em(0.6))
                .padding(.horizontal, metrics.em(0.9))
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    ink.wash,
                    in: RoundedRectangle(cornerRadius: metrics.em(0.6), style: .continuous))
        case .list(let list):
            self.list(list, depth: depth)
        case .code(let language, _, let text):
            code(text, language: language)
        case .html(let text):
            code(text, language: "html")
        case .table(let table):
            self.table(table)
        case .rule:
            Rectangle().fill(ink.hairline).frame(height: 1)
        }
    }

    /// Running text: the page's line height at this size.
    func prose(_ text: AttributedString, size: CGFloat, leading: CGFloat = Metrics.leading)
        -> some View
    {
        Text(text)
            .lineSpacing(metrics.lineSpacing(at: size, leading: leading))
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - lists

    func list(_ list: MarkdownDocument.List, depth: Int) -> some View {
        let tasks = list.items.contains { $0.checked != nil }
        let last = list.start + list.items.count - 1
        // The marker column, in ems: a bullet's, a box's, or the widest number's digits
        // and its period, then the gap before the words.
        let column =
            tasks ? 1.5 : list.ordered ? metrics.digit * CGFloat(String(last).count) + 0.85 : 1.15
        return VStack(
            alignment: .leading,
            spacing: metrics.em(list.tight ? Rhythm.tightItem : Rhythm.looseItem)
        ) {
            ForEach(Array(list.items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    marker(item, number: list.ordered ? list.start + index : nil, depth: depth)
                        .frame(
                            width: metrics.em(column - 0.45),
                            alignment: list.ordered && !tasks ? .trailing : .leading
                        )
                        .padding(.trailing, metrics.em(0.45))
                    blocks(item.blocks, tight: list.tight, depth: depth + 1)
                }
            }
        }
    }

    @ViewBuilder func marker(_ item: MarkdownDocument.Item, number: Int?, depth: Int) -> some View {
        if let checked = item.checked {
            Image(systemName: checked ? "checkmark.square.fill" : "square")
                .font(.system(size: metrics.em(0.9)))
                .foregroundStyle(checked ? ink.words : ink.quiet)
                .accessibilityLabel(checked ? "done" : "to do")
        } else if let number {
            Text(verbatim: "\(number).")
                .font(.system(size: metrics.em).monospacedDigit())
                .foregroundStyle(ink.quiet)
        } else {
            // A bullet a level, as a reader tells nesting at a glance: filled, open,
            // square, then filled again.
            Text(verbatim: ["•", "◦", "▪"][depth % 3])
                .font(.system(size: metrics.em))
                .foregroundStyle(ink.quiet)
        }
    }

    // MARK: - code

    func code(_ text: String, language: String?) -> some View {
        let size = metrics.em(Rhythm.codeSize)
        let colored =
            language.map { Syntax.highlight(text, language: $0, on: Syntax.Appearance(scheme)) }
            ?? AttributedString(text)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: metrics.em(0.5)) {
                Text(verbatim: language ?? "")
                    .font(.system(size: metrics.em(0.75), design: .monospaced))
                    .foregroundStyle(ink.quiet)
                Spacer(minLength: 0)
                #if os(macOS) || os(iOS)
                    Copy(text)
                #endif
            }
            .padding(.horizontal, metrics.em(0.9))
            .padding(.top, metrics.em(0.5))
            ScrollView(.horizontal) {
                Text(colored)
                    .font(.system(size: size, design: .monospaced))
                    .foregroundStyle(ink.words)
                    .lineSpacing(metrics.lineSpacing(at: size, leading: Rhythm.codeLeading))
                    .fixedSize()
                    .padding(.horizontal, metrics.em(0.9))
                    .padding(.top, metrics.em(0.35))
                    .padding(.bottom, metrics.em(0.85))
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ink.wash, in: RoundedRectangle(cornerRadius: metrics.em(0.6), style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: metrics.em(0.6), style: .continuous)
                .strokeBorder(ink.hairline, lineWidth: 1))
    }

    // MARK: - tables

    func table(_ table: MarkdownDocument.Table) -> some View {
        let cells = Page(metrics: metrics.scaled(Rhythm.tableSize), ink: ink, scheme: scheme)
        let columns = table.alignments.count
        return ScrollView(.horizontal) {
            // A row reads along its first line, whatever wraps below it in its neighbours.
            Grid(
                alignment: Alignment(horizontal: .leading, vertical: .firstTextBaseline),
                horizontalSpacing: 0, verticalSpacing: 0
            ) {
                GridRow {
                    ForEach(Array(table.head.enumerated()), id: \.offset) { column, cell in
                        cells.cell(cell, column: column, head: true)
                            .gridColumnAlignment(Self.alignment(table.alignments[column]))
                    }
                }
                Rectangle().fill(ink.hairline).frame(height: 1).gridCellUnsizedAxes(.horizontal)
                    .gridCellColumns(columns)
                ForEach(Array(table.rows.enumerated()), id: \.offset) { index, row in
                    if index > 0 {
                        Rectangle().fill(ink.wash).frame(height: 1).gridCellUnsizedAxes(.horizontal)
                            .gridCellColumns(columns)
                    }
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { column, cell in
                            cells.cell(cell, column: column, head: false)
                        }
                    }
                }
            }
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }

    func cell(_ cell: MarkdownDocument.Cell, column: Int, head: Bool) -> some View {
        let run =
            head
            ? Run(size: metrics.em, weight: .medium, color: ink.quiet)
            : Run(size: metrics.em, color: ink.words)
        // A long cell wraps at a measure of its own instead of stretching its column
        // across the screen; the table scrolls when the columns still do not fit.
        return Capped(width: metrics.em(metrics.ch * Rhythm.cellMeasure)) {
            prose(text(cell.content, run), size: metrics.em, leading: Rhythm.tableLeading)
        }
        .padding(.leading, column == 0 ? 0 : metrics.em(0.75))
        .padding(.trailing, metrics.em(0.75))
        .padding(.vertical, metrics.em(0.55))
    }

    static func alignment(_ alignment: MarkdownDocument.Table.Alignment) -> HorizontalAlignment {
        switch alignment {
        case .none, .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }

    // MARK: - footnotes

    func footnotes(_ notes: [MarkdownDocument.Footnote]) -> some View {
        VStack(alignment: .leading, spacing: metrics.em(0.5)) {
            Rectangle().fill(ink.hairline).frame(height: 1)
                .padding(.bottom, metrics.em(0.5))
            ForEach(notes, id: \.number) { note in
                HStack(alignment: .firstTextBaseline, spacing: metrics.em(0.5)) {
                    Text(verbatim: "\(note.number)")
                        .font(.system(size: metrics.em).monospacedDigit())
                        .foregroundStyle(ink.quiet)
                    blocks(note.blocks, tight: true, depth: 0)
                }
            }
        }
    }

    // MARK: - the preview

    /// The whole text as one run, cut at `lines`: each block on its line, headings in
    /// the words' size, code in its face, links as their words (a preview is tapped as a
    /// whole).
    func preview(_ document: MarkdownDocument, lines: Int) -> some View {
        var words = Run(size: metrics.em, color: ink.words)
        words.links = false
        var out = AttributedString()
        for line in previewLines(document.blocks, words) {
            if !out.characters.isEmpty { out += AttributedString("\n") }
            out += line
        }
        return Text(out)
            .lineLimit(lines)
            .truncationMode(.tail)
            .lineSpacing(metrics.lineSpacing(at: metrics.em))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    func previewLines(_ blocks: [MarkdownDocument.Block], _ words: Run) -> [AttributedString] {
        blocks.flatMap { block -> [AttributedString] in
            switch block.kind {
            case .paragraph(let inlines): return [text(inlines, words)]
            case .heading(_, let inlines):
                var strong = words
                strong.weight = .semibold
                strong.color = ink.titles
                return [text(inlines, strong)]
            case .quote(let inner): return previewLines(inner, words)
            case .list(let list):
                return list.items.enumerated().flatMap { index, item in
                    var marker = AttributedString(
                        item.checked.map { $0 ? "☑ " : "☐ " }
                            ?? (list.ordered ? "\(list.start + index). " : "• "))
                    marker.foregroundColor = ink.quiet
                    marker.font = .system(size: metrics.em)
                    let inner = previewLines(item.blocks, words)
                    return inner.isEmpty ? [marker] : [marker + inner[0]] + inner.dropFirst()
                }
            case .code(_, _, let code), .html(let code):
                var run = AttributedString(code)
                run.font = .system(size: metrics.em(Rhythm.codeSize), design: .monospaced)
                run.foregroundColor = ink.words
                return [run]
            case .table(let table):
                return ([table.head] + table.rows).map { row in
                    row.map { text($0.content, words) }.reduce(into: AttributedString()) {
                        line, cell in
                        if !line.characters.isEmpty { line += AttributedString("  ·  ") }
                        line += cell
                    }
                }
            case .rule: return []
            }
        }
    }

    // MARK: - inline runs

    /// What a run of words is set in, as the inlines nest into it.
    struct Run {
        var size: CGFloat
        var weight: Font.Weight = .regular
        var italic = false
        var color: Color
        var strike = false
        var link: URL?
        /// False in a preview: links are their words.
        var links = true

        var font: Font {
            let font = Font.system(size: size, weight: weight)
            return italic ? font.italic() : font
        }
    }

    func text(_ inlines: [MarkdownDocument.Inline], _ run: Run) -> AttributedString {
        inlines.reduce(into: AttributedString()) { out, inline in
            out += text(inline, run)
        }
    }

    func text(_ inline: MarkdownDocument.Inline, _ run: Run) -> AttributedString {
        switch inline.kind {
        case .text(let words), .html(let words): return plain(words, run)
        case .softBreak: return plain(" ", run)
        case .lineBreak: return plain("\n", run)
        case .code(let code):
            var piece = plain(code, run)
            piece.font = .system(size: run.size * Rhythm.codeSize, design: .monospaced)
            piece.backgroundColor = ink.wash
            return piece
        case .emphasis(let inner):
            var nested = run
            nested.italic = true
            return text(inner, nested)
        case .strong(let inner):
            var nested = run
            nested.weight = run.weight == .regular ? .semibold : .bold
            nested.color = ink.titles
            return text(inner, nested)
        case .strikethrough(let inner):
            var nested = run
            nested.strike = true
            nested.color = ink.quiet
            return text(inner, nested)
        case .link(let url, _, let inner):
            return text(inner, linking(run, url))
        case .image(let url, _, let alt):
            // Never loaded: the picture is a link to itself, by its words or its name.
            let words =
                alt.plainText.isEmpty ? (URL(string: url)?.lastPathComponent ?? url) : alt.plainText
            return plain(words, linking(run, url))
        case .footnote(_, let number):
            var mark = plain("\(number)", run)
            mark.font = .system(size: run.size * 0.7).monospacedDigit()
            mark.baselineOffset = run.size * 0.35
            mark.foregroundColor = ink.quiet
            return mark
        }
    }

    private func linking(_ run: Run, _ url: String) -> Run {
        guard run.links, let target = MarkdownDocument.link(url) else { return run }
        var nested = run
        nested.link = target
        nested.color = ink.titles
        return nested
    }

    private func plain(_ words: String, _ run: Run) -> AttributedString {
        var piece = AttributedString(words)
        piece.font = run.font
        piece.foregroundColor = run.color
        if run.strike {
            piece.strikethroughStyle = Text.LineStyle(pattern: .solid, color: ink.quiet)
        }
        if let link = run.link {
            piece.link = link
            piece.underlineStyle = Text.LineStyle(pattern: .solid, color: ink.quiet)
        }
        return piece
    }
}

/// The rhythm, in ems of the page's size: how far apart blocks stand and how big each
/// kind of text is beside the words.
enum Rhythm {
    static let codeSize: CGFloat = 0.85
    static let codeLeading: CGFloat = 1.5
    static let tableSize: CGFloat = 0.9
    static let tableLeading: CGFloat = 1.35
    static let headingLeading: CGFloat = 1.25
    /// A table cell's longest line, in characters.
    static let cellMeasure: CGFloat = 36
    static let tightItem: CGFloat = 0.3
    static let looseItem: CGFloat = 0.75
    static let footnotes: CGFloat = 2

    static func headingSize(_ level: Int) -> CGFloat {
        [1.45, 1.25, 1.1][safe: level - 1] ?? 1
    }

    /// The space between two blocks. A heading binds to what it titles: the space
    /// after it is its own (small), the space before it its own (large). Between other
    /// blocks the larger of the two wins, as margins collapse on a page. Inside a tight
    /// list item, a paragraph and the list nested under it sit close.
    static func gap(
        _ above: MarkdownDocument.Block.Kind, _ below: MarkdownDocument.Block.Kind, tight: Bool
    )
        -> CGFloat
    {
        if case .heading(let level, _) = above { return [0.55, 0.5, 0.45][safe: level - 1] ?? 0.4 }
        if case .heading(let level, _) = below { return [1.9, 1.7, 1.45][safe: level - 1] ?? 1.25 }
        if tight { return 0.3 }
        return max(around(above), around(below))
    }

    private static func around(_ kind: MarkdownDocument.Block.Kind) -> CGFloat {
        switch kind {
        case .paragraph, .list, .html: 0.9
        case .code, .table, .quote: 1.1
        case .rule: 1.6
        case .heading: 0
        }
    }
}

extension Array {
    fileprivate subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

/// Its content laid out no wider than `width`, and only as wide as it needs below that:
/// a text proposed no width (inside a sideways scroll) would otherwise run on one line.
struct Capped: Layout {
    let width: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        subviews[0].sizeThatFits(
            ProposedViewSize(width: min(proposal.width ?? width, width), height: nil))
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        subviews[0].place(
            at: bounds.origin,
            proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
    }
}
