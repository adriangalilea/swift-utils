import GitKit
import Ink
import SwiftUI
import Syntax

/// A diff, drawn. One line anywhere: in a markdown answer, a tool call's row, a card, a
/// list, a page:
///
/// ```swift
/// DiffView(unified: patch)                        // git's output or a fragment
/// DiffView(old: before, new: after, path: "a.swift")  // computed here
/// DiffView(file)                                  // a parsed Git.FileDiff
/// DiffView(diff)                                  // every file of a Git.Diff
/// ```
///
/// It sizes itself to its content like a code block and scrolls only sideways (lines that
/// run on, when `.diffWrap(false)`), so it sits in a `ScrollView`, a `List` or a card; a
/// whole screen of it is `DiffPage`, the same diff in a scroll view of its own. Everything
/// else is the environment's (`DiffOptions`): `.diffStyle(.split)`, `.diffWrap(false)`,
/// `.diffContext(lines:)`, `.diffMaxLines(8)`, `.diffLineNumbers(.hidden)`,
/// `.onQuote { quote in … }`. Text in, no setup, no async: a small diff is read and
/// colored in the frame that shows it, a big one off the main thread.
///
/// A tap selects a line, a second tap extends to it (shift-click on a Mac); the selection
/// offers Copy and Quote right under it. A long press (a right click) offers the same for
/// a line, its hunk, or the file.
public struct DiffView: View {
    let input: DiffInput

    public init(_ diff: Git.Diff) { input = DiffInput(.diff(diff)) }
    public init(_ file: Git.FileDiff) { input = DiffInput(.file(file)) }

    /// git's output (`git diff`, `git show`, a `.patch`), or a fragment someone wrote: a
    /// few `+`/`-` lines with or without `@@`. `path` names it (and picks its language)
    /// when the text does not.
    public init(unified: String, path: String? = nil) {
        input = DiffInput(.unified(unified, path: path))
    }

    /// The diff of two texts, computed here: what an edit's old string became. Line numbers
    /// count from `startLine` when the texts are a fragment further down their file.
    public init(old: String, new: String, path: String? = nil, startLine: Int = 1) {
        input = DiffInput(.texts(old: old, new: new, path: path, startLine: startLine))
    }

    public var body: some View {
        DiffSurface(input: input, page: false)
    }
}

/// A diff that is the whole screen: `DiffView` in a scroll view of its own, lazy for any
/// length (a 10,000-line diff scrolls as smoothly as ten), file headers pinned while
/// their file is in view, long lines scrolled sideways together when not wrapped, and the
/// style and wrap switches in the toolbar.
public struct DiffPage: View {
    let input: DiffInput
    @Environment(\.diffOptions) private var options
    @State private var style: DiffOptions.Style?
    @State private var wrap: Bool?

    public init(_ diff: Git.Diff) { input = DiffInput(.diff(diff)) }
    public init(_ file: Git.FileDiff) { input = DiffInput(.file(file)) }
    public init(unified: String, path: String? = nil) {
        input = DiffInput(.unified(unified, path: path))
    }
    public init(old: String, new: String, path: String? = nil, startLine: Int = 1) {
        input = DiffInput(.texts(old: old, new: new, path: path, startLine: startLine))
    }

    public var body: some View {
        DiffSurface(input: input, page: true)
            .diffStyle(style ?? options.style)
            .diffWrap(wrap ?? options.wrap)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    DiffControls(
                        style: Binding(get: { style ?? options.style }, set: { style = $0 }),
                        wrap: Binding(get: { wrap ?? options.wrap }, set: { wrap = $0 }))
                }
            }
    }
}

/// The two switches a reader of a diff reaches for: one column or two, and whether long
/// lines wrap. For a host that keeps them in its own state (`.diffStyle($style)`).
public struct DiffControls: View {
    @Binding var style: DiffOptions.Style
    @Binding var wrap: Bool

    public init(style: Binding<DiffOptions.Style>, wrap: Binding<Bool>) {
        _style = style
        _wrap = wrap
    }

    public var body: some View {
        Menu {
            Picker(selection: $style) {
                Label("Automatic", systemImage: "rectangle.split.2x1.slash").tag(
                    DiffOptions.Style.auto)
                Label("Unified", systemImage: "rectangle").tag(DiffOptions.Style.unified)
                Label("Side by Side", systemImage: "rectangle.split.2x1").tag(
                    DiffOptions.Style.split)
            } label: {
                Text("Layout")
            }
            .pickerStyle(.inline)
            Toggle(isOn: $wrap) { Label("Wrap Lines", systemImage: "text.word.spacing") }
        } label: {
            Label(
                "Diff Options",
                systemImage: style == .split ? "rectangle.split.2x1" : "text.alignleft")
        }
        .accessibilityLabel("Diff options")
    }
}

