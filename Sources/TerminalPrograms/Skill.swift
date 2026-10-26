import Foundation
import Terminal

extension TerminalProgram.Program {
    /// The line agents choose skills by: what the program is, what it is
    /// for, what never to do with it. The overview shows the same two lists.
    var skillDescription: String {
        guard let skill else { preconditionFailure("cli: \(name) has no skill") }
        let capital = says.prefix(1).uppercased() + says.dropFirst()
        let sentence = capital.last.map { ".!?".contains($0) } == true ? capital : capital + "."
        var text = "\(sentence) Use it for: \(skill.useWhen.joined(separator: "; "))."
        if !skill.never.isEmpty { text += " Never \(skill.never.joined(separator: "; "))." }
        return text
    }

    /// The skill as agents read it: the program's description as one
    /// Markdown document, unfolded and uncoloured, every visible command in
    /// full and every guide inline. Nothing in it the help does not say.
    public var skillMarkdown: String {
        guard skill != nil else { preconditionFailure("cli: \(name) has no skill") }
        var out = [
            "---",
            "name: \(name)",
            "description: \(Self.yaml(skillDescription))",
            "metadata:",
            "  generated-by: \(Self.yaml("\(name) \(version ?? "from source")"))",
            "---",
            "",
            "# \(name)",
            "",
            says,
        ]
        if !about.isEmpty { out += [""] + about }
        for guide in guides {
            out += ["", "## \(guide.title)", "", "*\(guide.says)*", "", guide.body]
        }

        let visible = Verb.allCases.map(\.command).filter { !$0.hidden }
        out += ["", "## Commands"]
        var sections: [String] = []
        for command in visible where !sections.contains(command.section) {
            sections.append(command.section)
        }
        for section in sections {
            out += ["", "### \(section)", ""]
            out += visible.filter { $0.section == section }.map {
                "- `\(plainUsage($0))`: \($0.says)"
            }
        }
        for command in visible {
            out += ["", "## `\(plainUsage(command))`", "", command.says]
            if let more = command.more { out += ["", more] }
            let listed = command.args.filter { $0.choices != nil }
            if !listed.isEmpty {
                out +=
                    [""] + listed.map { "- `\($0.text)`: \($0.choices!.joined(separator: ", "))" }
            }
            let rows = flagRows(command, Palette(enabled: false))
            if !rows.isEmpty { out += ["", "Flags:", ""] + rows.map { "- `\($0.0)`: \($0.1)" } }
            if let document = command.stdin { out += ["", "Reads `\(document)` on stdin."] }
            if !command.examples.isEmpty { out += ["", "```sh"] + command.examples + ["```"] }
            if let json = command.json { out += ["", "With `--json`: \(json)"] }
            if !command.exits.isEmpty {
                out += [
                    "",
                    "Exits: "
                        + command.exits.map { "\($0.code) \($0.says)" }.joined(separator: ", ")
                        + ".",
                ]
            }
        }
        if !programFlags.isEmpty {
            out += ["", "## Flags", ""] + programFlags.map { "- `\($0.0)`: \($0.1)" }
        }
        if !environment.isEmpty {
            out += ["", "## Environment", ""] + environment.map { "- `\($0.name)`: \($0.says)" }
        }
        out += ["", "## Exit status", ""] + allExits.map { "- `\($0.code)`: \($0.says)" }
        out += [
            "",
            "`\(name) help <command>` prints one command as above; `\(name) help --json` prints all of it as data.",
        ]
        return out.joined(separator: "\n") + "\n"
    }

    /// A YAML scalar: JSON's string form, which YAML reads as one.
    static func yaml(_ s: String) -> String {
        String(decoding: try! JSONEncoder().encode(s), as: UTF8.self)
    }

    // MARK: Install

    /// Where each agent reads skills from: the base homes every profile of it
    /// links into (`~/.claude/skills`, `~/.codex/skills`), never one
    /// profile's, or the skill would reach that profile alone.
    struct Agent {
        let name: String
        let home: URL
        var skills: URL { home.appending(path: "skills") }

        static var all: [Agent] {
            let home = URL(filePath: NSHomeDirectory())
            return [
                Agent(name: "Claude Code", home: home.appending(path: ".claude")),
                Agent(name: "Codex", home: home.appending(path: ".codex")),
            ]
        }
    }

    /// The skill this binary ships inside its app bundle
    /// (`Contents/Resources/skill/SKILL.md`, rendered at build time by
    /// `skill show`), nil for a program run from a folder.
    var bundledSkill: URL? {
        guard let executable = Bundle.main.executableURL?.resolvingSymlinksInPath() else {
            return nil
        }
        let contents = executable.deletingLastPathComponent().deletingLastPathComponent()
        guard contents.lastPathComponent == "Contents",
            contents.deletingLastPathComponent().pathExtension == "app"
        else { return nil }
        let folder = contents.appending(path: "Resources/skill")
        return FileManager.default.fileExists(atPath: folder.appending(path: "SKILL.md").path)
            ? folder : nil
    }

