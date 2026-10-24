import Foundation
import Testing

@testable import GitKit

/// Real output of real repositories, as git wrote it. `scenario/` is a capture
/// (`gitkit-capture`) of `scripts/gitkit-scenario.sh`'s repository: an agent's session in
/// every state git has; the rest are single reads of this package's own history, of vigil's
/// submodule and of a merge left in conflict.
enum Fixture {
    static let folder = Bundle.module.url(forResource: "Fixtures", withExtension: nil)!
    static func data(_ name: String) -> Data { try! Data(contentsOf: folder.appending(path: name)) }
    static func text(_ name: String) -> String { String(decoding: data(name), as: UTF8.self) }
    static var scenario: Git.FixtureSource {
        try! Git.FixtureSource(folder: folder.appending(path: "scenario"))
    }
}

struct DiffParsing {
    /// The agent's whole session (base → working tree, untracked included): every kind
    /// of change, each read as what it is.
    @Test func everyKindOfChange() throws {
        let manifest = Fixture.scenario.manifest
        let agent = try #require(manifest.agent)
        let file = try #require(manifest.diffs.first { $0.key == .since(agent.base) }?.file)
        let diff = try Git.Diff(parsing: Fixture.data("scenario/\(file)"))
        func find(_ path: String) throws -> Git.FileDiff {
            try #require(diff.files.first { $0.path == path })
        }

        let rename = try find("Sources/Ink/InkScrim.swift")
        #expect(rename.change == .renamed)
        #expect(rename.oldPath == "Sources/Ink/Scrim.swift")
        #expect(rename.similarity == 94)
        #expect(rename.additions == 1 && rename.deletions == 1)

        let deleted = try find("Sources/Ink/HUDGlass.swift")
        #expect(deleted.change == .deleted && deleted.newPath == nil && deleted.oldMode == "100644")
        #expect(deleted.hunks.allSatisfy { $0.lines.allSatisfy { $0.kind == .removed } })

        let added = try find("Sources/Ink/InkBadge.swift")
        #expect(added.change == .added && added.oldPath == nil && added.newMode == "100644")
        #expect(added.hunks.first?.newStart == 1 && added.deletions == 0)

        let mode = try find("scripts/grant-example-app.sh")
        #expect(
            mode.modeChanged && mode.oldMode == "100644" && mode.newMode == "100755"
                && mode.hunks.isEmpty)

        let binary = try find("Sources/Ink/Resources/badge.png")
        #expect(binary.isBinary && binary.change == .added && binary.hunks.isEmpty)

        let submodule = try find("Vendor/cmark")
        #expect(submodule.submodule?.old == "924936d0427cb25a61169739a7660230bffa6ea6")
        #expect(submodule.submodule?.new == "5698f9ff2cd2b4c0cf7d37e43440831d507a1aaa")

        // An untracked file, read through `diff --no-index`, with no final newline.
        let about = try find("Sources/Ink/Resources/ABOUT.txt")
        #expect(about.change == .added)
        #expect(about.hunks.last?.lines.last?.noNewline == true)
        #expect(about.hunks.last?.lines.dropLast().allSatisfy { !$0.noNewline } == true)

