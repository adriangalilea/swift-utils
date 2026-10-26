extension TerminalProgram {
    /// A program: its commands (an enum, `Commands`) and everything said
    /// about it as a whole. Built at start and checked there: a description
    /// that would not do what it says traps with a `cli:` message on the
    /// first run, never when a person types the one command that trips it.
    ///
    ///     let authz = TerminalProgram.Program<Authz>(
    ///       name: "authz", says: "Reach the human: ask them something, or tell them something.",
    ///       json: true, exits: [.denied, .unanswered], guides: Guides.all,
    ///       skill: .init(useWhen: ["a yes before something irreversible"], never: ["ask in the terminal"]))
    ///     await authz.main { call in
    ///       switch call.command { case .ask: … }
    ///     }
    public struct Program<Verb: Commands>: Sendable {
        public let name: String
        public let says: String
        /// Quieter lines under the title.
        public let about: [String]
        /// What a release is called (`--version`), for a program that has
        /// releases; nil for one run from its source, which has no
        /// `--version`.
        public let version: String?
        /// What the program alone runs: a command, or nil for the overview.
        public let bare: Verb?
        /// The command a first word no command spells is given to, as its
        /// first argument, when `claims` holds for it (`hf-get owner/repo`).
        public let defaultCommand: Default?
        /// Flags every command takes.
        public let global: [FlagSpec]
        /// Every command takes `--json`: refusals and the help answer as JSON
        /// on stdout then, and handlers read `call.json`.
        public let json: Bool
        public let environment: [Variable]
        /// Exit codes beyond 0, 1 and 64 its commands end with.
        public let exits: [Exit]
        public let guides: [Guide]
        public let skill: Skill?
        let table: Table

        public struct Default: Sendable {
            public let command: Verb
            public let claims: @Sendable (String) -> Bool
            public init(_ command: Verb, claims: @escaping @Sendable (String) -> Bool) {
                self.command = command
                self.claims = claims
            }
        }

        public init(
            name: String, says: String, about: [String] = [], version: String? = nil,
            bare: Verb? = nil, default defaultCommand: Default? = nil,
            global: [any FlagDescribing] = [], json: Bool = false,
            environment: [Variable] = [], exits: [Exit] = [], guides: [Guide] = [],
            skill: Skill? = nil
        ) {
            self.name = name
            self.says = says
            self.about = about
            self.version = version
            self.bare = bare
            self.defaultCommand = defaultCommand
            self.global = global.map(\.spec)
            self.json = json
            self.environment = environment
            self.exits = exits
            self.guides = guides
            self.skill = skill
            table = Table(
                name: name, version: version, json: json, global: self.global, skill: skill)
            check()
        }
    }

    /// What the program answers itself, beside its own commands.
    public enum Page: Sendable, Equatable {
        case overview
        case detail(String)
        case guide(String)
        case version
        case skill(SkillAction)
    }

    /// What every program has, whatever its commands.
    enum BuiltIn {
        static let helpFlag = Flag.on("help", short: "h", says: "this help").spec
        static let versionFlag = Flag.on("version", says: "the version").spec
        static let jsonFlag = Flag.on("json", says: "the answer as JSON on stdout").spec
        static let helpTopic = Arg.optional("topic")
        static let helpCommand = Command(
            "help", section: "help", args: [helpTopic],
            says: "these words, one command's in full, or a guide",
            more:
                "With --json, every command as data: its arguments, flags, words and what its --json prints."
        )
    }

    public enum SkillAction: String, Sendable, Equatable, CaseIterable {
        /// Where it is installed, per agent, and whether it is current.
        case status = "skill"
        case show = "skill show"
        case install = "skill install"
        case remove = "skill remove"
    }
}

extension TerminalProgram.Program {
    /// One entry of the table: a command of the program's, or one it answers
    /// itself.
    enum Entry: Sendable, Equatable {
        case verb(Verb)
        case help
        case skill(TerminalProgram.SkillAction)
    }

