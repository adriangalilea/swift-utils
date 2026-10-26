extension TerminalProgram {
    /// A flag, declared once and read back by the same value: its type is
    /// the compiler's, never a string lookup, and what it is when absent is
    /// its type's (`false`, `nil`, `[]`; a required one is never absent: the
    /// parse refuses the call without it).
    ///
    ///     static let secret = Flag.on("secret", short: "s", says: "hidden, never shown again")
    ///     static let minutes = Flag.number("minutes", value: "<n>", says: "how long it waits")
    ///     static let to = Flag.list("to", value: "<pane>", says: "a pane to type it into")
    ///     …
    ///     let minutes = call[F.minutes] ?? 5          // Double?
    public struct Flag<Value: Sendable>: Sendable, FlagDescribing {
        public let spec: FlagSpec
        /// What it reads as when the call does not give it; nil: required.
        let absent: Value?
    }

    /// A flag without its type: what the parse and the renderings read.
    public struct FlagSpec: Sendable {
        public enum Shape: Sendable {
            /// A switch: `--json`.
            case on
            /// One value: `--dir <path>`; given twice, the last one counts.
            case value
            /// Repeatable, each value read on its own (never split on commas:
            /// a URL holds commas): `--to a --to b`.
            case list
            /// Several switches that are one value: `--quiet|--active|--interrupt`.
            case oneOf([Option])
        }

        /// One switch of a `oneOf`, and the value it stands for.
        public struct Option: Sendable {
            public let name: String
            public let short: Character?
            public let says: String
            let value: any Sendable
        }

        /// The key the call holds its value by: the flag's name (a `oneOf`'s
        /// group name, which nobody types).
        public let name: String
        public let short: Character?
        /// The value as the help shows it (`<path>`); empty for a switch.
        public let placeholder: String
        public let says: String
        /// The words it takes, for the help (`(credit, debit)`).
        public let choices: [String]?
        public let required: Bool
        public let shape: Shape
        /// One value as typed, read into the flag's type or refused.
        let read: @Sendable (String) throws(Refusal) -> any Sendable
    }
}

extension TerminalProgram {
    /// Anything a command lists among its flags.
    public protocol FlagDescribing: Sendable {
        var spec: TerminalProgram.FlagSpec { get }
    }
}

extension TerminalProgram.Flag where Value == Bool {
    /// A switch, false when absent.
    public static func on(_ name: String, short: Character? = nil, says: String) -> Self {
        Self(
            spec: .init(
                name: name, short: short, placeholder: "", says: says, choices: nil,
                required: false,
                shape: .on, read: { _ in true }),
            absent: false)
    }
}

extension TerminalProgram.Flag where Value == String? {
    /// A value as typed, nil when absent.
    public static func value(
        _ name: String, short: Character? = nil, value: String = "<value>", says: String
    ) -> Self {
        Self(
            spec: .init(
                name: name, short: short, placeholder: value, says: says, choices: nil,
                required: false,
                shape: .value, read: { $0 }),
            absent: .some(nil))
    }
}

extension TerminalProgram.Flag where Value == Int? {
    /// A whole number, nil when absent.
    public static func integer(
        _ name: String, short: Character? = nil, value: String = "<n>", says: String
    ) -> Self {
        Self(
            spec: .init(
                name: name, short: short, placeholder: value, says: says, choices: nil,
                required: false,
                shape: .value,
                read: { s throws(TerminalProgram.Refusal) in
                    guard let n = Int(s) else {
                        throw .usage("--\(name) takes a whole number, not \"\(s)\"")
                    }
                    return n
                }),
            absent: .some(nil))
    }
}

extension TerminalProgram.Flag where Value == Double? {
    /// A number, nil when absent.
    public static func number(
        _ name: String, short: Character? = nil, value: String = "<n>", says: String
    ) -> Self {
        Self(
            spec: .init(
                name: name, short: short, placeholder: value, says: says, choices: nil,
                required: false,
                shape: .value,
                read: { s throws(TerminalProgram.Refusal) in
                    guard let n = Double(s), n.isFinite else {
                        throw .usage("--\(name) takes a number, not \"\(s)\"")
                    }
                    return n
                }),
            absent: .some(nil))
    }
}

