import Foundation
import Testing

@testable import TerminalPrograms

typealias Flag = TerminalProgram.Flag
typealias Arg = TerminalProgram.Arg

enum Env: String, CaseIterable, Sendable { case staging, production }
enum Loudness: Sendable, Equatable { case quiet, active, interrupt }

enum F {
    static let to = Flag.list("to", short: "t", value: "<people>", says: "only for them")
    static let selfOnly = Flag.on("self", short: "s", says: "for you")
    static let watch = Flag.on("watch", short: "w", says: "wait for sends")
    static let dir = Flag.value("dir", short: "d", value: "<path>", says: "where")
    static let limit = Flag.integer("limit", says: "at most")
    static let minutes = Flag.number("minutes", says: "how long it waits")
    static let folder = Flag.value("folder", value: "<folder>", says: "only these").required()
    static let loudness = Flag.oneOf(
        "loudness",
        [
            (name: "quiet", short: nil, value: Loudness.quiet, says: "in the list, never rings"),
            (name: "active", short: nil, value: Loudness.active, says: "rings, held by a Focus"),
            (name: "interrupt", short: nil, value: Loudness.interrupt, says: "through a Focus"),
        ])
    static let pay = Flag.value("pay", value: "<url>", says: "a yes that pays for it")
    static let wallet = Flag.value("wallet", value: "<ref>", says: "the key that pays")
    static let begin = Flag.on("begin", says: "start a line")
    static let end = Flag.on("end", says: "end it")
}

enum A {
    static let path = Arg.needed("path")
    static let name = Arg.optional("name")
    static let env = Arg.choice("env", Env.self)
    static let note = Arg.optional("note")
    static let words = Arg.rest("words")
    static let title = Arg.optional("title")
}

enum Eid: TerminalProgram.Commands {
    case send, inbox, ls, deploy, ask, notify, invoice, invoiceCreate, hook

    var command: TerminalProgram.Command {
        switch self {
        case .send:
            .init(
                "send", section: "files", args: [A.path, A.name], flags: [F.to, F.selfOnly],
                says: "send a file",
                more: "Sends one file or folder. Refuses a path that does not exist.",
                examples: ["eid send notes.zip", "eid send ~/x --to ada"],
                json: "SendMade: { id, url, expires }",
                aliases: ["s"])
        case .inbox:
            .init("inbox", section: "files", flags: [F.watch, F.dir], says: "what is waiting")
        case .ls: .init("ls", section: "files", flags: [F.limit, F.folder], says: "your links")
        case .deploy:
            .init(
                "deploy", section: "card", args: [A.env, A.note], says: "deploy",
                exits: [.init(77, "denied")])
        case .ask:
            .init(
                "ask", section: "card", args: [A.title],
                flags: [F.minutes, F.loudness, F.pay, F.wallet],
                passthrough: "command [args…]", says: "ask the person",
                requires: [(F.wallet, needs: F.pay)])
        case .notify:
            .init(
                "notify", section: "card", args: [A.words], flags: [F.begin, F.end],
                says: "tell them", excludes: [[F.begin, F.end]])
        case .invoice: .init("invoice", section: "card", args: [A.path], says: "one invoice")
        case .invoiceCreate: .init("invoice create", section: "card", says: "a draft")
        case .hook: .init("hook", says: "run by hooks", hidden: true)
        }
    }
}

let eid = TerminalProgram.Program<Eid>(
    name: "eid", says: "your e-ID from a terminal", about: ["also a second line"], version: "1.2.3",
    json: true,
    environment: [.init("EID_URL", says: "another e-ID")], exits: [.init(77, "denied")],
    guides: [
        .init(
            "waiting", title: "Waiting for an answer", says: "a question can take minutes",
            body: "Run it in the background.\n\n- read its exit\n- never poll")
    ],
    skill: .init(useWhen: ["sending files", "asking a person"], never: ["ask in the terminal"]))

func run(_ argv: [String]) throws(TerminalProgram.Refusal) -> TerminalProgram.Call<Eid> {
    guard case .run(let call) = try eid.parse(argv) else {
        preconditionFailure("not a run: \(argv)")
    }
    return call
}

func refusal(_ argv: [String]) -> String {
    do throws(TerminalProgram.Refusal) {
        _ = try eid.parse(argv)
        return "parsed"
    } catch {
        #expect(error.exit == .usage)
        return error.message
    }
}

@Test func typedValuesComeBackByTheirDeclaration() throws {
    let call = try run(["send", "notes.zip", "--to", "ada", "-t", "bob", "-s"])
    #expect(call.command == .send)
    #expect(call[A.path] == "notes.zip")
    #expect(call[A.name] == nil)
    #expect(call[F.to] == ["ada", "bob"])
    #expect(call[F.selfOnly] == true)
    let ls = try run(["ls", "--limit", "-5", "--folder=inbox"])
    #expect(ls[F.limit] == -5)
    #expect(ls[F.folder] == "inbox")
    let inbox = try run(["inbox", "-wd/x"])
    #expect(inbox[F.watch] && inbox[F.dir] == "/x")
    #expect(try run(["s", "a"]).command == .send)
}

