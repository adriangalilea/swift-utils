import Foundation
import Testing

@testable import TerminalPrograms

// The fixture is `notes`, a note-taking program made up for these tests and
// nothing else: one consistent program that uses every part of the module.
// A real program on it is listen (swift-senses).

typealias Flag = TerminalProgram.Flag
typealias Arg = TerminalProgram.Arg

enum Destination: String, CaseIterable, Sendable { case web, print }
enum Loudness: Sendable, Equatable { case quiet, active, interrupt }

enum F {
    static let tag = Flag.list("tag", short: "t", value: "<tag>", says: "a tag to file it under")
    static let pin = Flag.on("pin", short: "p", says: "keep it at the top")
    static let watch = Flag.on("watch", short: "w", says: "keep listing new notes")
    static let dir = Flag.value("dir", short: "d", value: "<path>", says: "the notes folder")
    static let limit = Flag.integer("limit", says: "at most this many")
    static let folder = Flag.value("folder", value: "<folder>", says: "only this folder").required()
    static let minutes = Flag.number("minutes", says: "how long from now")
    static let loudness = Flag.oneOf(
        "loudness",
        [
            (name: "quiet", short: nil, value: Loudness.quiet, says: "in the list, never rings"),
            (name: "active", short: nil, value: Loudness.active, says: "rings, held by a Focus"),
            (name: "interrupt", short: nil, value: Loudness.interrupt, says: "through a Focus"),
        ])
    static let every = Flag.value("every", value: "<n>d", says: "repeat every n days")
    static let until = Flag.value("until", value: "<date>", says: "the last repeat")
    static let begin = Flag.on("begin", says: "open a new day")
    static let end = Flag.on("end", says: "close the day")
}

enum A {
    static let file = Arg.needed("file")
    static let title = Arg.optional("title")
    static let destination = Arg.choice("destination", Destination.self)
    static let note = Arg.needed("note")
    static let words = Arg.rest("words")
    static let name = Arg.needed("name")
}

enum Notes: TerminalProgram.Commands {
    case add, ls, find, publish, remind, log, tag, tagCreate, sync

    var command: TerminalProgram.Command {
        switch self {
        case .add:
            .init(
                "add", section: "notes", args: [A.file, A.title], flags: [F.tag, F.pin],
                says: "add a file as a note",
                more: "Copies the file into the notes folder. Refuses a file that does not exist.",
                examples: ["notes add plan.md", "notes add ~/x.md --tag work"],
                json: "the note: { id, title, created }",
                aliases: ["a"])
        case .ls:
            .init(
                "ls", section: "notes", flags: [F.watch, F.dir], says: "every note, newest first")
        case .find:
            .init("find", section: "notes", flags: [F.limit, F.folder], says: "notes in a folder")
        case .publish:
            .init(
                "publish", section: "share", args: [A.destination, A.title],
                says: "publish the latest note", exits: [.init(77, "refused")])
        case .remind:
            .init(
                "remind", section: "share", args: [A.title],
                flags: [F.minutes, F.loudness, F.every, F.until],
                passthrough: "command [args…]", says: "remind you, then run the command",
                requires: [(F.until, needs: F.every)])
        case .log:
            .init(
                "log", section: "share", args: [A.words], flags: [F.begin, F.end],
                says: "append a line to today's log", excludes: [[F.begin, F.end]])
        case .tag: .init("tag", section: "tags", args: [A.name], says: "the notes with a tag")
        case .tagCreate: .init("tag create", section: "tags", says: "a new tag")
        case .sync: .init("sync", says: "run by the sync agent", hidden: true)
        }
    }
}

let notes = TerminalProgram.Program<Notes>(
    name: "notes", says: "notes from a terminal", about: ["Every note is a Markdown file."],
    version: "1.2.3", json: true,
    environment: [.init("NOTES_DIR", says: "where notes live")], exits: [.init(77, "refused")],
    guides: [
        .init(
            "folders", title: "Folders", says: "one folder per project",
            body: "Notes live in folders.\n\n- one folder per project\n- never nest them")
    ],
    skill: .init(
        useWhen: ["keeping what was decided", "finding an earlier note"],
        never: ["edit a note's file by hand"]))

func run(_ argv: [String]) throws(TerminalProgram.Refusal) -> TerminalProgram.Call<Notes> {
    guard case .run(let call) = try notes.parse(argv) else {
        preconditionFailure("not a run: \(argv)")
    }
    return call
}

func refusal(_ argv: [String]) -> String {
    do throws(TerminalProgram.Refusal) {
        _ = try notes.parse(argv)
        return "parsed"
    } catch {
        #expect(error.exit == .usage)
        return error.message
    }
}

@Test func typedValuesComeBackByTheirDeclaration() throws {
    let call = try run(["add", "plan.md", "--tag", "work", "-t", "q4", "-p"])
    #expect(call.command == .add)
    #expect(call[A.file] == "plan.md")
    #expect(call[A.title] == nil)
    #expect(call[F.tag] == ["work", "q4"])
    #expect(call[F.pin] == true)
    let find = try run(["find", "--limit", "-5", "--folder=work"])
    #expect(find[F.limit] == -5)
    #expect(find[F.folder] == "work")
    let ls = try run(["ls", "-wd/x"])
    #expect(ls[F.watch] && ls[F.dir] == "/x")
    #expect(try run(["a", "x.md"]).command == .add)
    #expect(try run(["publish", "web"])[A.destination] == .web)
}

