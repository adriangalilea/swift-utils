import Foundation
import cmark_gfm
import cmark_gfm_extensions

/// MARKDOWN AS A TREE: the one parse every reader of markdown in the studio's Apple apps
/// shares, so a text means the same thing wherever it is drawn. CommonMark with GitHub's
/// extensions (tables, strikethrough, task lists, autolinks, footnotes) and front matter
/// (YAML or TOML, kept as its own value, never read as a rule and a paragraph), the same
/// syntax ui's `markdown-core` reads on the web. cmark-gfm parses; this is a plain value
/// tree over it, `Sendable`, so a parse can happen anywhere and be drawn on the main
/// actor. Every block keeps its source span, and every inline whose position cmark knows,
/// so a reader can always go back to the exact text.
///
/// Two departures from GitHub, both for text an agent writes: strikethrough needs two
/// tildes (`~~gone~~`; one tilde is "about", as in `~5 min`), and punctuation is never
/// made smart (what is drawn is what was written).
public struct MarkdownDocument: Sendable, Hashable {
    /// The text this document was parsed from, as given.
    public let source: String
    /// The front matter, when the text opens with one.
    public let frontMatter: FrontMatter?
    /// The body, in order. Footnote definitions are not here: they are `footnotes`.
    public let blocks: [Block]
    /// The footnotes the body refers to, in the order of their first reference; their
    /// `number` is their place in this list. A definition nothing refers to is dropped.
    public let footnotes: [Footnote]

    /// `text` parsed. `streaming` reads it as text still arriving (an agent's answer
    /// mid-stream): what is cut mid-construct is settled first (`settled(_:)`), so an
    /// unclosed `**` or backtick, a link without its `)`, or a table whose head has not
    /// arrived yet never flashes as raw syntax. An unclosed code fence needs nothing:
    /// CommonMark already runs it to the end of the text. Spans then refer to the settled
    /// text, which is the source with at most its last few characters held back or
    /// closers appended, so every span inside what was kept is the source's.
    public init(_ text: String, streaming: Bool = false) {
        source = text
        let (front, body, lineOffset) = Self.splitFrontMatter(text)
        frontMatter = front
        let parsed = Parse(streaming ? Self.settled(body) : body, lineOffset: lineOffset)
        blocks = parsed.blocks
        footnotes = parsed.footnotes
    }

    // MARK: - the tree

    /// Where a node is in the source: lines from 1, columns from 1 counted in UTF-8 bytes
    /// (cmark's own unit), the end inclusive.
    public struct Span: Sendable, Hashable, CustomStringConvertible {
        public let start: Location
        public let end: Location
        public var description: String { "\(start)-\(end)" }
    }

    public struct Location: Sendable, Hashable, Comparable, CustomStringConvertible {
        public let line: Int
        public let column: Int
        public static func < (a: Location, b: Location) -> Bool {
            (a.line, a.column) < (b.line, b.column)
        }
        public var description: String { "\(line):\(column)" }
    }

    public struct Block: Sendable, Hashable {
        public let kind: Kind
        public let span: Span

        public enum Kind: Sendable, Hashable {
            case paragraph([Inline])
            /// `level` 1 to 6.
            case heading(level: Int, [Inline])
            case quote([Block])
            case list(List)
            /// `language` is the fence's first word (```` ```swift title=x ```` →
            /// `swift`), nil for an indented block or a bare fence; `info` the whole
            /// line after the fence. `text` without the closing newline.
            case code(language: String?, info: String, text: String)
            /// Raw HTML as written: drawn as its text, never interpreted.
            case html(String)
            case table(Table)
            case rule
        }
    }

    public struct List: Sendable, Hashable {
        public let ordered: Bool
        /// The first item's number (an unordered list's is 1).
        public let start: Int
        /// A tight list's items are their words; a loose one's (a blank line between
        /// items) are paragraphs, set apart.
        public let tight: Bool
        public let items: [Item]
    }

    public struct Item: Sendable, Hashable {
        /// A task item's box: true done, false open; nil for an ordinary item.
        public let checked: Bool?
        public let blocks: [Block]
        public let span: Span
    }

    public struct Table: Sendable, Hashable {
        public enum Alignment: Sendable, Hashable { case none, leading, center, trailing }
        /// One per column.
        public let alignments: [Alignment]
        public let head: [Cell]
        public let rows: [[Cell]]
    }

    public struct Cell: Sendable, Hashable {
        public let content: [Inline]
        public let span: Span
    }

