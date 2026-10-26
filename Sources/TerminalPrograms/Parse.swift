import Foundation

extension TerminalProgram {
    /// What argv asks for: a command of the program's to run, or something
    /// the program answers itself (the help, the version, the skill).
    public enum Parsed<Verb: Commands>: Sendable {
        case run(Call<Verb>)
        case show(Page)
    }

    /// One command asked for, its flags and arguments read and checked:
    /// `call[flag]` and `call[arg]` are typed by their declarations and never
    /// fail (the parse refused anything they could not be).
    public struct Call<Verb: Commands>: Sendable {
        public let command: Verb
        /// What followed `--`, for a command that passes it through.
        public let passthrough: [String]
        /// `--json` was given (a program declared with `json: true`).
        public let json: Bool
        let values: [String: any Sendable]
        let words: [String]

        public subscript<V>(_ flag: Flag<V>) -> V {
            let key = flag.spec.name
            precondition(
                command.command.flags.contains { $0.name == key },
                "cli: \(command.command.name) reads --\(key), which it does not declare")
            if let value = values[key] {
                guard let typed = value as? V else {
                    preconditionFailure("cli: --\(key) holds \(type(of: value)), read as \(V.self)")
                }
                return typed
            }
            guard let absent = flag.absent else {
                preconditionFailure("cli: --\(key) is required, and the parse let it go")
            }
            return absent
        }

        public subscript<V>(_ arg: Arg<V>) -> V {
            let args = command.command.args
            guard let at = args.firstIndex(where: { $0.name == arg.spec.name }) else {
                preconditionFailure(
                    "cli: \(command.command.name) reads <\(arg.spec.name)>, which it does not declare"
                )
            }
            // Needed arguments come first (the program's check), so position
            // `at` is the argument's word, and a rest argument's words are
            // every one from it on.
            let covered =
                arg.spec.rest ? Array(words.dropFirst(at)) : (at < words.count ? [words[at]] : [])
            return arg.take(covered)
        }

        /// The document the command reads from stdin, refused when stdin is
        /// a terminal: nobody is going to type it.
        public func stdin() throws(Refusal) -> Data {
            guard let document = command.command.stdin else {
                preconditionFailure(
                    "cli: \(command.command.name) reads stdin, which it does not declare")
            }
            guard isatty(STDIN_FILENO) != 1 else {
                throw .usage("\(command.command.name) reads \(document) on stdin: … < \(document)")
            }
            return FileHandle.standardInput.readDataToEndOfFile()
        }
    }
}

extension TerminalProgram.Program {
    /// One piece of argv: a word, or a flag as typed.
    enum Token: Equatable {
        case word(String)
        /// `name`: the long spelling, or the letter for a letter no flag has.
        case flag(name: String, said: String, value: String?, missing: Bool, extra: Bool)
    }