// MARK: - the surface

/// What a reader did to a diff: folded files and hunks, opened folds, the preview opened,
/// the lines selected. Lives with the view; nothing of it is the diff's.
@MainActor @Observable final class DiffState {
    var toggledFiles: Set<String> = []
    var collapsedHunks: [String: Set<Int>] = [:]
    var expandedFolds: [String: Set<Int>] = [:]
    var showAll = false
    var selection: DiffSelection?
    /// Bumped when work finished off the main thread lands in the store.
    var arrivals = 0
    #if os(macOS) || os(iOS)
        let copy = CopyFeedback()
    #endif
}

struct DiffSelection: Equatable {
    var file: String
    var anchor: Int
    var head: Int
    var range: ClosedRange<Int> { min(anchor, head)...max(anchor, head) }
}

struct DiffSurface: View {
    let input: DiffInput
    let page: Bool
    @Environment(\.diffOptions) private var options
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var state = DiffState()
    @State private var width: CGFloat = 0
    @State private var scrollX: CGFloat = 0

    private var documentKey: Int {
        var hasher = Hasher()
        hasher.combine(input.key)
        hasher.combine(options.context)
        return hasher.finalize()
    }

    /// Read now when small (the frame that shows it has it), else nil until `.task` has
    /// read it off the main thread.
    private var document: DiffDocument? {
        _ = state.arrivals
        if let known = DiffStore.shared.document(documentKey) { return known }
        guard input.size <= 1_500 else { return nil }
        let made = DiffDocument(input, context: options.context)
        DiffStore.shared.remember(made)
        return made
    }

    var body: some View {
        let metrics = DiffMetrics.of(size: options.fontSize, typeSize)
        let palette = DiffPalette.of(scheme)
        Group {
            if let document {
                if document.files.isEmpty {
                    GitStateView(.empty(title: "No changes", message: nil))
                        .frame(maxWidth: .infinity, minHeight: page ? 240 : 64)
                } else if page {
                    pageBody(document, metrics, palette)
                } else {
                    inlineBody(document, metrics, palette)
                }
            } else {
                GitStateView(.loading("Reading the diff"))
                    .frame(maxWidth: .infinity, minHeight: page ? 240 : 64)
            }
        }
        .onGeometryChange(for: CGFloat.self) {
            $0.size.width
        } action: {
            width = $0
        }
        .task(id: documentKey) {
            guard DiffStore.shared.document(documentKey) == nil else { return }
            let input = input
            let context = options.context
            let made = await Task.detached(priority: .userInitiated) {
                DiffDocument(input, context: context)
            }.value
            DiffStore.shared.remember(made)
            state.arrivals += 1
        }
    }

    private func layout(_ metrics: DiffMetrics) -> DiffLayout {
        let split =
            switch options.style {
            case .split: true
            case .unified: false
            case .auto: width >= max(900, metrics.advance * 130)
            }
        return DiffLayout(
            split: split, wrap: options.wrap, numbers: options.lineNumbers != .hidden,
            twoColumns: !split && width >= 560, width: width, page: page)
    }

    /// The files a preview shows, each with the lines it may still draw; the file where
    /// the budget runs out also counts the lines of every file after it.
    private func previewed(_ document: DiffDocument) -> [(
        file: RenderedFile, budget: Int?, after: Int
    )] {
        guard let limit = options.maxLines, !state.showAll else {
            return document.files.map { ($0, nil, 0) }
        }
        var out: [(file: RenderedFile, budget: Int?, after: Int)] = []
        var left = limit
        for (index, file) in document.files.enumerated() {
            let rest = document.files[(index + 1)...].reduce(0) { $0 + $1.lines.count }
            if left <= file.lines.count || rest == 0 {
                out.append((file, left, left <= file.lines.count ? rest : 0))
                break
            }
            out.append((file, left, 0))
            left -= file.lines.count
        }
        return out
    }

    @ViewBuilder
    private func inlineBody(
        _ document: DiffDocument, _ metrics: DiffMetrics, _ palette: DiffPalette
    ) -> some View {
        let layout = layout(metrics)
        VStack(alignment: .leading, spacing: .inkGap) {
            ForEach(previewed(document), id: \.file.id) { item in
                DiffFileView(
                    file: item.file, state: state, layout: layout.fitting(item.file),
                    metrics: metrics, palette: palette,
                    budget: item.budget, after: item.after, scrollX: 0
                )
                .modifier(DiffWell(framed: options.framed, palette: palette))
            }
        }
    }

