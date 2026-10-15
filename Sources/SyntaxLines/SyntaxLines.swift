import SwiftUI

/// What a requester SAID its review body is ("shell", "diff", "text"):
/// the one vocabulary every surface colors by. Anything unrecognized is
/// plain, never an error.
public enum CodeFormat: String, Sendable, Codable {
    case shell
    case diff
    case plain = "text"

    public init(_ raw: String?) {
        self = raw.flatMap(CodeFormat.init(rawValue:)) ?? .plain
    }
}

/// Coloring that needs no grammar engine: a diff by its line prefixes
/// (green added, red removed, `@@` headers muted; our diff format is ours
/// and its semantics are exact), everything else as written. What a
/// surface without JavaScriptCore draws (a widget, a Live Activity: tight
/// memory, no engine); `Syntax` builds its grammar pass on top. Coloring
/// never rewrites a character.
public enum SyntaxLines {
    public static func color(_ text: String, as format: CodeFormat) -> AttributedString {
        format == .diff ? diff(text) : AttributedString(text)
    }

    public static func diff(_ text: String) -> AttributedString {
        var out = AttributedString()
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        for (index, line) in lines.enumerated() {
            var run = AttributedString(String(line))
            if line.hasPrefix("+") {
                run.foregroundColor = .green
            } else if line.hasPrefix("-") {
                run.foregroundColor = .red
            } else if line.hasPrefix("@@") {
                run.foregroundColor = .secondary
            }
            out += run
            if index < lines.count - 1 { out += AttributedString("\n") }
        }
        return out
    }
}

/// A short excerpt of a review body for a glance (a Live Activity, a
/// widget): monospaced, line-colored, at most `lines` lines, with a shell
/// command marked by its prompt so it reads as something that will run.
/// The host brings the chrome; the full body belongs to a surface with
/// room (`SyntaxText`).
public struct CodeExcerpt: View {
    private let text: String
    private let format: CodeFormat
    private let lines: Int
    private let font: Font

    public init(
        _ text: String, format: CodeFormat, lines: Int = 3,
        font: Font = .system(.caption, design: .monospaced)
    ) {
        self.text = text
        self.format = format
        self.lines = lines
        self.font = font
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if format == .shell {
                Text("$").foregroundStyle(.secondary)
            }
            Text(SyntaxLines.color(text, as: format))
                .lineLimit(lines)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(font)
    }
}