        #expect(diff.files.map(\.path).contains("NOTES.md"))
        #expect(diff.files.map(\.path).contains("TODO.md"))
    }

    /// The agent scope kept to what it touched leaves the person's edit (TODO.md) out.
    @Test func agentScopeKeepsToTouchedPaths() async throws {
        let source = Fixture.scenario
        let agent = try #require(source.manifest.agent)
        let diff = try await source.diff(agent.scope)
        #expect(!diff.files.contains { $0.path == "TODO.md" })
        #expect(diff.files.contains { $0.path == "Sources/Ink/InkScrim.swift" })
        #expect(diff.files.count == agent.touched.count - 1)  // Scrim.swift is the rename's old side
    }

    /// Self-consistency against the raw bytes, on a big real diff (4,690 lines, renames):
    /// one file per header, every `+`/`-` line counted, every hunk's lines matching its
    /// header's counts, numbers running without a gap.
    @Test func bigDiffAgreesWithItsBytes() throws {
        let text = Fixture.text("swift-utils-renames.diff")
        let start = Date()
        let diff = try Git.Diff(parsing: Fixture.data("swift-utils-renames.diff"))
        let elapsed = Date().timeIntervalSince(start)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        #expect(diff.files.count == lines.filter { $0.hasPrefix("diff --git ") }.count)
        #expect(
            diff.files.filter { $0.change == .renamed }.count
                == lines.filter { $0.hasPrefix("rename from ") }.count)
        let plus = lines.filter { $0.hasPrefix("+") && !$0.hasPrefix("+++ ") }.count
        let minus = lines.filter { $0.hasPrefix("-") && !$0.hasPrefix("--- ") }.count
        #expect(diff.additions == plus)
        #expect(diff.deletions == minus)
        for file in diff.files {
            for hunk in file.hunks {
                #expect(hunk.lines.filter { $0.kind != .added }.count == hunk.oldCount)
                #expect(hunk.lines.filter { $0.kind != .removed }.count == hunk.newCount)
                var old = hunk.oldStart
                var new = hunk.newStart
                for line in hunk.lines {
                    if line.kind != .added {
                        #expect(line.old == old)
                        old += 1
                    }
                    if line.kind != .removed {
                        #expect(line.new == new)
                        new += 1
                    }
                }
            }
        }
        #expect(elapsed < 1, "parsing 4,690 lines took \(elapsed)s")
        let pure = try #require(
            diff.files.first { $0.path == "Sources/PermissionGrants/CLAUDE.md" })
        #expect(pure.change == .renamed && pure.similarity == 100 && pure.hunks.isEmpty)
    }

    /// vigil's ghostty bump: a submodule pointer and nothing else.
    @Test func submodulePointerChange() throws {
        let diff = try Git.Diff(parsing: Fixture.data("vigil-ghostty-bump.diff"))
        let file = try #require(diff.files.first)
        #expect(diff.files.count == 1 && file.path == "ghostty")
        #expect(file.oldMode == "160000" && file.newMode == "160000")
        #expect(file.submodule?.old?.hasPrefix("e598d81") == true)
        #expect(file.submodule?.new?.hasPrefix("efe10c8") == true)
    }

    /// A merge in conflict diffs as a combined diff, which is refused by name.
    @Test func combinedDiffIsRefused() {
        #expect(throws: Git.ParseError.combinedDiff(line: 1)) {
            try Git.Diff(parsing: Fixture.data("conflict-combined.diff"))
        }
    }

    @Test func quotedPathsAreUnquoted() throws {
        let diff = try Git.Diff(
            parsing: """
                diff --git "a/caf\\303\\251 menu.txt" "b/caf\\303\\251 menu.txt"
                index 1111111..2222222 100644
                --- "a/caf\\303\\251 menu.txt"
                +++ "b/caf\\303\\251 menu.txt"
                @@ -1 +1 @@
                -tea
                +coffee
                diff --git a/with space.txt b/with space.txt
                index 1111111..2222222 100644
                --- a/with space.txt\t
                +++ b/with space.txt\t
                @@ -1 +1,2 @@
                 same
                +more
                """)
        #expect(diff.files.map(\.path) == ["café menu.txt", "with space.txt"])
    }

    /// A removed line that reads like a header (`--- `) stays a line inside its hunk.
    @Test func headerLookalikesInsideAHunk() throws {
        let diff = try Git.Diff(
            parsing: """
                diff --git a/notes.md b/notes.md
                index 1111111..2222222 100644
                --- a/notes.md
                +++ b/notes.md
                @@ -1,2 +1,2 @@
                --- a rule
                ++++ a plus
                 kept
                """)
        let lines = try #require(diff.files.first?.hunks.first?.lines)
        #expect(lines.map(\.kind) == [.removed, .added, .context])
        #expect(lines.map(\.text) == ["-- a rule", "+++ a plus", "kept"])
    }
}

struct Snippets {
    /// What an agent writes in an answer: no headers, no numbers.
    @Test func bareLines() {
        let file = Git.FileDiff(snippet: "-let a = 1\n+let b = 2\n context", path: "x.swift")
        #expect(file.path == "x.swift")
        #expect(file.hunks.count == 1)
        #expect(file.hunks[0].lines.map(\.kind) == [.removed, .added, .context])
        #expect(file.hunks[0].lines.allSatisfy { $0.old == nil || $0.kind != .added })
        #expect(file.hunks[0].lines[0].old == nil)
    }

