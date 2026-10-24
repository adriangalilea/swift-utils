import GitKit
import SwiftUI

/// How a diff is set, carried by the environment so a parent says it once for every
/// diff under it: `.diffStyle(.split)`, `.diffWrap(false)`, `.diffMaxLines(12)`,
/// `.onQuote { … }`. A `DiffView` with none of them is a good default anywhere.
public struct DiffOptions: Sendable {
    /// Unified (one column, removed above added), split (old left, new right), or auto:
    /// split once the width holds two columns of code at a readable measure.
    public enum Style: String, Sendable, Hashable, CaseIterable { case auto, unified, split }

    public var style: Style = .auto
    /// Long lines wrap (true) or run on and scroll sideways (false).
    public var wrap: Bool = true
    /// Unchanged lines kept around each change; a longer run folds behind "N more lines".
    /// It is also the context a diff computed from two texts is cut with.
    public var context: Int = 3
    /// Lines shown before the rest folds behind "Show N more lines" (a card, a preview).
    /// Nil shows everything.
    public var maxLines: Int?
    public var lineNumbers: Visibility = .automatic
    /// The file's header (path, status, counts): automatic shows it when there is a path.
    public var header: Visibility = .automatic
    public var syntax: Bool = true
    /// The code's size in points; nil follows the platform's text style and the reader's
    /// Dynamic Type size.
    public var fontSize: CGFloat?
    /// Whether a file starts folded down to its header.
    public var collapsed: Bool = false
    /// An inline diff draws its own well (a hairline frame, the header on a band); off
    /// when the host's card is the frame.
    public var framed: Bool = true

    public init() {}
}

/// What a quote does is the host's: put it in a reply box, copy it, send it.
public struct DiffQuoteAction: Sendable {
    let perform: @MainActor @Sendable (DiffQuote) -> Void
    public init(_ perform: @escaping @MainActor @Sendable (DiffQuote) -> Void) {
        self.perform = perform
    }
    @MainActor public func callAsFunction(_ quote: DiffQuote) { perform(quote) }
}

/// A file's text as the diff's new side has it, for the lines a diff left out between
/// its hunks: set by a host that can read it (`GitBrowser` from its source).
public struct DiffContentsAction: Sendable {
    let read: @Sendable (Git.FileDiff) async throws -> String
    public init(_ read: @escaping @Sendable (Git.FileDiff) async throws -> String) {
        self.read = read
    }
}

/// What opening a submodule's pointer change does (a host drills into its repository).
public struct DiffSubmoduleAction: Sendable {
    let perform: @MainActor @Sendable (_ path: String, _ pointer: Git.FileDiff.Pointer) -> Void
    public init(_ perform: @escaping @MainActor @Sendable (String, Git.FileDiff.Pointer) -> Void) {
        self.perform = perform
    }
}

extension EnvironmentValues {
    @Entry public var diffOptions = DiffOptions()
    /// Set by `.onQuote`; without it a diff offers "Copy as Markdown" in its place.
    @Entry public var diffQuote: DiffQuoteAction? = nil
    @Entry public var diffOpenSubmodule: DiffSubmoduleAction? = nil
    /// Set by `.diffContents`; without it, the lines between hunks stay a count.
    @Entry public var diffContents: DiffContentsAction? = nil
}

extension View {
    public func diffStyle(_ style: DiffOptions.Style) -> some View {
        transformEnvironment(\.diffOptions) { $0.style = style }
    }

    public func diffWrap(_ wrap: Bool = true) -> some View {
        transformEnvironment(\.diffOptions) { $0.wrap = wrap }
    }

    public func diffContext(lines: Int) -> some View {
        transformEnvironment(\.diffOptions) { $0.context = max(0, lines) }
    }

    /// Show at most `lines` lines, the rest behind "Show N more lines": a card, a preview.
    public func diffMaxLines(_ lines: Int?) -> some View {
        transformEnvironment(\.diffOptions) { $0.maxLines = lines.map { max(1, $0) } }
    }

    public func diffLineNumbers(_ visibility: Visibility) -> some View {
        transformEnvironment(\.diffOptions) { $0.lineNumbers = visibility }
    }

    public func diffHeader(_ visibility: Visibility) -> some View {
        transformEnvironment(\.diffOptions) { $0.header = visibility }
    }

    public func diffSyntaxHighlighting(_ enabled: Bool) -> some View {
        transformEnvironment(\.diffOptions) { $0.syntax = enabled }
    }

    public func diffFontSize(_ size: CGFloat?) -> some View {
        transformEnvironment(\.diffOptions) { $0.fontSize = size }
    }

    /// Files start folded down to their headers.
    public func diffCollapsed(_ collapsed: Bool = true) -> some View {
        transformEnvironment(\.diffOptions) { $0.collapsed = collapsed }
    }

    /// Whether an inline diff draws its own well; off when a card around it is the frame.
    public func diffFramed(_ framed: Bool) -> some View {
        transformEnvironment(\.diffOptions) { $0.framed = framed }
    }

    /// Where a file's text comes from, so a hunk's `N lines above` opens on a tap: the
    /// file as the diff's new side has it.
    public func diffContents(
        _ read: @escaping @Sendable (_ file: Git.FileDiff) async throws -> String
    ) -> some View {
        environment(\.diffContents, DiffContentsAction(read))
    }

    /// What tapping a submodule's pointer change does.
    public func onOpenSubmodule(
        perform action:
            @escaping @MainActor @Sendable (_ path: String, _ pointer: Git.FileDiff.Pointer) -> Void
    ) -> some View {
        environment(\.diffOpenSubmodule, DiffSubmoduleAction(action))
    }

    /// What Quote does with a selection, a hunk or a file. Without it, a diff offers
    /// "Copy as Markdown" in its place.
    public func onQuote(perform action: @escaping @MainActor @Sendable (DiffQuote) -> Void)
        -> some View
    {
        environment(\.diffQuote, DiffQuoteAction(action))
    }
}
