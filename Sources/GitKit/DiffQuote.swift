import Foundation

/// A piece of a diff handed to someone else: a file, a hunk or a range of lines, with
/// where it is (`path:L10-L24`) and a Markdown snippet ready to paste into a message to
/// an agent. What a host does with it (put it in a reply box, copy it) is the host's.
public struct DiffQuote: Codable, Sendable, Hashable {
    /// Which side's line numbers `lines` counts: the new file's, or the old one's when
    /// every quoted line was removed.
    public enum Side: String, Codable, Sendable, Hashable { case old, new }

    public var path: String
    public var side: Side
    /// The first and last line on `side`; nil when the lines carry no numbers.
    public var range: ClosedRange<Int>?
    /// The quoted lines; empty for a file whose change has no lines (binary, a mode).
    public var lines: [Git.Line]
    /// The hunk header, when one whole hunk is quoted.
    public var header: String?
    /// `path:L10-L24` (`path:L10` for one line, the path alone without numbers).
    public var reference: String
    /// The reference in backticks and the lines in a fenced `diff` block.
    public var markdown: String

    /// `lines` of `file`, in the order given.
    public init(file: Git.FileDiff, lines: [Git.Line], header: String? = nil) {
        path = file.path
        self.lines = lines
        self.header = header
        let removedOnly = !lines.isEmpty && lines.allSatisfy { $0.kind == .removed }
        side = removedOnly ? .old : .new
        let numbers = lines.compactMap { removedOnly ? $0.old : $0.new }
        range = numbers.min().flatMap { low in numbers.max().map { low...$0 } }
        let where_: String =
            switch range {
            case .some(let r) where r.lowerBound == r.upperBound: ":L\(r.lowerBound)"
            case .some(let r): ":L\(r.lowerBound)-L\(r.upperBound)"
            case .none: ""
            }
        reference = (path.isEmpty ? "diff" : path) + where_ + (removedOnly ? " (removed)" : "")
        var body = lines.map(\.unified)
        if let header { body.insert(header, at: 0) }
        markdown = "`\(reference)`\n\n" + Self.fence(body.joined(separator: "\n"))
    }

    /// One hunk, header included.
    public static func hunk(_ hunk: Git.Hunk, of file: Git.FileDiff) -> DiffQuote {
        DiffQuote(file: file, lines: hunk.lines, header: hunk.header)
    }

    /// The whole file's change: every hunk under its header, or what changed when there
    /// are no lines to show (a binary file, a mode, a submodule's pointer).
    public static func file(_ file: Git.FileDiff) -> DiffQuote {
        var quote = DiffQuote(file: file, lines: file.hunks.flatMap(\.lines))
        quote.range = nil
        quote.reference = file.path
        let what: String
        if let pointer = file.submodule {
            what = "submodule \(pointer.old.map { String($0.prefix(7)) } ?? "none") → \(pointer.new.map { String($0.prefix(7)) } ?? "none")"
        } else if file.isBinary {
            what = "binary file, \(file.change.rawValue)"
        } else if file.hunks.isEmpty, file.modeChanged {
            what = "mode \(file.oldMode ?? "") → \(file.newMode ?? "")"
        } else {
            what = "+\(file.additions) −\(file.deletions)"
        }
        var title = "`\(file.path)`"
        if file.change == .renamed || file.change == .copied, let old = file.oldPath {
            title = "`\(old)` → `\(file.path)`"
        }
        let body = file.hunks.map { ([$0.header] + $0.lines.map(\.unified)).joined(separator: "\n") }
        quote.markdown =
            "\(title) (\(what))"
            + (body.isEmpty || file.submodule != nil ? "" : "\n\n" + fence(body.joined(separator: "\n")))
        return quote
    }

    /// A fenced `diff` block whose fence is longer than any backtick run inside it.
    static func fence(_ body: String) -> String {
        var longest = 0
        var run = 0
        for character in body {
            run = character == "`" ? run + 1 : 0
            longest = max(longest, run)
        }
        let fence = String(repeating: "`", count: max(3, longest + 1))
        return "\(fence)diff\n\(body)\n\(fence)"
    }
}
