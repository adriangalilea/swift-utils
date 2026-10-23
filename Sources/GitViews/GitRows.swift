import GitKit
import Ink
import SwiftUI

/// A commit in a log: its subject first (what a person reads), then the short hash, who
/// and when, quieter; the refs pointing at it as chips; a merge says so.
public struct GitCommitRow: View {
    let commit: Git.Commit

    public init(_ commit: Git.Commit) { self.commit = commit }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: commit.subject)
                .font(.callout.weight(.medium))
                .lineLimit(2)
            HStack(spacing: 6) {
                if commit.isMerge {
                    Image(systemName: "arrow.triangle.merge").foregroundStyle(.secondary)
                }
                Text(verbatim: commit.shortHash).font(.caption.monospaced()).foregroundStyle(
                    .secondary)
                Text(verbatim: commit.author.name).lineLimit(1)
                Text(commit.author.date, format: .relative(presentation: .named))
                    .lineLimit(1)
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
            let refs = commit.refs.map(GitRefChip.Ref.init).filter { $0.kind != .head }
            if !refs.isEmpty {
                HStack(spacing: 4) {
                    ForEach(refs.prefix(4), id: \.name) { GitRefChip($0) }
                }
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }
}

/// A ref pointing at a commit (`main`, `origin/main`, `v1.0`), as a small chip: the
/// branch checked out stands out, a remote and a tag stay quiet.
public struct GitRefChip: View {
    public struct Ref: Sendable, Hashable {
        public enum Kind: Sendable, Hashable { case current, local, remote, tag, head }
        public var name: String
        public var kind: Kind
        /// As `%D` writes it: `HEAD -> main`, `origin/main`, `tag: v1.0`.
        public init(_ decoration: String) {
            if let branch = decoration.after("HEAD -> ") {
                (name, kind) = (String(branch), .current)
            } else if let tag = decoration.after("tag: ") {
                (name, kind) = (String(tag), .tag)
            } else if decoration == "HEAD" {
                (name, kind) = ("HEAD", .head)
            } else if decoration.contains("/") {
                (name, kind) = (decoration, .remote)
            } else {
                (name, kind) = (decoration, .local)
            }
        }
    }

    let ref: Ref
    public init(_ ref: Ref) { self.ref = ref }

    public var body: some View {
        HStack(spacing: 3) {
            Image(
                systemName: ref.kind == .tag
                    ? "tag" : ref.kind == .remote ? "cloud" : "arrow.trianglehead.branch"
            )
            .imageScale(.small)
            Text(verbatim: ref.name).lineLimit(1)
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(ref.kind == .current ? Color.accentColor : .secondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            ref.kind == .current ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.06),
            in: Capsule())
    }
}

extension StringProtocol {
    func after(_ prefix: String) -> SubSequence? {
        hasPrefix(prefix) ? self[index(startIndex, offsetBy: prefix.count)...] : nil
    }
}

/// A branch: its name (a check when checked out), how far it is from its upstream, its
/// last commit's subject and age, and the worktree holding it.
public struct GitBranchRow: View {
    let branch: Git.Branch