    public struct Inline: Sendable, Hashable {
        public let kind: Kind
        /// Nil where cmark does not track the position (some inlines inside links and
        /// emphasis carry none).
        public let span: Span?

        public enum Kind: Sendable, Hashable {
            case text(String)
            /// A line ending inside a paragraph: a space when drawn.
            case softBreak
            /// A hard line ending (two spaces or a backslash before it).
            case lineBreak
            case code(String)
            case emphasis([Inline])
            case strong([Inline])
            case strikethrough([Inline])
            /// `url` as written; whether it may be followed is `MarkdownDocument.link`.
            /// A bare URL or `www.` address arrives here too (an autolink).
            case link(url: String, title: String, [Inline])
            /// `alt` is the image's words.
            case image(url: String, title: String, alt: [Inline])
            /// Raw inline HTML (`<kbd>`, or a `<placeholder>` in prose): drawn as its
            /// text, never interpreted.
            case html(String)
            /// A reference to `footnotes[number - 1]`.
            case footnote(label: String, number: Int)
        }
    }

    public struct Footnote: Sendable, Hashable {
        public let label: String
        public let number: Int
        public let blocks: [Block]
        public let span: Span
    }

    public struct FrontMatter: Sendable, Hashable {
        public enum Format: Sendable, Hashable { case yaml, toml }
        public let format: Format
        /// What is between the fences.
        public let text: String
    }

    // MARK: - reading the tree

    /// A link's target when it is safe to follow, else nil: the web, mail and a phone
    /// number. Anything else (`javascript:`, `file:`, another app's scheme, a path with
    /// no page to be relative to) stays its words. ui's `safeHref`, narrowed to what an
    /// app can open: text anyone wrote is safe to draw.
    public static func link(_ url: String) -> URL? {
        let trimmed = url.trimmingCharacters(in: .whitespaces)
        guard let parsed = URL(string: trimmed), let scheme = parsed.scheme?.lowercased() else {
            return nil
        }
        return ["http", "https", "mailto", "tel"].contains(scheme) ? parsed : nil
    }

    /// The words, markup gone: inline runs joined, blocks set apart by a newline. A
    /// preview's text, an accessibility label, a search.
    public var plainText: String {
        blocks.map(\.plainText).joined(separator: "\n")
    }
}

extension MarkdownDocument.Block {
    public var plainText: String {
        switch kind {
        case .paragraph(let inlines), .heading(_, let inlines): inlines.plainText
        case .quote(let blocks): blocks.map(\.plainText).joined(separator: "\n")
        case .list(let list):
            list.items.map { $0.blocks.map(\.plainText).joined(separator: "\n") }
                .joined(separator: "\n")
        case .code(_, _, let text), .html(let text): text
        case .table(let table):
            ([table.head] + table.rows).map { $0.map(\.content.plainText).joined(separator: "\t") }
                .joined(separator: "\n")
        case .rule: ""
        }
    }
}

extension [MarkdownDocument.Inline] {
    public var plainText: String {
        map { inline in
            switch inline.kind {
            case .text(let s), .code(let s), .html(let s): s
            case .softBreak: " "
            case .lineBreak: "\n"
            case .emphasis(let c), .strong(let c), .strikethrough(let c), .link(_, _, let c),
                .image(_, _, let c):
                c.plainText
            case .footnote(_, let number): "[\(number)]"
            }
        }
        .joined()
    }
}

// MARK: - front matter

extension MarkdownDocument {
    /// The front matter, the body after it, and how many lines it took: a first line of
    /// exactly `---` (YAML) or `+++` (TOML) and a closing line of the same (`...` also
    /// closes YAML). Unclosed, it is no front matter: the text is parsed as written.
    static func splitFrontMatter(_ text: String) -> (FrontMatter?, String, Int) {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard let first = lines.first else { return (nil, text, 0) }
        let fence = first.trimmingCharacters(in: .whitespaces)
        let format: FrontMatter.Format
        switch fence {
        case "---": format = .yaml
        case "+++": format = .toml
        default: return (nil, text, 0)
        }
        let closers = format == .yaml ? ["---", "..."] : ["+++"]
        guard
            let close = lines.indices.dropFirst().first(where: {
                closers.contains(lines[$0].trimmingCharacters(in: .whitespaces))
            })
        else { return (nil, text, 0) }
        let inside = lines[1..<close].joined(separator: "\n")
        let body = lines[(close + 1)...].joined(separator: "\n")
        return (FrontMatter(format: format, text: inside), body, close + 1)
    }
}

