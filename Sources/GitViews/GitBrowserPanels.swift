import GitKit
import Ink
import SwiftUI

/// Reads a value and shows it, or says it is reading, or why it could not (with a retry).
struct BrowserLoading<Value, Content: View>: View {
    let id: AnyHashable
    let load: @MainActor () async throws -> Value
    @ViewBuilder let content: (Value) -> Content
    @State private var value: Value?
    @State private var failure: Error?
    @State private var attempt = 0
    /// A new reading of the repository reads the page again, the last value shown
    /// until it arrives.
    @Environment(\.gitReading) private var reading

    var body: some View {
        Group {
            if let value {
                content(value)
            } else if let failure {
                GitStateView(.failed(failure, retry: { attempt += 1 }))
            } else {
                GitStateView(.loading("Reading"))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: Key(id: id, attempt: attempt, reading: reading)) {
            do {
                value = try await load()
                failure = nil
            } catch {
                // A page already shown keeps it: a re-read that failed is no reason
                // to take away what was read.
                if value == nil { failure = error }
            }
        }
    }

    struct Key: Hashable {
        let id: AnyHashable
        let attempt: Int
        let reading: Int
    }
}

/// A row that opens `target`: a selection in a column, a push in a stack.
struct BrowserRow<Label: View>: View {
    let target: BrowserTarget
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
struct BrowserList: View {
    let panel: GitBrowser.Panel
    let model: BrowserModel
    /// Set in columns: rows select; nil in a stack: rows push.
    var selection: Binding<BrowserTarget?>?

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
        .navigationTitle(panel.title(model.agent, []))
    }

    @ViewBuilder func content(_ snapshot: Git.Snapshot) -> some View {
        switch panel {
        case .agent: BrowserAgentList(model: model, selection: selection)
        case .workingTree: list { working(snapshot) }
        case .commits: list { commits(snapshot) }
        case .repository: list { repository(snapshot) }
        case .extra: EmptyView()
        }
    }

    @ViewBuilder func list(@ViewBuilder _ rows: () -> some View) -> some View {
        if let selection {
            List(selection: selection) { rows() }
        } else {
            List { rows() }
        }
    }

