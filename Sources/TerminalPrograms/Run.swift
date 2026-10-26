import Foundation
import Terminal

extension TerminalProgram {
    /// The description as data: what `help --json` prints, the same facts
    /// the help and the skill render.
    public struct Description: Codable, Sendable, Equatable {
        public struct Flag: Codable, Sendable, Equatable {
            public let flag: String
            public let says: String
        }
        public struct Exit: Codable, Sendable, Equatable {
            public let code: Int32
            public let says: String
        }
        public struct Command: Codable, Sendable, Equatable {
            public let name: String
            public let usage: String
            public let section: String
            public let says: String
            public let more: String?
            public let aliases: [String]?
            public let choices: [String: [String]]?
            public let flags: [Flag]
            public let stdin: String?
            public let passthrough: String?
            public let examples: [String]?
            public let json: String?
            public let exits: [Exit]?
            public let hidden: Bool?
        }
        public struct Guide: Codable, Sendable, Equatable {
            public let name: String
            public let title: String
            public let says: String
            public let body: String
        }
        public let name: String
        public let version: String?
        public let says: String
        public let about: [String]?
        public let useWhen: [String]?
        public let never: [String]?
        public let commands: [Command]
        public let guides: [Guide]
        public let global: [Flag]
        public let environment: [Flag]
        public let exits: [Exit]
    }
}

extension TerminalProgram.Program {
    public var described: TerminalProgram.Description {
        let plain = Palette(enabled: false)
        return .init(
            name: name, version: version, says: says, about: about.isEmpty ? nil : about,
            useWhen: skill?.useWhen, never: skill.flatMap { $0.never.isEmpty ? nil : $0.never },
            commands: table.entries.map { entry in
                let c = entry.command
                let choices = Dictionary(
                    uniqueKeysWithValues: c.args.compactMap { a in a.choices.map { (a.name, $0) } })
                return .init(
                    name: c.name, usage: plainUsage(c), section: c.section, says: c.says,
                    more: c.more,
                    aliases: c.aliases.isEmpty ? nil : c.aliases,
                    choices: choices.isEmpty ? nil : choices,
                    flags: flagRows(c, plain).map { .init(flag: $0.0, says: $0.1) }, stdin: c.stdin,
                    passthrough: c.passthrough, examples: c.examples.isEmpty ? nil : c.examples,
                    json: c.json,
                    exits: c.exits.isEmpty
                        ? nil : c.exits.map { .init(code: $0.code, says: $0.says) },
                    hidden: c.hidden ? true : nil)
            },
            guides: guides.map {
                .init(name: $0.name, title: $0.title, says: $0.says, body: $0.body)
            },
            global: programFlags.map { .init(flag: $0.0, says: $0.1) },
            environment: environment.map { .init(flag: $0.name, says: $0.says) },
            exits: allExits.map { .init(code: $0.code, says: $0.says) })
    }

    /// The program run: argv read, the help, the version and the skill
    /// answered, any command handed to `run`, and the process ended with the
    /// exit that came of it. A `Refusal` is said (red on stderr, or
    /// `{"error":{…}}` on stdout under `--json`) and ends with its exit; any
    /// other error is said with the program's name and ends with 1.
    public func main(
        _ run: @Sendable (TerminalProgram.Call<Verb>) async throws -> TerminalProgram.Exit
    ) async -> Never {
        let call = read()
        let ended: TerminalProgram.Exit
        do {
            ended = try await run(call)
        } catch let refusal as TerminalProgram.Refusal {
            fail(refusal, json: call.json)
        } catch {
            fail(TerminalProgram.Refusal(.failed, "\(name): \(error)"), json: call.json)
        }
        exit(ended.code)
    }

    /// argv read for a program written as a script (top-level code, not one
    /// handler): the help, the version, the skill and every refusal answered
    /// here, ending the process; a command's call returned.
    public func read(_ argv: [String] = Array(CommandLine.arguments.dropFirst()))
        -> TerminalProgram.Call<Verb>
    {
        // `--json` counts only before `--`: after it, the words are a command's.
        let json = self.json && argv.prefix { $0 != "--" }.contains("--json")
        do throws(TerminalProgram.Refusal) {
            switch try parse(argv) {
            case .run(let call): return call
            case .show(let page):
                try show(page, json: json, .terminal)
                exit(0)
            }
        } catch {
            fail(error, json: json)
        }
    }

    /// The refusal said (red on stderr, or `{"error":{…}}` on stdout under
    /// `--json`), and the process ended with its exit.
    public func fail(_ refusal: TerminalProgram.Refusal, json: Bool) -> Never {
        say(refusal, json: json)
        exit(refusal.exit.code)
    }

    func show(_ page: TerminalProgram.Page, json: Bool, _ r: Rendering) throws(TerminalProgram
        .Refusal)
    {
        switch page {
        case .version:
            print(json ? Self.encoded(["version": version ?? ""]) : version ?? "")
        case .overview:
            print(json ? Self.encoded(described) : overview(r), terminator: json ? "\n" : "")
        case .detail(let entryName):
            if json {
                print(Self.encoded(described.commands.first { $0.name == entryName }))
            } else {
                print(detail(entryName, r), terminator: "")
            }
        case .guide(let guideName):
            if json {
                print(Self.encoded(described.guides.first { $0.name == guideName }))
            } else {
                print(guide(guideName, r), terminator: "")
            }
        case .skill(.show): print(skillMarkdown, terminator: "")
        case .skill(.status): print(skillStatus())
        case .skill(.install): print(try installSkill())
        case .skill(.remove): print(try removeSkill())
        }
    }

    func say(_ refusal: TerminalProgram.Refusal, json: Bool) {
        if json {
            var error: [String: String] = [
                "code": String(refusal.exit.code), "message": refusal.message,
            ]
            for (k, v) in refusal.fields { error[k] = v }
            print(Self.encoded(["error": error]))
        } else {
            FileHandle.standardError.write(Data((ui.bad(refusal.message) + "\n").utf8))
        }
    }

    static func encoded<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try! encoder.encode(value), as: UTF8.self)
    }
}