extension TerminalProgram.Flag {
    /// A value read into the program's own type (a URL, a `label=url` pair),
    /// nil when absent. `read` refuses what it cannot read, saying why.
    public static func value<T: Sendable>(
        _ name: String, short: Character? = nil, value: String, says: String,
        read: @escaping @Sendable (String) throws(TerminalProgram.Refusal) -> T
    ) -> Self where Value == T? {
        .init(
            spec: .init(
                name: name, short: short, placeholder: value, says: says, choices: nil,
                required: false,
                shape: .value, read: { s throws(TerminalProgram.Refusal) in try read(s) }),
            absent: .some(nil))
    }

    /// One of the domain's own words (an enum of them), nil when absent: the
    /// flag cannot drift from the type it names.
    public static func choice<E: CaseIterable & RawRepresentable & Sendable>(
        _ name: String, _ type: E.Type, short: Character? = nil, value: String? = nil, says: String
    ) -> Self where Value == E?, E.RawValue == String {
        let words = E.allCases.map(\.rawValue)
        precondition(!words.isEmpty, "cli: --\(name): choices names nothing")
        return .init(
            spec: .init(
                name: name, short: short, placeholder: value ?? "<\(words.joined(separator: "|"))>",
                says: says,
                choices: words, required: false, shape: .value,
                read: { s throws(TerminalProgram.Refusal) in
                    guard let word = E(rawValue: s) else {
                        throw .usage("--\(name): \"\(s)\" is not \(words.joined(separator: ", "))")
                    }
                    return word
                }),
            absent: .some(nil))
    }

    /// Repeatable, each value read on its own, [] when absent.
    public static func list<T: Sendable>(
        _ name: String, short: Character? = nil, value: String, says: String,
        read: @escaping @Sendable (String) throws(TerminalProgram.Refusal) -> T
    ) -> Self where Value == [T] {
        .init(
            spec: .init(
                name: name, short: short, placeholder: value, says: says, choices: nil,
                required: false,
                shape: .list, read: { s throws(TerminalProgram.Refusal) in try read(s) }),
            absent: [])
    }

    /// Repeatable values as typed, [] when absent.
    public static func list(
        _ name: String, short: Character? = nil, value: String, says: String
    ) -> Self where Value == [String] {
        list(name, short: short, value: value, says: says, read: { $0 })
    }

    /// Several switches that are one value, nil when none is given, refused
    /// when two are: `--quiet|--active|--interrupt` read as one `Urgency?`.
    /// `name` is the group's, for the call and the help, never typed.
    public static func oneOf<E: Sendable>(
        _ name: String, _ options: [(name: String, short: Character?, value: E, says: String)]
    ) -> Self where Value == E? {
        precondition(options.count >= 2, "cli: \(name): one of needs two switches at least")
        return .init(
            spec: .init(
                name: name, short: nil, placeholder: "", says: "", choices: nil, required: false,
                shape: .oneOf(
                    options.map {
                        .init(name: $0.name, short: $0.short, says: $0.says, value: $0.value)
                    }),
                read: { _ in preconditionFailure("cli: a oneOf is read by its switches") }),
            absent: .some(nil))
    }

    /// This flag, refused when absent, and so never nil.
    public func required<T: Sendable>() -> TerminalProgram.Flag<T> where Value == T? {
        guard case .value = spec.shape else {
            preconditionFailure("cli: --\(spec.name): only a value is required")
        }
        return .init(
            spec: .init(
                name: spec.name, short: spec.short, placeholder: spec.placeholder, says: spec.says,
                choices: spec.choices, required: true, shape: spec.shape, read: spec.read),
            absent: nil)
    }
}

extension TerminalProgram.FlagSpec {
    /// Every spelling a person types: the flag itself, or each switch of a
    /// `oneOf`.
    var spellings: [(name: String, short: Character?, takesValue: Bool)] {
        switch shape {
        case .on: [(name, short, false)]
        case .value, .list: [(name, short, true)]
        case .oneOf(let options): options.map { ($0.name, $0.short, false) }
        }
    }

    /// As the help shows it: `-d, --dir <path>`, a list `--to <pane>…`, a
    /// group `--quiet|--active|--interrupt`.
    var text: String {
        switch shape {
        case .on: "\(short.map { "-\($0), " } ?? "")--\(name)"
        case .value: "\(short.map { "-\($0), " } ?? "")--\(name) \(placeholder)"
        case .list: "\(short.map { "-\($0), " } ?? "")--\(name) \(placeholder)…"
        case .oneOf(let options): options.map { "--\($0.name)" }.joined(separator: "|")
        }
    }
}