    /// A pasted patch: its path from `+++`, its numbers from `@@`, wrong counts ignored.
    @Test func pastedPatch() {
        let file = Git.FileDiff(
            snippet:
                "--- a/Sources/x.swift\n+++ b/Sources/x.swift\n@@ -10,9 +10,9 @@ func f()\n a\n-b\n+c\n"
        )
        #expect(file.path == "Sources/x.swift")
        #expect(file.hunks[0].section == "func f()")
        #expect(file.hunks[0].lines.map(\.new) == [10, nil, 11])
        #expect(file.hunks[0].lines.map(\.old) == [10, 11, nil])
    }
}

struct LineDiffs {
    /// Applying the computed hunks to the old text gives the new one, for edits at the
    /// start, middle and end, a newline lost and found, and nothing in common.
    @Test(arguments: [
        ("a\nb\nc\nd\ne\nf\ng\nh\ni\nj\n", "a\nB\nc\nd\ne\nf\ng\nh\nI\nj\nk\n"),
        ("one\ntwo\n", "one\ntwo"),
        ("", "new\nfile\n"),
        ("gone\n", ""),
        ("x\ny\nz\n", "p\nq\n"),
        ("same\n", "same\n"),
    ])
    func roundTrip(old: String, new: String) {
        let file = Git.FileDiff(old: old, new: new, path: "f.txt", context: 1)
        #expect(apply(file, to: old) == new)
        if old == new { #expect(file.hunks.isEmpty) }
    }

    @Test func contextAndNumbers() {
        let old = (1...20).map { "line \($0)" }.joined(separator: "\n") + "\n"
        let new = old.replacingOccurrences(of: "line 5\n", with: "line five\n")
            .replacingOccurrences(of: "line 17\n", with: "line seventeen\n")
        let file = Git.FileDiff(old: old, new: new, context: 3)
        #expect(file.hunks.count == 2)
        #expect(file.hunks[0].header == "@@ -2,7 +2,7 @@")
        #expect(file.hunks[1].oldStart == 14)
        let joined = Git.FileDiff(old: old, new: new, context: 6)
        #expect(joined.hunks.count == 1)
    }

    /// The lines between two hunks, revealed from the new text, join the lower hunk with
    /// both sides' numbers, a limit taking the nearest; the diff still turns old into new.
    @Test func linesAboveAHunkRevealed() throws {
        let old = (1...30).map { "line \($0)" }.joined(separator: "\n") + "\n"
        let new = old.replacingOccurrences(of: "line 3\n", with: "line 3\nadded\n")
            .replacingOccurrences(of: "line 25\n", with: "line twenty-five\n")
        let file = Git.FileDiff(old: old, new: new, context: 3)
        #expect(file.hunks.count == 2)
        let gap = try #require(file.gap(above: 1))
        #expect(gap == 8...22)
        let some = try #require(file.revealing(above: 1, in: new, limit: 5))
        #expect(some.gap(above: 1) == 8...17)
        #expect(
            some.hunks[1].lines.first.map { ($0.old, $0.new, $0.text) } ?? (nil, nil, "") == (
                17, 18, "line 17"
            ))
        #expect(apply(some, to: old) == new)
        let all = try #require(file.revealing(above: 1, in: new))
        #expect(all.gap(above: 1) == nil && apply(all, to: old) == new)
        #expect(all.additions == file.additions && all.deletions == file.deletions)
        // Another text than the diff's new side is refused.
        #expect(
            file.revealing(above: 1, in: old.replacingOccurrences(of: "line 23", with: "x")) == nil)
        #expect(file.revealing(above: 0, in: new)?.gap(above: 0) == nil)
    }

    func apply(_ file: Git.FileDiff, to old: String) -> String {
        var lines = Git.FileDiff.split(old).map { (String($0.text), $0.noNewline) }
        for hunk in file.hunks.reversed() {
            let start = hunk.oldCount == 0 ? hunk.oldStart : hunk.oldStart - 1
            let replacement = hunk.lines.filter { $0.kind != .removed }.map {
                ($0.text, $0.noNewline)
            }
            lines.replaceSubrange(start..<(start + hunk.oldCount), with: replacement)
        }
        return lines.map { $0.0 + ($0.1 ? "" : "\n") }.joined()
    }
}

