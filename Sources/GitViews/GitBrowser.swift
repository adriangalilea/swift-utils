import GitKit
import Ink
import SwiftUI

/// A repository to read, lazygit's way, over any `Git.Source`: the agent's work since it
/// started (when there is an agent), the working tree, the commits, and the branches with
/// their worktrees and submodules, each drilling into diffs. Tabs at a compact width,
/// columns at a regular one, where the reading pane always has something open.
///
/// ```swift
/// GitBrowser(source: remote, agent: .init(base: start, touched: edited, name: "Claude"))
///     .onQuote { quote in reply.insert(quote.markdown) }
/// ```
///
/// Every read is async and each panel says it is reading on its own, so a slow source
/// on another machine never blocks the screen. Nothing is presented inside it: a quote
/// reaches the host through `.onQuote`, and the host decides what it does. A new
/// `reloadToken` reads the repository again; a different source is a different browser
/// (`.id(…)` it).
public struct GitBrowser: View {
    /// An agent's session: the commit it started from, the paths it touched (nil: every
    /// path since), and what to call it.
    public struct Agent: Sendable, Hashable {
        public var base: String
        public var touched: [String]?
        public var name: String?
        public init(base: String, touched: [String]? = nil, name: String? = nil) {
            self.base = base
            self.touched = touched
            self.name = name
        }
    }

    public enum Panel: Sendable, Hashable {
        case agent, workingTree, commits, repository
        /// A host's own panel (`panel(_:systemImage:content:)`), by the order it was added.
        case extra(Int)
    }

    /// Where the browser opens: a panel, and optionally a row in it.
    public struct Opening: Sendable, Hashable {
        public enum Row: Sendable, Hashable {
            /// The Nth row of the panel's list (0 the first).
            case index(Int)
            /// Every file of the panel's scope on one page.
            case allFiles
            /// The first submodule whose pointer moved (the repository panel).
            case submodule
        }
        public var panel: Panel
        public var row: Row?
        public init(_ panel: Panel, row: Row? = nil) {
            self.panel = panel
            self.row = row
        }
    }

    struct Extra {
        let title: String
        let symbol: String
        let content: () -> AnyView
    }

    let source: any Git.Source
    let agent: Agent?
    let opening: Opening?
    let reloadToken: AnyHashable?
    var extras: [Extra] = []
    @State private var model: BrowserModel
    @Environment(\.horizontalSizeClass) private var size

    public init(
        source: any Git.Source, agent: Agent? = nil, opening: Opening? = nil,
        reloadToken: AnyHashable? = nil
    ) {
        self.source = source
        self.agent = agent
        self.opening = opening
        self.reloadToken = reloadToken
        _model = State(initialValue: BrowserModel(source: source, agent: agent))
    }

    /// A panel of the host's own beside the browser's (a tab, or a row in the sidebar).
    public func panel(
        _ title: String, systemImage: String, @ViewBuilder content: @escaping () -> some View
    )
        -> GitBrowser
    {
        var copy = self
        copy.extras.append(
            Extra(title: title, symbol: systemImage, content: { AnyView(content()) }))
        return copy
    }

    var panels: [Panel] {
        (agent == nil ? [] : [.agent]) + [.workingTree, .commits, .repository]
            + extras.indices.map { .extra($0) }
    }

    public var body: some View {
        Group {
            if size == .compact {
                BrowserTabs(model: model, panels: panels, extras: extras, opening: opening)
            } else {
                BrowserColumns(model: model, panels: panels, extras: extras, opening: opening)
            }
        }
        .onChange(of: agent) { model.agent = agent }
        .task(id: reloadToken) { await model.reload() }
    }
}

// MARK: - the model

/// What the browser has read and what the reader chose, for one source.
@MainActor @Observable final class BrowserModel {
    let source: any Git.Source
    var agent: GitBrowser.Agent?
    private(set) var snapshot: Git.Snapshot?
    private(set) var failure: Error?
    var onlyTouched = true
    private var diffs: [Git.ChangeScope: Git.Diff] = [:]

    init(source: any Git.Source, agent: GitBrowser.Agent?) {
        self.source = source
        self.agent = agent
    }

