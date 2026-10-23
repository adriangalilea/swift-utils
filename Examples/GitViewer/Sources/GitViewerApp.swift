import GitKit
import GitViews
import SwiftUI

// Launch arguments, for a screenshot or a demo:
//   -repo PATH        the repository on a Mac (default ~/Developer/vigil)
//   -panel NAME       agent, working, commits, repo, embeds
//   -open N           open the panel's Nth row (0 the first); -open all opens "All files"
//   -embed NAME       markdown, cards, page (with -panel embeds)
//   -appearance NAME  light or dark

@main
struct GitViewerApp: App {
    @State private var model = RepoModel.launch()

    var body: some Scene {
        WindowGroup {
            Root(model: model)
                .task { await model.load() }
        }
        #if os(macOS)
            .defaultSize(width: 1360, height: 860)
        #endif
    }
}

struct Root: View {
    let model: RepoModel
    @Environment(\.horizontalSizeClass) private var size

    var body: some View {
        Group {
            if size == .compact {
                Tabs(model: model)
            } else {
                Columns(model: model)
            }
        }
        .onQuote { quote in model.quote = QuoteItem(quote: quote) }
        .preferredColorScheme(Launch.appearance)
        .sheet(item: Bindable(model).quote) { QuoteSheet(item: $0) }
    }
}

enum Launch {
    static var panel: Panel { Panel(rawValue: UserDefaults.standard.string(forKey: "panel") ?? "") ?? .agent }
    static var open: String? { UserDefaults.standard.string(forKey: "open") }
    static var embed: Embed? { Embed(rawValue: UserDefaults.standard.string(forKey: "embed") ?? "") }
    static var appearance: ColorScheme? {
        switch UserDefaults.standard.string(forKey: "appearance") {
        case "light": .light
        case "dark": .dark
        default: nil
        }
    }

    /// The row `open` names in a panel, once the panel has what it lists: a launch's
    /// `-open`, or the first row, which a column layout always opens (Mail and lazygit
    /// never leave the reading pane empty).
    @MainActor static func target(_ panel: Panel, _ model: RepoModel, open: String?) async -> Target? {
        if panel == .embeds { return (embed ?? (open == nil ? nil : .markdown)).map(Target.embed) }
        guard let open, let snapshot = model.snapshot else { return nil }
        let index = Int(open) ?? 0
        switch panel {
        case .agent:
            guard let scope = model.agentScope, let diff = try? await model.diff(scope) else { return nil }
            if open == "all" { return .files(scope, title: "Since agent") }
            return diff.files.indices.contains(index) ? .file(scope, path: diff.files[index].path) : nil
        case .working:
            let files = snapshot.status.groups.flatMap { group in group.files.map { (group.group, $0) } }
            guard files.indices.contains(index) else { return nil }
            let (group, change) = files[index]
            let scope: Git.ChangeScope = group == .staged ? .staged : group == .untracked ? .uncommitted : .unstaged
            return .file(scope, path: change.path)
        case .commits:
            guard snapshot.commits.indices.contains(index) else { return nil }
            let commit = snapshot.commits[index]
            return .commit(hash: commit.hash, subject: commit.subject, repository: nil)
        case .repo:
            guard open == "submodule" else {
                return snapshot.branches.first(where: \.isCurrent).map(PanelList.target)
            }
            guard let submodule = snapshot.submodules.first,
                let pointer = try? await model.diff(.uncommitted).files.first(where: { $0.path == submodule.path })?
                    .submodule,
                let old = pointer.old, let new = pointer.new
            else { return nil }
            return .submodule(path: submodule.path, old: old, new: new)
        case .embeds:
            return nil
        }
    }
}

/// iPhone: a tab per panel, each a stack that drills into its diffs.
struct Tabs: View {
    let model: RepoModel
    @State private var panel = Launch.panel
    @State private var paths: [Panel: [Target]] = [:]

    var body: some View {
        TabView(selection: $panel) {
            ForEach(Panel.allCases) { panel in
                Tab(panel.title, systemImage: panel.symbol, value: panel) {
                    NavigationStack(path: Binding(get: { paths[panel] ?? [] }, set: { paths[panel] = $0 })) {
                        PanelList(panel: panel, model: model)
                            .navigationDestination(for: Target.self) { Detail(target: $0, model: model) }
                    }
                }
            }
        }
        #if os(iOS)
            .tabBarMinimizeBehavior(.onScrollDown)
        #endif
        .task(id: model.snapshot?.status) {
            if let target = await Launch.target(panel, model, open: Launch.open), paths[panel, default: []].isEmpty {
                paths[panel] = [target]
            }
        }
    }
}

struct Opening: Hashable {
    let panel: Panel?
    let status: Git.Status?
}

/// Mac and iPad: panels, their list, and the diff, side by side.
struct Columns: View {
    let model: RepoModel
    @State private var panel: Panel? = Launch.panel
    @State private var selection: Target?
    #if os(macOS)
        @State private var picking = false
    #endif

    var body: some View {
        NavigationSplitView {
            List(selection: $panel) {
                Section {
                    ForEach(Panel.allCases) { panel in
                        Label(panel.title, systemImage: panel.symbol).tag(Optional(panel))
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
        } content: {
            if let panel {
                PanelList(panel: panel, model: model, selection: $selection)
                    .navigationSplitViewColumnWidth(min: 280, ideal: 360)
            }
        } detail: {
            NavigationStack {
                Group {
                    if let selection {
                        Detail(target: selection, model: model)
                    } else {
                        GitStateView(.empty(title: "Pick a file or a commit", message: nil, symbol: "doc.text.magnifyingglass"))
                    }
                }
                .navigationDestination(for: Target.self) { Detail(target: $0, model: model) }
            }
            .id(selection)
        }
        // The reading pane is never empty: a panel opens on its first row (or the one a
        // launch named), and so does a repository read again.
        .task(id: Opening(panel: panel, status: model.snapshot?.status)) {
            selection = nil
            guard let panel else { return }
            selection = await Launch.target(panel, model, open: Launch.open ?? "0")
        }
        #if os(macOS)
            .toolbar {
                ToolbarItem {
                    Button("Open Repository…", systemImage: "folder") { picking = true }
                }
                ToolbarItem {
                    Button("Reload", systemImage: "arrow.clockwise") { Task { await model.reload() } }
                }
            }
            .fileImporter(isPresented: $picking, allowedContentTypes: [.folder]) { result in
                if case .success(let folder) = result { model.open(folder) }
            }
        #endif
    }
}