@Test func whatFollowsTheDashIsTheCommandsOwn() throws {
    let call = try run(["ask", "Deploy?", "--quiet", "--", "./deploy", "--help", "--json"])
    #expect(call[A.title] == "Deploy?")
    #expect(call.passthrough == ["./deploy", "--help", "--json"])
    #expect(call[F.loudness] == .quiet)
    #expect(call.json == false)
    // A command that passes nothing through takes those words as arguments.
    #expect(try run(["notify", "--", "--begin", "x"])[A.words] == ["--begin", "x"])
}

@Test func refusalsSayWhatToTypeInstead() {
    #expect(refusal(["inbox", "--wach"]) == "--wach is no flag of eid inbox: --watch?")
    #expect(refusal(["inbox", "-x"]) == "-x is no flag of eid inbox: eid help inbox")
    #expect(
        refusal(["send", "a", "--watch"]) == "--watch is not a flag of eid send: it is eid inbox's")
    #expect(refusal(["inbox", "--dir"]) == "--dir needs a value: -d, --dir <path>")
    #expect(refusal(["inbox", "--watch=yes"]) == "--watch takes no value")
    #expect(
        refusal(["ls", "--limit", "x", "--folder", "a"])
            == "--limit takes a whole number, not \"x\"")
    #expect(refusal(["ls"]) == "eid ls needs --folder <folder>: only these")
    #expect(refusal(["send"]) == "eid send needs <path>: eid send <path> [name]")
    #expect(
        refusal(["send", "a", "b", "c"]) == "eid send takes <path> [name]; \"c\" is one too many")
    #expect(refusal(["inbox", "x"]) == "eid inbox takes no arguments; \"x\" is one too many")
    #expect(refusal(["deploy", "stagin"]) == "\"stagin\" is no <env> of eid deploy: staging?")
    #expect(refusal(["sned"]) == "No command \"sned\": eid send?")
    #expect(refusal(["zzz"]) == "No command \"zzz\": eid help")
    #expect(
        refusal(["invoice", "crate"]) == "eid invoice crate: no such action: eid invoice create?")
    #expect(
        refusal(["ask", "--quiet", "--active"]) == "--quiet and --active are one choice: give one")
    #expect(
        refusal(["notify", "x", "--begin", "--end"]) == "--begin and --end: give one, not both")
    #expect(refusal(["ask", "--wallet", "w"]) == "--wallet needs --pay")
    #expect(refusal(["waiting"]) == "\"waiting\" is a guide: eid help waiting")
}

func page(_ argv: [String]) throws -> TerminalProgram.Page? {
    if case .show(let page) = try eid.parse(argv) { page } else { nil }
}

@Test func theProgramAnswersItsOwnPages() throws {
    #expect(try page([]) == .overview)
    #expect(try page(["help"]) == .overview)
    #expect(try page(["help", "send"]) == .detail("send"))
    #expect(try page(["send", "--help"]) == .detail("send"))
    #expect(try page(["--help"]) == .overview)
    #expect(try page(["help", "waiting"]) == .guide("waiting"))
    #expect(try page(["--version", "send"]) == .version)
    #expect(try page(["skill"]) == .skill(.status))
    #expect(try page(["skill", "install"]) == .skill(.install))
    // Help after `--` is the command's, never the program's.
    #expect(try run(["ask", "--", "x", "--help"]).passthrough == ["x", "--help"])
}

@Test func theHelpAndTheSkillSayTheSameThings() {
    let overview = eid.overview(.plain)
    let skill = eid.skillMarkdown
    for said in [
        "send a file", "a question can take minutes", "sending files", "ask in the terminal",
        "denied", "EID_URL",
    ] {
        #expect(overview.contains(said), "overview lacks \(said)")
        #expect(skill.contains(said), "skill lacks \(said)")
    }
    let detail = eid.detail("send", .plain)
    for said in [
        "Sends one file or folder", "eid send ~/x --to ada", "SendMade", "-t, --to <people>…",
    ] {
        #expect(detail.contains(said), "detail lacks \(said)")
        #expect(skill.contains(said), "skill lacks \(said)")
    }
    #expect(!overview.contains("run by hooks") && !skill.contains("run by hooks"))
    #expect(eid.detail("hook", .plain).contains("run by hooks"))
    #expect(
        skill.hasPrefix(
            "---\nname: eid\ndescription: \"Your e-ID from a terminal. Use it for: sending files; asking a person. Never ask in the terminal.\"\n"
        ))
    #expect(eid.detail("ask", .plain).contains("eid ask [title] -- command [args…]"))
    #expect(eid.detail("ask", .plain).contains("(with --pay)"))
    #expect(eid.detail("notify", .plain).contains("(not with --end)"))
}

@Test func theOverviewReadsLikeTsUtils() {
    print(eid.overview(.plain))
    print(eid.detail("send", .plain))
    print(eid.skillMarkdown)
}