    enum Installed: Equatable {
        case absent
        /// A link to this binary's bundled skill: current by construction.
        case linked
        /// A link somewhere else (another copy of the program, an old app).
        case linkedElsewhere(String)
        /// A copy with exactly this binary's text.
        case current
        /// A copy with other text: an older program wrote it, or a hand.
        case stale
    }

    func installed(at agent: Agent) -> Installed {
        let target = agent.skills.appending(path: name)
        let fm = FileManager.default
        if let destination = try? fm.destinationOfSymbolicLink(atPath: target.path) {
            let resolved = URL(filePath: destination, relativeTo: agent.skills).standardizedFileURL
                .path
            return resolved == bundledSkill?.standardizedFileURL.path
                ? .linked : .linkedElsewhere(resolved)
        }
        guard
            let text = try? String(contentsOf: target.appending(path: "SKILL.md"), encoding: .utf8)
        else { return .absent }
        return text == skillMarkdown ? .current : .stale
    }

    /// `skill`: per agent, whether the skill is there and current.
    func skillStatus() -> String {
        Agent.all.map { agent in
            guard FileManager.default.fileExists(atPath: agent.home.path) else {
                return "\(agent.name): not installed on this Mac"
            }
            return switch installed(at: agent) {
            case .absent: "\(agent.name): no skill (\(name) skill install)"
            case .linked: "\(agent.name): linked to this \(name), current"
            case .linkedElsewhere(let path):
                "\(agent.name): linked to \(path), another copy (\(name) skill install points it here)"
            case .current: "\(agent.name): a copy, current"
            case .stale: "\(agent.name): a copy older than this \(name) (\(name) skill install)"
            }
        }.joined(separator: "\n")
    }

    /// `skill install`: for every agent on this Mac, a link to the bundled
    /// skill (an app) or a copy (a program run from a folder). Replaces what
    /// was there, a hand-edited copy included: the program is the source,
    /// the file its rendering.
    func installSkill() throws(TerminalProgram.Refusal) -> String {
        let fm = FileManager.default
        var said: [String] = []
        for agent in Agent.all {
            guard fm.fileExists(atPath: agent.home.path) else {
                said.append("\(agent.name): not installed on this Mac, skipped")
                continue
            }
            let target = agent.skills.appending(path: name)
            do {
                try fm.createDirectory(at: agent.skills, withIntermediateDirectories: true)
                if (try? fm.destinationOfSymbolicLink(atPath: target.path)) != nil
                    || fm.fileExists(atPath: target.path)
                {
                    try fm.trashOrRemove(target)
                }
                if let bundled = bundledSkill {
                    try fm.createSymbolicLink(at: target, withDestinationURL: bundled)
                    said.append("\(agent.name): \(target.path) → \(bundled.path)")
                } else {
                    try fm.createDirectory(at: target, withIntermediateDirectories: true)
                    try Data(skillMarkdown.utf8).write(
                        to: target.appending(path: "SKILL.md"), options: .atomic)
                    said.append("\(agent.name): \(target.appending(path: "SKILL.md").path)")
                }
            } catch {
                throw TerminalProgram.Refusal(
                    .failed,
                    "\(agent.name): the skill was not installed at \(target.path): \(error)")
            }
        }
        return said.joined(separator: "\n")
    }

    /// `skill remove`: the skill out of every agent.
    func removeSkill() throws(TerminalProgram.Refusal) -> String {
        let fm = FileManager.default
        var said: [String] = []
        for agent in Agent.all where installed(at: agent) != .absent {
            let target = agent.skills.appending(path: name)
            do {
                try fm.trashOrRemove(target)
                said.append("\(agent.name): removed \(target.path)")
            } catch {
                throw TerminalProgram.Refusal(
                    .failed, "\(agent.name): \(target.path) was not removed: \(error)")
            }
        }
        return said.isEmpty
            ? "no agent on this Mac had the \(name) skill" : said.joined(separator: "\n")
    }
}

extension FileManager {
    /// A link is unlinked (its destination untouched); anything else goes to
    /// the Trash, never deleted outright.
    fileprivate func trashOrRemove(_ url: URL) throws {
        if (try? destinationOfSymbolicLink(atPath: url.path)) != nil {
            try removeItem(at: url)
        } else {
            try trashItem(at: url, resultingItemURL: nil)
        }
    }
}