@Test func whatFollowsTheDashIsTheCommandsOwn() throws {
    let call = try run(["remind", "Standup", "--quiet", "--", "./standup", "--help", "--json"])
    #expect(call[A.title] == "Standup")
    #expect(call.passthrough == ["./standup", "--help", "--json"])
    #expect(call[F.loudness] == .quiet)
    #expect(call.json == false)
    // A command that passes nothing through takes those words as arguments.
    #expect(try run(["log", "--", "--begin", "x"])[A.words] == ["--begin", "x"])
}

@Test func jsonIsTakenWhereACommandPrintsIt() throws {
    #expect(try run(["add", "x.md", "--json"]).json)
    #expect(
        refusal(["ls", "--json"]) == "notes ls prints no JSON; --json is notes add's")
    #expect(try page(["ls", "--help", "--json"]) == .detail("ls"))
    #expect(
        notes.programFlags.contains {
            $0 == ("--json", "the answer as JSON on stdout, on notes add")
        })
}

@Test func refusalsSayWhatToTypeInstead() {
    #expect(refusal(["ls", "--wach"]) == "--wach is no flag of notes ls: --watch?")
    #expect(refusal(["ls", "-x"]) == "-x is no flag of notes ls: notes help ls")
    #expect(
        refusal(["add", "a", "--watch"]) == "--watch is not a flag of notes add: it is notes ls's")
    #expect(refusal(["ls", "--dir"]) == "--dir needs a value: -d, --dir <path>")
    #expect(refusal(["ls", "--watch=yes"]) == "--watch takes no value")
    #expect(
        refusal(["find", "--limit", "x", "--folder", "a"])
            == "--limit takes a whole number, not \"x\"")
    #expect(refusal(["find"]) == "notes find needs --folder <folder>: only this folder")
    #expect(refusal(["add"]) == "notes add needs <file>: notes add <file> [title]")
    #expect(
        refusal(["add", "a", "b", "c"]) == "notes add takes <file> [title]; \"c\" is one too many")
    #expect(refusal(["ls", "x"]) == "notes ls takes no arguments; \"x\" is one too many")
    #expect(
        refusal(["publish", "wbe"]) == "\"wbe\" is no <destination> of notes publish: web?")
    #expect(refusal(["ad"]) == "No command \"ad\": notes add?")
    #expect(refusal(["zzz"]) == "No command \"zzz\": notes help")
    #expect(refusal(["tag", "crate"]) == "notes tag crate: no such action: notes tag create?")
    #expect(
        refusal(["remind", "--quiet", "--active"])
            == "--quiet and --active are one choice: give one")
    #expect(refusal(["log", "x", "--begin", "--end"]) == "--begin and --end: give one, not both")
    #expect(refusal(["remind", "--until", "friday"]) == "--until needs --every")
    #expect(refusal(["folders"]) == "\"folders\" is a guide: notes help folders")
}

func page(_ argv: [String]) throws -> TerminalProgram.Page? {
    if case .show(let page) = try notes.parse(argv) { page } else { nil }
}

@Test func theProgramAnswersItsOwnPages() throws {
    #expect(try page([]) == .overview)
    #expect(try page(["help"]) == .overview)
    #expect(try page(["help", "add"]) == .detail("add"))
    #expect(try page(["add", "--help"]) == .detail("add"))
    #expect(try page(["--help"]) == .overview)
    #expect(try page(["help", "folders"]) == .guide("folders"))
    #expect(try page(["--version", "add"]) == .version)
    #expect(try page(["skill"]) == .skill(.status))
    #expect(try page(["skill", "install"]) == .skill(.install))
    // Help after `--` is the command's, never the program's.
    #expect(try run(["remind", "--", "x", "--help"]).passthrough == ["x", "--help"])
}

@Test func theHelpAndTheSkillSayTheSameThings() {
    let overview = notes.overview(.plain)
    let skill = notes.skillMarkdown
    for said in [
        "add a file as a note", "one folder per project", "keeping what was decided",
        "edit a note's file by hand", "refused", "NOTES_DIR",
    ] {
        #expect(overview.contains(said), "overview lacks \(said)")
        #expect(skill.contains(said), "skill lacks \(said)")
    }
    let detail = notes.detail("add", .plain)
    for said in [
        "Copies the file into the notes folder", "notes add ~/x.md --tag work", "{ id, title",
        "-t, --tag <tag>…",
    ] {
        #expect(detail.contains(said), "detail lacks \(said)")
        #expect(skill.contains(said), "skill lacks \(said)")
    }
    #expect(!overview.contains("run by the sync agent") && !skill.contains("run by the sync agent"))
    #expect(notes.detail("sync", .plain).contains("run by the sync agent"))
    #expect(
        skill.hasPrefix(
            "---\nname: notes\ndescription: \"Notes from a terminal. Use it for: keeping what was decided; finding an earlier note. Never edit a note's file by hand.\"\n"
        ))
    #expect(notes.detail("remind", .plain).contains("notes remind [title] -- command [args…]"))
    #expect(notes.detail("remind", .plain).contains("(with --every)"))
    #expect(notes.detail("log", .plain).contains("(not with --end)"))
}
