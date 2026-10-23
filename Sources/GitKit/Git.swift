import Foundation

/// A repository as values. Everything GitKit makes public is nested here (`Git.Diff`,
/// `Git.Status`, `Git.Commit`), so an app's own `Commit` or `Status` never clashes with
/// it; `DiffQuote` is the one other name, the value a selection hands its host.
///
/// Every value is read from git's own machine output (`git diff`, `git status
/// --porcelain=v2 -z`, a log in a format defined here), never from text meant for a
/// person, and every value is `Codable`, `Sendable` and `Hashable`, so it crosses a
/// network, a process or an actor as it is. Nothing here runs git: a host brings the
/// bytes through a `Git.Source` (`GitLocal` runs /usr/bin/git on a Mac; a phone gets them
/// over its own transport).
public enum Git {
    /// Output git produced that is not what the parser was promised. Each case names the
    /// line it stopped at (1-based) so a capture can be found again.
    public enum ParseError: Error, Hashable, Sendable, CustomStringConvertible {
        /// `diff --cc` / `diff --combined`: a merge's combined diff, which has one column
        /// per parent. Ask for the diff against one parent instead (`--diff-merges=first-parent`).
        case combinedDiff(line: Int)
        /// A hunk header that does not read `@@ -a,b +c,d @@`.
        case hunkHeader(line: Int, text: String)
        /// A record with fewer fields than its format writes.
        case record(kind: String, line: Int, text: String)

        public var description: String {
            switch self {
            case .combinedDiff(let line):
                "line \(line): a combined diff (a merge against all its parents) is not read; "
                    + "diff against one parent"
            case .hunkHeader(let line, let text): "line \(line): not a hunk header: \(text)"
            case .record(let kind, let line, let text): "\(kind) record \(line): \(text)"
            }
        }
    }
}

extension Git {
    /// The lines of git's output as UTF-8 strings, split on `\n` without trimming
    /// anything else: a `\r` stays where the file had it. Invalid UTF-8 (a Latin-1 file)
    /// is repaired, never refused.
    static func lines(_ data: Data) -> [Substring] {
        let text = String(decoding: data, as: UTF8.self)
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        if lines.last?.isEmpty == true { lines.removeLast() }
        return lines
    }

    /// NUL-terminated records (`-z` output) as strings.
    public static func records(_ data: Data, separator: UInt8 = 0) -> [String] {
        var out: [String] = []
        var start = data.startIndex
        for index in data.indices where data[index] == separator {
            out.append(String(decoding: data[start..<index], as: UTF8.self))
            start = data.index(after: index)
        }
        if start < data.endIndex {
            out.append(String(decoding: data[start...], as: UTF8.self))
        }
        return out
    }

    /// A path as git writes it in a diff header: plain, or C-quoted (`"a/caf\303\251"`)
    /// when it holds a byte git escapes. Quoting is undone to the path's own bytes.
    static func unquote(_ text: Substring) -> String {
        guard text.count >= 2, text.first == "\"", text.last == "\"" else { return String(text) }
        var bytes: [UInt8] = []
        var chars = Array(text.dropFirst().dropLast().utf8)[...]
        while let byte = chars.popFirst() {
            guard byte == UInt8(ascii: "\\"), let next = chars.popFirst() else {
                bytes.append(byte)
                continue
            }
            switch next {
            case UInt8(ascii: "n"): bytes.append(0x0A)
            case UInt8(ascii: "t"): bytes.append(0x09)
            case UInt8(ascii: "r"): bytes.append(0x0D)
            case UInt8(ascii: "a"): bytes.append(0x07)
            case UInt8(ascii: "b"): bytes.append(0x08)
            case UInt8(ascii: "f"): bytes.append(0x0C)
            case UInt8(ascii: "v"): bytes.append(0x0B)
            case UInt8(ascii: "0")...UInt8(ascii: "7"):
                var value = Int(next - UInt8(ascii: "0"))
                for _ in 0..<2 {
                    guard let digit = chars.first, (UInt8(ascii: "0")...UInt8(ascii: "7")).contains(digit)
                    else { break }
                    chars.removeFirst()
                    value = value * 8 + Int(digit - UInt8(ascii: "0"))
                }
                bytes.append(UInt8(truncatingIfNeeded: value))
            default: bytes.append(next)
            }
        }
        return String(decoding: bytes, as: UTF8.self)
    }
}
