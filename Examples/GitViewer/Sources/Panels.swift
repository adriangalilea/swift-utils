import GitKit
import GitViews
import SwiftUI

/// Loads a value and shows it, or says it is reading, or why it could not.
struct Loading<Value, Content: View>: View {
    let id: AnyHashable
    let load: @MainActor () async throws -> Value
    @ViewBuilder let content: (Value) -> Content
    @State private var value: Value?
    @State private var failure: Error?

    init(
        id: AnyHashable, load: @escaping @MainActor () async throws -> Value,
        @ViewBuilder content: @escaping (Value) -> Content
    ) {
        self.id = id
        self.load = load
        self.content = content
    }

    var body: some View {
        Group {
            if let value {
                content(value)
            } else if let failure {
                GitStateView(.failed(failure, retry: { self.failure = nil }))
            } else {
                GitStateView(.loading("Reading"))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: Key(id: id, retry: failure == nil)) {
            guard failure == nil else { return }
            do {
                value = try await load()
            } catch {
                failure = error
            }
        }
    }

    struct Key: Hashable {
        let id: AnyHashable
        let retry: Bool
    }
}

/// A row that opens `target`: a selection in a split view's column, a push in a stack.
struct Row<Label: View>: View {
    let target: Target
    let selecting: Bool
    @ViewBuilder let label: Label

    var body: some View {
        if selecting {
            label.tag(Optional(target))
        } else {
            NavigationLink(value: target) { label }
        }
    }
}

/// A panel's list: the files, commits or refs it is about.
struct PanelList: View {
    let panel: Panel
    let model: RepoModel
    /// Set in a split view: rows select; nil in a stack: rows push.
    var selection: Binding<Target?>?

    var body: some View {
        Group {
            if let snapshot = model.snapshot {
                content(snapshot)
            } else if let failure = model.failure {
                GitStateView(.failed(failure, retry: { Task { await model.reload() } }))
            } else {
                GitStateView(.loading("Reading \(model.source.name)"))
            }
        }
        .navigationTitle(panel.title)
    }

    @ViewBuilder func content(_ snapshot: Git.Snapshot) -> some View {
        switch panel {
        case .agent: AgentList(model: model, selecting: selection != nil, selection: selection)
        case .working: list { working(snapshot) }
        case .commits: list { commits(snapshot) }
        case .repo: list { repo(snapshot) }
        case .embeds: list { embeds }
        }
    }

    @ViewBuilder func list(@ViewBuilder _ rows: () -> some View) -> some View {
        if let selection {
            List(selection: selection) { rows() }
        } else {
            List { rows() }
        }
    }

    // MARK: - working tree

    @ViewBuilder func working(_ snapshot: Git.Snapshot) -> some View {
        Section {
            GitStatusSummary(snapshot.status).padding(.vertical, 4)
        }
        if snapshot.status.isClean {
            GitStateView(.empty(title: "Nothing to commit", message: "The working tree matches HEAD."))
        }
        ForEach(snapshot.status.groups, id: \.group) { group in
            Section {
                Row(target: .files(scope(group.group), title: group.group.title), selecting: selection != nil) {
                    Label("All \(group.group.title.lowercased())", systemImage: "doc.on.doc")
                        .foregroundStyle(.secondary)
                }
                ForEach(group.files) { change in
                    Row(target: .file(scope(group.group), path: change.path), selecting: selection != nil) {
                        GitFileRow(change)
                    }
                }
            } header: {
                HStack {
                    Text(group.group.title)
                    Spacer()
                    Text(verbatim: "\(group.files.count)").monospacedDigit()
                }
            }
        }
    }

    func scope(_ group: Git.FileChange.Group) -> Git.ChangeScope {
        switch group {
        case .staged: .staged
        case .untracked: .uncommitted
        default: .unstaged
        }
    }

    // MARK: - commits

    @ViewBuilder func commits(_ snapshot: Git.Snapshot) -> some View {
        Section {
            ForEach(snapshot.commits) { commit in
                Row(
                    target: .commit(hash: commit.hash, subject: commit.subject, repository: nil),
                    selecting: selection != nil
                ) {
                    GitCommitRow(commit)
                }
            }
        } header: {
            Text(verbatim: snapshot.status.branch.head ?? "HEAD")
        }
    }

    // MARK: - branches, worktrees, submodules

