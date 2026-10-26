extension TerminalProgram {
    /// One command, everything a person and an agent are told about it. The
    /// prose fields (`more`, a guide's body) are Markdown of a small subset
    /// (paragraphs, `- ` bullets, inline code, **bold**, fenced blocks): the
    /// terminal folds it, the skill keeps it as written.
    public struct Command: Sendable {
        /// Its words as typed after the program's name: `ask`, `secrets read`.
        public let name: String
        /// The overview's group it is listed under, in the order the program's
        /// commands first name each.
        public let section: String
        public let args: [ArgSpec]
        public let flags: [FlagSpec]
        /// What follows `--`, as the usage shows it (`command [args…]`): handed
        /// to the handler untouched (`call.passthrough`), help and `--json` in
        /// it never read. nil: words after `--` are arguments, as before it.
        public let passthrough: String?
        /// The document read from stdin, as the usage shows it (`request.json`):
        /// `call.stdin()` reads it, refusing at a terminal.
        public let stdin: String?
        /// One line: what it does, in the person's words.
        public let says: String
        /// What `help <command>` and the skill add: when it is the one to use,
        /// how it behaves, what it refuses, how it fails.
        public let more: String?
        public let examples: [String]
        /// What `--json` prints.
        public let json: String?
        /// The exit codes it ends with beyond 0, 1 and 64 (declared by the
        /// program too).
        public let exits: [Exit]
        /// Other words it answers to: input only, never in the help's usage
        /// lines, the skill or a message (scripts and skills use the name).
        public let aliases: [String]
        /// Left out of the overview and the skill (an internal verb, run by
        /// hooks or scripts), still answered by `help <command>`.
        public let hidden: Bool
        /// Flags of which at most one may be given (by key).
        public let excludes: [[String]]
        /// A flag that is refused without another (by key).
        public let requires: [(flag: String, needs: String)]

        public init(
            _ name: String, section: String = "commands",
            args: [any ArgDescribing] = [], flags: [any FlagDescribing] = [],
            passthrough: String? = nil, stdin: String? = nil,
            says: String, more: String? = nil, examples: [String] = [], json: String? = nil,
            exits: [Exit] = [], aliases: [String] = [], hidden: Bool = false,
            excludes: [[any FlagDescribing]] = [],
            requires: [(any FlagDescribing, needs: any FlagDescribing)] = []
        ) {
            self.name = name
            self.section = section
            self.args = args.map(\.spec)
            self.flags = flags.map(\.spec)
            self.passthrough = passthrough
            self.stdin = stdin
            self.says = says
            self.more = more
            self.examples = examples
            self.json = json
            self.exits = exits
            self.aliases = aliases
            self.hidden = hidden
            self.excludes = excludes.map { $0.map(\.spec.name) }
            self.requires = requires.map { ($0.0.spec.name, $0.needs.spec.name) }
        }
    }

    /// A program's prose a person reads on request and an agent reads in the
    /// skill: when to reach for it, the patterns, what never to do.
    /// `help <name>` prints one; the overview lists them; the skill inlines
    /// them all.
    public struct Guide: Sendable {
        public let name: String
        public let title: String
        public let says: String
        /// Markdown of the small subset (`Command.more`'s).
        public let body: String

        public init(_ name: String, title: String, says: String, body: String) {
            self.name = name
            self.title = title
            self.says = says
            self.body = body
        }
    }

    /// The program offers itself to agents: `skill` prints, installs and
    /// removes a Claude Code skill rendered from its description. What the
    /// skill's `description` says (the line agents choose skills by) is the
    /// program's `says`, then `useWhen`, then `never`; the overview shows the
    /// same two lists, so a person reads them too.
    public struct Skill: Sendable {
        public let useWhen: [String]
        public let never: [String]

        public init(useWhen: [String], never: [String] = []) {
            precondition(!useWhen.isEmpty, "cli: a skill says when to use it")
            self.useWhen = useWhen
            self.never = never
        }
    }

    /// An environment variable the program reads, as the overview lists it.
    public struct Variable: Sendable {
        public let name: String
        public let says: String

        public init(_ name: String, says: String) {
            self.name = name
            self.says = says
        }
    }
}

extension TerminalProgram {
    /// A program's commands: one case each, described by `command` and
    /// dispatched by a `switch` over the same enum, so the compiler refuses a
    /// command described and not handled, or handled and not described. The
    /// case order is the overview's order.
    public protocol Commands: CaseIterable, Hashable, Sendable where AllCases: Sendable {
        var command: TerminalProgram.Command { get }
    }
}
