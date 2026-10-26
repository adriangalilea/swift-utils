extension TerminalProgram {
    /// A command's argument, declared once and read back by the same value,
    /// typed by its declaration: a needed one is a `String`, an optional one
    /// a `String?`, the rest a `[String]`, one of the domain's words its enum.
    /// The usage grammar (`<ref> [title] <words>…`) is rendered from them.
    public struct Arg<Value: Sendable>: Sendable, ArgDescribing {
        public let spec: ArgSpec
        /// The value from the words the argument covers (none, one, or the
        /// rest), already counted and checked by the parse.
        let take: @Sendable ([String]) -> Value
    }

    /// An argument without its type: what the parse and the renderings read.
    public struct ArgSpec: Sendable {
        public let name: String
        /// Given or the call is refused.
        public let needed: Bool
        /// Takes every word left (only the last argument).
        public let rest: Bool
        /// The only words it takes.
        public let choices: [String]?

        /// As the usage shows it: `<ref>`, `[title]`, `<words>…`, `[paths]…`
        /// (the ellipsis outside, as a list flag's `--to <pane>…`).
        var text: String {
            (needed ? "<\(name)>" : "[\(name)]") + (rest ? "…" : "")
        }
    }
}

extension TerminalProgram {
    /// Anything a command lists among its arguments.
    public protocol ArgDescribing: Sendable {
        var spec: TerminalProgram.ArgSpec { get }
    }
}

extension TerminalProgram.Arg where Value == String {
    /// Given, or the call is refused.
    public static func needed(_ name: String) -> Self {
        Self(spec: .init(name: name, needed: true, rest: false, choices: nil), take: { $0[0] })
    }
}

extension TerminalProgram.Arg where Value == String? {
    /// May be left out.
    public static func optional(_ name: String) -> Self {
        Self(spec: .init(name: name, needed: false, rest: false, choices: nil), take: { $0.first })
    }
}

extension TerminalProgram.Arg where Value == [String] {
    /// Every word left; at least one when `needed`.
    public static func rest(_ name: String, needed: Bool = true) -> Self {
        Self(spec: .init(name: name, needed: needed, rest: true, choices: nil), take: { $0 })
    }
}

extension TerminalProgram.Arg
where Value: CaseIterable & RawRepresentable, Value.RawValue == String {
    /// One of the domain's own words (an enum of them), given or refused,
    /// the nearest named when it is a slip.
    public static func choice(_ name: String, _ type: Value.Type) -> Self {
        let words = Value.allCases.map(\.rawValue)
        precondition(!words.isEmpty, "cli: <\(name)>: choices names nothing")
        return .init(
            spec: .init(name: name, needed: true, rest: false, choices: words),
            take: { Value(rawValue: $0[0])! })
    }
}