// MARK: - the parse

/// One cmark-gfm parse, read into the value tree and freed.
private struct Parse {
    typealias Node = UnsafeMutablePointer<cmark_node>

    var blocks: [MarkdownDocument.Block] = []
    var footnotes: [MarkdownDocument.Footnote] = []
    let lineOffset: Int

    init(_ text: String, lineOffset: Int) {
        self.lineOffset = lineOffset
        cmark_gfm_core_extensions_ensure_registered()
        // Footnotes are core cmark-gfm; the rest are extensions. Two tildes for a strike
        // and no smart punctuation: see the type's comment.
        let options =
            CMARK_OPT_SOURCEPOS | CMARK_OPT_FOOTNOTES | CMARK_OPT_STRIKETHROUGH_DOUBLE_TILDE
        let parser = cmark_parser_new(options)!
        for name in ["table", "strikethrough", "tasklist", "autolink"] {
            let extensionFound = cmark_find_syntax_extension(name)
            assert(extensionFound != nil, "cmark-gfm has no \(name) extension")
            cmark_parser_attach_syntax_extension(parser, extensionFound)
        }
        var bytes = text
        bytes.withUTF8 { buffer in
            guard let base = buffer.baseAddress else { return }
            base.withMemoryRebound(to: CChar.self, capacity: buffer.count) {
                cmark_parser_feed(parser, $0, buffer.count)
            }
        }
        let root = cmark_parser_finish(parser)!
        defer {
            cmark_node_free(root)
            cmark_parser_free(parser)
        }
        for node in Self.children(root) {
            if cmark_node_get_type(node) == CMARK_NODE_FOOTNOTE_DEFINITION {
                footnotes.append(
                    MarkdownDocument.Footnote(
                        label: Self.literal(node), number: footnotes.count + 1,
                        blocks: blocks(of: node), span: span(node)!))
            } else if let block = block(node) {
                blocks.append(block)
            }
        }
    }

    static func children(_ node: Node) -> [Node] {
        var out: [Node] = []
        var child = cmark_node_first_child(node)
        while let current = child {
            out.append(current)
            child = cmark_node_next(current)
        }
        return out
    }

    static func literal(_ node: Node) -> String {
        cmark_node_get_literal(node).map { String(cString: $0) } ?? ""
    }

    static func typeName(_ node: Node) -> String {
        String(cString: cmark_node_get_type_string(node))
    }

    func span(_ node: Node) -> MarkdownDocument.Span? {
        let line = Int(cmark_node_get_start_line(node))
        guard line > 0 else { return nil }
        return MarkdownDocument.Span(
            start: .init(line: line + lineOffset, column: Int(cmark_node_get_start_column(node))),
            end: .init(
                line: Int(cmark_node_get_end_line(node)) + lineOffset,
                column: Int(cmark_node_get_end_column(node))))
    }

    func blocks(of node: Node) -> [MarkdownDocument.Block] {
        Self.children(node).compactMap(block)
    }

    func block(_ node: Node) -> MarkdownDocument.Block? {
        // Every block cmark makes has a position (SOURCEPOS is on).
        let at = span(node)!
        let kind: MarkdownDocument.Block.Kind
        switch cmark_node_get_type(node) {
        case CMARK_NODE_PARAGRAPH: kind = .paragraph(inlines(of: node))
        case CMARK_NODE_HEADING:
            kind = .heading(level: Int(cmark_node_get_heading_level(node)), inlines(of: node))
        case CMARK_NODE_BLOCK_QUOTE: kind = .quote(blocks(of: node))
        case CMARK_NODE_LIST: kind = .list(list(node))
        case CMARK_NODE_CODE_BLOCK:
            let info = cmark_node_get_fence_info(node).map { String(cString: $0) } ?? ""
            let language = info.split(whereSeparator: \.isWhitespace).first.map(String.init)
            var text = Self.literal(node)
            if text.hasSuffix("\n") { text.removeLast() }
            kind = .code(language: language, info: info, text: text)
        case CMARK_NODE_HTML_BLOCK:
            var text = Self.literal(node)
            if text.hasSuffix("\n") { text.removeLast() }
            kind = .html(text)
        case CMARK_NODE_THEMATIC_BREAK: kind = .rule
        default:
            switch Self.typeName(node) {
            case "table": kind = .table(table(node))
            default:
                assertionFailure(
                    "markdown: a block cmark made that the tree has no place for: \(Self.typeName(node))"
                )
                return nil
            }
        }
        return MarkdownDocument.Block(kind: kind, span: at)
    }