    @ViewBuilder func repo(_ snapshot: Git.Snapshot) -> some View {
        Section("Branches") {
            ForEach(snapshot.branches.filter { !$0.isRemote }) { branch in
                Row(target: Self.target(branch), selecting: selection != nil) { GitBranchRow(branch) }
            }
        }
        if snapshot.branches.contains(where: \.isRemote) {
            Section("Remote branches") {
                ForEach(snapshot.branches.filter(\.isRemote)) { branch in
                    Row(target: Self.target(branch), selecting: selection != nil) { GitBranchRow(branch) }
                }
            }
        }
        Section("Worktrees") {
            ForEach(snapshot.worktrees) { GitWorktreeRow($0) }
        }
        if !snapshot.submodules.isEmpty {
            Section("Submodules") {
                ForEach(snapshot.submodules) { submodule in
                    SubmoduleRow(submodule: submodule, model: model, selecting: selection != nil)
                }
            }
        }
    }

    static func target(_ branch: Git.Branch) -> Target {
        .branch(name: branch.name, revision: branch.isCurrent ? nil : branch.ref)
    }

    // MARK: - embeds

    @ViewBuilder var embeds: some View {
        Section {
            ForEach(Embed.allCases, id: \.self) { embed in
                Row(target: .embed(embed), selecting: selection != nil) {
                    Label(embed.title, systemImage: embed.symbol)
                }
            }
        } footer: {
            Text("DiffView is one line anywhere: a fence in a markdown answer, a card in a conversation, a whole screen.")
        }
    }
}

/// A submodule with the pointer move the working tree holds, if any: opening it lists the
/// commits between the two pointers.
struct SubmoduleRow: View {
    let submodule: Git.Submodule
    let model: RepoModel
    let selecting: Bool
    @State private var pointer: Git.FileDiff.Pointer?

    var body: some View {
        Group {
            if let pointer, let old = pointer.old, let new = pointer.new, old != new {
                Row(target: .submodule(path: submodule.path, old: old, new: new), selecting: selecting) {
                    GitSubmoduleRow(submodule, pointer: pointer)
                }
            } else {
                GitSubmoduleRow(submodule, pointer: pointer)
            }
        }
        .task {
            let diff = try? await model.diff(.uncommitted)
            pointer = diff?.files.first { $0.path == submodule.path }?.submodule
        }
    }
}

/// The headline panel: what the agent changed since it started, kept to what it touched,
/// with the scope one tap away.
struct AgentList: View {
    let model: RepoModel
    let selecting: Bool
    var selection: Binding<Target?>?
    @State private var choice: Choice = .agent

    enum Choice: String, CaseIterable {
        case agent = "Since agent"
        case uncommitted = "Uncommitted"
        case staged = "Staged"
        case unstaged = "Unstaged"
    }

    var scope: Git.ChangeScope? {
        switch choice {
        case .agent: model.agentScope
        case .uncommitted: .uncommitted
        case .staged: .staged
        case .unstaged: .unstaged
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Scope", selection: $choice) {
                ForEach(Choice.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal)
            .padding(.vertical, 8)
            if let scope {
                Loading(id: scope) { try await model.diff(scope) } content: { diff in
                    files(diff, scope)
                        .task(id: scope) {
                            // A new scope opens its first file beside the list.
                            guard let selection, case .file(let shown, _)? = selection.wrappedValue, shown != scope
                            else { return }
                            selection.wrappedValue = diff.files.first.map { .file(scope, path: $0.path) }
                        }
                }
            } else {
                GitStateView(.empty(title: "No agent session", message: "Too few commits to start from."))
            }
        }
    }

    @ViewBuilder func files(_ diff: Git.Diff, _ scope: Git.ChangeScope) -> some View {
        let rows = Group {
            Section {
                if choice == .agent, let base = model.agentBase {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(verbatim: "Started at \(base.prefix(7))")
                            .font(.callout.weight(.medium))
                        Text(
                            model.onlyTouched && model.agentTouched != nil
                                ? "\(diff.files.count) files the agent touched · +\(diff.additions) −\(diff.deletions)"
                                : "\(diff.files.count) files since then · +\(diff.additions) −\(diff.deletions)"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        if model.agentTouched != nil {
                            Toggle("Only the agent's files", isOn: Bindable(model).onlyTouched)
                                .font(.caption)
                                .toggleStyle(.switch)
                                .controlSize(.mini)
                        }
                    }
                    .padding(.vertical, 2)
                }
                if diff.isEmpty {
                    GitStateView(.empty(title: "No changes", message: nil))
                } else {
                    Row(target: .files(scope, title: choice.rawValue), selecting: selecting) {
                        Label("All \(diff.files.count) files", systemImage: "doc.on.doc").foregroundStyle(.secondary)
                    }
                }
            }
            if !diff.isEmpty {
                Section("Files") {
                    ForEach(diff.files) { file in
                        Row(target: .file(scope, path: file.path), selecting: selecting) {
                            GitFileRow(Git.FileChange(file))
                        }
                    }
                }
            }
        }
        if let selection {
            List(selection: selection) { rows }
        } else {
            List { rows }
        }
    }
}
