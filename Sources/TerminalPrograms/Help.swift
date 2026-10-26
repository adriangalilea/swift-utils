import Foundation
import Terminal

extension TerminalProgram {
    /// How a renderer lays text out: the terminal's columns (folded to 80 at
    /// most, a reading measure) and the palette (`ui`, or plain).
    public struct Rendering: Sendable {
        public let columns: Int
        public let palette: Palette

        public init(columns: Int, palette: Palette) {
            self.columns = columns
            self.palette = palette
        }

        /// This process's terminal: stdout's width, `ui`'s palette.
        public static var terminal: Rendering {
            var size = winsize()
            let columns =
                ioctl(STDOUT_FILENO, TIOCGWINSZ, &size) == 0 && size.ws_col > 0
                ? Int(size.ws_col) : 80
            return Rendering(columns: columns, palette: ui)
        }

        /// No colour, 80 columns: what a test or a file reads.
        public static let plain = Rendering(columns: 80, palette: Palette(enabled: false))
    }
}

extension TerminalProgram.Program {
    public typealias Rendering = TerminalProgram.Rendering

    // MARK: The overview

    /// The program in one screen: title, what it is for and never for, the
    /// commands by section, the guides, the skill, the flags every command
    /// takes, the environment and the exits.
    public func overview(_ r: Rendering) -> String {
        let p = r.palette
        var sections: [(String, [(String, String)])] = []
        for verb in Verb.allCases where !verb.command.hidden {
            let command = verb.command
            let row = (usage(command, p), command.says)
            if let at = sections.firstIndex(where: { $0.0 == command.section }) {
                sections[at].1.append(row)
            } else {
                sections.append((command.section, [row]))
            }
        }
        var groups = sections
        if !guides.isEmpty { groups.append(("guides", guides.map { ($0.name, $0.says) })) }
        if skill != nil {
            groups.append(
                (
                    "for agents",
                    TerminalProgram.SkillAction.allCases.map { action in
                        let command = Table.skillCommand(action, name)
                        return (usage(command, p), command.says)
                    }
                ))
        }
        if !programFlags.isEmpty { groups.append(("flags", programFlags)) }
        if !environment.isEmpty {
            groups.append(("environment", environment.map { ($0.name, $0.says) }))
        }
        groups.append(("exits", allExits.map { (String($0.code), $0.says) }))

        var lines = ["", "  \(p.head(name))\(version.map { " " + p.muted($0) } ?? "")  \(says)"]
        lines += about.map { p.muted(Fold.wrap($0, indent: 2, columns: r.columns)) }
        if let skill {
            lines += [""]
            lines.append(
                Fold.hang(
                    "  " + p.muted("use it for"), column: 14,
                    text: skill.useWhen.joined(separator: "; "), columns: r.columns))
            if !skill.never.isEmpty {
                lines.append(
                    Fold.hang(
                        "  " + p.muted("never"), column: 14,
                        text: skill.never.joined(separator: "; "), columns: r.columns))
            }
        }
        lines += Fold.aligned(groups, palette: p, columns: r.columns)
        let foot =
            ["\(name) help <command> for one in full"]
            + (guides.isEmpty ? [] : ["\(name) help <guide> to read one"])
        lines += ["", "  " + p.muted(foot.joined(separator: " · ")), ""]
        return lines.joined(separator: "\n")
    }

    /// The flags that are the program's, not one command's: `--version`
    /// (about the program), `--json` and the program's globals (taken by any
    /// command, which is said only where there is more than one). The
    /// overview, the skill and `help --json` list these rows.
    var programFlags: [(String, String)] {
        let several = table.entries.filter { !$0.command.hidden }.count > 1
        return table.common.filter { $0.name != "help" }.map { spec in
            spec.name == "version"
                ? (spec.text, "\(name)'s version")
                : (spec.text, spec.says + (several ? ", on any command" : ""))
        }
    }

    // MARK: One command