    /// The description read once, every name and flag spelling resolved, so
    /// the parse and the renderings look things up instead of searching.
    struct Table: Sendable {
        let entries: [(name: String, entry: Entry, command: TerminalProgram.Command)]
        /// Every word a command answers to (its name and aliases) → its name.
        let canonical: [String: String]
        let mostWords: Int
        /// Every flag spelling of every command → whether it takes a value
        /// (argv is read before the command is known).
        let takesValue: [String: Bool]
        let shortOf: [Character: String]
        /// A spelling → the commands that take it, for "it is X's".
        let owners: [String: [String]]
        /// The flags every command takes beside its own: help, version, json,
        /// the program's global ones.
        let common: [TerminalProgram.FlagSpec]

        init(
            name: String, version: String?, json: Bool, global: [TerminalProgram.FlagSpec],
            skill: TerminalProgram.Skill?
        ) {
            var common: [TerminalProgram.FlagSpec] = [TerminalProgram.BuiltIn.helpFlag]
            if version != nil { common.append(TerminalProgram.BuiltIn.versionFlag) }
            if json { common.append(TerminalProgram.BuiltIn.jsonFlag) }
            common += global
            self.common = common
            var entries: [(String, Entry, TerminalProgram.Command)] = Verb.allCases.map {
                ($0.command.name, .verb($0), $0.command)
            }
            entries.append(("help", .help, TerminalProgram.BuiltIn.helpCommand))
            if skill != nil {
                entries += TerminalProgram.SkillAction.allCases.map {
                    ($0.rawValue, .skill($0), Self.skillCommand($0, name))
                }
            }
            self.entries = entries
            var canonical: [String: String] = [:]
            for (entryName, _, command) in entries {
                precondition(
                    entryName.wholeMatch(of: /[a-z][a-z0-9-]*( [a-z][a-z0-9-]*)*/) != nil,
                    "cli: command \"\(entryName)\": words of lower case, digits and hyphens, one space apart"
                )
                for word in [entryName] + command.aliases {
                    if let had = canonical[word] {
                        preconditionFailure(
                            "cli: \(name): \"\(word)\" names both \(had) and \(entryName)")
                    }
                    canonical[word] = entryName
                }
            }
            self.canonical = canonical
            mostWords = canonical.keys.map { $0.split(separator: " ").count }.max() ?? 1
            var takesValue: [String: Bool] = [:]
            var shortsOf: [String: Character?] = [:]
            var owners: [String: [String]] = [:]
            let commonNames = Set(common.flatMap { $0.spellings.map(\.name) })
            for (entryName, _, command) in entries {
                var shorts: [Character: String] = [:]
                for spec in common + command.flags {
                    precondition(
                        spec.name.wholeMatch(of: /[a-z][a-z0-9-]*/) != nil,
                        "cli: --\(spec.name): lower case, digits and hyphens")
                    for spelling in spec.spellings {
                        precondition(
                            spelling.name.wholeMatch(of: /[a-z][a-z0-9-]*/) != nil,
                            "cli: --\(spelling.name): lower case, digits and hyphens")
                        if let short = spelling.short {
                            if let had = shorts[short], had != spelling.name {
                                preconditionFailure(
                                    "cli: \(name) \(entryName): -\(short) is both --\(had) and --\(spelling.name)"
                                )
                            }
                            shorts[short] = spelling.name
                        }
                        if let seen = takesValue[spelling.name],
                            seen != spelling.takesValue || shortsOf[spelling.name] != spelling.short
                        {
                            preconditionFailure(
                                "cli: --\(spelling.name) is spelled two ways (\(entryName) and another): one kind, one short letter"
                            )
                        }
                        takesValue[spelling.name] = spelling.takesValue
                        shortsOf[spelling.name] = spelling.short
                        if !commonNames.contains(spelling.name) {
                            owners[spelling.name, default: []].append(entryName)
                        }
                    }
                }
            }
            self.takesValue = takesValue
            self.owners = owners
            var shortOf: [Character: String] = [:]
            for (spelling, short) in shortsOf {
                guard let short else { continue }
                if let had = shortOf[short] {
                    preconditionFailure(
                        "cli: \(name): -\(short) is both --\(had) and --\(spelling)")
                }
                shortOf[short] = spelling
            }
            self.shortOf = shortOf
        }

        func command(named entryName: String) -> (entry: Entry, command: TerminalProgram.Command)? {
            entries.first { $0.name == entryName }.map { ($0.entry, $0.command) }
        }

        /// The flags a command takes: the common ones and its own.
        func flags(of entryName: String) -> [TerminalProgram.FlagSpec] {
            common + (command(named: entryName)?.command.flags ?? [])
        }