struct IntralineWords {
    @Test func renamedVariable() throws {
        let found = try #require(
            Git.Intraline.ranges(old: "let count = items.count", new: "let total = items.count"))
        #expect(found.old == [4..<9])
        #expect(found.new == [4..<9])
    }

    @Test func neighbouringChangesJoinAcrossSpaces() throws {
        let found = try #require(
            Git.Intraline.ranges(
                old: "public init(_ text: String, tail: Tail = 4)",
                new: "public init(_ text: String, tail: Tail = 6)"))
        #expect(found.new == [41..<42])
        let joined = try #require(Git.Intraline.ranges(old: "let a b = c", new: "var x y = c"))
        #expect(joined.new == [0..<7])
    }

    @Test func unrelatedLinesAreWhole() {
        #expect(Git.Intraline.ranges(old: "import SwiftUI", new: "    return value * 2") == nil)
    }

    @Test func pairsInAHunk() throws {
        let file = Git.FileDiff(
            old: "a\nlet x = 1\nlet y = 2\nb\n", new: "a\nlet x = 10\nlet y = 20\nb\n")
        let pairs = Git.Intraline.pairs(in: try #require(file.hunks.first))
        #expect(pairs.count == 4)
    }
}

struct StatusParsing {
    @Test func agentWorkingTree() throws {
        let status = try Git.Status(parsing: Fixture.data("scenario/status.z"))
        #expect(status.branch.head == "main")
        #expect(status.branch.upstream == "origin/main")
        #expect(status.branch.ahead == 3 && status.branch.behind == 0)
        let readme = try #require(status.entries.first { $0.path == "README.md" })
        #expect(
            readme.isStaged && readme.isUnstaged && readme.index == .modified
                && readme.worktree == .modified)
        let cmark = try #require(status.entries.first { $0.path == "Vendor/cmark" })
        #expect(
            cmark.submodule?.commitChanged == true && cmark.modes == ["160000", "160000", "160000"])
        #expect(
            status.untracked.map(\.path).sorted() == [
                "NOTES.md", "Sources/Ink/Resources/ABOUT.txt", "Tests/InkTests/InkBadgeTests.swift",
            ])
        #expect(status.staged.count == 3 && status.unstaged.count == 4)
        #expect(status.groups.map(\.group) == [.staged, .unstaged, .untracked])
    }

    @Test func mergeInConflict() throws {
        let status = try Git.Status(parsing: Fixture.data("conflict-status.z"))
        let entry = try #require(status.conflicted.first)
        #expect(
            entry.path == "README.md" && entry.index == .unmerged && entry.worktree == .unmerged)
        #expect(status.groups.first?.group == .conflicted)
    }

    @Test func renameRecordsCarryTheirOrigin() throws {
        let raw =
            "# branch.oid (initial)\0# branch.head (detached)\0"
            + "2 R. N... 100644 100644 100644 aaaa bbbb R87 new name.swift\0old.swift\0"
        let status = try Git.Status(parsing: Data(raw.utf8))
        #expect(status.branch.oid == nil && status.branch.head == nil)
        let entry = try #require(status.entries.first)
        #expect(
            entry.kind == .renamed && entry.score == 87 && entry.path == "new name.swift"
                && entry.origPath == "old.swift")
    }
}

struct RefsAndHistory {
    @Test func log() throws {
        let commits = try Git.Commit.parse(Fixture.data("swift-utils-log.txt"))
        #expect(commits.count == 40)
        #expect(commits.allSatisfy { $0.hash.count == 40 && !$0.subject.isEmpty })
        #expect(
            zip(commits, commits.dropFirst()).allSatisfy {
                $0.parents.contains($1.hash) || $0.isMerge
            })
        #expect(commits[0].refs.contains { $0.contains("main") })
        let scenario = try Git.Commit.parse(Fixture.data("scenario/log.txt"))
        #expect(
            scenario[0].subject
                == "refactor(ink): the scrim is named for its module; the HUD glass goes")
        #expect(scenario[0].author.date == (try Date("2026-10-23T08:31:00Z", strategy: .iso8601)))
    }

    @Test func branches() throws {
        let branches = try Git.Branch.parse(Fixture.data("scenario/branches.txt"))
        let main = try #require(branches.first { $0.name == "main" })
        #expect(
            main.isCurrent && main.upstream == "origin/main" && main.ahead == 3 && main.behind == 0)
        #expect(!branches.contains { $0.ref.hasSuffix("/HEAD") })
        #expect(branches.first { $0.name == "review" }?.worktree?.hasSuffix("app-review") == true)
        let local = try Git.Branch.parse(Fixture.data("swift-utils-branches.txt"))
        #expect(local.filter(\.isRemote).map(\.name) == ["origin/main"])
    }

    @Test func worktrees() {
        let trees = Git.Worktree.parse(Fixture.data("swift-utils-worktrees.txt"))
        #expect(trees.map(\.branchName) == ["main", "feat/gitkit"])
        #expect(trees.map(\.isMain) == [true, false])
        let scenario = Git.Worktree.parse(Fixture.data("scenario/worktrees.txt"))
        #expect(scenario.count == 2 && scenario[1].branchName == "review")
    }

    @Test func submodules() {
        let status = Git.Submodule.parseStatus(Fixture.data("vigil-submodules.txt"))
        #expect(status.count == 1 && status[0].path == "ghostty" && status[0].state == .current)
        #expect(status[0].describe?.hasPrefix("tip-") == true)
        let moved = Git.Submodule.parseStatus(Fixture.data("scenario/submodules.txt"))
        #expect(moved.first?.state == .moved && moved.first?.path == "Vendor/cmark")
        let staged = Git.Submodule.parseStage(Fixture.data("vigil-ls-files.txt"))
        #expect(staged.map(\.path) == ["ghostty"] && staged[0].commit == status[0].commit)
    }
}

