import GitKit
import Ink
import SwiftUI

/// One file in a list: its status letter, its name with the folder quiet before it, and
/// its + and − counts when known.
public struct GitFileRow: View {
    let change: Git.FileChange
    /// The folder is already said by a heading above (folder grouping).
    let nameOnly: Bool
    @Environment(\.colorScheme) private var scheme

    public init(_ change: Git.FileChange, nameOnly: Bool = false) {
        self.change = change
        self.nameOnly = nameOnly
    }

    public var body: some View {
        let palette = DiffPalette.of(scheme)
        HStack(spacing: .inkGap) {
            GitStatusBadge(change.kind, submodule: change.isSubmodule)
            VStack(alignment: .leading, spacing: 1) {
                if nameOnly {
                    Text(verbatim: change.name).font(.callout.weight(.medium)).lineLimit(1)
                } else {
                    GitPathLabel(change.path)
                }
                if let old = change.oldPath {
                    Text(verbatim: "from " + DiffFileHeader.relative(old, to: change.path))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }
            Spacer(minLength: .inkGap)
            HStack(spacing: 5) {
                if let added = change.additions, added > 0 {
                    Text(verbatim: "+\(added)").foregroundStyle(palette.added)
                }
                if let removed = change.deletions, removed > 0 {
                    Text(verbatim: "−\(removed)").foregroundStyle(palette.removed)
                }
                if change.isBinary {
                    Text("binary").foregroundStyle(.tertiary)
                }
            }
            .font(.caption.weight(.medium).monospacedDigit())
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(change.kind.spoken) \(change.path)"
                + (change.additions.map { ", \($0) added" } ?? "")
                + (change.deletions.map { ", \($0) removed" } ?? ""))
    }
}

/// Files grouped as lazygit groups them (in conflict, staged, changed, untracked) or as
/// one group, each group a section with its count, optionally split by folder. Selection
/// is by `Git.FileChange.id`, so a `NavigationSplitView` drives the diff beside it.
public struct GitFileList: View {
    public struct Group: Identifiable, Sendable {
        public var title: String
        public var files: [Git.FileChange]
        public var id: String { title }
        public init(_ title: String, _ files: [Git.FileChange]) {
            self.title = title
            self.files = files
        }
    }

    let groups: [Group]
    @Binding var selection: Git.FileChange.ID?
    let folders: Bool

    public init(_ groups: [Group], selection: Binding<Git.FileChange.ID?>, folders: Bool = false) {
        self.groups = groups
        _selection = selection
        self.folders = folders
    }

    /// A status as lazygit lists it.
    public init(status: Git.Status, selection: Binding<Git.FileChange.ID?>, folders: Bool = false) {
        self.init(
            status.groups.map { Group($0.group.title, $0.files) }, selection: selection,
            folders: folders)
    }

    /// The files of a diff, under one heading.
    public init(
        _ diff: Git.Diff, title: String = "Changed", selection: Binding<Git.FileChange.ID?>,
        folders: Bool = false
    ) {
        self.init(
            [Group(title, diff.files.map(Git.FileChange.init))], selection: selection,
            folders: folders)
    }

    public var body: some View {
        List(selection: $selection) {
            ForEach(groups) { group in
                Section {
                    if folders {
                        let byFolder = Dictionary(grouping: group.files, by: \.folder)
                        ForEach(byFolder.keys.sorted(), id: \.self) { folder in
                            Label(folder.isEmpty ? "/" : folder, systemImage: "folder")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .selectionDisabled()
                            ForEach(byFolder[folder] ?? []) { change in
                                GitFileRow(change, nameOnly: true).padding(.leading, 14).tag(
                                    change.id)
                            }
                        }
                    } else {
                        ForEach(group.files) { change in
                            GitFileRow(change).tag(change.id)
                        }
                    }
                } header: {
                    HStack {
                        Text(group.title)
                        Spacer()
                        Text(verbatim: "\(group.files.count)").monospacedDigit()
                    }
                }
            }
        }
    }
}

extension Git.FileChange.Group {
    public var title: String {
        switch self {
        case .conflicted: "Conflicts"
        case .staged: "Staged"
        case .unstaged: "Changes"
        case .untracked: "Untracked"
        case .changed: "Changed"
        }
    }
}