    /// One command in full: its usage, what it says, its `more`, the
    /// commands under it, its arguments' words, its flags, examples, what
    /// `--json` prints and how it exits.
    public func detail(_ entryName: String, _ r: Rendering) -> String {
        guard let (_, command) = table.command(named: entryName) else {
            preconditionFailure("cli: detail of \"\(entryName)\", which \(name) lacks")
        }
        let p = r.palette
        var lines = ["", "  " + usage(command, p), "  " + command.says]
        if let more = command.more {
            lines += ["", Fold.markdown(more, indent: 2, columns: r.columns, palette: p)]
        }
        let under = table.entries.filter {
            $0.name.hasPrefix(entryName + " ") && !$0.command.hidden
        }
        if !under.isEmpty {
            lines += Fold.aligned(
                [("commands", under.map { (usage($0.command, p), $0.command.says) })], palette: p,
                columns: r.columns)
        }
        let listed = command.args.filter { $0.choices != nil }
        if !listed.isEmpty {
            lines += Fold.aligned(
                [("arguments", listed.map { ($0.text, $0.choices!.joined(separator: ", ")) })],
                palette: p, columns: r.columns)
        }
        let rows = flagRows(command, p)
        if !rows.isEmpty {
            let column = (rows.map { width($0.0) }.max() ?? 0) + 2 + 4
            lines += ["", "  " + p.accent("flags")]
            lines += rows.map {
                Fold.hang("    " + $0.0, column: column, text: $0.1, columns: r.columns)
            }
        }
        if let document = command.stdin {
            lines += ["", "  " + p.accent("stdin"), "    " + document]
        }
        if !command.examples.isEmpty {
            lines +=
                ["", "  " + p.accent("examples")]
                + command.examples.map { "    " + p.muted("$") + " " + $0 }
        }
        if let json = command.json {
            lines += [
                "", "  " + p.accent("--json"), Fold.wrap(json, indent: 4, columns: r.columns),
            ]
        }
        if !command.exits.isEmpty {
            lines += Fold.aligned(
                [("exits", command.exits.map { (String($0.code), $0.says) })], palette: p,
                columns: r.columns)
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }

    /// One guide, as `help <guide>` prints it.
    public func guide(_ guideName: String, _ r: Rendering) -> String {
        guard let guide = guides.first(where: { $0.name == guideName }) else {
            preconditionFailure("cli: guide \"\(guideName)\", which \(name) lacks")
        }
        let p = r.palette
        return [
            "", "  " + p.head(guide.title), "",
            Fold.markdown(guide.body, indent: 2, columns: r.columns, palette: p), "",
        ]
        .joined(separator: "\n")
    }

    // MARK: Shared

    /// Every exit the program can end with, by code: 0, the declared ones, 1, 64.
    var allExits: [TerminalProgram.Exit] {
        ([.ok, .failed, .usage] + exits).sorted { $0.code < $1.code }
    }

    /// A command as typed: `authz secrets read <ref>`, `authz ask [title] -- command < request.json`.
    func usage(_ command: TerminalProgram.Command, _ p: Palette) -> String {
        let aliases =
            command.aliases.isEmpty ? "" : p.muted("|" + command.aliases.joined(separator: "|"))
        let isDefault = defaultCommand?.command.command.name == command.name
        let said =
            isDefault
            ? p.muted("[") + p.head(command.name) + aliases + p.muted("]")
            : p.head(command.name) + aliases
        return p.muted(name) + " " + said
            + (plainTail(command).isEmpty ? "" : " " + p.muted(plainTail(command)))
    }

    /// The same, uncoloured: for refusals, the skill and `help --json`.
    func plainUsage(_ command: TerminalProgram.Command) -> String {
        "\(name) \(command.name)" + (plainTail(command).isEmpty ? "" : " " + plainTail(command))
    }

    private func plainTail(_ command: TerminalProgram.Command) -> String {
        var parts = command.args.map(\.text)
        if let passthrough = command.passthrough { parts.append("-- " + passthrough) }
        if let document = command.stdin { parts.append("< " + document) }
        return parts.joined(separator: " ")
    }

    /// A command's own flags as rows: each spelling (a `oneOf`'s every
    /// switch), what it says, and what binds it.
    func flagRows(_ command: TerminalProgram.Command, _ p: Palette) -> [(String, String)] {
        command.flags.flatMap { spec -> [(String, String)] in
            var notes: [String] = []
            if let choices = spec.choices, !spec.placeholder.contains("|") {
                notes.append(choices.joined(separator: ", "))
            }
            if spec.required { notes.append("required") }
            for group in command.excludes where group.contains(spec.name) {
                notes.append(
                    "not with "
                        + group.filter { $0 != spec.name }.map { "--\($0)" }.joined(separator: ", ")
                )
            }
            for rule in command.requires where rule.flag == spec.name {
                notes.append("with --\(rule.needs)")
            }
            let suffix = notes.isEmpty ? "" : p.muted(" (\(notes.joined(separator: "; ")))")
            if case .oneOf(let options) = spec.shape {
                return options.map { option in
                    (
                        "\(option.short.map { "-\($0), " } ?? "")--\(option.name)",
                        option.says
                            + p.muted(
                                " (one of " + options.map { "--\($0.name)" }.joined(separator: ", ")
                                    + ")")
                    )
                }
            }
            return [(spec.text, spec.says + suffix)]
        }
    }
}

/// Text folded to a terminal: never past 80 columns, never under 30 a line,
/// so a narrow terminal folds words rather than letters.
enum Fold {
    static func lines(_ text: String, column: Int, columns: Int) -> [String] {
        let room = max(30, min(80, columns) - column)
        var lines: [String] = []
        var line = ""
        for word in text.split(whereSeparator: \.isWhitespace) {
            if !line.isEmpty, width(line) + 1 + width(String(word)) > room {
                lines.append(line)
                line = String(word)
            } else {
                line = line.isEmpty ? String(word) : line + " " + word
            }
        }
        if !line.isEmpty { lines.append(line) }
        return lines
    }

