/// A command-line program described once, as data, and everything a person
/// or an agent meets read from that one description: the parse (`-wo`
/// groups, `--dir=x`, `--`), the refusals (a flag the command does not take,
/// an argument too few or too many), the values' types, the help (`--help`,
/// `help <command>`, `help <guide>`, `help --json`) and the Claude Code skill
/// (`skill`). An agent needs nothing a person does not, and a person nothing
/// an agent does not: the help and the skill are two renderings of the same
/// description, so neither can say what the other does not.
///
/// Ported from ts-utils `cli` (`program`), whose parse, refusals and help
/// layout it keeps; README "TerminalPrograms" says where it differs.
public enum TerminalProgram {}

extension TerminalProgram {
    /// How a program ends, declared in its description so the help and the
    /// skill say every code it can exit with. A handler returns one; a
    /// refusal carries one.
    public struct Exit: Sendable, Hashable {
        public let code: Int32
        public let says: String

        public init(_ code: Int32, _ says: String) {
            precondition((0...255).contains(code), "an exit code is 0 to 255, not \(code)")
            self.code = code
            self.says = says
        }

        public static let ok = Exit(0, "done")
        public static let failed = Exit(1, "anything else")
        /// A wrong call: a flag the command does not take, an argument too
        /// few or too many (EX_USAGE, the same in every program).
        public static let usage = Exit(64, "a wrong call")

        /// A child's status passed through as this program's own, by design
        /// undeclared (`authz ask -- ./deploy` exits as `./deploy` did).
        public static func child(_ status: Int32) -> Exit { Exit(status, "the command's own") }
    }

    /// What a person did wrong, or what the world refused, said as one line
    /// with what to type instead; and how the program ends for it. A
    /// confusion of the program itself is never a refusal: it is a
    /// `precondition`, with a stack.
    public struct Refusal: Error, Sendable, CustomStringConvertible {
        public let exit: Exit
        public let message: String
        /// What the message names, as data under `--json`.
        public let fields: [String: String]

        public init(_ exit: Exit = .failed, _ message: String, fields: [String: String] = [:]) {
            precondition(exit.code != 0, "a refusal ends in failure: \(message)")
            self.exit = exit
            self.message = message
            self.fields = fields
        }

        static func usage(_ message: String) -> Refusal { Refusal(.usage, message) }

        public var description: String { message }
    }
}