    private func pageBody(_ document: DiffDocument, _ metrics: DiffMetrics, _ palette: DiffPalette)
        -> some View
    {
        let layout = layout(metrics)
        let columns = document.files.map { $0.columns }.max() ?? 0
        let content = layout.contentWidth(
            columns: columns, digits: document.files.map(\.digits).max() ?? 2, metrics)
        return ScrollView(layout.wrap ? .vertical : [.vertical, .horizontal]) {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(document.files) { file in
                    DiffFileView(
                        file: file, state: state, layout: layout.fitting(file), metrics: metrics,
                        palette: palette,
                        budget: nil, after: 0, scrollX: layout.wrap ? 0 : scrollX)
                }
            }
            .frame(width: layout.wrap ? nil : max(content, width), alignment: .leading)
            .padding(.bottom, 24)
        }
        .onScrollGeometryChange(for: CGFloat.self) {
            $0.contentOffset.x
        } action: { _, x in
            if !layout.wrap { scrollX = max(0, x) }
        }
    }
}

/// The decisions a file's rows share, made once per frame from the width and options.
struct DiffLayout: Equatable {
    var split: Bool
    var wrap: Bool
    var numbers: Bool
    /// Unified with both numbers (old and new) rather than one.
    var twoColumns: Bool
    var width: CGFloat
    var page: Bool

    static let markerColumns: CGFloat = 2

    /// A file only added to or only removed from has nothing to set beside it: split
    /// would leave half the width empty, so it stays unified.
    func fitting(_ file: RenderedFile) -> DiffLayout {
        guard split, file.file.additions == 0 || file.file.deletions == 0 else { return self }
        var copy = self
        copy.split = false
        copy.twoColumns = width >= 560
        return copy
    }

    func numberWidth(_ digits: Int, _ metrics: DiffMetrics) -> CGFloat {
        (metrics.advance * 0.92 * CGFloat(digits) + metrics.advance * 2).rounded(.up)
    }

    func gutterWidth(_ file: RenderedFile, _ metrics: DiffMetrics) -> CGFloat {
        guard numbers, file.hasNumbers else { return metrics.advance }
        return numberWidth(file.digits, metrics) * (twoColumns && !split ? 2 : 1)
    }

    /// The width that holds the longest line, for a page whose lines do not wrap.
    func contentWidth(columns: Int, digits: Int, _ metrics: DiffMetrics) -> CGFloat {
        let code = metrics.width(columns) + metrics.advance * Self.markerColumns + 24
        let gutter = numbers ? numberWidth(digits, metrics) * (twoColumns && !split ? 2 : 1) : 0
        return split ? 2 * (gutter + code) + 1 : gutter + code
    }
}

/// An inline diff's own well: the code block's frame (a faint wash, a hairline, rounded)
/// unless the host's card is the frame.
struct DiffWell: ViewModifier {
    let framed: Bool
    let palette: DiffPalette

    func body(content: Content) -> some View {
        if framed {
            content
                .background(palette.wash.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(
                        palette.hairline, lineWidth: 1))
        } else {
            content
        }
    }
}

// MARK: - one file

struct DiffFileView: View {
    let file: RenderedFile
    let state: DiffState
    let layout: DiffLayout
    let metrics: DiffMetrics
    let palette: DiffPalette
    let budget: Int?
    /// Lines of the files after this one a preview leaves out.
    let after: Int
    let scrollX: CGFloat
    @Environment(\.diffOptions) private var options
    @Environment(\.colorScheme) private var scheme
    @Environment(\.diffQuote) private var quote

    private var collapsed: Bool { options.collapsed != state.toggledFiles.contains(file.id) }

    private var showsHeader: Bool {
        switch options.header {
        case .hidden: false
        case .visible: true
        default: !file.file.path.isEmpty
        }
    }

    /// The painted lines: from the store, painted now when the file is small, else plain
    /// until `.task` has painted it off the main thread.
    private var painted: [AttributedString]? {
        _ = state.arrivals
        let key = DiffStore.paintKey(file, scheme, options.syntax)
        if let known = DiffStore.shared.painted(key) { return known }
        guard file.lines.count <= 160 else { return nil }
        let made = DiffPainter.paint(
            file, palette: palette, appearance: Syntax.Appearance(scheme), syntax: options.syntax)
        DiffStore.shared.remember(key, made)
        return made
    }

