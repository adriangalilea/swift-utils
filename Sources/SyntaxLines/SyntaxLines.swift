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

/// A grammar coloring as data: computed where the engine runs (`Syntax`,
/// JavaScriptCore) and painted where it cannot (a Live Activity, a widget),
/// so both show the same inks. `palette` is `#rrggbb` inks; `runs` covers
/// the text in order, each `[characters, ink]` (ink -1 = the host's color).
/// Small by construction: a few hundred bytes for a glance's excerpt.
public struct CodeColors: Codable, Hashable, Sendable {
    public var palette: [String]
    public var runs: [[Int]]
    public init(palette: [String], runs: [[Int]]) {
        self.palette = palette
        self.runs = runs
    }

    /// `text` painted with these inks; nil when they do not cover it
    /// exactly (colors for other text are never applied).
    public func paint(_ text: String) -> AttributedString? {
        guard runs.reduce(0, { $0 + $1[0] }) == text.count else { return nil }
        var out = AttributedString()
        var rest = Substring(text)
        for run in runs {
            var piece = AttributedString(String(rest.prefix(run[0])))
            rest = rest.dropFirst(run[0])
            if run[1] >= 0, run[1] < palette.count, let color = Color(hex: palette[run[1]]) {
                piece.foregroundColor = color
            }
            out += piece
        }
        return out
    }
}

extension Color {
    /// `#rrggbb`.
    init?(hex: String) {
        guard hex.count == 7, hex.hasPrefix("#"), let value = UInt32(hex.dropFirst(), radix: 16)
        else { return nil }
        self.init(
            red: Double((value >> 16) & 0xff) / 255, green: Double((value >> 8) & 0xff) / 255,
            blue: Double(value & 0xff) / 255)
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
    private let colors: CodeColors?
    private let lines: Int
    private let font: Font

    /// `colors`: the grammar's inks, computed where the engine runs
    /// (`Syntax.colors`); without them a diff is still line-colored and
    /// anything else plain.
    public init(
        _ text: String, format: CodeFormat, colors: CodeColors? = nil, lines: Int = 3,
        font: Font = .system(.caption, design: .monospaced)
    ) {
        self.text = text
        self.format = format
        self.colors = colors
        self.lines = lines
        self.font = font
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if format == .shell {
                Text("$").foregroundStyle(.secondary)
            }
            Text(colors?.paint(text) ?? SyntaxLines.color(text, as: format))
                .lineLimit(lines)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(font)
    }
}
