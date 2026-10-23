import Foundation
import GitKit
import GitLocal

// gitkit-capture <repository> <folder> [--agent-base REV] [--touched a,b,c] [--shows N]
//
// Writes a repository's state into <folder> as `Git.FixtureSource` reads it back: git's
// own bytes for the status, refs, worktrees, submodules and log, the diffs of the
// working tree's scopes, `git show` of the newest N commits, an agent scope when a base
// is given, and each submodule whose pointer moved as a capture of its own (the log of
// the move and its commits). Everything is read with `Git.Command`'s argv, the same a
// live `LocalSource` runs.

#if os(macOS)
    struct Options {
        var repository: URL
        var folder: URL
        var agentBase: String?
        var touched: [String]?
        var shows = 20
        var logLimit = 80

        init(_ arguments: [String]) {
            var rest = arguments[...]
            var positional: [String] = []
            while let argument = rest.popFirst() {
                switch argument {
                case "--agent-base": agentBase = rest.popFirst()
                case "--touched": touched = rest.popFirst()?.split(separator: ",").map(String.init)
                case "--shows": shows = rest.popFirst().flatMap(Int.init) ?? shows
                case "--log": logLimit = rest.popFirst().flatMap(Int.init) ?? logLimit
                default: positional.append(argument)
                }
            }
            guard positional.count == 2 else {
                FileHandle.standardError.write(
                    Data(
                        "usage: gitkit-capture <repository> <folder> [--agent-base REV] [--touched a,b] [--shows N] [--log N]\n"
                            .utf8))
                exit(2)
            }
            repository = URL(filePath: (positional[0] as NSString).expandingTildeInPath)
            folder = URL(filePath: (positional[1] as NSString).expandingTildeInPath)
        }
    }

    func capture(
        _ source: Git.LocalSource, into folder: URL, agentBase: String?, touched: [String]?,
        shows: Int,
        logLimit: Int, depth: Int
    ) async throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        func write(_ data: Data, _ name: String) throws {
            try data.write(to: folder.appending(path: name))
        }
        var manifest = Git.FixtureSource.Manifest(name: source.name)
        try write(await source.run(Git.Command.status()), manifest.status)
        try write(await source.run(Git.Command.branches()), manifest.branches)
        try write(await source.run(Git.Command.worktrees()), manifest.worktrees)
        try write(await source.run(Git.Command.submodules()), manifest.submodules)
        let log = try await source.run(Git.Command.log(limit: logLimit))
        try write(log, manifest.log)

        var scopes: [Git.ChangeScope] = [.unstaged, .staged, .uncommitted]
        if let agentBase {
            scopes.append(.since(agentBase))
        }
        for commit in try Git.Commit.parse(log).prefix(shows) {
            scopes.append(.commit(commit.hash))
        }
        var pointers: [String: Git.FileDiff.Pointer] = [:]
        for (index, scope) in scopes.enumerated() {
            let diff = try await source.diff(scope)
            let name: String =
                switch scope.target {
                case .commit(let hash): "show-\(hash.prefix(12)).diff"
                default: "diff-\(index).diff"
                }
            // The diff written back as git wrote it, untracked files appended as git's own
            // `--no-index` output, so the file parses exactly like a live read.
            var bytes = try await source.run(Git.Command.diff(scope))
            if scope.untracked, scope.target == .worktree {
                let listed = Git.records(try await source.run(Git.Command.untracked(scope))).filter
                { !$0.isEmpty }
                for path in listed.prefix(source.untrackedLimit) {
                    bytes += try await source.run(
                        Git.Command.newFile(path, context: scope.context), allowing: [1])
                }
            }
            try write(bytes, name)
            manifest.diffs.append(.init(key: scope, file: name))
            if case .commit = scope.target { continue }
            for file in diff.files {
                if let pointer = file.submodule, pointer.old != pointer.new {
                    pointers[file.path] = pointer
                }
            }
        }
        if let agentBase {
            let agentDiff = try await source.diff(.since(agentBase))
            manifest.agent = .init(base: agentBase, touched: touched ?? agentDiff.files.map(\.path))
        }

        guard depth == 0 else {
            try write(JSONEncoder.pretty.encode(manifest), "manifest.json")
            return
        }
        for (path, pointer) in pointers.sorted(by: { $0.key < $1.key }) {
            guard let nested = source.submodule(path) as? Git.LocalSource else { continue }
            let relative = "submodules/" + path.replacingOccurrences(of: "/", with: "_")
            try await capture(
                nested, into: folder.appending(path: relative), agentBase: nil, touched: nil,
                shows: 0,
                logLimit: logLimit, depth: depth + 1)
            // The move itself: the commits between the two pointers and each one's diff.
            var nestedManifest = try JSONDecoder().decode(
                Git.FixtureSource.Manifest.self,
                from: Data(
                    contentsOf: folder.appending(path: relative).appending(path: "manifest.json")))
            if let old = pointer.old, let new = pointer.new {
                let range = "\(old)..\(new)"
                let moved = try await nested.run(Git.Command.log(range, limit: 50))
                try moved.write(
                    to: folder.appending(path: relative).appending(path: "log-range.txt"))
                nestedManifest.logs.append(
                    .init(key: .init(revision: range, limit: 50), file: "log-range.txt"))
                for commit in try Git.Commit.parse(moved).prefix(10) {
                    let name = "show-\(commit.hash.prefix(12)).diff"
                    let scope = Git.ChangeScope.commit(commit.hash)
                    try await nested.run(Git.Command.diff(scope)).write(
                        to: folder.appending(path: relative).appending(path: name))
                    nestedManifest.diffs.append(.init(key: scope, file: name))
                }
            }
            try JSONEncoder.pretty.encode(nestedManifest).write(
                to: folder.appending(path: relative).appending(path: "manifest.json"))
            manifest.nested[path] = relative
        }
        try write(JSONEncoder.pretty.encode(manifest), "manifest.json")
    }

    extension JSONEncoder {
        static var pretty: JSONEncoder {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            return encoder
        }
    }

    let options = Options(Array(CommandLine.arguments.dropFirst()))
    do {
        try await capture(
            Git.LocalSource(repository: options.repository), into: options.folder,
            agentBase: options.agentBase,
            touched: options.touched, shows: options.shows, logLimit: options.logLimit, depth: 0)
        print("gitkit-capture: \(options.folder.path)")
    } catch {
        FileHandle.standardError.write(Data("gitkit-capture: \(error)\n".utf8))
        exit(1)
    }
#else
    print("gitkit-capture runs git, on a Mac")
#endif
