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
/// The ground code is drawn on, which picks its inks: a dark theme's pale
/// inks vanish on a light ground, and the reverse. The one definition:
/// `Syntax.Appearance` is this type, and every grammar (the engine's, the
/// command line's) takes it, so the same text on the same ground has the
/// same inks everywhere.
public enum CodeGround: Sendable {
    case light, dark
    public init(_ scheme: ColorScheme) { self = scheme == .dark ? .dark : .light }
}

public enum SyntaxLines {
    public static func color(_ text: String, as format: CodeFormat, on ground: CodeGround)
        -> AttributedString
    {
        switch format {
        case .diff: diff(text)
        case .shell where !text.contains("\n"): command(text, on: ground)
        case .shell, .plain: AttributedString(text)
        }
    }

    /// The command line's inks, the atom-one theme's own (light and dark), the
    /// one the engine paints scripts with: a one-line command and a script
    /// read in one palette.
    struct CommandInks {
        let program, flag, path, value, string, variable, op: Color
        static func on(_ ground: CodeGround) -> CommandInks {
            switch ground {
            case .dark:
                CommandInks(
                    program: Color(hex: "#61aeee")!, flag: Color(hex: "#d19a66")!,
                    path: Color(hex: "#56b6c2")!, value: Color(hex: "#e5c07b")!,
                    string: Color(hex: "#98c379")!, variable: Color(hex: "#e06c75")!,
                    op: Color(hex: "#c678dd")!)
            case .light:
                CommandInks(
                    program: Color(hex: "#4078f2")!, flag: Color(hex: "#986801")!,
                    path: Color(hex: "#0184bc")!, value: Color(hex: "#c18401")!,
                    string: Color(hex: "#50a14f")!, variable: Color(hex: "#e45649")!,
                    op: Color(hex: "#a626a4")!)
            }
        }
    }

    /// One command line as a person reads one before saying yes: the program
    /// it runs (bold), its flags, the paths it touches, values (numbers,
    /// hashes), variables, quoted strings, and the operators that start the
    /// next command; a plain argument stays the host's color. A command line
    /// is argv, and argv is ours to read exactly: highlight.js's bash grammar
    /// tokenizes only keywords, strings and variables, so a release's
    /// `…/ship release-run …/plan.json 89b9…` came out one flat grey
    /// (2026-10-27). Never rewrites a character.
    public static func command(_ text: String, on ground: CodeGround) -> AttributedString {
        let ink = CommandInks.on(ground)
        var out = AttributedString()
        var program = true
        for token in CommandLine.tokens(text) {
            var run = AttributedString(token.text)
            switch token.kind {
            case .space: break
            case .operator:
                run.foregroundColor = ink.op
                program = token.startsCommand
            case .quoted: run.foregroundColor = ink.string
            case .variable: run.foregroundColor = ink.variable
            case .word:
                let word = token.text
                if program, let equals = word.firstIndex(of: "="), word.first != "=",
                    word[..<equals].allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" })
                {
                    // A leading NAME=value: the environment it runs with.
                    var name = AttributedString(String(word[..<equals]))
                    name.foregroundColor = ink.variable
                    run = name + AttributedString(String(word[equals...]))
                } else if program {
                    run.foregroundColor = ink.program
                    run.inlinePresentationIntent = .stronglyEmphasized
                    program = false
                } else if word.hasPrefix("-") {
                    run.foregroundColor = ink.flag
                } else if word.contains("/") || word.hasPrefix("~") {
                    run.foregroundColor = ink.path
                } else if word.allSatisfy(\.isHexDigit),
                    word.count >= 7 || word.allSatisfy(\.isNumber)
                {
                    run.foregroundColor = ink.value
                }
            }
            out += run
        }
        return out
    }

    /// A command line cut into what `command` colors, every character in
    /// exactly one token, in order.
    enum CommandLine {
        enum Kind { case space, word, quoted, variable, `operator` }
        struct Token {
            let kind: Kind
            let text: String
            /// An operator after which a new command (its program) begins.
            var startsCommand = false
        }

        static func tokens(_ text: String) -> [Token] {
            var tokens: [Token] = []
            var rest = Substring(text)
            while let first = rest.first {
                if first == " " || first == "\t" {
                    let run = rest.prefix { $0 == " " || $0 == "\t" }
                    tokens.append(Token(kind: .space, text: String(run)))
                    rest = rest.dropFirst(run.count)
                } else if first == "'" || first == "\"" {
                    // To the closing quote (a backslash escapes inside "…"),
                    // or the end of the line when it never closes.
                    var length = 1
                    var escaped = false
                    for character in rest.dropFirst() {
                        length += 1
                        if escaped {
                            escaped = false
                            continue
                        }
                        if first == "\"", character == "\\" {
                            escaped = true
                            continue
                        }
                        if character == first { break }
                    }
                    tokens.append(Token(kind: .quoted, text: String(rest.prefix(length))))
                    rest = rest.dropFirst(length)
                } else if first == "$" {
                    let length: Int
                    if rest.dropFirst().first == "{" {
                        length =
                            (rest.firstIndex(of: "}").map {
                                rest.distance(from: rest.startIndex, to: $0) + 1
                            })
                            ?? rest.count
                    } else {
                        length =
                            1
                            + rest.dropFirst().prefix { $0.isLetter || $0.isNumber || $0 == "_" }
                            .count
                    }
                    tokens.append(Token(kind: .variable, text: String(rest.prefix(length))))
                    rest = rest.dropFirst(length)
                } else if let op = ["&&", "||", ">>", "|", ";", "&", ">", "<"].first(where: {
                    rest.hasPrefix($0)
                }) {
                    tokens.append(
                        Token(
                            kind: .operator, text: op,
                            startsCommand: ["&&", "||", "|", ";", "&"].contains(op)))
                    rest = rest.dropFirst(op.count)
                } else {
                    let run = rest.prefix { !" \t'\"$|;&<>".contains($0) }
                    tokens.append(Token(kind: .word, text: String(run)))
                    rest = rest.dropFirst(run.count)
                }
            }
            return tokens
        }
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
    @Environment(\.colorScheme) private var scheme

    /// `colors`: the grammar's inks, computed where the engine runs
    /// (`Syntax.colors`); without them a diff is still line-colored, a
    /// command line colored by its own grammar, anything else plain.
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
            Text(colors?.paint(text) ?? SyntaxLines.color(text, as: format, on: CodeGround(scheme)))
                .lineLimit(lines)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(font)
    }
}