    @ViewBuilder func working(_ snapshot: Git.Snapshot) -> some View {
        Section {
            GitStatusSummary(snapshot.status).padding(.vertical, 4)
        }
        if snapshot.status.isClean {
            GitStateView(
                .empty(title: "Nothing to commit", message: "The working tree matches HEAD."))
        }
        ForEach(snapshot.status.groups, id: \.group) { group in
            let scope = BrowserTarget.scope(group.group)
            Section {
                BrowserRow(
                    target: .files(scope, title: group.group.title), selecting: selection != nil
                ) {
                    Label("All \(group.group.title.lowercased())", systemImage: "doc.on.doc")
                        .foregroundStyle(.secondary)
                }
                ForEach(group.files) { change in
                    BrowserRow(target: .file(scope, path: change.path), selecting: selection != nil)
                    {
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

    @ViewBuilder func commits(_ snapshot: Git.Snapshot) -> some View {
        Section {
            ForEach(snapshot.commits) { commit in
                BrowserRow(
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

    @ViewBuilder func repository(_ snapshot: Git.Snapshot) -> some View {
        let local = snapshot.branches.filter { !$0.isRemote }
        let remote = snapshot.branches.filter(\.isRemote)
        Section("Branches") {
            ForEach(local) { branch in
                BrowserRow(target: .branch(branch), selecting: selection != nil) {
                    GitBranchRow(branch)
                }
            }
        }
        if !remote.isEmpty {
            Section("Remote branches") {
                ForEach(remote) { branch in
                    BrowserRow(target: .branch(branch), selecting: selection != nil) {
                        GitBranchRow(branch)
                    }
                }
            }
        }
        Section("Worktrees") {
            ForEach(snapshot.worktrees) { GitWorktreeRow($0) }
        }
        if !snapshot.submodules.isEmpty {
            Section("Submodules") {
                ForEach(snapshot.submodules) { submodule in
                    BrowserSubmoduleRow(
                        submodule: submodule, model: model, selecting: selection != nil)
                }
            }
        }
    }
}

/// A submodule with the pointer move the working tree holds, if any; opening it lists
/// the commits between the two pointers.
struct BrowserSubmoduleRow: View {
    let submodule: Git.Submodule
    let model: BrowserModel
    let selecting: Bool
    @State private var pointer: Git.FileDiff.Pointer?

    var body: some View {
        Group {
            if let pointer, let old = pointer.old, let new = pointer.new, old != new {
                BrowserRow(
                    target: .submodule(path: submodule.path, old: old, new: new),
                    selecting: selecting
                ) {
                    GitSubmoduleRow(submodule, pointer: pointer)
                }
            } else {
                GitSubmoduleRow(submodule, pointer: pointer)
            }
        }
        .task(id: model.reading) {
            let diff = try? await model.diff(.uncommitted)
            pointer = diff?.files.first { $0.path == submodule.path }?.submodule
        }
    }
}

/// The agent's work since it started, kept to what it touched, the scope one tap away.
struct BrowserAgentList: View {
    let model: BrowserModel
    var selection: Binding<BrowserTarget?>?
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
                BrowserLoading(id: scope, load: { try await model.diff(scope) }) { diff in
                    files(diff, scope)
                        .task(id: scope) {
                            // A new scope opens its first file beside the list.
                            guard let selection, case .file(let shown, _)? = selection.wrappedValue,
                                shown != scope
                            else { return }
                            selection.wrappedValue = diff.files.first.map {
                                .file(scope, path: $0.path)
                            }
                        }
                }
            }
        }
    }

    @ViewBuilder func files(_ diff: Git.Diff, _ scope: Git.ChangeScope) -> some View {
        let selecting = selection != nil
        let rows = Group {
            Section {
                if choice == .agent, let agent = model.agent {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(verbatim: "Started at \(agent.base.prefix(7))")
                            .font(.callout.weight(.medium))
                        Text(
                            verbatim: model.onlyTouched && agent.touched != nil
                                ? "\(diff.files.count) files it touched · +\(diff.additions) −\(diff.deletions)"
                                : "\(diff.files.count) files since then · +\(diff.additions) −\(diff.deletions)"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        if agent.touched != nil {
                            Toggle("Only the files it touched", isOn: Bindable(model).onlyTouched)
                                .font(.caption)
                                #if !os(tvOS)
                                    .toggleStyle(.switch)
                                #endif
                                .controlSize(.mini)
                        }
                    }
                    .padding(.vertical, 2)
                }
                if diff.isEmpty {
                    GitStateView(.empty(title: "No changes", message: nil))
                } else {
                    BrowserRow(target: .files(scope, title: choice.rawValue), selecting: selecting)
                    {
                        Label("All \(diff.files.count) files", systemImage: "doc.on.doc")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if !diff.isEmpty {
                Section("Files") {
                    ForEach(diff.files) { file in
                        BrowserRow(target: .file(scope, path: file.path), selecting: selecting) {
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

/// What a row opens: a page of diff, a commit, a branch's log, a submodule's move.
struct BrowserDetail: View {
    let target: BrowserTarget
    let model: BrowserModel

    var body: some View {
        content
            #if os(iOS)
                // The pinned file header already names the file: a large title would say it twice.
                .navigationBarTitleDisplayMode(.inline)
            #endif
    }

    @ViewBuilder var content: some View {
        switch target {
        case .files(let scope, let title):
            BrowserLoading(id: target, load: { try await model.diff(scope) }) { diff in
                DiffPage(diff).diffCollapsed(diff.files.count > 12)
            }
            .diffContents(model.contents(scope.target))
            .navigationTitle(title)
        case .file(let scope, let path):
            BrowserLoading(id: target, load: { try await model.diff(scope) }) { diff in
                if let file = diff.files.first(where: { $0.path == path }) {
                    DiffPage(file)
                } else {
                    GitStateView(.empty(title: "No changes", message: path))
                }
            }
            .diffContents(model.contents(scope.target))
            .navigationTitle((path as NSString).lastPathComponent)
        case .commit(let hash, let subject, let repository):
            BrowserLoading(
                id: target, load: { try await model.diff(.commit(hash), in: repository) }
            ) { diff in
                DiffPage(diff)
                    .diffCollapsed(diff.files.count > 12)
                    .safeAreaInset(edge: .top, spacing: 0) { header(hash, subject, diff) }
            }
            .diffContents(model.contents(.commit(hash), in: repository))
            .navigationTitle(String(hash.prefix(7)))
        case .branch(let name, let revision):
            BrowserLoading(id: target, load: { try await model.log(revision) }) { commits in
                List {
                    ForEach(commits) { commit in
                        NavigationLink(
                            value: BrowserTarget.commit(
                                hash: commit.hash, subject: commit.subject, repository: nil)
                        ) {
                            GitCommitRow(commit)
                        }
                    }
                }
            }
            .navigationTitle(name)
        case .submodule(let path, let old, let new):
            BrowserLoading(id: target, load: { try await model.log("\(old)..\(new)", in: path) }) {
                commits in
                List {
                    Section {
                        GitStateView(
                            .empty(
                                title: "\(old.prefix(7)) → \(new.prefix(7))",
                                message: "\(commits.count) commits moved the pointer",
                                symbol: "shippingbox"))
                    }
                    Section("Commits") {
                        ForEach(commits) { commit in
                            NavigationLink(
                                value: BrowserTarget.commit(
                                    hash: commit.hash, subject: commit.subject, repository: path)
                            ) {
                                GitCommitRow(commit)
                            }
                        }
                    }
                }
            }
            .navigationTitle(path)
        }
    }

    private func header(_ hash: String, _ subject: String, _ diff: Git.Diff) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: subject).font(.headline).lineLimit(3)
            HStack(spacing: 8) {
                Text(verbatim: String(hash.prefix(10))).monospaced()
                Text(verbatim: "\(diff.files.count) files")
                Text(verbatim: "+\(diff.additions)").foregroundStyle(DiffPalette.light.added)
                Text(verbatim: "−\(diff.deletions)").foregroundStyle(DiffPalette.light.removed)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
    }
}