    func list(_ node: Node) -> MarkdownDocument.List {
        let ordered = cmark_node_get_list_type(node) == CMARK_ORDERED_LIST
        let items = Self.children(node).map { item in
            MarkdownDocument.Item(
                checked: Self.typeName(item) == "tasklist"
                    ? cmark_gfm_extensions_get_tasklist_item_checked(item) : nil,
                blocks: blocks(of: item), span: span(item)!)
        }
        return MarkdownDocument.List(
            ordered: ordered, start: ordered ? Int(cmark_node_get_list_start(node)) : 1,
            tight: cmark_node_get_list_tight(node) != 0, items: items)
    }

    func table(_ node: Node) -> MarkdownDocument.Table {
        let columns = Int(cmark_gfm_extensions_get_table_columns(node))
        let raw = cmark_gfm_extensions_get_table_alignments(node)
        let alignments: [MarkdownDocument.Table.Alignment] = (0..<columns).map { column in
            switch raw.map({ UnicodeScalar($0[column]) }) {
            case "l": .leading
            case "c": .center
            case "r": .trailing
            default: .none
            }
        }
        var head: [MarkdownDocument.Cell] = []
        var rows: [[MarkdownDocument.Cell]] = []
        for row in Self.children(node) {
            let cells = Self.children(row).map {
                MarkdownDocument.Cell(content: inlines(of: $0), span: span($0)!)
            }
            if cmark_gfm_extensions_get_table_row_is_header(row) != 0 {
                head = cells
            } else {
                rows.append(cells)
            }
        }
        return MarkdownDocument.Table(alignments: alignments, head: head, rows: rows)
    }

    func inlines(of node: Node) -> [MarkdownDocument.Inline] {
        var out: [MarkdownDocument.Inline] = []
        for child in Self.children(node) {
            guard let next = inline(child) else { continue }
            // cmark splits a run of words at every character that might have opened
            // something (`[`, `!`, `_`); the tree holds the run whole.
            if case .text(let more) = next.kind, let last = out.last,
                case .text(let words) = last.kind
            {
                let joined: MarkdownDocument.Span? =
                    if let a = last.span, let b = next.span {
                        .init(start: a.start, end: b.end)
                    } else { nil }
                out[out.count - 1] = .init(kind: .text(words + more), span: joined)
            } else {
                out.append(next)
            }
        }
        return out
    }

    func inline(_ node: Node) -> MarkdownDocument.Inline? {
        let kind: MarkdownDocument.Inline.Kind
        switch cmark_node_get_type(node) {
        case CMARK_NODE_TEXT: kind = .text(Self.literal(node))
        case CMARK_NODE_SOFTBREAK: kind = .softBreak
        case CMARK_NODE_LINEBREAK: kind = .lineBreak
        case CMARK_NODE_CODE: kind = .code(Self.literal(node))
        case CMARK_NODE_HTML_INLINE: kind = .html(Self.literal(node))
        case CMARK_NODE_EMPH: kind = .emphasis(inlines(of: node))
        case CMARK_NODE_STRONG: kind = .strong(inlines(of: node))
        case CMARK_NODE_LINK:
            kind = .link(url: Self.url(node), title: Self.title(node), inlines(of: node))
        case CMARK_NODE_IMAGE:
            kind = .image(url: Self.url(node), title: Self.title(node), alt: inlines(of: node))
        case CMARK_NODE_FOOTNOTE_REFERENCE:
            // cmark has numbered it (its literal) and points it at its definition, whose
            // literal is the label.
            let definition = cmark_node_parent_footnote_def(node)!
            kind = .footnote(label: Self.literal(definition), number: Int(Self.literal(node))!)
        default:
            switch Self.typeName(node) {
            case "strikethrough": kind = .strikethrough(inlines(of: node))
            default:
                assertionFailure(
                    "markdown: an inline cmark made that the tree has no place for: \(Self.typeName(node))"
                )
                return nil
            }
        }
        return MarkdownDocument.Inline(kind: kind, span: span(node))
    }

    static func url(_ node: Node) -> String {
        cmark_node_get_url(node).map { String(cString: $0) } ?? ""
    }

    static func title(_ node: Node) -> String {
        cmark_node_get_title(node).map { String(cString: $0) } ?? ""
    }
}