    /// argv read once, against every spelling of every command (whether a
    /// flag takes a value is known before the command is): `--dir=x` and
    /// `--dir x`, letters grouped (`-wo`, `-wd ~/x`, `-wd~/x`), a lone `-` a
    /// word, a dash before a digit no flag spells (`-5`, `--09-29`) a word.
    /// Everything after `--` is returned apart, untouched.
    func tokenize(_ argv: [String]) -> (tokens: [Token], afterDash: [String]?) {
        func spellsFlag(_ a: String) -> Bool {
            if a.hasPrefix("--") {
                return table.takesValue[
                    String(a.dropFirst(2).split(separator: "=", maxSplits: 1).first ?? "")] != nil
            }
            return a.dropFirst().first.map { table.shortOf[$0] != nil } ?? false
        }
        func isWord(_ a: String) -> Bool {
            !a.hasPrefix("-") || a == "-" || (a.wholeMatch(of: /--?\d.*/) != nil && !spellsFlag(a))
        }
        var out: [Token] = []
        var i = 0
        while i < argv.count {
            let a = argv[i]
            if a == "--" { return (out, Array(argv[(i + 1)...])) }
            if isWord(a) {
                out.append(.word(a))
                i += 1
                continue
            }
            func valueAfter(_ name: String, _ said: String) {
                if i + 1 < argv.count, argv[i + 1] != "--", isWord(argv[i + 1]) {
                    out.append(
                        .flag(
                            name: name, said: said, value: argv[i + 1], missing: false, extra: false
                        ))
                    i += 1
                } else {
                    out.append(
                        .flag(name: name, said: said, value: nil, missing: true, extra: false))
                }
            }
            if a.hasPrefix("--") {
                let body = a.dropFirst(2)
                let name = String(
                    body.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)[0])
                let inline = body.contains("=") ? String(body.drop { $0 != "=" }.dropFirst()) : nil
                let said = "--\(name)"
                switch table.takesValue[name] {
                case nil:
                    out.append(
                        .flag(name: name, said: said, value: nil, missing: false, extra: false))
                case false?:
                    out.append(
                        .flag(
                            name: name, said: said, value: nil, missing: false, extra: inline != nil
                        ))
                case true?:
                    if let inline {
                        out.append(
                            .flag(
                                name: name, said: said, value: inline, missing: false, extra: false)
                        )
                    } else {
                        valueAfter(name, said)
                    }
                }
                i += 1
                continue
            }
            var letters = Substring(a.dropFirst())
            while let letter = letters.popFirst() {
                let said = "-\(letter)"
                guard let name = table.shortOf[letter] else {
                    out.append(
                        .flag(
                            name: String(letter), said: said, value: nil, missing: false,
                            extra: false))
                    continue
                }
                guard table.takesValue[name] == true else {
                    out.append(
                        .flag(name: name, said: said, value: nil, missing: false, extra: false))
                    continue
                }
                if letters.isEmpty {
                    valueAfter(name, said)
                } else {
                    out.append(
                        .flag(
                            name: name, said: said, value: String(letters), missing: false,
                            extra: false))
                }
                break
            }
            i += 1
        }
        return (out, nil)
    }

    /// argv read: the command asked for, or what the program answers itself.
    /// A mistake throws a `Refusal` (exit 64) saying what to type instead.
    /// Pure: no environment, no files, no terminal.
    public func parse(_ argv: [String]) throws(TerminalProgram.Refusal)
        -> TerminalProgram.Parsed<Verb>
    {
        let (tokens, afterDash) = tokenize(argv)
        let before = tokens.compactMap { if case .word(let w) = $0 { w } else { nil } }
        let commandNames = table.entries.map(\.name)

        func spelled(_ words: [String]) -> (name: String, rest: [String])? {
            for k in stride(from: min(words.count, table.mostWords), through: 1, by: -1) {
                if let entryName = table.canonical[words.prefix(k).joined(separator: " ")] {
                    return (entryName, Array(words.dropFirst(k)))
                }
            }
            return nil
        }
        func noCommand(_ word: String) -> TerminalProgram.Refusal {
            let guess = Words.nearest(word, among: commandNames)
            if let guess {
                let also =
                    defaultCommand.map {
                        $0.claims(word) ? ", or \(name) \($0.command.command.name) \(word)" : ""
                    } ?? ""
                return .usage("No command \"\(word)\": \(name) \(guess)?\(also)")
            }
            if guides.contains(where: { $0.name == word }) {
                return .usage("\"\(word)\" is a guide: \(name) help \(word)")
            }
            if let taken = defaultCommand?.command.command.args.first?.name {
                return .usage("\"\(word)\" is no command and no <\(taken)>: \(name) help")
            }
            return .usage("No command \"\(word)\": \(name) help")
        }

        // A command passes `--` through: what follows is its, untouched. Any
        // other reads it as words, as before `--`.
        let words = before + (afterDash ?? [])
        var found: (name: String, rest: [String])
        var namedBeforeDash = true
        if let spelledBefore = spelled(before) {
            found = spelledBefore
        } else if words.isEmpty {
            found = bare.map { ($0.command.name, []) } ?? ("help", [])
        } else if let first = before.first, let defaultCommand, defaultCommand.claims(first),
            Words.nearest(first, among: commandNames) == nil
        {
            found = (defaultCommand.command.command.name, before)
        } else if before.isEmpty, let spelledAfter = spelled(words) {
            found = spelledAfter
            namedBeforeDash = false
        } else {
            throw noCommand(before.first ?? words[0])
        }
        guard let (entry, command) = table.command(named: found.name) else {
            preconditionFailure("cli: the table spelled \(found.name), which it lacks")
        }
        // What follows `--`: the command's own when it passes it through,
        // else more of its arguments.
        var passthrough: [String] = []
        if namedBeforeDash, let afterDash {
            if command.passthrough != nil {
                passthrough = afterDash
            } else {
                found.rest += afterDash
            }
        }

        // Under a command with actions (`secrets read`), a first argument a
        // slip away from an action is the action misspelt, never a value.
        let actions = commandNames.filter {
            $0.hasPrefix(found.name + " ") && !$0.dropFirst(found.name.count + 1).contains(" ")
        }.map { String($0.dropFirst(found.name.count + 1)) }
        if let first = found.rest.first, let meant = Words.nearest(first, among: actions) {
            throw .usage(
                "\(name) \(found.name) \(first): no such action: \(name) \(found.name) \(meant)?")
        }

        let allowed = table.flags(of: found.name)
        // A spelling → the flag it is (a switch of a `oneOf` → its group).
        var spellingOf: [String: TerminalProgram.FlagSpec] = [:]
        for spec in allowed { for spelling in spec.spellings { spellingOf[spelling.name] = spec } }
        let flags = tokens.compactMap {
            token -> (name: String, said: String, value: String?, missing: Bool, extra: Bool)? in
            if case .flag(let n, let s, let v, let m, let e) = token {
                (n, s, v, m, e)
            } else {
                nil
            }
        }
        let typedName = before.isEmpty ? name : "\(name) \(found.name)"
        let list = before.isEmpty ? "\(name) help" : "\(name) help \(found.name)"
        for flag in flags where spellingOf[flag.name] == nil {
            if let whose = table.owners[flag.name] {
                throw .usage(
                    "\(flag.said) is not a flag of \(typedName): it is \(whose.map { "\(name) \($0)" }.joined(separator: ", "))'s"
                )
            }
            if flag.name == "version", version == nil {
                throw .usage("\(name) has no version: it runs from its source, never released")
            }
            let guess = Words.nearest(
                flag.name, among: allowed.flatMap { $0.spellings.map(\.name) })
            throw .usage(
                "\(flag.said) is no flag of \(typedName): \(guess.map { "--\($0)?" } ?? list)")
        }
        for flag in flags {
            let spec = spellingOf[flag.name]!
            if flag.missing { throw .usage("--\(flag.name) needs a value: \(spec.text)") }
            if flag.extra { throw .usage("--\(flag.name) takes no value") }
        }

        var values: [String: any Sendable] = [:]
        var lists: [String: [any Sendable]] = [:]
        var askedHelp = false
        var askedVersion = false
        var chosen: [String: String] = [:]
        for flag in flags {
            let spec = spellingOf[flag.name]!
            switch spec.shape {
            case .on:
                if spec.name == "help" {
                    askedHelp = true
                } else if spec.name == "version" {
                    askedVersion = true
                } else {
                    values[spec.name] = true
                }
            case .value: values[spec.name] = try spec.read(flag.value!)
            case .list: lists[spec.name, default: []].append(try spec.read(flag.value!))
            case .oneOf(let options):
                if let had = chosen[spec.name], had != flag.name {
                    throw .usage("--\(had) and --\(flag.name) are one choice: give one")
                }
                chosen[spec.name] = flag.name
                values[spec.name] = options.first { $0.name == flag.name }!.value
            }
        }
        for (key, items) in lists { values[key] = items }

        if askedVersion { return .show(.version) }
        if askedHelp || entry == .help {
            // `--help` with no command typed is the program's, even when a
            // bare program runs one.
            if askedHelp, entry != .help {
                return .show(words.isEmpty ? .overview : .detail(found.name))
            }
            guard let topic = found.rest.first else { return .show(.overview) }
            if let about = spelled(found.rest) { return .show(.detail(about.name)) }
            if guides.contains(where: { $0.name == topic }) { return .show(.guide(topic)) }
            throw noCommand(topic)
        }

        // Arguments: counted, then each against the words it takes.
        let shape = command.args
        let least = shape.filter(\.needed).count
        let most = shape.last?.rest == true ? Int.max : shape.count
        let usage =
            "\(name) \(found.name)\(shape.isEmpty ? "" : " " + shape.map(\.text).joined(separator: " "))"
        if found.rest.count < least {
            let missing = shape.dropFirst(found.rest.count).filter(\.needed).map(\.text).joined(
                separator: " ")
            throw .usage("\(name) \(found.name) needs \(missing): \(usage)")
        }
        if found.rest.count > most {
            throw .usage(
                shape.isEmpty
                    ? "\(name) \(found.name) takes no arguments; \"\(found.rest[0])\" is one too many"
                    : "\(name) \(found.name) takes \(shape.map(\.text).joined(separator: " ")); \"\(found.rest[shape.count])\" is one too many"
            )
        }
        for (i, value) in found.rest.enumerated() {
            let arg = shape[min(i, shape.count - 1)]
            guard let choices = arg.choices, !choices.contains(value) else { continue }
            let guess = Words.nearest(value, among: choices)
            throw .usage(
                "\"\(value)\" is no <\(arg.name)> of \(name) \(found.name): \(guess.map { "\($0)?" } ?? choices.joined(separator: ", "))"
            )
        }
        for spec in allowed where spec.required && values[spec.name] == nil {
            throw .usage("\(name) \(found.name) needs \(spec.text): \(spec.says)")
        }
        for group in command.excludes {
            let given = group.filter { values[$0] != nil && (values[$0] as? Bool) != false }
            if given.count > 1 {
                throw .usage(
                    "\(given.map { "--\($0)" }.joined(separator: " and ")): give one, not both")
            }
        }
        for rule in command.requires where values[rule.flag] != nil && values[rule.needs] == nil {
            throw .usage("--\(rule.flag) needs --\(rule.needs)")
        }

        switch entry {
        case .verb(let verb):
            let json = self.json && values["json"] as? Bool == true
            values["json"] = nil
            return .run(
                .init(
                    command: verb, passthrough: passthrough, json: json, values: values,
                    words: found.rest))
        case .skill(let action): return .show(.skill(action))
        case .help: preconditionFailure("cli: help is answered above")
        }
    }
}

/// The word a person meant, for every "did you mean".
enum Words {
    /// The edits from `a` to `b`: a letter added, dropped or changed, or two
    /// neighbours swapped (`sned` → `send` is one, as a hand makes it).
    static func distance(_ a: String, _ b: String) -> Int {
        let a = Array(a)
        let b = Array(b)
        var d = (0...a.count).map { i in (0...b.count).map { j in i == 0 ? j : j == 0 ? i : 0 } }
        for i in stride(from: 1, through: a.count, by: 1) {
            for j in stride(from: 1, through: b.count, by: 1) {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                d[i][j] = min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + cost)
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
                    d[i][j] = min(d[i][j], d[i - 2][j - 2] + 1)
                }
            }
        }
        return d[a.count][b.count]
    }

    /// The word meant, where one is near enough to be a slip: one edit for a
    /// word of four letters or fewer, two for a longer one. The first of the
    /// nearest wins.
    static func nearest(_ word: String, among candidates: [String]) -> String? {
        let reach = word.count <= 4 ? 1 : 2
        return candidates.map { ($0, distance(word, $0)) }.filter { $0.1 <= reach }.min {
            $0.1 < $1.1
        }?.0
    }
}