        static func skillCommand(_ action: TerminalProgram.SkillAction, _ name: String)
            -> TerminalProgram.Command
        {
            switch action {
            case .status:
                .init(
                    action.rawValue, section: "for agents",
                    says: "where the skill for agents is installed, and whether it is current")
            case .show:
                .init(
                    action.rawValue, section: "for agents",
                    says: "the skill as agents read it: these words, as one Markdown document")
            case .install:
                .init(
                    action.rawValue, section: "for agents",
                    says: "install the skill for Claude Code and Codex, kept current with \(name)",
                    more:
                        "An app's skill is a link into its bundle, so the app's update is the skill's; a program run from a folder writes a copy, and `\(name) skill` says when that copy is older than the program."
                )
            case .remove:
                .init(
                    action.rawValue, section: "for agents",
                    says: "remove the skill from every agent")
            }
        }
    }

    /// The description's own consistency, beyond the table's spellings.
    func check() {
        let commandNames = Set(table.entries.map(\.name))
        for builtIn in ["help", "skill"]
        where Verb.allCases.contains(where: {
            $0.command.name.split(separator: " ").first.map(String.init) == builtIn
        }) {
            preconditionFailure("cli: \"\(builtIn)\" is built in, \(name) cannot declare it")
        }
        for spec in global {
            precondition(
                !["help", "version", "json"].contains(spec.name),
                "cli: --\(spec.name) is built in, \(name) cannot declare it")
        }
        for verb in Verb.allCases {
            let command = verb.command
            for spec in command.flags {
                precondition(
                    !["help", "version", "json"].contains(spec.name),
                    "cli: --\(spec.name) is built in, \(name) cannot declare it")
            }
            var optionalSeen = false
            for (i, arg) in command.args.enumerated() {
                precondition(
                    !arg.rest || i == command.args.count - 1,
                    "cli: \(name) \(command.name): only the last argument may take the rest")
                precondition(
                    !(arg.needed && optionalSeen),
                    "cli: \(name) \(command.name): <\(arg.name)> is needed after one that may be missing; the parse could not tell them apart"
                )
                if !arg.needed { optionalSeen = true }
            }
            let keys = Set(command.flags.map(\.name) + table.common.map(\.name))
            for group in command.excludes {
                precondition(
                    group.count >= 2,
                    "cli: \(name) \(command.name): excludes names two flags at least")
                for key in group {
                    precondition(
                        keys.contains(key),
                        "cli: \(name) \(command.name): excludes --\(key), which it does not take")
                }
            }
            for rule in command.requires {
                precondition(
                    keys.contains(rule.flag) && keys.contains(rule.needs),
                    "cli: \(name) \(command.name): --\(rule.flag) needs --\(rule.needs), and it takes both"
                )
            }
            for exit in command.exits {
                precondition(
                    exits.contains(exit) || [.ok, .failed, .usage].contains(exit),
                    "cli: \(name) \(command.name) exits \(exit.code), which \(name)'s exits do not declare"
                )
            }
        }
        for guide in guides {
            precondition(
                guide.name.wholeMatch(of: /[a-z][a-z0-9-]*/) != nil,
                "cli: guide \"\(guide.name)\": lower case, digits and hyphens")
            precondition(
                !commandNames.contains(guide.name) && table.canonical[guide.name] == nil,
                "cli: guide \"\(guide.name)\" is also a command: help \(guide.name) would mean both"
            )
        }
        precondition(
            Set(guides.map(\.name)).count == guides.count, "cli: \(name): two guides share a name")
        if let defaultCommand {
            let command = defaultCommand.command.command
            precondition(
                !command.args.isEmpty,
                "cli: \(name) \(command.name) is the default, so it takes the word as an argument: give it args"
            )
        }
        for code in exits.map(\.code) {
            precondition(
                ![0, 1, 64].contains(code), "cli: \(name): exit \(code) is built in, not declared")
        }
        precondition(
            Set(exits.map(\.code)).count == exits.count,
            "cli: \(name): one exit code declared twice")
        if skill != nil {
            let description = skillDescription
            precondition(
                description.count <= 1024,
                "cli: \(name)'s skill description is \(description.count) characters; agents read at most 1024"
            )
        }
    }
}