    func reload() async {
        diffs = [:]
        do {
            snapshot = try await source.snapshot()
            failure = nil
        } catch {
            failure = error
        }
    }

    /// The agent's work: everything since its base, kept to what it touched unless the
    /// reader asked for everything.
    var agentScope: Git.ChangeScope? {
        agent.map { .since($0.base, touched: onlyTouched ? $0.touched : nil) }
    }

    func diff(_ scope: Git.ChangeScope, in repository: String? = nil) async throws -> Git.Diff {
        if repository == nil, let known = diffs[scope] { return known }
        let from = repository.flatMap { source.submodule($0) } ?? source
        let read = try await from.diff(scope)
        if repository == nil { diffs[scope] = read }
        return read
    }

    func log(_ revision: String?, in repository: String? = nil) async throws -> [Git.Commit] {
        guard let repository else { return try await source.log(revision, limit: 200) }
        guard let nested = source.submodule(repository) else {
            throw Git.SourceError.notCaptured("the repository at \(repository)")
        }
        return try await nested.log(revision, limit: 50)
    }

    /// The row an opening names, once its panel has what it lists.
    func target(_ panel: GitBrowser.Panel, _ row: GitBrowser.Opening.Row) async -> BrowserTarget? {
        guard let snapshot else { return nil }
        let index: Int = if case .index(let n) = row { n } else { 0 }
        switch panel {
        case .agent:
            guard let scope = agentScope else { return nil }
            if row == .allFiles { return .files(scope, title: agent?.name ?? "Agent") }
            guard let diff = try? await diff(scope), diff.files.indices.contains(index) else {
                return nil
            }
            return .file(scope, path: diff.files[index].path)
        case .workingTree:
            let files = snapshot.status.groups.flatMap { group in
                group.files.map { (group.group, $0) }
            }
            guard files.indices.contains(index) else { return nil }
            return .file(BrowserTarget.scope(files[index].0), path: files[index].1.path)
        case .commits:
            guard snapshot.commits.indices.contains(index) else { return nil }
            let commit = snapshot.commits[index]
            return .commit(hash: commit.hash, subject: commit.subject, repository: nil)
        case .repository:
            if row == .submodule {
                for submodule in snapshot.submodules {
                    if let pointer = try? await diff(.uncommitted).files.first(where: {
                        $0.path == submodule.path
                    })?
                    .submodule, let old = pointer.old, let new = pointer.new, old != new {
                        return .submodule(path: submodule.path, old: old, new: new)
                    }
                }
                return nil
            }
            return snapshot.branches.first(where: \.isCurrent).map(BrowserTarget.branch)
        case .extra:
            return nil
        }
    }
}

/// What a row opens.
enum BrowserTarget: Hashable {
    case files(Git.ChangeScope, title: String)
    case file(Git.ChangeScope, path: String)
    case commit(hash: String, subject: String, repository: String?)
    case submodule(path: String, old: String, new: String)
    /// A branch's commits (nil revision: HEAD's).
    case branch(name: String, revision: String?)

    static func branch(_ branch: Git.Branch) -> BrowserTarget {
        .branch(name: branch.name, revision: branch.isCurrent ? nil : branch.ref)
    }

    static func scope(_ group: Git.FileChange.Group) -> Git.ChangeScope {
        switch group {
        case .staged: .staged
        case .untracked: .uncommitted
        default: .unstaged
        }
    }
}

extension GitBrowser.Panel {
    func title(_ agent: GitBrowser.Agent?, _ extras: [GitBrowser.Extra]) -> String {
        switch self {
        case .agent: agent?.name ?? "Agent"
        case .workingTree: "Working Tree"
        case .commits: "Commits"
        case .repository: "Repository"
        case .extra(let index): extras[index].title
        }
    }

    func symbol(_ extras: [GitBrowser.Extra]) -> String {
        switch self {
        case .agent: "sparkles"
        // The diff's own sign: what is changed on disk, added and removed.
        case .workingTree: "plus.forwardslash.minus"
        case .commits: "clock.arrow.circlepath"
        case .repository: "arrow.trianglehead.branch"
        case .extra(let index): extras[index].symbol
        }
    }
}

// MARK: - layouts

