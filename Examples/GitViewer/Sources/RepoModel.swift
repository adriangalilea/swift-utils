import Foundation
import GitKit
import GitViews
import SwiftUI

#if os(macOS)
    import GitLocal
#endif

/// The repository the app shows and what the reader is looking at. The Mac reads a real
/// repository through `/usr/bin/git`; the iPhone reads the bundled capture of the scenario
/// repository (an agent's session in every state git has).
@MainActor @Observable final class RepoModel {
    private(set) var source: any Git.Source
    private(set) var snapshot: Git.Snapshot?
    private(set) var failure: Error?
    /// Where the agent started and what it touched (the host supplies both).
    var agentBase: String?
    var agentTouched: [String]?
    var onlyTouched = true
    var quote: QuoteItem?
    private var diffs: [Git.ChangeScope: Git.Diff] = [:]

    init(source: any Git.Source, agent: Git.FixtureSource.Manifest.Agent? = nil) {
        self.source = source
        agentBase = agent?.base
        agentTouched = agent?.touched
    }

    static func launch() -> RepoModel {
        #if os(macOS)
            let path = UserDefaults.standard.string(forKey: "repo") ?? "~/Developer/vigil"
            return RepoModel(
                source: Git.LocalSource(repository: URL(filePath: (path as NSString).expandingTildeInPath)))
        #else
            let folder = Bundle.main.url(forResource: "scenario", withExtension: nil)!
            let capture = try! Git.FixtureSource(folder: folder)
            return RepoModel(source: capture, agent: capture.manifest.agent)
        #endif
    }

    #if os(macOS)
        func open(_ folder: URL) {
            source = Git.LocalSource(repository: folder)
            snapshot = nil
            failure = nil
            agentBase = nil
            agentTouched = nil
            diffs = [:]
            Task { await load() }
        }
    #endif

    func load() async {
        do {
            let read = try await source.snapshot()
            snapshot = read
            failure = nil
            // A live repository has no agent on record: the session is simulated as the
            // last three commits and whatever is on disk since.
            if agentBase == nil, read.commits.count > 3 {
                agentBase = read.commits[3].hash
            }
        } catch {
            failure = error
        }
    }

    func reload() async {
        diffs = [:]
        await load()
    }

    /// The agent's work as a scope: everything since its base, kept to the paths it
    /// touched unless the reader asked for everything.
    var agentScope: Git.ChangeScope? {
        agentBase.map { .since($0, touched: onlyTouched ? agentTouched : nil) }
    }

    func diff(_ scope: Git.ChangeScope, in repository: String? = nil) async throws -> Git.Diff {
        if repository == nil, let known = diffs[scope] { return known }
        let source = repository.flatMap { self.source.submodule($0) } ?? self.source
        let read = try await source.diff(scope)
        if repository == nil { diffs[scope] = read }
        return read
    }

    func log(_ revision: String?) async throws -> [Git.Commit] {
        try await source.log(revision, limit: 200)
    }

    func log(_ revision: String, in repository: String) async throws -> [Git.Commit] {
        guard let nested = source.submodule(repository) else {
            throw Git.SourceError.notCaptured("the repository at \(repository)")
        }
        return try await nested.log(revision, limit: 50)
    }
}

/// What a list row opens.
enum Target: Hashable {
    /// Every file of a scope on one page.
    case files(Git.ChangeScope, title: String)
    /// One file of a scope.
    case file(Git.ChangeScope, path: String)
    /// A commit, in this repository or a submodule's.
    case commit(hash: String, subject: String, repository: String?)
    /// A submodule's move, its commits between the two pointers.
    case submodule(path: String, old: String, new: String)
    /// A branch's commits (nil revision: HEAD's, which a capture always holds).
    case branch(name: String, revision: String?)
    case embed(Embed)
}

enum Embed: String, Hashable, CaseIterable {
    case markdown, cards, page

    var title: String {
        switch self {
        case .markdown: "In a markdown answer"
        case .cards: "In a tool call's card"
        case .page: "Full screen, 10,000 lines"
        }
    }

    var symbol: String {
        switch self {
        case .markdown: "text.bubble"
        case .cards: "rectangle.stack"
        case .page: "rectangle.portrait"
        }
    }
}

struct QuoteItem: Identifiable {
    let quote: DiffQuote
    let id = UUID()
}

enum Panel: String, Hashable, CaseIterable, Identifiable {
    case agent, working, commits, repo, embeds
    var id: String { rawValue }

    var title: String {
        switch self {
        case .agent: "Agent"
        case .working: "Working Tree"
        case .commits: "Commits"
        case .repo: "Repository"
        case .embeds: "Embeds"
        }
    }

    var symbol: String {
        switch self {
        case .agent: "sparkles"
        // The diff's own sign: what is changed on disk, added and removed.
        case .working: "plus.forwardslash.minus"
        case .commits: "clock.arrow.circlepath"
        case .repo: "arrow.trianglehead.branch"
        case .embeds: "rectangle.on.rectangle.angled"
        }
    }
}