    var body: some View {
        let key = DiffStore.paintKey(file, scheme, options.syntax)
        Group {
            if layout.page {
                Section {
                    if !collapsed { rowsView }
                } header: {
                    if showsHeader { header.offset(x: scrollX) }
                }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    if showsHeader {
                        header
                        if !collapsed { Rectangle().fill(palette.hairline).frame(height: 1) }
                    }
                    if !collapsed {
                        if layout.wrap {
                            rowsView
                        } else {
                            ScrollView(.horizontal) {
                                rowsView
                                    .frame(
                                        minWidth: max(
                                            layout.width,
                                            layout.contentWidth(
                                                columns: file.columns, digits: file.digits, metrics)
                                        ),
                                        alignment: .leading)
                            }
                            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
                        }
                    }
                }
            }
        }
        .task(id: key) {
            guard DiffStore.shared.painted(key) == nil else { return }
            let file = file
            let palette = palette
            let appearance = Syntax.Appearance(scheme)
            let syntax = options.syntax
            let made = await Task.detached(priority: .userInitiated) {
                DiffPainter.paint(file, palette: palette, appearance: appearance, syntax: syntax)
            }.value
            DiffStore.shared.remember(key, made)
            state.arrivals += 1
        }
    }

    private var header: some View {
        DiffFileHeader(
            file.file,
            collapsed: Binding(
                get: { collapsed },
                set: { _ in
                    withAnimation(.inkSettle) {
                        if state.toggledFiles.contains(file.id) {
                            state.toggledFiles.remove(file.id)
                        } else {
                            state.toggledFiles.insert(file.id)
                        }
                    }
                })
        )
        .padding(.horizontal, layout.page ? 16 : 12)
        .padding(.vertical, layout.page ? 10 : 8)
        .frame(width: layout.page && !layout.wrap ? layout.width : nil)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if layout.page {
                Group {
                    #if os(tvOS)
                        Rectangle().fill(.regularMaterial)
                    #else
                        Rectangle().fill(.bar)
                    #endif
                }
                .overlay(alignment: .bottom) { Rectangle().fill(palette.hairline).frame(height: 1) }
            } else {
                palette.wash
            }
        }
        .contextMenu { fileMenu }
    }

    @ViewBuilder private var fileMenu: some View {
        DiffMenuItems(
            copy: [("Copy Path", file.file.path), ("Copy Diff", unified(file.file))],
            quote: DiffQuote.file(file.file), quoteTitle: "Quote File", action: quote)
    }

    private var plan: DiffRowPlan {
        var plan = DiffRowPlan(split: layout.split, context: options.context)
        plan.collapsedHunks = state.collapsedHunks[file.id] ?? []
        plan.expandedFolds = state.expandedFolds[file.id] ?? []
        plan.budget = budget
        plan.after = after
        if let selection = state.selection, selection.file == file.id {
            plan.selection = selection.range
            plan.actions = true
        }
        return plan
    }

    @ViewBuilder private var rowsView: some View {
        let rows = plan.rows(file).rows
        let painted = painted
        let selected = state.selection?.file == file.id ? state.selection?.range : nil
        let gutter = layout.gutterWidth(file, metrics)
        let content = ForEach(rows, id: \.self) { row in
            DiffRowView(
                row: row, file: file, painted: painted, selected: selected, layout: layout,
                metrics: metrics,
                palette: palette, gutter: gutter, state: state)
        }
        if layout.page || rows.count > 400 {
            LazyVStack(alignment: .leading, spacing: 0) { content }
        } else {
            VStack(alignment: .leading, spacing: 0) { content }
        }
    }

    private func unified(_ file: Git.FileDiff) -> String {
        file.hunks.map { ([$0.header] + $0.lines.map(\.unified)).joined(separator: "\n") }.joined(
            separator: "\n")
    }
}

/// Copy items and the quote item (or "Copy as Markdown" when the host set no quote).
struct DiffMenuItems: View {
    let copy: [(String, String)]
    let quote: DiffQuote
    let quoteTitle: String
    let action: DiffQuoteAction?

    var body: some View {
        if let action {
            Button(quoteTitle, systemImage: "text.quote") { action(quote) }
        }
        ForEach(copy, id: \.0) { title, value in
            Button(title, systemImage: "doc.on.doc") { DiffPasteboard.copy(value) }
        }
        if action == nil {
            Button("Copy as Markdown", systemImage: "text.quote") {
                DiffPasteboard.copy(quote.markdown)
            }
        }
    }
}

enum DiffPasteboard {
    @MainActor static func copy(_ text: String) {
        #if os(macOS)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        #elseif os(iOS)
            UIPasteboard.general.string = text
        #endif
    }
}
