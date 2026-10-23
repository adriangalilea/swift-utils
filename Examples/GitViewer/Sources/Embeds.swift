import GitKit
import GitViews
import Ink
import MarkdownText
import SwiftUI

/// The same diff component in the three places a host puts it, each one line.
struct EmbedDetail: View {
    let embed: Embed

    var body: some View {
        switch embed {
        case .markdown:
            ScrollView {
                MarkdownViewBox(text: Samples.answer)
                    .padding(20)
                    .frame(maxWidth: 760, alignment: .leading)
                    .frame(maxWidth: .infinity)
            }
            .navigationTitle("Markdown")
        case .cards:
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Samples.edits, id: \.path) { edit in
                        ToolCallCard(edit: edit)
                    }
                }
                .padding(16)
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Tool calls")
        case .page:
            // The whole screen: one line, any length.
            DiffPage(old: Samples.long.old, new: Samples.long.new, path: "Generated.swift")
                .navigationTitle("10,000 lines")
        }
    }
}

struct MarkdownViewBox: View {
    let text: String
    var body: some View { MarkdownView(text) }
}

/// A conversation's Edit call: what the agent did, then the edit as a diff cut to a
/// preview, the card being its frame.
struct ToolCallCard: View {
    let edit: Samples.Edit

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "pencil.line").foregroundStyle(.secondary)
                Text("Edit").font(.callout.weight(.semibold))
                GitPathLabel(edit.path)
                Spacer()
            }
            DiffView(old: edit.old, new: edit.new, path: edit.path, startLine: edit.line)
                .diffMaxLines(6)
                .diffHeader(.hidden)
        }
        .padding(12)
        .background(.inkGroup, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

enum Samples {
    struct Edit {
        let path: String
        let line: Int
        let old: String
        let new: String
    }

    static let answer = """
        Done. The middle cut now keeps six characters by default, and its docs say why:

        ```diff
        diff --git a/Sources/Ink/MiddleTruncate.swift b/Sources/Ink/MiddleTruncate.swift
        index f1da1a5..f49e861 100644
        --- a/Sources/Ink/MiddleTruncate.swift
        +++ b/Sources/Ink/MiddleTruncate.swift
        @@ -6,7 +6,7 @@ import SwiftUI
         /// `.truncationMode(.middle)` cuts at the exact centre, so how much of the end
         /// survives depends on the width.
         ///
        -/// `tail` says what stays whole: a count of characters (`tail: 6` for a hash), or a
        +/// `tail` says what stays whole: a count of characters (`tail: 6`, the default: a short hash), or a
         /// separator, everything from its last occurrence (`tail: "/"` keeps a path's file,
         /// `"."` an extension). A separator the text does not hold guarantees no tail: the
         /// text cuts at its end. The tail is a promise: wider than the room, it overflows.
        @@ -32,7 +32,7 @@ public struct MiddleTruncate: View {
             let text: String
             let tail: Tail

        -    public init(_ text: String, tail: Tail = 4) {
        +    public init(_ text: String, tail: Tail = 6) {
                 self.text = text
                 self.tail = tail
             }
        ```

        A fragment without headers reads too:

        ```diff
        -let tail: Tail = 4
        +let tail: Tail = 6
        ```

        `swift test` passes, 25 tests.
        """

    static let edits = [
        Edit(
            path: "Sources/Totals.swift", line: 12,
            old: "func total(_ items: [Item]) -> Int {\n    items.reduce(0) { $0 + $1.count }\n}\n",
            new:
                "func total(_ items: [Item]) -> Int {\n    // Only the visible ones count.\n    items.filter(\\.visible).reduce(0) { $0 + $1.count }\n}\n"
        ),
        Edit(
            path: "Sources/Ink/InkBadge.swift", line: 1,
            old: "",
            new: """
                import SwiftUI

                /// A count on a quiet capsule: how many things wait behind a row.
                public struct InkBadge: View {
                    let count: Int

                    public init(_ count: Int) { self.count = count }

                    public var body: some View {
                        Text(verbatim: "\\(count)")
                            .font(.caption2.weight(.semibold).monospacedDigit())
                            .padding(.horizontal, .inkTight)
                            .background(.inkRaised, in: Capsule())
                    }
                }

                """),
        Edit(
            path: "README.md", line: 3,
            old: "Swift utilities for mac apps. One repo, multiple products, each module links only if imported.\n",
            new: "Swift utilities for Mac and iPhone apps. One repo, many products, each module linked only when imported.\n"
        ),
    ]

    /// A generated file of 10,000 lines with an edit every 7th: the page's scroll test.
    static let long: (old: String, new: String) = {
        var old: [String] = []
        var new: [String] = []
        for index in 1...10_000 {
            let line = "    let value\(index) = compute(\(index), scale: 2) // step \(index)"
            old.append(line)
            new.append(
                index % 7 == 0 ? "    let value\(index) = compute(\(index), scale: 3, clamp: true) // step \(index)" : line)
        }
        return (old.joined(separator: "\n") + "\n", new.joined(separator: "\n") + "\n")
    }()
}