    static func wrap(_ text: String, indent: Int, columns: Int) -> String {
        lines(text, column: indent, columns: columns).map {
            String(repeating: " ", count: indent) + $0
        }.joined(separator: "\n")
    }

    /// `left` padded to `column`, then `text` folded so its later lines start
    /// under its first.
    static func hang(_ left: String, column: Int, text: String, columns: Int) -> String {
        let folded = lines(text, column: column, columns: columns).joined(
            separator: "\n" + String(repeating: " ", count: column))
        var out = padEnd(left, column) + folded
        while out.last?.isWhitespace == true { out.removeLast() }
        return out
    }

    /// Rows in one column whatever group they stand in.
    static func aligned(_ groups: [(String, [(String, String)])], palette p: Palette, columns: Int)
        -> [String]
    {
        let column = (groups.flatMap { $0.1.map { width($0.0) } }.max() ?? 0) + 6
        return groups.flatMap { title, rows in
            ["", "  " + p.accent(title)]
                + rows.map { hang("    " + $0.0, column: column, text: $0.1, columns: columns) }
        }
    }

    /// Markdown of the small subset, for a terminal: paragraphs folded,
    /// bullets folded under their marker, fenced blocks kept as written.
    static func markdown(_ text: String, indent: Int, columns: Int, palette p: Palette) -> String {
        let lead = String(repeating: " ", count: indent)
        var out: [String] = []
        var paragraph: [String] = []
        var fenced = false
        func flush() {
            guard !paragraph.isEmpty else { return }
            let joined = paragraph.joined(separator: " ")
            if joined.hasPrefix("- ") {
                out.append(
                    hang(
                        lead + "- ", column: indent + 2, text: String(joined.dropFirst(2)),
                        columns: columns))
            } else {
                out.append(wrap(joined, indent: indent, columns: columns))
            }
            paragraph = []
        }
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            if line.hasPrefix("```") {
                flush()
                fenced.toggle()
                continue
            }
            if fenced {
                out.append(lead + "  " + p.muted(line))
                continue
            }
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                flush()
                if out.last != "" { out.append("") }
                continue
            }
            if line.hasPrefix("- ") { flush() }
            paragraph.append(line.trimmingCharacters(in: .whitespaces))
        }
        flush()
        while out.last == "" { out.removeLast() }
        return out.joined(separator: "\n")
    }
}