struct Sources {
    @Test func fixtureSnapshotAndDrillIn() async throws {
        let source = Fixture.scenario
        let snapshot = try await source.snapshot()
        #expect(snapshot.worktrees.count == 2 && snapshot.submodules.count == 1)
        #expect(snapshot.commits.count == 40)
        let shown = try await source.show(snapshot.commits[0].hash)
        #expect(shown.files.contains { $0.change == .renamed })
        let nested = try #require(source.submodule("Vendor/cmark"))
        let moved = try await nested.log(
            "924936d0427cb25a61169739a7660230bffa6ea6..5698f9ff2cd2b4c0cf7d37e43440831d507a1aaa",
            limit: 50)
        #expect(!moved.isEmpty)
        let diff = try await nested.show(moved[0].hash)
        #expect(!diff.files.isEmpty)
        await #expect(throws: Git.SourceError.self) { try await source.diff(.commit("0000000")) }
    }
}

struct Commands {
    /// Every read turns the fsmonitor hook off: a repository's config can name one, and
    /// `git status` would run it for whoever reads, a remote viewer included.
    @Test func noReadRunsTheRepositorysFsmonitor() {
        let scopes: [Git.ChangeScope] = [
            .unstaged, .staged, .uncommitted, .since("HEAD~3", touched: ["a.swift"]),
            .commit("abc1234"),
            Git.ChangeScope(base: "main", target: .commit("abc1234")),
            Git.ChangeScope(base: "HEAD", target: .index, paths: ["Sources/"]),
        ]
        let reads: [[String]] =
            [
                Git.Command.status(), Git.Command.log(limit: 10),
                Git.Command.log("a..b", limit: 10),
                Git.Command.branches(), Git.Command.worktrees(), Git.Command.submodules(),
                Git.Command.newFile("NOTES.md"),
            ] + scopes.map(Git.Command.diff) + scopes.map(Git.Command.untracked)
        for argv in reads {
            let flag = argv.firstIndex(of: "core.fsmonitor=false")
            #expect(flag.map { $0 > 0 && argv[$0 - 1] == "-c" } == true, "\(argv)")
            // A `-c` counts only before the subcommand.
            let subcommand = argv.firstIndex { !$0.hasPrefix("-") && !$0.contains("=") }
            #expect(flag.flatMap { f in subcommand.map { f < $0 } } == true, "\(argv)")
        }
    }
}

struct Quotes {
    @Test func linesRangeAndMarkdown() throws {
        let file = Git.FileDiff(old: "a\nb\nc\n", new: "a\nB\nc\n", path: "Sources/x.swift")
        let lines = try #require(file.hunks.first?.lines)
        let quote = DiffQuote(file: file, lines: lines)
        #expect(quote.reference == "Sources/x.swift:L1-L3")
        #expect(quote.markdown == "`Sources/x.swift:L1-L3`\n\n```diff\n a\n-b\n+B\n c\n```")
        let removed = DiffQuote(file: file, lines: lines.filter { $0.kind == .removed })
        #expect(removed.side == .old && removed.reference == "Sources/x.swift:L2 (removed)")
    }

    @Test func fenceOutgrowsBackticks() {
        let file = Git.FileDiff(old: "", new: "```swift\n", path: "README.md")
        #expect(DiffQuote.file(file).markdown.contains("````diff"))
    }
}