    public init(_ branch: Git.Branch) { self.branch = branch }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: .inkGap) {
            Image(systemName: branch.isRemote ? "cloud" : "arrow.trianglehead.branch")
                .foregroundStyle(branch.isCurrent ? Color.accentColor : .secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(verbatim: branch.name)
                        .font(.callout.weight(branch.isCurrent ? .semibold : .regular))
                        .lineLimit(1)
                    if branch.isCurrent {
                        Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(
                            Color.accentColor)
                    }
                    Spacer(minLength: .inkGap)
                    GitAheadBehind(
                        ahead: branch.ahead, behind: branch.behind, gone: branch.upstreamGone)
                }
                HStack(spacing: 6) {
                    Text(verbatim: branch.subject).lineLimit(1)
                    if let date = branch.date {
                        Text(date, format: .relative(presentation: .named)).lineLimit(1)
                            .layoutPriority(1)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if let worktree = branch.worktree, !branch.isCurrent {
                    Label {
                        MiddleTruncate(worktree, tail: "/")
                    } icon: {
                        Image(systemName: "folder")
                    }
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

/// `↑2 ↓1` against an upstream; `gone` when the upstream was deleted.
public struct GitAheadBehind: View {
    let ahead: Int?
    let behind: Int?
    let gone: Bool

    public init(ahead: Int?, behind: Int?, gone: Bool = false) {
        self.ahead = ahead
        self.behind = behind
        self.gone = gone
    }

    public var body: some View {
        HStack(spacing: 6) {
            if gone {
                Text("upstream gone").foregroundStyle(.orange)
            } else {
                if let ahead, ahead > 0 { Label("\(ahead)", systemImage: "arrow.up") }
                if let behind, behind > 0 { Label("\(behind)", systemImage: "arrow.down") }
                if ahead == 0, behind == 0 {
                    Text("in sync")
                }
            }
        }
        .labelStyle(GitTightLabel())
        .font(.caption.weight(.medium).monospacedDigit())
        .foregroundStyle(.secondary)
    }
}

struct GitTightLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 1) {
            configuration.icon.imageScale(.small)
            configuration.title
        }
    }
}

/// A worktree: where it is (the folder's name first), its branch or a detached HEAD, and
/// whether it is locked or can be pruned.
public struct GitWorktreeRow: View {
    let worktree: Git.Worktree

    public init(_ worktree: Git.Worktree) { self.worktree = worktree }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: .inkGap) {
            Image(systemName: worktree.isMain ? "folder.fill" : "folder")
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(verbatim: (worktree.path as NSString).lastPathComponent)
                        .font(.callout.weight(.medium))
                    if worktree.isMain { Text("main").font(.caption2).foregroundStyle(.tertiary) }
                    Spacer(minLength: .inkGap)
                    if worktree.locked != nil {
                        Image(systemName: "lock.fill").foregroundStyle(.secondary)
                            .accessibilityLabel("Locked")
                    }
                    if worktree.prunable != nil {
                        Text("prunable").font(.caption).foregroundStyle(.orange)
                    }
                }
                HStack(spacing: 6) {
                    if let branch = worktree.branchName {
                        Label(branch, systemImage: "arrow.trianglehead.branch")
                    } else if worktree.isBare {
                        Text("bare")
                    } else {
                        Label(
                            "detached",
                            systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                    }
                    if let head = worktree.head {
                        Text(verbatim: String(head.prefix(7))).monospaced()
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                MiddleTruncate(worktree.path, tail: "/")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

/// A submodule: its path, the commit checked out, its state, and, when the superproject
/// moved it, the pointer change (old → new) with a way in.
public struct GitSubmoduleRow: View {
    let submodule: Git.Submodule
    let pointer: Git.FileDiff.Pointer?

    public init(_ submodule: Git.Submodule, pointer: Git.FileDiff.Pointer? = nil) {
        self.submodule = submodule
        self.pointer = pointer
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: .inkGap) {
            Image(systemName: "shippingbox").foregroundStyle(.secondary).frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    GitPathLabel(submodule.path)
                    Spacer(minLength: .inkGap)
                    Text(verbatim: state)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(submodule.state == .current ? Color.secondary : .orange)
                }
                if let pointer, pointer.old != pointer.new {
                    HStack(spacing: 4) {
                        Text(verbatim: pointer.old.map { String($0.prefix(7)) } ?? "none")
                        Image(systemName: "arrow.right").imageScale(.small)
                        Text(verbatim: pointer.new.map { String($0.prefix(7)) } ?? "none")
                        if pointer.dirty { Text("dirty").foregroundStyle(.orange) }
                    }
                    .font(.caption.monospaced())
                    .foregroundStyle(.primary.opacity(0.8))
                }
                HStack(spacing: 6) {
                    Text(verbatim: String(submodule.commit.prefix(7))).monospaced()
                    if let describe = submodule.describe { Text(verbatim: describe).lineLimit(1) }
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var state: String {
        switch submodule.state {
        case .current: "up to date"
        case .moved: "moved"
        case .uninitialized: "not checked out"
        case .conflicted: "in conflict"
        }
    }
}

/// A repository's state in one band: the branch (or a detached commit), how far it is
/// from its upstream, and what waits in the tree, or that it is clean.
public struct GitStatusSummary: View {
    let status: Git.Status

    public init(_ status: Git.Status) { self.status = status }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: .inkGap) {
                Image(
                    systemName: status.branch.isDetached
                        ? "point.topleft.down.to.point.bottomright.curvepath"
                        : "arrow.trianglehead.branch"
                )
                .foregroundStyle(Color.accentColor)
                Text(
                    verbatim: status.branch.head ?? status.branch.oid.map { String($0.prefix(7)) }
                        ?? "no commits"
                )
                .font(.headline)
                .lineLimit(1)
                Spacer(minLength: .inkGap)
                if status.branch.upstream != nil {
                    GitAheadBehind(ahead: status.branch.ahead, behind: status.branch.behind)
                }
            }
            if let upstream = status.branch.upstream {
                Text(verbatim: "tracking \(upstream)").font(.caption).foregroundStyle(.tertiary)
            }
            HStack(spacing: 6) {
                if status.isClean {
                    count("Clean", nil, "checkmark.circle", .green)
                } else {
                    if !status.conflicted.isEmpty {
                        count(
                            "conflicts", status.conflicted.count, "exclamationmark.triangle",
                            .orange)
                    }
                    if !status.staged.isEmpty {
                        count("staged", status.staged.count, "tray.full", .green)
                    }
                    if !status.unstaged.isEmpty {
                        count("changed", status.unstaged.count, "plus.forwardslash.minus", .orange)
                    }
                    if !status.untracked.isEmpty {
                        count("untracked", status.untracked.count, "questionmark.folder", .gray)
                    }
                }
                if let stash = status.branch.stash, stash > 0 {
                    count("stashed", stash, "archivebox", .gray)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// A count as words: the number in its hue, the word quiet beside it, no chip around
    /// either, so a row of them reads as a sentence.
    private func count(_ word: String, _ value: Int?, _ symbol: String, _ tint: Color) -> some View
    {
        HStack(spacing: 3) {
            if let value {
                Text(verbatim: "\(value)").foregroundStyle(tint).fontWeight(.semibold)
            } else {
                Image(systemName: symbol).imageScale(.small).foregroundStyle(tint)
            }
            Text(verbatim: word).foregroundStyle(.secondary)
        }
        .font(.caption.monospacedDigit())
        .padding(.trailing, 6)
    }
}
