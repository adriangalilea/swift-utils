import GitKit
import GitViews
import SwiftUI

/// What a row opens: a page of diff, a commit, a submodule's move, an embedding.
struct Detail: View {
    let target: Target
    let model: RepoModel

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
            Loading(id: scope) { try await model.diff(scope) } content: { diff in
                DiffPage(diff).diffCollapsed(diff.files.count > 12)
            }
            .navigationTitle(title)
        case .file(let scope, let path):
            Loading(id: target) { try await model.diff(scope) } content: { diff in
                if let file = diff.files.first(where: { $0.path == path }) {
                    DiffPage(file)
                } else {
                    GitStateView(.empty(title: "No changes", message: path))
                }
            }
            .navigationTitle((path as NSString).lastPathComponent)
        case .commit(let hash, let subject, let repository):
            CommitDetail(hash: hash, subject: subject, repository: repository, model: model)
        case .submodule(let path, let old, let new):
            Loading(id: target) { try await model.log("\(old)..\(new)", in: path) } content: { commits in
                List {
                    Section {
                        GitStateView(
                            .empty(
                                title: "\(old.prefix(7)) → \(new.prefix(7))",
                                message: "\(commits.count) commits moved the pointer", symbol: "shippingbox"))
                    }
                    Section("Commits") {
                        ForEach(commits) { commit in
                            NavigationLink(
                                value: Target.commit(hash: commit.hash, subject: commit.subject, repository: path)
                            ) {
                                GitCommitRow(commit)
                            }
                        }
                    }
                }
            }
            .navigationTitle(path)
        case .branch(let name, let revision):
            Loading(id: target) { try await model.log(revision) } content: { commits in
                List {
                    ForEach(commits) { commit in
                        NavigationLink(
                            value: Target.commit(hash: commit.hash, subject: commit.subject, repository: nil)
                        ) {
                            GitCommitRow(commit)
                        }
                    }
                }
            }
            .navigationTitle(name)
        case .embed(let embed):
            EmbedDetail(embed: embed)
        }
    }
}

struct CommitDetail: View {
    let hash: String
    let subject: String
    let repository: String?
    let model: RepoModel

    var body: some View {
        Loading(id: hash) { try await model.diff(.commit(hash), in: repository) } content: { diff in
            DiffPage(diff)
                .diffCollapsed(diff.files.count > 12)
                .safeAreaInset(edge: .top, spacing: 0) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: subject).font(.headline).lineLimit(3)
                        HStack(spacing: 8) {
                            Text(verbatim: String(hash.prefix(10))).monospaced()
                            Text(verbatim: "\(diff.files.count) files")
                            Text(verbatim: "+\(diff.additions)").foregroundStyle(.green)
                            Text(verbatim: "−\(diff.deletions)").foregroundStyle(.red)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.bar)
                }
        }
        .navigationTitle(String(hash.prefix(7)))
    }
}

/// The quote a reader made, as an agent would receive it: the Markdown, drawn and as text.
struct QuoteSheet: View {
    let item: QuoteItem
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Send to the agent").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    MarkdownViewBox(text: item.quote.markdown)
                    Text("Markdown").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Text(verbatim: item.quote.markdown)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                }
                .padding(20)
            }
            .navigationTitle(item.quote.reference)
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Copy") {
                        #if os(macOS)
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(item.quote.markdown, forType: .string)
                        #else
                            UIPasteboard.general.string = item.quote.markdown
                        #endif
                        dismiss()
                    }
                }
            }
        }
        #if os(macOS)
            .frame(minWidth: 560, minHeight: 480)
        #endif
    }
}
