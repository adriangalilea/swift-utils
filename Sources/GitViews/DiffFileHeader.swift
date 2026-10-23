import GitKit
import Ink
import SwiftUI

/// A file's line above its diff: what happened to it (a status letter), where it is (the
/// folder quiet and cut from the front, the name whole), where it came from when renamed,
/// and how much changed (+ and − counts and GitHub's five squares). With `collapsed`, a
/// chevron folds the file down to this line.
public struct DiffFileHeader: View {
    let file: Git.FileDiff
    let collapsed: Binding<Bool>?
    @Environment(\.colorScheme) private var scheme

    public init(_ file: Git.FileDiff, collapsed: Binding<Bool>? = nil) {
        self.file = file
        self.collapsed = collapsed
    }

    public var body: some View {
        let palette = DiffPalette.of(scheme)
        let change = Git.FileChange(file)
        HStack(spacing: .inkGap) {
            if let collapsed {
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(collapsed.wrappedValue ? -90 : 0))
                    .frame(width: 14)
            }
            GitStatusBadge(change.kind, submodule: change.isSubmodule)
            VStack(alignment: .leading, spacing: 1) {
                GitPathLabel(file.path)
                if let old = change.oldPath, old != file.path {
                    HStack(spacing: 4) {
                        Image(
                            systemName: change.kind == .copied
                                ? "doc.on.doc" : "arrow.turn.down.right"
                        )
                        .imageScale(.small)
                        Text(verbatim: "from " + Self.relative(old, to: file.path))
                            .lineLimit(1)
                            .truncationMode(.head)
                        if let similarity = file.similarity, similarity < 100 {
                            Text(verbatim: "\(similarity)%").monospacedDigit()
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .layoutPriority(1)
            Spacer(minLength: .inkGap)
            if !file.isBinary, file.submodule == nil, file.additions + file.deletions > 0 {
                DiffStat(additions: file.additions, deletions: file.deletions, palette: palette)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if let collapsed { collapsed.wrappedValue.toggle() }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Self.spoken(file, change))
        .accessibilityAddTraits(collapsed == nil ? [] : .isButton)
    }

    /// A rename in the same folder says only the old name.
    static func relative(_ old: String, to new: String) -> String {
        let oldFolder = (old as NSString).deletingLastPathComponent
        let newFolder = (new as NSString).deletingLastPathComponent
        return oldFolder == newFolder ? (old as NSString).lastPathComponent : old
    }

    static func spoken(_ file: Git.FileDiff, _ change: Git.FileChange) -> String {
        var words = "\(change.kind.spoken) \(file.path)"
        if let old = change.oldPath { words += ", from \(old)" }
        if !file.isBinary { words += ", \(file.additions) added, \(file.deletions) removed" }
        return words
    }
}

/// A path as a list shows it: the name in the primary ink, its folder before it in a
/// quieter one, cut from the front when there is no room, so the name always shows.
public struct GitPathLabel: View {
    let path: String

    public init(_ path: String) { self.path = path }

    public var body: some View {
        let slash = path.lastIndex(of: "/")
        let folder = slash.map { String(path[...$0]) } ?? ""
        let name = slash.map { String(path[path.index(after: $0)...]) } ?? path
        HStack(spacing: 0) {
            if !folder.isEmpty {
                Text(verbatim: folder)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Text(verbatim: name)
                .fontWeight(.medium)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .layoutPriority(1)
        }
        .font(.callout)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(path)
    }
}

/// What happened to a file, as one outlined square in the change's hue, GitHub's file
/// marks drawn with SF Symbols: a plus added, a dot modified, a minus deleted, an arrow
/// renamed, two squares copied, a swap for a type change, a dashed question untracked, an
/// exclamation in conflict; a box for a submodule. A glyph, never a filled tile: a list of
/// files is a column of them, and tiles turn it into a quilt.
public struct GitStatusBadge: View {
    let kind: Git.FileChange.Kind
    let submodule: Bool

    public init(_ kind: Git.FileChange.Kind, submodule: Bool = false) {
        self.kind = kind
        self.submodule = submodule
    }

    public var body: some View {
        Image(systemName: submodule ? "shippingbox" : kind.symbol)
            .font(.body.weight(.medium))
            .imageScale(.medium)
            .foregroundStyle(kind.tint)
            .frame(minWidth: 20)
            .accessibilityLabel(submodule ? "submodule, \(kind.spoken)" : kind.spoken)
    }
}

extension Git.FileChange.Kind {
    var symbol: String {
        switch self {
        case .added: "plus.square"
        case .modified: "dot.square"
        case .deleted: "minus.square"
        case .renamed: "arrow.right.square"
        case .copied: "plus.square.on.square"
        case .typeChanged: "arrow.left.arrow.right.square"
        case .untracked: "questionmark.square.dashed"
        case .conflicted: "exclamationmark.square"
        }
    }

    var tint: Color {
        switch self {
        case .added: Color(red: 0.20, green: 0.66, blue: 0.36)
        case .modified: Color(red: 0.86, green: 0.58, blue: 0.10)
        case .deleted: Color(red: 0.88, green: 0.28, blue: 0.28)
        case .renamed, .copied: Color(red: 0.36, green: 0.52, blue: 0.95)
        case .typeChanged: Color(red: 0.62, green: 0.42, blue: 0.90)
        case .untracked: .gray
        case .conflicted: Color(red: 0.95, green: 0.38, blue: 0.20)
        }
    }

    var spoken: String {
        switch self {
        case .added: "added"
        case .modified: "modified"
        case .deleted: "deleted"
        case .renamed: "renamed"
        case .copied: "copied"
        case .typeChanged: "type changed"
        case .untracked: "untracked"
        case .conflicted: "in conflict"
        }
    }
}

/// `+12 −3` and five squares filled in the share each had, as GitHub draws a diffstat.
struct DiffStat: View {
    let additions: Int
    let deletions: Int
    let palette: DiffPalette

    var body: some View {
        let total = additions + deletions
        let green = total == 0 ? 0 : Int((Double(additions) / Double(total) * 5).rounded())
        let red =
            total == 0 ? 0 : min(5 - green, Int((Double(deletions) / Double(total) * 5).rounded()))
        HStack(spacing: 6) {
            if additions > 0 {
                Text(verbatim: "+\(additions)").foregroundStyle(palette.added)
            }
            if deletions > 0 {
                Text(verbatim: "−\(deletions)").foregroundStyle(palette.removed)
            }
            HStack(spacing: 1.5) {
                ForEach(0..<5, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(
                            index < green
                                ? palette.added
                                : index < green + red ? palette.removed : palette.hairline
                        )
                        .frame(width: 7, height: 7)
                }
            }
            .accessibilityHidden(true)
        }
        .font(.caption.weight(.medium).monospacedDigit())
        .fixedSize()
    }
}