/// Compact: a tab per panel, each a stack that drills into its diffs.
struct BrowserTabs: View {
    let model: BrowserModel
    let panels: [GitBrowser.Panel]
    let extras: [GitBrowser.Extra]
    let opening: GitBrowser.Opening?
    @State private var panel: GitBrowser.Panel
    @State private var paths: [GitBrowser.Panel: [BrowserTarget]] = [:]

    init(
        model: BrowserModel, panels: [GitBrowser.Panel], extras: [GitBrowser.Extra],
        opening: GitBrowser.Opening?
    ) {
        self.model = model
        self.panels = panels
        self.extras = extras
        self.opening = opening
        _panel = State(initialValue: opening?.panel ?? panels[0])
    }

    var body: some View {
        TabView(selection: $panel) {
            ForEach(panels, id: \.self) { panel in
                Tab(
                    panel.title(model.agent, extras), systemImage: panel.symbol(extras),
                    value: panel
                ) {
                    if case .extra(let index) = panel {
                        extras[index].content()
                    } else {
                        NavigationStack(
                            path: Binding(get: { paths[panel] ?? [] }, set: { paths[panel] = $0 })
                        ) {
                            BrowserList(panel: panel, model: model)
                                .navigationDestination(for: BrowserTarget.self) {
                                    BrowserDetail(target: $0, model: model)
                                }
                        }
                    }
                }
            }
        }
        #if os(iOS)
            .tabBarMinimizeBehavior(.onScrollDown)
        #endif
        // A phone opens on its list; only an opening that names a row pushes it.
        .task(id: model.snapshot?.status) {
            guard let opening, let row = opening.row, paths[opening.panel, default: []].isEmpty,
                let target = await model.target(opening.panel, row)
            else { return }
            paths[opening.panel] = [target]
        }
    }
}

/// Regular: panels, their list, and the reading pane, side by side. The reading pane is
/// never empty: a panel opens on its first row, as Mail and lazygit do.
struct BrowserColumns: View {
    let model: BrowserModel
    let panels: [GitBrowser.Panel]
    let extras: [GitBrowser.Extra]
    let opening: GitBrowser.Opening?
    @State private var panel: GitBrowser.Panel?
    @State private var selection: BrowserTarget?

    init(
        model: BrowserModel, panels: [GitBrowser.Panel], extras: [GitBrowser.Extra],
        opening: GitBrowser.Opening?
    ) {
        self.model = model
        self.panels = panels
        self.extras = extras
        self.opening = opening
        _panel = State(initialValue: opening?.panel ?? panels[0])
    }

    struct Key: Hashable {
        let panel: GitBrowser.Panel?
        let status: Git.Status?
    }

    var body: some View {
        if case .extra(let index)? = panel {
            NavigationSplitView {
                sidebar
            } detail: {
                extras[index].content()
            }
        } else {
            NavigationSplitView {
                sidebar
            } content: {
                if let panel {
                    BrowserList(panel: panel, model: model, selection: $selection)
                        .navigationSplitViewColumnWidth(min: 280, ideal: 360)
                }
            } detail: {
                NavigationStack {
                    Group {
                        if let selection {
                            BrowserDetail(target: selection, model: model)
                        } else {
                            GitStateView(
                                .empty(
                                    title: "Nothing to show", message: nil,
                                    symbol: "doc.text.magnifyingglass"))
                        }
                    }
                    .navigationDestination(for: BrowserTarget.self) {
                        BrowserDetail(target: $0, model: model)
                    }
                }
                .id(selection)
            }
            .task(id: Key(panel: panel, status: model.snapshot?.status)) {
                selection = nil
                guard let panel else { return }
                let row = opening?.panel == panel ? opening?.row ?? .index(0) : .index(0)
                selection = await model.target(panel, row)
            }
        }
    }

    private var sidebar: some View {
        List(selection: $panel) {
            Section {
                ForEach(panels, id: \.self) { panel in
                    Label(panel.title(model.agent, extras), systemImage: panel.symbol(extras)).tag(
                        Optional(panel))
                }
            }
            if let status = model.snapshot?.status {
                Section(model.source.name) {
                    GitStatusSummary(status).padding(.vertical, 4)
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 240)
        .navigationTitle(model.source.name)
    }
}
